#pragma once

#define PAGE_SIZE   4096UL
#define PAGE_SHIFT  12

// Инициализирует аллокатор физических страниц.
// start — первый свободный адрес (обычно _kernel_end, выровненный на PAGE_SIZE).
// end   — конец доступной RAM.
void  pmem_init(unsigned long start, unsigned long end);

// Выделяет одну физическую страницу (4 KB) и возвращает её адрес.
// Возвращает 0 при нехватке памяти (OOM).
void *alloc_page(void);

// Освобождает страницу, выделенную alloc_page.
// Текущая реализация — нет (bump). Будет нужна для свопа/COW позже.
void  free_page(void *page);

// Статистика
unsigned long pmem_free_pages(void);
unsigned long pmem_total_pages(void);
