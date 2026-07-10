#include "../include/axiom.h"

// Hardened heap: shadow memory + 64-bit generation tags + redzones + quarantine.
//
// Изначально тег был 32-бит; расширен до 64 (см. тот же приём в
// src/kernel/heap.c и src/user/rv64/malloc.h) - "long long" гарантированно
// 64-бит даже в -m32 коде (компилятор сам генерирует парную 32-битную
// арифметику), так что расширение не требует перехода на -m64.
//
// Макет каждого блока:
//   [struct block : HDR]
//   [левая redzone : RZONE_SIZE байт, 0xBE]   ← shadow RZONE
//   [пользовательские данные : N байт, 0x00]  ← shadow OK + 64-bit тег
//   [правая redzone : RZONE_SIZE байт, 0xBE]  ← shadow RZONE
//   [канарейка : CANARY_SIZE байт, BASE^tag]
//
// Shadow-массивы (гранула SHADOW_GRANULE = 8 байт):
//   shadow_state[i]  — OK / RZONE / FREED
//   shadow_tag[i]    — 64-бит тег поколения (1..2^64-1; 0 = rzone/freed)
//
// 64 бита → коллизия поколений при переиспользовании адреса ≈ 1/2^64
// (было 1/2^32) - не криптографическая гарантия (тег не секрет, если
// атакующий уже читает память процесса), а снижение шанса случайного
// совпадения при UAF на много порядков.
//
// Что ловится:
//   heap underflow     → left redzone 0xBE испорчен при free()
//   heap overflow      → right redzone 0xBE испорчен при free()
//   heap overflow+     → канарейка BASE^tag не совпала
//   use-after-free     → shadow FREED; ax_check_tag() возвращает 0
//   double-free        → magic == QUARANTINE при повторном free()
//   stale ptr (reuse)  → новое поколение = новый 32-бит тег; ax_check_tag() = 0
//   данные прошлого    → zero-on-alloc: всегда 0x00 при выдаче
//
// API:
//   ax_alloc_tag(ptr)              — тег текущего поколения (0 если freed).
//   ax_check(ptr, size)            — доступен ли диапазон (state == OK).
//   ax_check_tag(ptr, tag, size)   — доступен И тег совпадает.

#define ALIGN8(n) (((unsigned int)(n) + 7u) & ~7u)

#define MAGIC_ALLOC      0x4C41434Bu
#define MAGIC_QUARANTINE 0x51524E54u
#define MAGIC_FREE       0x46524545u

#define RZONE_SIZE   8u
#define RZONE_BYTE   0xBEu
#define CANARY_SIZE  8u
#define CANARY_BASE  (0xACACACACu | ((unsigned long long)0xACACACACu << 32))
#define QUARANTINE_N 8u

// COVER уменьшен вдвое (32КБ -> 16КБ) относительно 32-битной версии: тег
// стал вдвое шире (8 байт вместо 4), и этот массив зашит статически в
// КАЖДУЮ программу, слинкованную с libaxiom (~30 штук в fs/) - без этой
// компенсации суммарный прирост не влезал в 1МБ FAT12-образ. Итоговый
// футпринт shadow-массивов на бинарник (16КБ тегов + 2КБ состояний) даже
// чуть меньше исходных 32-битных (16КБ + 4КБ).
#define SHADOW_GRANULE     8u
#define SHADOW_COVER       (16u * 1024u)
#define SHADOW_SIZE        (SHADOW_COVER / SHADOW_GRANULE)

#define SHADOW_STATE_OK    0x00u
#define SHADOW_STATE_RZONE 0xFAu
#define SHADOW_STATE_FREED 0xFDu

struct block {
    unsigned int  size;
    struct block* next;
    unsigned int  free;
    unsigned int  magic;
    unsigned long long tag;    // 64-битный тег поколения (1..2^64-1)
};

#define HDR sizeof(struct block)

static struct block*  free_list        = 0;
static struct block*  quarantine[QUARANTINE_N];
static unsigned int   quarantine_pos   = 0;
static unsigned int   quarantine_count = 0;
static unsigned long long prng_state   = 0;

static unsigned char  shadow_state[SHADOW_SIZE];     // OK / RZONE / FREED  (4 KB)
static unsigned long long shadow_tag[SHADOW_SIZE];   // 64-бит тег поколения (32 KB)
static unsigned char* heap_base = 0;

// --- Shadow ---

static int shadow_idx(void* p) {
    if (!heap_base) return -1;
    int off = (int)((unsigned char*)p - heap_base);
    if (off < 0 || (unsigned int)off >= SHADOW_COVER) return -1;
    return off / (int)SHADOW_GRANULE;
}

