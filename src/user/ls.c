#include "axiom.h"

static void print_padded(const char* s, int width) {
    int len = 0;
    const char* p = s;
    while (*p++) len++;
    ax_print((char*)s);
    while (len++ < width) ax_putchar(' ');
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    struct readdir_args a;
    unsigned int total = 0;
    unsigned int count = 0;

    for (unsigned int i = 0; ; i++) {
        a.index  = i;
        a.result = 0;
        ax_readdir(&a);
        if (!a.result) break;

        if (a.is_dir) {
            // Каталоги - циан, как и остальные заголовки/категории в UI
            // (см. "Цвет в AxSH" в README).
            ax_print("\033[36m");
            print_padded(a.name, 13);
            ax_print("  <DIR>\033[0m\n");
        } else {
            ax_print("\033[32m");
            print_padded(a.name, 13);
            ax_print("\033[0m");
            ax_printf("  %7u B\n", a.size);
            total += a.size;
        }
        count++;
    }

    if (count == 0) {
        ax_print("\033[33m(no files)\033[0m\n");
    } else {
        ax_print("\033[32m---\n");
        ax_print_uint(count);
        ax_print(" file(s), ");
        ax_print_uint(total);
        ax_print(" B total\033[0m\n");
    }
    return 0;
}
