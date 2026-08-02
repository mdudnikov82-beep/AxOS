#ifndef PAGING_H
#define PAGING_H

// 4-уровневая страничная адресация (PML4 → PDPT → PD → PT).
// Глобальные таблицы (identity-map первых 4 МБ + 32 МБ кучи + пул
// изолированных задач, см. ниже):
//   0x9C000 - PML4 (512 × 8Б) — CR3 для ядровых задач
//   0x9D000 - PDPT (512 × 8Б)
//   0x9E000 - PD   (512 × 8Б): [0] → PT0, [1]/[2] = 2МБ huge pages (2-6МБ,
//                              фиксировано - [2] нужен с тех пор, как
//                              FAT12 выросла до 2МБ, см. FAT12_BASE в
//                              fat12.c),
//                              [g_kheap_pd_index..+KHEAP_PAGES-1] = куча,
//                              [g_pool_pd_index] = пул изолированных задач
//                              (оба - KASLR, случайные каждую загрузку)
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
// PAE_USER), с NX (данные, не код, как и PD[1]). QEMU запускается с
// -m 512M (было QEMU-default 128МБ - см. подробный разбор у
// kheap_pick_pd_index() в paging.c, включая реальный overlap-баг со
// старым 128МБ диапазоном, найденный и исправленный при этом
// расширении) - 32МБ кучи по-прежнему солидный запас, детектирование
// реального объёма RAM не требуется (BIOS E820 тут не читается).
//
// KASLR: база кучи не константа - g_kheap_base выбирается случайно при
// каждой загрузке в init_paging() (см. paging.c) - диапазон кандидатов
// теперь [3,223) (было [3,48) при 128МБ RAM - см. kheap_pick_pd_index()
// в paging.c за тем, ПОЧЕМУ РАЗВОДИТЬ VA/PA ради ещё большей энтропии
// нельзя (пробовали - нашли реальный double fault, откатили), и почему
// РАСШИРЕНИЕ RAM - безопасная альтернатива). Куча остаётся
// identity-mapped (VA==PA), как и всегда. Полноценный KASLR (случайный
// адрес ЗАГРУЗКИ самого ядра) недостижим без position-independent
// линковки (kernel.ld/user.ld жёстко линкуют на фиксированные адреса,
// десятки мест в коде на них ссылаются напрямую) - слишком большая
// переделка. Эксплойт, захардкоженный под 0x400000 (старое фиксированное
// значение), промахивается мимо кучи на следующей загрузке.
extern unsigned long long g_kheap_base;
#define KHEAP_PAGES  16                       // 16 × 2МБ = 32МБ
#define KHEAP_SIZE   (KHEAP_PAGES * 0x200000ULL)

// CR3 для ядровых задач (task0 / heartbeat) = адрес GLOBAL_PML4.
#define PAGE_DIRECTORY 0x9C000ULL

// Пул приватных PML4/PDPT/PD/PT для изолированных ring3-задач (до 4 штук).
// Раньше жил на фиксированных 0x140000-0x14FFFF - внутри первых 2МБ,
// которые целиком копируются (GLOBAL_PT0 -> dst_pt) в КАЖДУЮ изолированную
// задачу, так что доступность пула под чужим CR3 доставалась "бесплатно",
// как побочный эффект.
//
// KASLR: пул переехал в свою собственную 2МБ huge page на случайном
// PD-слоте (g_pool_base, выбирается в init_paging() отдельно от кучи -
// см. её комментарий у g_kheap_base; зона кандидатов пула [223,255)
// disjoint от зоны кучи [3,223) ПО ПОСТРОЕНИЮ, с учётом того, что куча
// занимает 16 слотов подряд от своего старта - см. kheap_pick_pd_index()/
// kpool_pick_pd_index() в paging.c за точным разбором зон и за реальным
// overlap-багом в СТАРОМ [3,48)/[48,64) варианте, который не учитывал
// ширину кучи. Обе зоны остаются внутри QEMU-шных 512МБ RAM (-m 512M -
// см. run.bat/qemu_test_helpers.py). Раз пул
// больше не часть первых 2МБ, его PD-запись теперь ЯВНО копируется в
// каждую изолированную задачу в paging_create_user_directory() - иначе
// первый же run() ИЗНУТРИ уже запущенной изолированной задачи (например,
// `run X` в AxSH, а сам SH.BIN - тоже изолированная задача) поймал бы #PF
// прямо в момент записи новых таблиц в пул.
//
// Слоты (4 штуки) размещены внутри этой 2МБ страницы по тем же смещениям,
// что раньше были абсолютными адресами:
//   PML4_POOL: +0x0000..+0x3FFF (4 × 4КБ)
//   PDPT_POOL: +0x4000..+0x7FFF
//   PD_POOL:   +0x8000..+0xBFFF
//   PT_POOL:   +0xC000..+0xFFFF
extern unsigned long long g_pool_base;
#define POOL_PML4_OFF 0x0000ULL
#define POOL_PDPT_OFF 0x4000ULL
#define POOL_PD_OFF   0x8000ULL
#define POOL_PT_OFF   0xC000ULL

// Виртуальное окно пользователя [USER_WINDOW_BASE, +SIZE) - см. memmap.h
// (централизованная карта адресов + _Static_assert на непересечение).
#include "memmap.h"
// USER_SPIN_ADDR — последние 2 байта окна: "jmp $" (EB FE) для spin.
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
