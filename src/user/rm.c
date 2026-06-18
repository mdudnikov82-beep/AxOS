#include "axiom.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        ax_print("Usage: rm <file>\n");
        return 1;
    }

    char upper[13];
    int i = 0;
    char* src = argv[1];
    while (*src && i < 12) {
        char c = *src++;
        upper[i++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    upper[i] = '\0';

    int ok = ax_unlink(upper);
    if (ok) {
        ax_printf("removed '%s'\n", upper);
    } else {
        ax_printf("rm: cannot remove '%s': No such file or disk locked\n", upper);
    }
    return ok ? 0 : 1;
}
