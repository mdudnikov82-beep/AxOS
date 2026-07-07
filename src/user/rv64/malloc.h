#pragma once
#include "syscall.h"

/* ---- Software MTE for AxOS/RV64 ----
 *
 * Real ARM MTE packs a 4-bit tag into unused pointer bits and checks it in
 * hardware on every load/store. RISC-V has no ratified, widely-supported
 * equivalent (Pointer Masking extensions only let you IGNORE tag bits in a
 * pointer for translation — they don't store a tag per memory granule or
 * check it on every access). So instead of pretending to have hardware we
 * don't, this ports the same idea AxOS's x86 side already uses
 * (src/libaxiom/src/malloc.c, 4-bit tag) but widened all the way to a full
 * 64-bit generation tag per 8-byte granule: on RV64 `unsigned long` IS the
 * native register/ALU width, so a 64-bit tag/canary/PRNG state costs no more
 * than the 32-bit version did — every check is still a single native load
 * and compare, not a double-word emulation like it would be on rv32. The
 * wider tag just makes stale-pointer/use-after-free collisions astronomically
 * less likely (1-in-2^64 vs 1-in-2^32 for a reused address to accidentally
 * carry the same generation tag). Checked explicitly via
 * mte_check()/mte_check_tag() (or automatically inside free()) instead of
 * on every CPU load/store.
 *
 * Block layout:
 *   [heap_block_t header]
 *   [left redzone  : RZONE_SIZE bytes, 0xBE]   <- shadow RZONE
 *   [user data     : N bytes, zeroed on alloc] <- shadow OK + 32-bit tag
 *   [right redzone : RZONE_SIZE bytes, 0xBE]   <- shadow RZONE
 *   [canary        : CANARY_SIZE bytes, BASE^tag]
 *
 * Catches:
 *   heap underflow   -> left redzone corrupted, caught at free()
 *   heap overflow    -> right redzone / canary corrupted, caught at free()
 *   use-after-free   -> shadow state == FREED, mte_check_tag() returns 0
 *   double-free      -> magic == QUARANTINE/FREE on second free()
 *   stale generation -> reused address gets a new 64-bit tag; an old
 *                       pointer's remembered tag no longer matches
 *
 * API:
 *   malloc(size) / free(ptr)         — the allocator itself
 *   mte_tag(ptr)                     — current generation's tag (0 if freed)
 *   mte_check(ptr, size)             — 1 if the whole range is live (OK)
 *   mte_check_tag(ptr, tag, size)    — 1 if live AND tag matches
 *
 * Header-only (matches syscall.h's convention): each translation unit gets
 * its own private heap state, which is correct since each AxOS/RV64 process
 * is its own address space. */

#define HEAP_ALIGN8(x) (((x) + 7u) & ~7u)

#define HEAP_MAGIC_ALLOC      0x4C41434Cu  /* "LCAL" */
#define HEAP_MAGIC_QUARANTINE 0x51524E54u  /* "QRNT" */
#define HEAP_MAGIC_FREE       0x46524545u  /* "EERF" */

#define HEAP_RZONE_SIZE   8u
#define HEAP_RZONE_BYTE   0xBEu
#define HEAP_CANARY_SIZE  8u
#define HEAP_CANARY_BASE  (0xACACACACu | ((unsigned long)0xACACACACu << 32))
#define HEAP_QUARANTINE_CAPACITY 8

/* Shadow memory: one state byte + one 64-bit tag per 8-byte granule,
 * covering the first MTE_SHADOW_COVER bytes of the heap. Allocations (or
 * parts of them) beyond that window are still allocated/freed correctly,
 * they just aren't shadow-tracked (mte_check* on them returns 0/miss). */
#define MTE_GRANULE       8u
#define MTE_SHADOW_COVER  (64u * 1024u)
#define MTE_SHADOW_SIZE   (MTE_SHADOW_COVER / MTE_GRANULE)

#define MTE_STATE_OK      0x00u
#define MTE_STATE_RZONE   0xFAu
#define MTE_STATE_FREED   0xFDu

typedef struct heap_block {
    unsigned int        size;   /* lzone + user + rzone + canary, excl. header */
    struct heap_block  *next;
    unsigned int         free;
    unsigned int         magic;
    unsigned long         tag;   /* 64-bit generation tag (1..2^64-1; 0 = none) */
} heap_block_t;

#define HEAP_HDR_SIZE ((unsigned int)sizeof(heap_block_t))

static heap_block_t  *__heap_free_list = 0;
static heap_block_t  *__heap_quarantine[HEAP_QUARANTINE_CAPACITY];
static unsigned int    __heap_quarantine_count = 0;
static unsigned int    __heap_quarantine_pos   = 0;
static unsigned long   __heap_prng             = 0;
static unsigned char  *__heap_base             = 0;  /* first sbrk-ed address */

static unsigned char   __mte_state[MTE_SHADOW_SIZE];
static unsigned long   __mte_tag[MTE_SHADOW_SIZE];

