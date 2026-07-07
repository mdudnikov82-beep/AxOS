#include "heap.h"
#include "pmem.h"
#include "drivers/uart.h"

// Kernel heap — free-list аллокатор поверх физических страниц.
//
// Схема:
//   • Арена — непрерывный регион из нескольких страниц, взятых через alloc_page().
//   • Каждый блок предваряется заголовком block_hdr (16 байт).
//   • Свободные блоки связаны в односвязный free-list.
//   • При нехватке места в текущей арене — расширяем на одну страницу.
//
// 16-байтный заголовок: size включает заголовок, next — следующий свободный блок.

#define HEAP_INIT_PAGES  4          // 16 KB при старте
#define HDR_SIZE         16UL       // sizeof(block_hdr), выровненный на 16
#define MIN_SPLIT        (HDR_SIZE + 16)  // минимальный остаток при split

typedef struct block_hdr {
    unsigned long   size;   // полный размер блока, включая заголовок
    unsigned long   free;   // 1 = свободен, 0 = занят
    struct block_hdr *next; // следующий блок в free-list (если free=1)
    unsigned long   _pad;   // выравнивание заголовка на 16 байт
} block_hdr;

static block_hdr *free_list = 0;   // голова free-list
static unsigned long arena_end = 0;// конец текущей арены (для расширения)

// Добавляет одну страницу к арене, создаёт в ней один свободный блок
static int arena_grow(void) {
    void *page = alloc_page();
    if (!page) return 0;

    block_hdr *blk = (block_hdr *)page;
    blk->size = PAGE_SIZE;
    blk->free = 1;
    blk->next = free_list;
    blk->_pad  = 0;
    free_list = blk;
    arena_end = (unsigned long)page + PAGE_SIZE;
    return 1;
}

void heap_init(void) {
    free_list = 0;
    for (unsigned int i = 0; i < HEAP_INIT_PAGES; i++) {
        if (!arena_grow()) break;
    }
    uart_puts("[heap] initialized (");
    // print arena size
    unsigned long sz = HEAP_INIT_PAGES * PAGE_SIZE / 1024;
    char buf[10]; int bi = 0;
    while (sz) { buf[bi++] = '0' + (sz % 10); sz /= 10; }
    for (int j = bi-1; j >= 0; j--) uart_putc(buf[j]);
    uart_puts(" KB arena, free-list allocator)\r\n");
}

void *kmalloc(unsigned long size) {
    if (!size) return 0;

    // Выравниваем запрос на 16 байт и добавляем заголовок
    unsigned long need = ((size + 15) & ~15UL) + HDR_SIZE;

    // Ищем первый подходящий свободный блок (first-fit)
    block_hdr **pp = &free_list;
    while (*pp) {
        block_hdr *b = *pp;
        if (b->size >= need) {
            // Разбиваем блок если остаток достаточно велик
            if (b->size >= need + MIN_SPLIT) {
                block_hdr *rest = (block_hdr *)((unsigned long)b + need);
                rest->size = b->size - need;
                rest->free = 1;
                rest->next = b->next;
                rest->_pad  = 0;
                b->size = need;
                *pp = rest;
            } else {
                *pp = b->next;
            }
            b->free = 0;
            b->next = 0;
            return (void *)((unsigned long)b + HDR_SIZE);
        }
        pp = &b->next;
    }

    // Нет подходящего блока — расширяем арену
    if (!arena_grow()) return 0;
    return kmalloc(size);  // повторная попытка
}

void kfree(void *ptr) {
    if (!ptr) return;

    block_hdr *blk = (block_hdr *)((unsigned long)ptr - HDR_SIZE);
    blk->free = 1;

    // Добавляем в голову free-list (O(1))
    blk->next = free_list;
    free_list = blk;

    // Простое слияние: если следующий блок в памяти тоже свободен, объединяем.
    // Только один проход — для полного coalescing нужен двусвязный список.
    block_hdr *next_phys = (block_hdr *)((unsigned long)blk + blk->size);
    if ((unsigned long)next_phys < arena_end && next_phys->free) {
        // Удаляем next_phys из free-list
        block_hdr **pp = &free_list;
        while (*pp && *pp != next_phys) pp = &(*pp)->next;
        if (*pp) *pp = next_phys->next;
        blk->size += next_phys->size;
    }
}

unsigned long heap_free_bytes(void) {
    unsigned long total = 0;
    block_hdr *b = free_list;
    while (b) { total += b->size - HDR_SIZE; b = b->next; }
    return total;
}
