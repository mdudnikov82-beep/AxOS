#include "../include/axiom.h"

// MinGW вставляет вызов __main() в начало main() для инициализации рантайма.
// В нашей freestanding среде он не нужен — пустая заглушка убирает undefined reference.
void __main(void) {}

void ax_putchar(char c) {
    char s[2] = {c, '\0'};
    ax_print(s);
}

void ax_print_uint(unsigned int n) {
    if (n == 0) { ax_putchar('0'); return; }
    char buf[10];
    int i = 0;
    while (n > 0) { buf[i++] = '0' + (n % 10); n /= 10; }
    while (i > 0) ax_putchar(buf[--i]);
}