static void heap_abort(const char *why) {
    puts_rv("\r\n\033[31m*** HEAP CORRUPTION: ");
    puts_rv(why);
    puts_rv(" ***\033[0m\r\n");
    exit(139);  /* distinct exit code, like a SIGSEGV, not a normal 0/1 */
}

/* ---- shadow memory ---- */

static long __mte_idx(const void *p) {
    if (!__heap_base) return -1;
    long off = (long)((const unsigned char *)p - __heap_base);
    if (off < 0 || (unsigned long)off >= MTE_SHADOW_COVER) return -1;
    return off / (long)MTE_GRANULE;
}

static void __mte_fill(const void *start, unsigned int nbytes,
                       unsigned char state, unsigned long tag) {
    if (!nbytes) return;
    long i0 = __mte_idx(start);
    long i1 = __mte_idx((const unsigned char *)start + nbytes - 1);
    if (i0 < 0 || i1 < 0 || i0 > i1) return;
    for (long i = i0; i <= i1; i++) { __mte_state[i] = state; __mte_tag[i] = tag; }
}

/* 1 if [ptr, ptr+size) is entirely live (state OK), regardless of tag. */
static int mte_check(const void *ptr, unsigned int size) {
    if (!ptr || !size) return 0;
    long i0 = __mte_idx(ptr);
    long i1 = __mte_idx((const unsigned char *)ptr + size - 1);
    if (i0 < 0 || i1 < 0) return 0;
    for (long i = i0; i <= i1; i++) if (__mte_state[i] != MTE_STATE_OK) return 0;
    return 1;
}

/* Current generation's tag, or 0 if freed / not shadow-tracked. */
static unsigned long mte_tag(const void *ptr) {
    long idx = __mte_idx(ptr);
    if (idx < 0 || __mte_state[idx] != MTE_STATE_OK) return 0;
    return __mte_tag[idx];
}

/* 1 if [ptr, ptr+size) is live AND every granule's tag matches expected. */
static int mte_check_tag(const void *ptr, unsigned long expected_tag, unsigned int size) {
    if (!ptr || !size || !expected_tag) return 0;
    long i0 = __mte_idx(ptr);
    long i1 = __mte_idx((const unsigned char *)ptr + size - 1);
    if (i0 < 0 || i1 < 0) return 0;
    for (long i = i0; i <= i1; i++)
        if (__mte_state[i] != MTE_STATE_OK || __mte_tag[i] != expected_tag) return 0;
    return 1;
}

/* ---- tag PRNG (xorshift64, never returns 0) ----
 * Canonical xorshift64 shift triple (13, 7, 17) — not the (13, 17, 5)
 * triple used for the 32-bit version, which is tuned for a 32-bit word
 * and would give a weaker/shorter-period sequence at 64 bits. Runs as a
 * single native register op on RV64, same cost as the old 32-bit version. */

static unsigned long __heap_next_tag(void) {
    if (__heap_prng == 0) {
        __heap_prng = (unsigned long)gettime() ^ 0x9E3779B97F4A7C15UL;
        if (__heap_prng == 0) __heap_prng = 1UL;
    }
    __heap_prng ^= (unsigned long)gettime();
    __heap_prng ^= __heap_prng << 13;
    __heap_prng ^= __heap_prng >> 7;
    __heap_prng ^= __heap_prng << 17;
    unsigned long t = __heap_prng;
    return t ? t : 1UL;
}

static unsigned long __heap_tagged_canary(unsigned long tag) {
    return HEAP_CANARY_BASE ^ tag;
}

/* ---- quarantine / free list ---- */

static void __heap_release_to_free_list(heap_block_t *b) {
    unsigned char *payload   = (unsigned char *)b + HEAP_HDR_SIZE + HEAP_RZONE_SIZE;
    unsigned int   user_size = b->size - 2u * HEAP_RZONE_SIZE - HEAP_CANARY_SIZE;
    for (unsigned int i = 0; i < user_size; i++) payload[i] = 0xDDu;
    /* Shadow state was already marked FREED at free()-time (see
     * __heap_quarantine_push) — only the actual data poisoning and free
     * list merge are deferred until eviction from quarantine. */

    b->free  = 1;
    b->magic = HEAP_MAGIC_FREE;
    b->tag   = 0;

    heap_block_t *next_adj = (heap_block_t *)((unsigned char *)b + HEAP_HDR_SIZE + b->size);
    heap_block_t *prev = 0, *cur = __heap_free_list;
    while (cur) {
        if (cur == next_adj) {
            b->size += HEAP_HDR_SIZE + cur->size;
            if (prev) prev->next = cur->next; else __heap_free_list = cur->next;
            break;
        }
        prev = cur; cur = cur->next;
    }

    cur = __heap_free_list;
    while (cur) {
        if ((unsigned char *)cur + HEAP_HDR_SIZE + cur->size == (unsigned char *)b) {
            cur->size += HEAP_HDR_SIZE + b->size;
            return;
        }
        cur = cur->next;
    }

    b->next         = __heap_free_list;
    __heap_free_list = b;
}

