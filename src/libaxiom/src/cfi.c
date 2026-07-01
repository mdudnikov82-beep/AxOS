// =================================================================
//  Software CFI (Control Flow Integrity) — backward-edge shadow stack
// =================================================================
//
// GCC -finstrument-functions вставляет вызовы __cyg_profile_func_enter /
// __cyg_profile_func_exit в пролог и эпилог каждой C-функции в программе.
//
// На входе сохраняем call_site (адрес возврата, он же compile-time константа
// в коде вызывающего) в shadow stack.
//
// На выходе читаем ФАКТИЧЕСКИЙ адрес возврата со стека через EBP-цепочку:
//   *(EBP_exit)  = EBP инструментируемой функции  (сохранён нашим прологом)
//   *(foo_EBP+4) = адрес возврата foo на стеке
//
// Если атакующий перезаписал return address через переполнение буфера,
// actual != expected → CFI violation → процесс немедленно убивается.
//
// Требования:
//   - GCC -O0 (фрейм EBP всегда поддерживается — флаг не нужен)
//   - libaxiom компилируется БЕЗ -finstrument-functions (нет рекурсии)
//   - Пользовательские .c файлы компилируются С -finstrument-functions

#include "../include/axiom.h"

#define CFI_DEPTH 256

static unsigned int __cfi_shadow[CFI_DEPTH];
static unsigned int __cfi_top = 0;

__attribute__((no_instrument_function))
void __cyg_profile_func_enter(void* this_fn, void* call_site) {
    (void)this_fn;
    if (__cfi_top < CFI_DEPTH)
        __cfi_shadow[__cfi_top++] = (unsigned int)call_site;
}

__attribute__((no_instrument_function))
void __cyg_profile_func_exit(void* this_fn, void* call_site) {
    (void)this_fn; (void)call_site;
    if (__cfi_top == 0) return;

    unsigned int expected = __cfi_shadow[--__cfi_top];

    // Читаем фактический адрес возврата через EBP-цепочку.
    // Мы сейчас в __cyg_profile_func_exit, вызванной из foo (до её ret):
    //   (%%ebp)     = foo_EBP (сохранён в нашем прологе push ebp)
    //   4(%%eax)    = *(foo_EBP + 4) = return address foo → его вызывающему
    // Если буферное переполнение испортило этот адрес, actual != expected.
    unsigned int actual;
    __asm__ volatile (
        "movl (%%ebp), %%eax\n"
        "movl 4(%%eax), %0\n"
        : "=r"(actual) :: "eax", "memory"
    );

    if (actual != expected) {
        ax_print((char*)"\033[31m*** CFI: return address hijacked! ***\033[0m\n");
        ax_exit();
    }
}
