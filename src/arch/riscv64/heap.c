#include "heap.h"
#include "pmem.h"
#include "drivers/uart.h"

// Kernel heap — free-list аллокатор поверх физических страниц, с той же
// software-MTE-style защитой (тег + redzone + канарейка + карантин), что
// уже стоит на src/kernel/heap.c (x86-64 kmalloc) и src/user/rv64/malloc.h
// (userspace) — раньше эта куча была единственной из четырёх БЕЗ какой-либо
// защиты (голый free-list, никакого magic/tag/canary).
//
// Схема:
//   • Арена — непрерывный регион из нескольких страниц, взятых через alloc_page().
//   • Каждый блок предваряется заголовком block_hdr.
//   • Свободные блоки связаны в односвязный free-list.
//   • При нехватке места в текущей арене — расширяем на одну страницу.
//   • ВАЖНО: b->size у ЭТОГО файла всегда включает HDR_SIZE (в отличие от
//     x86 kernel heap.c, где size - только полезная нагрузка) - сохраняем
//     исходную конвенцию этого файла, чтобы не переписывать arena_grow()/
//     heap_free_bytes().
//
// Макет каждого выделенного блока:
//   [block_hdr : HDR_SIZE]
//   [левая redzone : RZONE_SIZE байт, 0xBE]
//   [пользовательские данные : N байт]
//   [канарейка : CANARY_SIZE байт, BASE^tag]
//
// Тег - составной, 144 бита (tag144_t ниже: два 64-битных слова + одно
// 16-битное, 64+64+16=144) - шире родного 64-битного регистра RV64/lp64,
// так что сравнение тега/канарейки - честных три сравнения вместо одного
// (сознательный компромисс скорости, см. src/kernel/heap.c за тем же
// решением на x86). Каждое из трёх 64-битных слов генерируется отдельным
// шагом канонического xorshift64 (сдвиги 13,7,17), энтропия - CSR `time`
// (тот же регистр, что использует таймер планировщика).
//
// Карантин: free() не возвращает блок в free-list немедленно, а кладёт в
// маленькое кольцо (QUARANTINE_CAPACITY последних free()) - typical
// use-after-free сразу после free() с большой вероятностью попадёт в блок,
// который ещё никто не успел переиспользовать. Отравление данных и
// физическое слияние с соседями откладываются до вытеснения из карантина.

#define HEAP_INIT_PAGES  4          // 16 KB при старте

#define HEAP_MAGIC_ALLOC      0x4C41434Cul // "LCAL" - выделен
#define HEAP_MAGIC_QUARANTINE 0x51524E54ul // "QRNT" - свободен, но не виден kmalloc()
#define HEAP_MAGIC_FREE       0x46524545ul // "EERF" - свободен и виден kmalloc()

#define RZONE_SIZE   16UL
#define RZONE_BYTE   0xBEu

typedef struct {
    unsigned long long lo;
    unsigned long long mid;
    unsigned short      hi;   // используются только младшие 16 бит
} __attribute__((packed)) tag144_t;

static tag144_t tag144_zero(void) {
    tag144_t t; t.lo = 0; t.mid = 0; t.hi = 0; return t;
}
static int tag144_is_zero(tag144_t t) {
    return !t.lo && !t.mid && !t.hi;
}
static int tag144_eq(tag144_t a, tag144_t b) {
    return a.lo == b.lo && a.mid == b.mid && a.hi == b.hi;
}

#define CANARY_SIZE  18UL   // sizeof(tag144_t)
#define CANARY_BASE_LO  0xACACACACACACACACULL
#define CANARY_BASE_MID 0xACACACACACACACACULL
#define CANARY_BASE_HI  ((unsigned short)0xACACu)

#define QUARANTINE_CAPACITY 8

typedef struct block_hdr {
    unsigned long   size;    // полный размер блока, ВКЛЮЧАЯ заголовок (см. выше)
    unsigned long   free;    // 1 = свободен И виден kmalloc() (не в карантине)
    struct block_hdr *next;  // следующий блок в free-list (если free=1)
    unsigned long   magic;   // HEAP_MAGIC_*
    tag144_t        tag;     // 144-битный тег текущего поколения блока
} block_hdr;

#define HDR_SIZE ((unsigned long)sizeof(block_hdr))

