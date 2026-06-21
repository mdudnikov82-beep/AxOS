#include "axiom.h"

static int streq(const char* a, const char* b) {
    while (*a && *b) if (*a++ != *b++) return 0;
    return *a == *b;
}

int main(int argc, char** argv) {
    if (argc < 2 || (!streq(argv[1], "set") && !streq(argv[1], "get") && !streq(argv[1], "clear"))) {
        ax_print("Usage: clip set <text>  |  clip get  |  clip clear\n");
        return 1;
    }

    if (streq(argv[1], "set")) {
        static char text[CLIPBOARD_MAX_SIZE];
        int len = 0;
        for (int i = 2; i < argc; i++) {
            char* a = argv[i];
            while (*a && len < (int)sizeof(text) - 1) text[len++] = *a++;
            if (i < argc - 1 && len < (int)sizeof(text) - 1) text[len++] = ' ';
        }
        ax_clipboard_set((unsigned char*)text, (unsigned int)len);
        ax_printf("clip: set %d bytes\n", len);
        return 0;
    }

    if (streq(argv[1], "clear")) {
        // size=0, но указатель всё равно должен лежать в окне задачи -
        // validate_user_ptr (kernel.c) не пропустит NULL/0, даже с size=0.
        static unsigned char dummy;
        ax_clipboard_set(&dummy, 0);
        ax_print("clip: cleared\n");
        return 0;
    }

    static unsigned char buf[CLIPBOARD_MAX_SIZE];
    unsigned int got = ax_clipboard_get(buf, sizeof(buf) - 1);
    buf[got] = '\0';
    ax_print((char*)buf);
    ax_putchar('\n');
    return 0;
}
