#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    unsigned int before, after, elapsed;

    ax_print("sleep_test: sleeping 3 seconds...\n");
    ax_print("ticks before: ");
    before = ax_get_ticks();
    ax_print_uint(before);
    ax_print("\n");

    ax_sleep_ms(3000);

    after = ax_get_ticks();
    ax_print("ticks after:  ");
    ax_print_uint(after);
    ax_print("\n");

    elapsed = after - before;
    ax_print("elapsed ticks: ");
    ax_print_uint(elapsed);
    ax_print(" (~");
    ax_print_uint(elapsed / 100);
    ax_print("s at 100Hz)\n");

    return 0;
}
