#include "axiom.h"

int main(int argc, char** argv) {
    ax_print("Hello from HELLO.BIN, loaded from FAT12 and run in ring3!\n");
    ax_print("argc="); ax_print_uint(argc); ax_putchar('\n');
    for (int i = 0; i < argc; i++) {
        ax_print("argv["); ax_print_uint(i); ax_print("]=");
        ax_print(argv[i]); ax_putchar('\n');
    }

    char* msg = "Written from ring3 via SYS_WRITE_FILE!\n";
    unsigned int len = 0;
    while (msg[len] != '\0') len++;
    ax_writefile("RING3.TXT", (unsigned char*)msg, len);

    char buf[128];
    unsigned int n = ax_readfile("RING3.TXT", (unsigned char*)buf, sizeof(buf) - 1);
    buf[n] = '\0';
    ax_print(buf);

    while (1) {
        char key = ax_readkey();
        if (key != 0 && key != '\n' && key != '\b')
            ax_putchar(key);
    }
}
