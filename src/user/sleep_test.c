#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned int before = ax_get_ticks();
    ax_printf("sleep_test: ticks before = %u\n", before);
    ax_printf("sleeping 3 seconds...\n");

    ax_sleep_ms(3000);

    unsigned int after = ax_get_ticks();
    unsigned int elapsed = after - before;
    ax_printf("ticks after  = %u\n", after);
    ax_printf("elapsed      = %u ticks (~%u sec)\n", elapsed, elapsed / 100);
    return 0;
}
