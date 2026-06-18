#include "axiom.h"

static int contains(const char* line, const char* pat) {
    for (int i = 0; line[i]; i++) {
        int j = 0;
        while (pat[j] && line[i + j] == pat[j]) j++;
        if (!pat[j]) return 1;
    }
    return 0;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        ax_print("Usage: grep <pattern> <file>\n");
        return 1;
    }
    char* pattern = argv[1];

    int fd = ax_open(argv[2], O_RDONLY);
    if (fd < 0) {
        ax_print("grep: not found: ");
        ax_print(argv[2]);
        ax_putchar('\n');
        return 1;
    }

    char buf[64];
    char line[128];
    int linelen = 0;
    int n;
    while ((n = ax_fread(fd, (unsigned char*)buf, sizeof(buf))) > 0) {
        for (int i = 0; i < n; i++) {
            char c = buf[i];
            if (c == '\n' || linelen >= 126) {
                line[linelen] = '\0';
                if (contains(line, pattern)) { ax_print(line); ax_putchar('\n'); }
                linelen = 0;
            } else {
                line[linelen++] = c;
            }
        }
    }
    if (linelen > 0) {
        line[linelen] = '\0';
        if (contains(line, pattern)) { ax_print(line); ax_putchar('\n'); }
    }

    ax_close(fd);
    return 0;
}
