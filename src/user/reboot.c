#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    ax_print("Rebooting...\n");
    ax_reboot();
    return 0; // не достигается - ax_reboot() не возвращается
}
