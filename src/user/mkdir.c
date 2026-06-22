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

    int result = ax_mkdir(upper);
    if (result == 1) {
        ax_printf("\033[32mmkdir: created '%s'\033[0m\n", upper);
    } else if (result == AX_MKDIR_EXISTS) {
        ax_printf("\033[31mmkdir: cannot create '%s': already exists\033[0m\n", upper);
    } else if (result == AX_MKDIR_NOSPACE) {
        ax_printf("\033[31mmkdir: cannot create '%s': no space left\033[0m\n", upper);
    } else {
        ax_printf("\033[31mmkdir: cannot create '%s': disk locked or not ready\033[0m\n", upper);
    }
    return result == 1 ? 0 : 1;
}
