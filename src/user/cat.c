#include "axiom.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        ax_print("Usage: run cat.bin <filename>\n");
        return 1;
    }

    int fd = ax_open(argv[1], O_RDONLY);
    if (fd < 0) {
        ax_print("cat: not found: ");
        ax_print(argv[1]);
        ax_putchar('\n');
        return 1;
    }

    char buf[64];
    int n;
    while ((n = ax_fread(fd, (unsigned char*)buf, sizeof(buf) - 1)) > 0) {
        buf[n] = '\0';
        ax_print(buf);
    }
    ax_close(fd);
    return 0;
}
