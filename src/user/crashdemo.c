#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    ax_print("CRASH.BIN: about to access forbidden memory at 0x200000...\n");

    volatile unsigned int* bad = (unsigned int*)0x200000;
    *bad = 0xDEADBEEF;

    ax_print("CRASH.BIN: this should never print.\n");
}
