#ifndef PAGING_H
#define PAGING_H

// PAE (Physical Address Extension) включён в init_paging().
// Структуры: PDPT (4 × 8B) → PD (512 × 8B) → PT (512 × 8B).
// Бит 63 каждой PTE = XD (Execute-Disable / NX), если EFER.NXE=1.
//
// Глобальные таблицы (identity-map первых 4 МБ):
//   0x9C000 - PDPT (4 записей × 8Б)
//   0x9D000 - PD   (512 записей × 8Б)
//   0x9E000 - PT0  (512 записей × 8Б, VA 0x000000-0x1FFFFF)
//   0x9F000 - PT1  (512 записей × 8Б, VA 0x200000-0x3FFFFF)
#define GLOBAL_PDPT ((unsigned long long*)0x9C000)
#define GLOBAL_PD   ((unsigned long long*)0x9D000)
#define GLOBAL_PT0  ((unsigned long long*)0x9E000)
#define GLOBAL_PT1  ((unsigned long long*)0x9F000)

// PAGE_DIRECTORY остаётся 0x9C000 - теперь это физический адрес PDPT
// (в PAE режиме CR3 = адрес PDPT, не PD). Используется в tasking.c для
// нерасщеплённых задач (task0/heartbeat).
#define PAGE_DIRECTORY ((unsigned int*)0x9C000)

// Пул приватных PDPT/PD/PT для изолированных ring3-задач (команда "run").
// Лежит сразу за слотами пользовательских программ (0x100000-0x13FFFF).
//   PDPT_POOL_BASE: 4 слота × 32Б = 128Б (всё в первой странице 0x140000)
//   PD_POOL_BASE:   4 слота × 4КБ = 16КБ (0x141000-0x145000)
//   PT_POOL_BASE:   4 слота × 4КБ = 16КБ (0x145000-0x149000)
#define PDPT_POOL_BASE 0x140000
#define PD_POOL_BASE   0x141000
#define PT_POOL_BASE   0x145000

// Виртуальное окно пользователя [USER_WINDOW_BASE, USER_WINDOW_BASE+SIZE).
// USER_SPIN_ADDR - последние 2 байта окна: "jmp $" (EB FE) для безопасного
// ожидания реапа изолированной задачи (page_fault_handler_main -> schedule).
// Последняя страница (страница 15, VA 0x10F000-0x10FFFF) - "spin page":
// всегда RW+X, даже при W^X, т.к. содержит аргументы/стек И spin-код.
#define USER_WINDOW_BASE  0x100000
#define USER_WINDOW_PAGES 16
#define USER_WINDOW_SIZE  (USER_WINDOW_PAGES * 0x1000)
#define USER_SPIN_ADDR    (USER_WINDOW_BASE + USER_WINDOW_SIZE - 2)

// Включает PAE-страничную адресацию (3-уровневые таблицы, 8Б PTE).
// При поддержке ЦП (CPUID.80000001H:EDX[20]) включает NX/XD.
// Страницы .text ядра помечаются read-only (CR0.WP=1 блокирует запись
// даже из ring0). Страницы данных ядра помечаются NX (не исполняемые).
void init_paging();

// Обработчик исключения #14 (Page Fault), см. idt.asm
extern void page_fault_handler();

// Строит приватный PDPT/PD/PT для изолированной ring3-задачи:
//   - Копия глобальной PT0 без PAGE_USER (ядро невидимо для ring3)
//   - Окно USER_WINDOW_BASE..+SIZE переотображается на phys_slot_base
//   - W^X: страницы кода (байты слота < wx_delta+wx_data_off) → R+X, без записи
//          страницы данных (байты слота >= wx_delta+wx_data_off) → RW+NX
//          spin-страница (последняя) → всегда RW+X
//   - wx_data_off=0 → W^X отключён (fallback: все страницы RW, без NX)
// Возвращает физический адрес приватного PDPT (для CR3).
unsigned int paging_create_user_directory(int user_slot_index,
                                           unsigned int phys_slot_base,
                                           unsigned int wx_delta,
                                           unsigned int wx_data_off);

#endif