static void shadow_fill(void* start, unsigned int nbytes,
                        unsigned char state, unsigned long long tag) {
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
unsigned long long ax_alloc_tag(void* ptr) {
    int idx = shadow_idx(ptr);
    if (idx < 0) return 0;
    if (shadow_state[idx] != SHADOW_STATE_OK) return 0;
    return shadow_tag[idx];
}

// 1 если OK И тег совпадает с expected_tag.
int ax_check_tag(void* ptr, unsigned long long expected_tag, unsigned int size) {
    if (!ptr || size == 0 || expected_tag == 0) return 0;
    int i0 = shadow_idx(ptr);
    int i1 = shadow_idx((unsigned char*)ptr + size - 1);
    if (i0 < 0 || i1 < 0) return 0;
    for (int i = i0; i <= i1; i++)
        if (shadow_state[i] != SHADOW_STATE_OK || shadow_tag[i] != expected_tag) return 0;
    return 1;
}

// "Software TBI" stand-in: снимок (addr, поколение) в момент вызова -
// resolve() позже перепроверяет тег против ТЕКУЩЕГО поколения блока,
// программный аналог того, что настоящий MTE делает аппаратно на каждом
// load/store (ни x86-64, ни RISC-V sv39 здесь этого не умеют - нет
// LAM/Zjpm, тег в старших битах указателя железо бы просто не проигнорировало).
ax_handle_t ax_handle(void* ptr) {
    ax_handle_t h;
    h.addr = ptr;
    h.tag  = ax_alloc_tag(ptr);
    return h;
}

// Указатель, если блок всё ещё того же поколения, что было при
// ax_handle(); иначе 0 (freed / переиспользован / никогда не был живым).
void* ax_resolve(ax_handle_t h, unsigned int size) {
    if (h.tag == 0) return 0;
    return ax_check_tag(h.addr, h.tag, size) ? h.addr : 0;
}

// --- PRNG: xorshift64, никогда не возвращает 0 ---
// Канонические сдвиги для 64-битного слова (13, 7, 17) - не та тройка
// (13, 17, 5), что была тут для 32-битной версии: она подобрана под 32
// бита и на 64 давала бы более слабую/короткую последовательность.
// "long long" арифметика в -m32 коде компилируется в пару 32-битных
// регистров - дороже одного regis­тра, но не требует -m64.

static unsigned long long next_tag(void) {
    if (prng_state == 0) {
        unsigned int sp;
        __asm__("mov %%esp, %0" : "=r"(sp));
        prng_state = (unsigned long long)sp ^ 0x9E3779B97F4A7C15ull;
        if (prng_state == 0) prng_state = 1ull;
    }
    prng_state ^= prng_state << 13;
    prng_state ^= prng_state >> 7;
    prng_state ^= prng_state << 17;
    return prng_state ? prng_state : 1ull;
}

static unsigned long long tagged_canary(unsigned long long tag) {
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
    size = ALIGN8(size);
    // Макет: [lzone:RZONE_SIZE][user:size][rzone:RZONE_SIZE][canary:CANARY_SIZE]
    unsigned int total = RZONE_SIZE + size + RZONE_SIZE + CANARY_SIZE;

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

    // user_size = байты полезных данных (без обеих rzone и canary)
    unsigned int user_size = b->size - 2u * RZONE_SIZE - CANARY_SIZE;
    unsigned long long tag = next_tag();

    b->free  = 0;
    b->next  = 0;
    b->magic = MAGIC_ALLOC;
    b->tag   = tag;

    // Левая redzone
    unsigned char* lzone = (unsigned char*)b + HDR;
    for (unsigned int i = 0; i < RZONE_SIZE; i++) lzone[i] = RZONE_BYTE;
    shadow_fill(lzone, RZONE_SIZE, SHADOW_STATE_RZONE, 0);

    // Пользовательские данные: zero-on-alloc + shadow OK
    void* ptr = (void*)(lzone + RZONE_SIZE);
    for (unsigned int i = 0; i < user_size; i++) ((unsigned char*)ptr)[i] = 0;
    shadow_fill(ptr, user_size, SHADOW_STATE_OK, tag);

    // Правая redzone
    unsigned char* rzone = (unsigned char*)ptr + user_size;
    for (unsigned int i = 0; i < RZONE_SIZE; i++) rzone[i] = RZONE_BYTE;
    shadow_fill(rzone, RZONE_SIZE, SHADOW_STATE_RZONE, 0);

    // Канарейка после правой rzone
    *(unsigned long long*)(rzone + RZONE_SIZE) = tagged_canary(tag);

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

    unsigned int user_size = b->size - 2u * RZONE_SIZE - CANARY_SIZE;

    // Правая redzone: overflow между концом данных и канарейкой
    unsigned char* rzone = (unsigned char*)ptr + user_size;
    for (unsigned int i = 0; i < RZONE_SIZE; i++)
        if (rzone[i] != RZONE_BYTE) heap_corrupted("right redzone overflow");

    if (*(unsigned long long*)(rzone + RZONE_SIZE) != tagged_canary(b->tag))
        heap_corrupted("buffer overflow (canary)");

    b->magic = MAGIC_QUARANTINE;
    b->free  = 0;
    quarantine_push(b);
}
