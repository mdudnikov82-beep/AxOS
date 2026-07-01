#include "../include/axiom.h"

// Shadow memory + Memory Tagging (software MTE, 32-bit теги):
//
// Два параллельных shadow-массива (1 байт на 8 байт кучи):
//   shadow_state[i]  — состояние гранулы: OK / RZONE / FREED  (4 KB)
//   shadow_tag[i]    — 32-битный тег поколения (1..2^32-1; 0 = freed) (16 KB)
//
// 32 бит → вероятность угадать ≈ 1/4294967295 ≈ 2.3×10⁻¹⁰ (практически невозможно).
//
// API:
//   ax_alloc_tag(ptr)              — тег текущего поколения (0 если freed).
//   ax_check(ptr, size)            — доступен ли диапазон (state == OK).
//   ax_check_tag(ptr, tag, size)   — доступен И тег совпадает.
//
// ax_check_tag ловит use-after-free даже после переиспользования адреса:
// новое поколение имеет другой тег → возвращает 0.

#define ALIGN4(n) (((unsigned int)(n) + 3u) & ~3u)

#define MAGIC_ALLOC      0x4C41434Bu
#define MAGIC_QUARANTINE 0x51524E54u
#define MAGIC_FREE       0x46524545u

#define RZONE_SIZE   8u
#define RZONE_BYTE   0xBEu
#define CANARY_SIZE  4u
#define CANARY_BASE  0xACACACACu
#define TAG_MASK     0xFFFFFFFFu   // 32 бита: теги 1..2^32-1
#define QUARANTINE_N 8u

#define SHADOW_GRANULE     8u
#define SHADOW_COVER       (32u * 1024u)
#define SHADOW_SIZE        (SHADOW_COVER / SHADOW_GRANULE)  // 4096 байт

#define SHADOW_STATE_OK    0x00u
#define SHADOW_STATE_RZONE 0xFAu
#define SHADOW_STATE_FREED 0xFDu

struct block {
    unsigned int  size;
    struct block* next;
    unsigned int  free;
    unsigned int  magic;
    unsigned int  tag;    // 8-битный тег поколения (1-255)
};

#define HDR sizeof(struct block)

static struct block*  free_list        = 0;
static struct block*  quarantine[QUARANTINE_N];
static unsigned int   quarantine_pos   = 0;
static unsigned int   quarantine_count = 0;
static unsigned int   prng_state       = 0;

static unsigned char  shadow_state[SHADOW_SIZE];     // OK / RZONE / FREED  (4 KB)
static unsigned int   shadow_tag[SHADOW_SIZE];       // 32-бит тег поколения (16 KB)
static unsigned char* heap_base = 0;

// --- Shadow ---

static int shadow_idx(void* p) {
    if (!heap_base) return -1;
    int off = (int)((unsigned char*)p - heap_base);
    if (off < 0 || (unsigned int)off >= SHADOW_COVER) return -1;
    return off / (int)SHADOW_GRANULE;
}

static void shadow_fill(void* start, unsigned int nbytes,
                        unsigned char state, unsigned int tag) {
    int i0 = shadow_idx(start);
    int i1 = shadow_idx((unsigned char*)start + nbytes - 1);
    if (i0 < 0 || i1 < 0 || i0 > i1) return;
    for (int i = i0; i <= i1; i++) {
        shadow_state[i] = state;
        shadow_tag[i]   = tag;
    }
}

// 1 если весь диапазон в состоянии OK (тег не проверяется).
int ax_check(void* ptr, unsigned int size) {
    if (!ptr || size == 0) return 0;
    int i0 = shadow_idx(ptr);
    int i1 = shadow_idx((unsigned char*)ptr + size - 1);
    if (i0 < 0 || i1 < 0) return 0;
    for (int i = i0; i <= i1; i++)
        if (shadow_state[i] != SHADOW_STATE_OK) return 0;
    return 1;
}

// Тег текущего поколения блока. 0 если freed или не выделен.
unsigned int ax_alloc_tag(void* ptr) {
    int idx = shadow_idx(ptr);
    if (idx < 0) return 0;
    if (shadow_state[idx] != SHADOW_STATE_OK) return 0;
    return shadow_tag[idx];
}

// 1 если OK И тег совпадает с expected_tag.
int ax_check_tag(void* ptr, unsigned int expected_tag, unsigned int size) {
    if (!ptr || size == 0 || expected_tag == 0) return 0;
    int i0 = shadow_idx(ptr);
    int i1 = shadow_idx((unsigned char*)ptr + size - 1);
    if (i0 < 0 || i1 < 0) return 0;
    for (int i = i0; i <= i1; i++)
        if (shadow_state[i] != SHADOW_STATE_OK || shadow_tag[i] != expected_tag) return 0;
    return 1;
}

// --- PRNG: 32 бита, никогда не возвращает 0 ---

