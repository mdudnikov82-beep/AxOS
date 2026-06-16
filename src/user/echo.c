#include "axiom.h"

int main(int argc, char** argv) {
    for (int i = 1; i < argc; i++) {
        ax_print(argv[i]);
        if (i < argc - 1) ax_putchar(' ');
    }
    ax_putchar('\n');
}
