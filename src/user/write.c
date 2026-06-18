#include "axiom.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        ax_print("Usage: write <file> <text>\n");
        return 1;
    }

    static char text[512];
    int len = 0;
    for (int i = 2; i < argc; i++) {
        char* a = argv[i];
        while (*a && len < (int)sizeof(text) - 1) text[len++] = *a++;
        if (i < argc - 1 && len < (int)sizeof(text) - 1) text[len++] = ' ';
    }

    ax_writefile(argv[1], (unsigned char*)text, (unsigned int)len);
    ax_print("Written.\n");
    return 0;
}
