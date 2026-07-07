// Stack canary для -fstack-protector-strong (см. KFLAGS в build.bat).
//
// GCC читает __stack_chk_guard в прологе каждой защищённой функции
// (сохраняет в кадре) и сравнивает в эпилоге; расхождение -> вызывается
// __stack_chk_fail(). До сих пор у ЯДРА этой защиты не было вообще -
// -fstack-protector стоял только для userspace (src/libaxiom/src/stack_chk.c,
// -m32). Это тот же приём, перенесённый на -m64 ядро.
//
// __stack_chk_guard ОБЯЗАН быть настоящим 8-байтным объектом: сгенерированный
// код на этом тулчейне делает честную 64-битную загрузку
// (movq .refptr.__stack_chk_guard(%rip), %rbx; movq (%rbx), %rax - см.
// разобранный вывод gcc -S). "unsigned long" здесь только 32 бита (MinGW/
// Windows LLP64 - та же ловушка, что уже была в heap.c/paging.c), поэтому
// нужен "unsigned long long".
//
// Также этот тулчейн НЕ использует TLS (%fs:0x28, как на "обычном" Linux
// x86-64) - читает обычный глобальный символ через refptr-таблицу. Это
// удобно: TLS в этом freestanding-ядре всё равно не настроен.
//
// kernel_init_stack_guard() должна быть ПЕРВЫМ вызовом в kernel_main(),
// до init_idt()/init_ttys() и т.д. - иначе первые защищённые функции
// использовали бы нулевой (BSS) canary. Сам kernel_main() никогда не
// возвращается (бесконечный цикл), так что его СОБСТВЕННЫЙ canary-слот
// в прологе (снятый ДО этого вызова) неважен - его эпилог просто никогда
// не выполнится.

unsigned long long __stack_chk_guard;

static inline unsigned long long rdtsc64(void) {
    unsigned int lo, hi;
    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    return ((unsigned long long)hi << 32) | lo;
}

// RDTSC, а не timer_ticks: должна работать ДО init_idt() (PIT/IRQ0 ещё не
// настроены), rdtsc доступен сразу после сброса CPU.
void kernel_init_stack_guard(void) {
    __stack_chk_guard = rdtsc64() ^ 0x9E3779B97F4A7C15ull;
    if (__stack_chk_guard == 0) __stack_chk_guard = 0x9E3779B97F4A7C15ull;
}

extern void print_string(char* str);

void __stack_chk_fail(void) {
    print_string("\n\033[31m*** STACK SMASHING DETECTED ***\nSystem halted.\033[0m\n");
    while (1) {
        __asm__("hlt");
    }
}