// Минимальный остаток при split: должен вместить заголовок + redzone +
// хоть немного данных + канарейку следующего блока, иначе не разбиваем.
#define MIN_SPLIT (HDR_SIZE + RZONE_SIZE + 16UL + CANARY_SIZE)

static block_hdr *free_list = 0;   // голова free-list
static unsigned long arena_end = 0;// конец текущей арены (для расширения)

static block_hdr *quarantine[QUARANTINE_CAPACITY];
static unsigned int quarantine_count = 0;
static unsigned int quarantine_pos   = 0;

static unsigned long tag_prng_state = 0;

static inline unsigned long rdtime(void) {
    unsigned long t;
    __asm__ volatile("csrr %0, time" : "=r"(t));
    return t;
}

// xorshift64 - не криптографический ГПСЧ, нужен только разброс тегов между
// поколениями одного и того же адреса, не сопротивление атакующему,
// который уже читает память ядра. Канонические сдвиги для 64-битного слова
// (13, 7, 17).
static unsigned long xorshift64_step(void) {
    if (tag_prng_state == 0) {
        tag_prng_state = rdtime() ^ 0x9E3779B97F4A7C15UL;
        if (tag_prng_state == 0) tag_prng_state = 1UL;
    }
    tag_prng_state ^= rdtime();
    tag_prng_state ^= tag_prng_state << 13;
    tag_prng_state ^= tag_prng_state >> 7;
    tag_prng_state ^= tag_prng_state << 17;
    return tag_prng_state ? tag_prng_state : 1UL;
}

static tag144_t next_tag(void) {
    tag144_t t;
    t.lo  = xorshift64_step();
    t.mid = xorshift64_step();
    t.hi  = (unsigned short)(xorshift64_step() & 0xFFFFu);
    if (tag144_is_zero(t)) t.lo = 1;
    return t;
}

static tag144_t tagged_canary144(tag144_t tag) {
    tag144_t c;
    c.lo  = CANARY_BASE_LO  ^ tag.lo;
    c.mid = CANARY_BASE_MID ^ tag.mid;
    c.hi  = (unsigned short)(CANARY_BASE_HI ^ tag.hi);
    return c;
}

static void heap_corrupted(const char *why) {
    uart_puts("\r\n\033[31m*** HEAP CORRUPTION: ");
    uart_puts(why);
    uart_puts(" ***\r\nSystem halted.\033[0m\r\n");
    while (1) __asm__ volatile("wfi");
}

// Добавляет одну страницу к арене, создаёт в ней один свободный блок
static int arena_grow(void) {
    void *page = alloc_page();
    if (!page) return 0;

    block_hdr *blk = (block_hdr *)page;
    blk->size  = PAGE_SIZE;
    blk->free  = 1;
    blk->magic = HEAP_MAGIC_FREE;
    blk->tag   = tag144_zero();
    blk->next  = free_list;
    free_list  = blk;
    arena_end  = (unsigned long)page + PAGE_SIZE;
    return 1;
}

void heap_init(void) {
    free_list = 0;
    quarantine_count = 0;
    quarantine_pos   = 0;
    for (unsigned int i = 0; i < HEAP_INIT_PAGES; i++) {
        if (!arena_grow()) break;
    }
    uart_puts("[heap] initialized (");
    // print arena size
    unsigned long sz = HEAP_INIT_PAGES * PAGE_SIZE / 1024;
    char buf[10]; int bi = 0;
    while (sz) { buf[bi++] = '0' + (sz % 10); sz /= 10; }
    for (int j = bi-1; j >= 0; j--) uart_putc(buf[j]);
    uart_puts(" KB arena, tagged+redzone free-list allocator)\r\n");
}

