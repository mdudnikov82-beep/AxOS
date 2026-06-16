#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned int ticks = ax_get_ticks();
    unsigned int secs  = ticks / 100;
    unsigned int mins  = secs / 60;
    unsigned int h     = mins / 60;
    mins %= 60;
    secs %= 60;

    ax_print("Uptime: ");
    ax_print_uint(h);   ax_putchar(':');
    // Ведущий ноль для минут и секунд
    if (mins < 10) ax_putchar('0');
    ax_print_uint(mins); ax_putchar(':');
    if (secs < 10) ax_putchar('0');
    ax_print_uint(secs);
    ax_print("  (");
    ax_print_uint(ticks);
    ax_print(" ticks @ 100 Hz)\n");
    return 0;
}
