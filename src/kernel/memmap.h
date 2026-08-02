#pragma once

// =================================================================
//  Централизованная карта фиксированных физических адресов (kernel.exe,
//  paging-based - НЕ kernel_gfx.exe/kernel_shell.exe, у них своя,
//  несвязанная раскладка, см. project_x86_kernel_merge_infeasible).
// =================================================================
//
// Раньше эти константы были независимо разбросаны по kernel.c/screen.c/
// paging.h с собственными #define - никакой компиляторской/рантайм
// проверки на пересечение НЕ было. За время разработки это уже ДВАЖДЫ
// приводило к реальным багам с тихой порчей памяти:
//   - FAT12_BASE наезжал на USER_PROGRAM_BASE (см. память проекта,
//     project_fat12_user_conflict)
//   - TTYS_BASE лежал ВНУТРИ ELF_STAGING_BASE (см. подробный разбор в
//     screen.c у struct tty_state - реальный, живьём подтверждённый
//     баг с порчей второй консоли, project_ttys_elf_staging_overlap)
// Теперь одно место + _Static_assert на непересечение соседних
// регионов - компилятор ловит будущий сдвиг ДО того, как он станет
// живым багом, а не постфактум через отладку испорченной памяти.
//
// FAT12_BASE - особый случай: fs/fat12.c переопределяет его через -D
// для сборок БЕЗ paging (kernel_gfx.exe/kernel_shell.exe, своя
// раскладка). Этот файл НЕ включается в те сборки (memmap.h нужен
// только kernel.c/screen.c/tss.c/paging.h - все три файла существуют
// ТОЛЬКО в kernel.exe), так что здесь всегда действует именно paging-
// раскладка. Значение ниже должно вручную совпадать со значением по
// умолчанию в fs/fat12.c (там #ifndef FAT12_BASE / 0x300000) - это
// единственная оставшаяся ручная синхронизация, задокументированная
// явно, а не молчаливая, как было раньше.

#define TSS_BASE           0x9B000UL

#define USER_WINDOW_BASE   0x100000UL
#define USER_WINDOW_PAGES  16
#define USER_WINDOW_SIZE   (USER_WINDOW_PAGES * 0x1000UL)

#define USER_PROGRAM_BASE      0x200000UL
#define USER_PROGRAM_SLOT_SIZE 0x10000UL
#define USER_PROGRAM_SLOTS     4
#define USER_PROGRAM_END       (USER_PROGRAM_BASE + (unsigned long)USER_PROGRAM_SLOTS * USER_PROGRAM_SLOT_SIZE)

#define USER_ARGS_OFFSET   0xF800UL
#define ELF_STAGING_BASE   0x150000UL
#define ELF_STAGING_SIZE   (USER_ARGS_OFFSET + 0x200UL)

#define TTYS_BASE          0x160000UL

#define FAT12_BASE         0x300000UL  // должно совпадать с default в fs/fat12.c - см. коммент выше

// --- Проверки непересечения соседних регионов - компилятор ловит любой
// будущий сдвиг констант выше, который случайно наложит один регион на
// другой (ровно та проверка, которой не было при ОБОИХ реальных багах). ---
_Static_assert(TSS_BASE + 0x1000UL <= USER_WINDOW_BASE,
               "memmap: TSS_BASE наезжает на USER_WINDOW_BASE");
_Static_assert(USER_WINDOW_BASE + USER_WINDOW_SIZE <= ELF_STAGING_BASE,
               "memmap: USER_WINDOW наезжает на ELF_STAGING_BASE");
_Static_assert(ELF_STAGING_BASE + ELF_STAGING_SIZE <= TTYS_BASE,
               "memmap: ELF_STAGING наезжает на TTYS_BASE (см. project_ttys_elf_staging_overlap)");
_Static_assert(USER_PROGRAM_END <= FAT12_BASE,
               "memmap: USER_PROGRAM слоты наезжают на FAT12_BASE (см. project_fat12_user_conflict)");