void *kmalloc(unsigned long size) {
    if (!size) return 0;

    // Выравниваем полезные данные на 16 байт и добавляем заголовок,
    // левую redzone и канарейку.
    unsigned long want = (size + 15) & ~15UL;
    unsigned long need = HDR_SIZE + RZONE_SIZE + want + CANARY_SIZE;

    // Ищем первый подходящий свободный блок (first-fit)
    block_hdr **pp = &free_list;
    while (*pp) {
        block_hdr *b = *pp;
        if (b->size >= need) {
            // Разбиваем блок если остаток достаточно велик
            if (b->size >= need + MIN_SPLIT) {
                block_hdr *rest = (block_hdr *)((unsigned long)b + need);
                rest->size  = b->size - need;
                rest->free  = 1;
                rest->magic = HEAP_MAGIC_FREE;
                rest->tag   = tag144_zero();
                rest->next  = b->next;
                b->size = need;
                *pp = rest;
            } else {
                *pp = b->next;
            }

            tag144_t tag = next_tag();
            b->free  = 0;
            b->magic = HEAP_MAGIC_ALLOC;
            b->tag   = tag;
            b->next  = 0;

            unsigned char *lzone = (unsigned char *)b + HDR_SIZE;
            for (unsigned long i = 0; i < RZONE_SIZE; i++) lzone[i] = RZONE_BYTE;

            // Канарейка - у фактической границы блока (b->size), а не у
            // запрошенного size: в неразбитом случае "хвост" остаётся
            // частью этого же блока (как и в исходном алгоритме до
            // хардненинга), и канарейка должна стоять там, иначе free()
            // проверял бы не ту область.
            void *ptr = (void *)(lzone + RZONE_SIZE);
            unsigned long user_span = b->size - HDR_SIZE - RZONE_SIZE - CANARY_SIZE;
            *(tag144_t *)((unsigned char *)ptr + user_span) = tagged_canary144(tag);

            return ptr;
        }
        pp = &b->next;
    }

    // Нет подходящего блока — расширяем арену
    if (!arena_grow()) return 0;
    return kmalloc(size);  // повторная попытка
}

// Возвращает блок в обычный free-list: физическое слияние со следующим
// соседом (тот же однопроходный алгоритм, что был здесь до хардненинга) +
// отравление данных. Вызывается ТОЛЬКО при вытеснении из карантина.
static void release_from_quarantine(block_hdr *blk) {
    unsigned char *payload   = (unsigned char *)blk + HDR_SIZE + RZONE_SIZE;
    unsigned long  user_span = blk->size - HDR_SIZE - RZONE_SIZE - CANARY_SIZE;
    for (unsigned long i = 0; i < user_span; i++) payload[i] = 0xDD;

    blk->free  = 1;
    blk->magic = HEAP_MAGIC_FREE;
    blk->tag   = tag144_zero();

    blk->next = free_list;
    free_list = blk;

    block_hdr *next_phys = (block_hdr *)((unsigned long)blk + blk->size);
    if ((unsigned long)next_phys < arena_end && next_phys->free) {
        block_hdr **pp = &free_list;
        while (*pp && *pp != next_phys) pp = &(*pp)->next;
        if (*pp) *pp = next_phys->next;
        blk->size += next_phys->size;
    }
}

static void quarantine_push(block_hdr *blk) {
    if (quarantine_count == QUARANTINE_CAPACITY) {
        release_from_quarantine(quarantine[quarantine_pos]);
    } else {
        quarantine_count++;
    }
    quarantine[quarantine_pos] = blk;
    quarantine_pos = (quarantine_pos + 1) % QUARANTINE_CAPACITY;
}

void kfree(void *ptr) {
    if (!ptr) return;

    block_hdr *blk = (block_hdr *)((unsigned long)ptr - RZONE_SIZE - HDR_SIZE);

    if (blk->magic == HEAP_MAGIC_FREE || blk->magic == HEAP_MAGIC_QUARANTINE)
        heap_corrupted("double free()");
    if (blk->magic != HEAP_MAGIC_ALLOC)
        heap_corrupted("free() on invalid/foreign pointer");

    unsigned char *lzone = (unsigned char *)blk + HDR_SIZE;
    for (unsigned long i = 0; i < RZONE_SIZE; i++)
        if (lzone[i] != RZONE_BYTE) heap_corrupted("buffer underflow (left redzone)");

    unsigned long user_span = blk->size - HDR_SIZE - RZONE_SIZE - CANARY_SIZE;
    tag144_t canary = *(tag144_t *)((unsigned char *)ptr + user_span);
    if (!tag144_eq(canary, tagged_canary144(blk->tag)))
        heap_corrupted("buffer overflow (canary)");

    // В карантин, а не сразу в free-list - не трогаем данные блока здесь
    // (только что прочитанная канарейка - последнее чтение).
    blk->magic = HEAP_MAGIC_QUARANTINE;
    quarantine_push(blk);
}

unsigned long heap_free_bytes(void) {
    unsigned long total = 0;
    block_hdr *b = free_list;
    while (b) { total += b->size - HDR_SIZE; b = b->next; }
    return total;
}
