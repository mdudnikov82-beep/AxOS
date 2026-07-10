// Stack canary для -fstack-protector (GCC).
// GCC читает __stack_chk_guard в прологе защищённой функции и проверяет
// его в эпилоге. Если значение изменилось — вызывается __stack_chk_fail.
//
// Инициализация происходит в crt0.asm, до вызова main(), вызовом
// ax_init_stack_guard(). Это важно: main() сам защищён канарейкой,
// поэтому значение должно быть установлено до его пролога.

#include "../include/axiom.h"

unsigned int __stack_chk_guard;

void ax_init_stack_guard(void) {
    // XOR с константой гарантирует ненулевое значение даже при ticks=0.
    __stack_chk_guard = ax_get_ticks() ^ 0x4158494Du; // "AXIM"
}

void __stack_chk_fail(void) {
    ax_print("\033[31m*** STACK SMASH DETECTED ***\033[0m\n");
    ax_exit(-1);
}
