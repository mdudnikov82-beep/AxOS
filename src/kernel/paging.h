#ifndef PAGING_H
#define PAGING_H

// Включает paging с identity-mapping первых 4 МБ (виртуальный адрес = физический).
// Страницы, целиком занятые кодом ядра (.text), помечаются как read-only,
// а CR0.WP=1 заставляет процессор соблюдать этот запрет даже в ring0.
void init_paging();

// Обработчик исключения #14 (Page Fault), см. idt.asm
extern void page_fault_handler();

#endif
