#ifndef PAGING_H
#define PAGING_H

// 4-уровневая страничная адресация (PML4 → PDPT → PD → PT).
// Глобальные таблицы (identity-map первых 4 МБ + 32 МБ кучи, см. ниже):
//   0x9C000 - PML4 (512 × 8Б) — CR3 для ядровых задач
//   0x9D000 - PDPT (512 × 8Б)
//   0x9E000 - PD   (512 × 8Б): [0] → PT0, [1] = 2МБ huge page (2-4МБ),
//                              [2..2+KHEAP_PAGES-1] = 2МБ huge pages кучи
//   0x9F000 - PT0  (512 × 8Б, VA 0x000000-0x1FFFFF)
#define GLOBAL_PML4 ((unsigned long long*)0x9C000)
#define GLOBAL_PDPT ((unsigned long long*)0x9D000)
#define GLOBAL_PD   ((unsigned long long*)0x9E000)
#define GLOBAL_PT0  ((unsigned long long*)0x9F000)

// Куча ядра: раньше жила в 128КБ внутри тех же первых 4МБ (0x70000-0x90000,
// зажатая между FAT12-образом и стеком). PDPT[0] уже покрывает 1ГБ (512
// записей PD × 2МБ) - из них реально замаплены были только PD[0] и PD[1]
// (первые 4МБ), а PD[2..511] стояли занулёнными (not present), хотя сама
// 64-битная адресация (4-уровневые таблицы, 64-битные PTE) для этого
// диапазона доступна с самого init_paging(). Задействуем её: добавляем ещё
// KHEAP_PAGES × 2МБ huge pages сразу после первых 4МБ - ядро-only (без
// PAE_USER), с NX (данные, не код, как и PD[1]). QEMU по умолчанию даёт
// 128МБ RAM (see -m default) - 32МБ кучи оставляют солидный запас и не
// требуют детектирования реального объёма RAM (BIOS E820 тут не читается).
#define KHEAP_BASE   0x400000
#define KHEAP_PAGES  16                       // 16 × 2МБ = 32МБ
#define KHEAP_SIZE   (KHEAP_PAGES * 0x200000ULL)

// CR3 для ядровых задач (task0 / heartbeat) = адрес GLOBAL_PML4.
#define PAGE_DIRECTORY 0x9C000ULL

// Пул приватных PML4/PDPT/PD/PT для изолированных ring3-задач (до 4 штук).
// 0x140000-0x14FFFF: 4 слота × 4 таблицы × 4КБ = 64КБ.
//   PML4_POOL: 0x140000-0x143FFF (4 × 4КБ)
//   PDPT_POOL: 0x144000-0x147FFF
//   PD_POOL:   0x148000-0x14BFFF
//   PT_POOL:   0x14C000-0x14FFFF
#define PML4_POOL_BASE 0x140000
#define PDPT_POOL_BASE 0x144000
#define PD_POOL_BASE   0x148000
#define PT_POOL_BASE   0x14C000

// Виртуальное окно пользователя [USER_WINDOW_BASE, +SIZE).
// USER_SPIN_ADDR — последние 2 байта окна: "jmp $" (EB FE) для spin.
#define USER_WINDOW_BASE  0x100000
#define USER_WINDOW_PAGES 16
#define USER_WINDOW_SIZE  (USER_WINDOW_PAGES * 0x1000)
#define USER_SPIN_ADDR    (USER_WINDOW_BASE + USER_WINDOW_SIZE - 2)

// Включает 4-уровневую страничную адресацию.
// Настраивает GLOBAL_PT0 (4КБ страницы 0-2МБ), заменяет boot-huge-page.
// Включает NX/XD, SMEP, SMAP если поддерживаются ЦП.
void init_paging();

// SMAP: временно разрешить/запретить ring0 обращаться к user-страницам.
void smap_allow(void);
void smap_deny(void);

// Обработчик исключения #14 (Page Fault), cм. idt.asm.
extern void page_fault_handler();

// Строит приватный PML4/PDPT/PD/PT для изолированной ring3-задачи.
// Возвращает физический адрес PML4 (для CR3) как unsigned long long.
unsigned long long paging_create_user_directory(int user_slot_index,
                                                 unsigned int phys_slot_base,
                                                 unsigned int wx_delta,
                                                 unsigned int wx_data_off);

#endif
