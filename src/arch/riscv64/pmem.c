#include "pmem.h"
#include "drivers/uart.h"

// Простой bump-аллокатор физических страниц.
//
// Принцип: «указатель next» идёт только вперёд; free_page пока не реализован.
// Этого достаточно для загрузки таблиц страниц, heap, стека пользователя.
// Настоящий buddy/slab подключим, когда понадобится reclaim памяти.

static unsigned long next_free;  // следующий свободный физический адрес
static unsigned long mem_end;    // конец RAM (не включая)
static unsigned long total;      // всего страниц при инициализации

// Простой hex-print без зависимости от stdio
static void put_hex(unsigned long v, int digits) {
    for (int s = (digits - 1) * 4; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(v >> s) & 0xF]);
}
static void put_dec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int j = i - 1; j >= 0; j--) uart_putc(buf[j]);
}

void pmem_init(unsigned long start, unsigned long end) {
    // Выравниваем start на PAGE_SIZE
    next_free = (start + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    mem_end   = end & ~(PAGE_SIZE - 1);
    total     = (mem_end - next_free) / PAGE_SIZE;

    uart_puts("[pmem] free: 0x"); put_hex(next_free, 8);
    uart_puts(" .. 0x");         put_hex(mem_end, 8);
    uart_puts("  (");            put_dec(total);
    uart_puts(" pages = ");      put_dec(total * PAGE_SIZE / (1024 * 1024));
    uart_puts(" MB)\r\n");
}

void *alloc_page(void) {
    if (next_free + PAGE_SIZE > mem_end) {
        uart_puts("[alloc_page] OOM! next_free=0x");
        put_hex(next_free, 8);
        uart_puts(" mem_end=0x");
        put_hex(mem_end, 8);
        uart_puts("\r\n");
        return 0;
    }
    void *page = (void *)next_free;
    next_free += PAGE_SIZE;

    // Обнуляем страницу (важно для таблиц страниц — нули = invalid PTE)
    unsigned long *p = (unsigned long *)page;
    for (unsigned long i = 0; i < PAGE_SIZE / 8; i++)
        p[i] = 0;

    return page;
}

// Stub — bump не умеет освобождать; понадобится при добавлении buddy
void free_page(void *page) { (void)page; }

unsigned long pmem_free_pages(void) {
    return (mem_end - next_free) / PAGE_SIZE;
}

unsigned long pmem_total_pages(void) {
    return total;
}
