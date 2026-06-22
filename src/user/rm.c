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

    int result = ax_unlink(upper);
    if (result == 1) {
        ax_printf("\033[32mremoved '%s'\033[0m\n", upper);
    } else if (result == AX_UNLINK_NOTFOUND) {
        ax_printf("\033[31mrm: cannot remove '%s': no such file\033[0m\n", upper);
    } else {
        ax_printf("\033[31mrm: cannot remove '%s': disk locked or not ready\033[0m\n", upper);
    }
    return result == 1 ? 0 : 1;
}
