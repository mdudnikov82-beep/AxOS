#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    ax_print("EXIT.BIN: running, about to exit via SYS_EXIT with code 7...\n");
    return 7;
}