static unsigned int next_tag(void) {
    if (prng_state == 0) {
        unsigned int sp;
        __asm__("mov %%esp, %0" : "=r"(sp));
        prng_state = sp ^ 0x2545F491u;
        if (prng_state == 0) prng_state = 1u;
    }
    prng_state ^= prng_state << 13;
    prng_state ^= prng_state >> 17;
    prng_state ^= prng_state << 5;
    unsigned int t = prng_state & TAG_MASK;
    return t ? t : 1u;
}

static unsigned int tagged_canary(unsigned int tag) {
    return CANARY_BASE ^ tag;
}

// --- Heap corruption ---

static void heap_corrupted(char* why) {
    ax_print("\n*** HEAP CORRUPTION: ");
    ax_print(why);
    ax_print(" ***\n");
    while (1) {}
}

// --- Quarantine / free list ---

static void release_to_free_list(struct block* b) {
    unsigned char* payload   = (unsigned char*)b + HDR + RZONE_SIZE;
    unsigned int   user_size = b->size - RZONE_SIZE - CANARY_SIZE;
    for (unsigned int i = 0; i < user_size; i++) payload[i] = 0xDDu;

    b->free  = 1;
    b->magic = MAGIC_FREE;
    b->tag   = 0;

    struct block* next_adj = (struct block*)((char*)b + HDR + b->size);
    struct block* prev = 0, *cur = free_list;
    while (cur) {
        if (cur == next_adj) {
            b->size += HDR + cur->size;
            if (prev) prev->next = cur->next;
            else      free_list  = cur->next;
            break;
        }
        prev = cur; cur = cur->next;
    }

    prev = 0; cur = free_list;
    while (cur) {
        if ((char*)cur + HDR + cur->size == (char*)b) {
            cur->size += HDR + b->size;
            return;
        }
        prev = cur; cur = cur->next;
    }

    b->next   = free_list;
    free_list = b;
}

static void quarantine_push(struct block* b) {
    unsigned char* payload   = (unsigned char*)b + HDR + RZONE_SIZE;
    unsigned int   user_size = b->size - RZONE_SIZE - CANARY_SIZE;
    shadow_fill(payload, user_size, SHADOW_STATE_FREED, 0);

    if (quarantine_count == QUARANTINE_N)
        release_to_free_list(quarantine[quarantine_pos]);
    else
        quarantine_count++;
    quarantine[quarantine_pos] = b;
    quarantine_pos = (quarantine_pos + 1) % QUARANTINE_N;
}

// --- Public API ---

void* ax_malloc(unsigned int size) {
    if (size == 0) return 0;
    size = ALIGN4(size);
    unsigned int total = RZONE_SIZE + size + CANARY_SIZE;

    struct block* b = 0;
    struct block* prev = 0, *cur = free_list;
    while (cur) {
        if (cur->size >= total) {
            if (prev) prev->next = cur->next;
            else      free_list  = cur->next;
            b = cur;
            break;
        }
        prev = cur; cur = cur->next;
    }

    if (!b) {
        b = (struct block*)ax_sbrk((int)(HDR + total));
        if ((unsigned int)b == (unsigned int)-1) return 0;
        if (!heap_base) heap_base = (unsigned char*)b;
        b->size = total;
    }

    unsigned int user_size = b->size - RZONE_SIZE - CANARY_SIZE;
    unsigned int tag       = next_tag();

    b->free  = 0;
    b->next  = 0;
    b->magic = MAGIC_ALLOC;
    b->tag   = tag;

    unsigned char* lzone = (unsigned char*)b + HDR;
    for (unsigned int i = 0; i < RZONE_SIZE; i++) lzone[i] = RZONE_BYTE;
    shadow_fill(lzone, RZONE_SIZE, SHADOW_STATE_RZONE, 0);

    void* ptr = (void*)(lzone + RZONE_SIZE);
    shadow_fill(ptr, user_size, SHADOW_STATE_OK, (unsigned char)tag);

    *(unsigned int*)((char*)ptr + user_size) = tagged_canary(tag);

    return ptr;
}

void ax_free(void* ptr) {
    if (!ptr) return;
    struct block* b = (struct block*)((char*)ptr - RZONE_SIZE - HDR);

    if (b->magic == MAGIC_FREE || b->magic == MAGIC_QUARANTINE)
        heap_corrupted("double free");
    if (b->magic != MAGIC_ALLOC)
        heap_corrupted("free on invalid pointer");

    unsigned char* lzone = (unsigned char*)b + HDR;
    for (unsigned int i = 0; i < RZONE_SIZE; i++)
        if (lzone[i] != RZONE_BYTE) heap_corrupted("left redzone underflow");

    unsigned int user_size = b->size - RZONE_SIZE - CANARY_SIZE;
    if (*(unsigned int*)((char*)ptr + user_size) != tagged_canary(b->tag))
        heap_corrupted("buffer overflow (canary)");

    b->magic = MAGIC_QUARANTINE;
    b->free  = 0;
    quarantine_push(b);
}
