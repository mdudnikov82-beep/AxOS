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

// Блокирующее чтение строки с клавиатуры (эхо, backspace).
// Используется, когда shell захватил клавиатуру через ax_shell_claim(1).
int ax_readline(char* buf, int max) {
    int i = 0;
    while (i < max - 1) {
        char c;
        do { c = ax_readkey(); } while (!c);
        if (c == '\n') {
            ax_putchar('\n');
            break;
        }
        if (c == '\b') {
            if (i > 0) { i--; ax_putchar('\b'); }
        } else {
            buf[i++] = c;
            ax_putchar(c);
        }
    }
    buf[i] = '\0';
    return i;
}
