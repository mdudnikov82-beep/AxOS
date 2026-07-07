#pragma once

// Инициализирует kernel heap.
// Берёт страницы из pmem; изначально выделяет HEAP_INIT_PAGES.
void heap_init(void);

// Выделяет size байт из kernel heap.
// Возвращает NULL при нехватке памяти.
void *kmalloc(unsigned long size);

// Освобождает блок, выделенный kmalloc.
void  kfree(void *ptr);

// Сколько байт осталось в текущей арене (для отладки)
unsigned long heap_free_bytes(void);
