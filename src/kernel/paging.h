#ifndef PAGING_H
#define PAGING_H

// Физические адреса глобального Page Directory/Page Table (identity-map
// первых 4 МБ, см. init_paging). Используются также в tasking.c как
// "общий" page_directory для задач без изоляции (task0/heartbeat/ring3demo).
#define PAGE_DIRECTORY ((unsigned int*)0x9C000)
#define PAGE_TABLE     ((unsigned int*)0x9D000)

// Пул приватных PD/PT для изолированных ring3-задач (команда "run") - по
// одной паре 4КБ+4КБ на каждый USER_PROGRAM_SLOTS (kernel.c). Лежит сразу
// после слотов пользовательских программ (0x100000-0x120000) - НЕ в
// 0xA0000-0xBFFFF, это апертура видеопамяти VGA (MMIO в QEMU), а не RAM.
#define PD_POOL_BASE 0x120000
#define PT_POOL_BASE 0x124000

// Включает paging с identity-mapping первых 4 МБ (виртуальный адрес = физический).
// Страницы, целиком занятые кодом ядра (.text), помечаются как read-only,
// а CR0.WP=1 заставляет процессор соблюдать этот запрет даже в ring0.
void init_paging();

// Обработчик исключения #14 (Page Fault), см. idt.asm
extern void page_fault_handler();

// Строит приватный Page Directory/Page Table для изолированной ring3-задачи
// (команда "run", user_slot_index = 0..USER_PROGRAM_SLOTS-1): копия
// глобальной PT с PAGE_USER=0 везде, кроме окна 0x100000-0x108000, которое
// переотображается на phys_slot_base..+0x8000 (PRESENT|RW|USER). Возвращает
// физический адрес приватного PD (для CR3).
unsigned int paging_create_user_directory(int user_slot_index, unsigned int phys_slot_base);

#endif
