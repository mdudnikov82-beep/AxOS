#include "axiom.h"

/* Вспомогательная программа для pipehog.c - пишет один короткий маркер
 * (argv[1], если есть) после небольшой паузы и выходит. Используется
 * как "писатель" для проверки эксклюзивности PIPE:N. */
int main(int argc, char** argv) {
    ax_sleep_ms(100);
    ax_print("W");
    if (argc > 1) ax_print(argv[1]);
    ax_print(";");
    ax_sleep_ms(400);
    return 0;
}
