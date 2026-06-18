#include "axiom.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        ax_print("Usage: mkdir <dirname>\n");
        return 1;
    }

    char upper[9];
    int i = 0;
    char* src = argv[1];
    while (*src && i < 8) {
        char c = *src++;
        upper[i++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    upper[i] = '\0';

    int ok = ax_mkdir(upper);
    if (ok) {
        ax_printf("mkdir: created '%s'\n", upper);
    } else {
        ax_printf("mkdir: cannot create '%s': exists or disk locked\n", upper);
    }
    return ok ? 0 : 1;
}
