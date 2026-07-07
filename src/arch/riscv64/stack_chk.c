// Stack canary для -fstack-protector-strong (см. KFLAGS в build_riscv.bat).
//
// Зеркалит src/kernel/stack_chk.c (x86-64 ядро). GCC читает
// __stack_chk_guard в прологе каждой защищённой функции (сохраняет в
// кадре) и сравнивает в эпилоге; расхождение -> вызывается
// __stack_chk_fail(). До сих пор у RV64-ядра этой защиты не было вообще -
// build_riscv.bat собирал его с -fno-stack-protector, в отличие от
// x86-ядра (уже -fstack-protector-strong).
//
// Проверено разбором `gcc -S` на этом тулчейне: __stack_chk_guard
// читается как обычный PC-relative глобальный символ
// (`lla a5, __stack_chk_guard; ld a4, 0(a5)`), без TLS/tp - значит
// обычная 64-битная глобальная переменная корректна. В отличие от
// x86-ядра (MinGW/LLP64, где "unsigned long" - только 32 бита, и
// понадобился "unsigned long long"), на RV64 (lp64 ABI) "unsigned long"
// сам по себе честные 64 бита - трюк с расширением не нужен.
//
// kernel_init_stack_guard() ОБЯЗАНА быть первым вызовом в kernel_main(),
// до вообще любого другого кода - иначе первые же защищённые функции
// получили бы нулевой (BSS) canary вместо случайного.

unsigned long __stack_chk_guard;

// Не timer_ticks и не SBI-таймер: должна работать ДО timer_init()/любой
// другой инициализации. CSR `time` - свободно бегущий счётчик CLINT,
// читается сразу после сброса CPU, без какой-либо настройки.
static inline unsigned long read_time_early(void) {
    unsigned long t;
    __asm__ volatile("csrr %0, time" : "=r"(t));
    return t;
}

void kernel_init_stack_guard(void) {
    __stack_chk_guard = read_time_early() ^ 0x9E3779B97F4A7C15UL;
    if (__stack_chk_guard == 0) __stack_chk_guard = 0x9E3779B97F4A7C15UL;
}

#include "drivers/uart.h"

void __stack_chk_fail(void) {
    uart_puts("\r\n\033[31m*** STACK SMASHING DETECTED ***\r\nSystem halted.\033[0m\r\n");
    while (1) __asm__ volatile("wfi");
}
