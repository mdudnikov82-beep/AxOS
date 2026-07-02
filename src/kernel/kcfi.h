#ifndef KCFI_H
#define KCFI_H

// =================================================================
//  Kernel CFI (Forward-edge Control Flow Integrity)
// =================================================================
//
// GrapheneOS использует LLVM CFI: тип-классовая проверка («функция
// должна иметь нужную сигнатуру» — 1 из N валидных целей).
//
// AxOS kcfi: 1-to-1 binding + cookie-аутентификация + RO-страница:
//   - каждый слот таблицы привязан ровно к ОДНОЙ функции (сильнее)
//   - cookie = master_key ^ fn_ptr ^ slot*prime (32-bit auth)
//   - вся CFI-таблица (shadow + cookies) хранится в странице без W
//     (paging_mark_kernel_ro) → CR0.WP=1 запрещает запись ring0
//
// Атака:                 LLVM CFI  AxOS CFI
//   подмена fn_ptr       50% (тип) 0% (1-to-1 + RO table)
//   угадать cookie                 2^-32 (~0)
//   перезапись cfi_tbl             page fault (RO page)

// Инициализация: читает syscall_table[0..n-1], генерирует master_key
// (RDTSC+ESP), заполняет теневую таблицу + cookies, запечатывает
// страницу (read-only).  Вызвать ПОСЛЕ init_paging().
void kcfi_init(void** fn_table, unsigned int n);

// Проверка перед косвенным вызовом fn через слот slot.
// При нарушении: печатает "[CFI] forward-edge violation", убивает
// задачу (если изолирована) или halt (если ядро).
void kcfi_check(unsigned char slot, void* fn);

#endif