static void __heap_quarantine_push(heap_block_t *b) {
    /* Mark the shadow FREED immediately — mte_check()/mte_check_tag() must
     * report "not live" right after free(), even though the actual bytes
     * aren't poisoned and the block isn't merged into the free list until
     * it's evicted from quarantine later. */
    unsigned char *payload   = (unsigned char *)b + HEAP_HDR_SIZE + HEAP_RZONE_SIZE;
    unsigned int   user_size = b->size - 2u * HEAP_RZONE_SIZE - HEAP_CANARY_SIZE;
    __mte_fill(payload, user_size, MTE_STATE_FREED, 0);

    if (__heap_quarantine_count == HEAP_QUARANTINE_CAPACITY) {
        __heap_release_to_free_list(__heap_quarantine[__heap_quarantine_pos]);
    } else {
        __heap_quarantine_count++;
    }
    __heap_quarantine[__heap_quarantine_pos] = b;
    __heap_quarantine_pos = (__heap_quarantine_pos + 1) % HEAP_QUARANTINE_CAPACITY;
}

/* ---- public API ---- */

static void *malloc(unsigned int size) {
    if (!size) return 0;
    size = HEAP_ALIGN8(size);
    unsigned int total = HEAP_RZONE_SIZE + size + HEAP_RZONE_SIZE + HEAP_CANARY_SIZE;

    heap_block_t *b = 0, *prev = 0, *cur = __heap_free_list;
    while (cur) {
        if (cur->size >= total) {
            if (prev) prev->next = cur->next; else __heap_free_list = cur->next;
            b = cur;
            break;
        }
        prev = cur; cur = cur->next;
    }

    if (!b) {
        long base = sbrk((long)(HEAP_HDR_SIZE + total));
        if (base < 0) return 0;
        b = (heap_block_t *)(unsigned long)base;
        if (!__heap_base) __heap_base = (unsigned char *)b;
        b->size = total;
    }

    unsigned int user_size = b->size - 2u * HEAP_RZONE_SIZE - HEAP_CANARY_SIZE;
    unsigned long tag      = __heap_next_tag();

    b->free  = 0;
    b->next  = 0;
    b->magic = HEAP_MAGIC_ALLOC;
    b->tag   = tag;

    unsigned char *lzone = (unsigned char *)b + HEAP_HDR_SIZE;
    for (unsigned int i = 0; i < HEAP_RZONE_SIZE; i++) lzone[i] = HEAP_RZONE_BYTE;
    __mte_fill(lzone, HEAP_RZONE_SIZE, MTE_STATE_RZONE, 0);

    void *ptr = (void *)(lzone + HEAP_RZONE_SIZE);
    for (unsigned int i = 0; i < user_size; i++) ((unsigned char *)ptr)[i] = 0;
    __mte_fill(ptr, user_size, MTE_STATE_OK, tag);

    unsigned char *rzone = (unsigned char *)ptr + user_size;
    for (unsigned int i = 0; i < HEAP_RZONE_SIZE; i++) rzone[i] = HEAP_RZONE_BYTE;
    __mte_fill(rzone, HEAP_RZONE_SIZE, MTE_STATE_RZONE, 0);

    *(unsigned long *)(rzone + HEAP_RZONE_SIZE) = __heap_tagged_canary(tag);

    return ptr;
}

static void free(void *ptr) {
    if (!ptr) return;
    heap_block_t *b = (heap_block_t *)((unsigned char *)ptr - HEAP_RZONE_SIZE - HEAP_HDR_SIZE);

    if (b->magic == HEAP_MAGIC_FREE || b->magic == HEAP_MAGIC_QUARANTINE)
        heap_abort("double free()");
    if (b->magic != HEAP_MAGIC_ALLOC)
        heap_abort("free() on invalid/foreign pointer");

    unsigned char *lzone = (unsigned char *)b + HEAP_HDR_SIZE;
    for (unsigned int i = 0; i < HEAP_RZONE_SIZE; i++)
        if (lzone[i] != HEAP_RZONE_BYTE) heap_abort("left redzone underflow");

    unsigned int user_size = b->size - 2u * HEAP_RZONE_SIZE - HEAP_CANARY_SIZE;
    unsigned char *rzone = (unsigned char *)ptr + user_size;
    for (unsigned int i = 0; i < HEAP_RZONE_SIZE; i++)
        if (rzone[i] != HEAP_RZONE_BYTE) heap_abort("right redzone overflow");

    if (*(unsigned long *)(rzone + HEAP_RZONE_SIZE) != __heap_tagged_canary(b->tag))
        heap_abort("buffer overflow (canary)");

    b->magic = HEAP_MAGIC_QUARANTINE;
    b->free  = 0;
    __heap_quarantine_push(b);
}
