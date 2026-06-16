#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned int ticks = ax_get_ticks();
    unsigned int secs  = ticks / 100;
    unsigned int mins  = secs / 60;
    unsigned int h     = mins / 60;
    mins %= 60;
    secs %= 60;

    ax_printf("Uptime: %u:%02u:%02u  (%u ticks @ 100Hz)\n", h, mins, secs, ticks);
    return 0;
}
