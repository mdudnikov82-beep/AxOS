#include "syscall.h"

/* grep <pattern> [file] - если файл не указан, читает stdin (fd 0) до
 * EOF - что делает его полезным как читатель конца pipe'а
 * ("cmd1 | grep pattern"), см. axsh.c. buf/line - static, не локальные:
 * пользовательский стек - одна 4КБ-страница на всю цепочку вызовов (см.
 * память project_riscv_single_page_stack), большие локальные массивы
 * рискуют store page fault. */
static char buf[64];
static char line[128];

static int contains(const char *s, const char *pat) {
    for (int i = 0; s[i]; i++) {
        int j = 0;
        while (pat[j] && s[i + j] == pat[j]) j++;
        if (!pat[j]) return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        puts_rv("Usage: grep <pattern> [file]\r\n");
        exit(1);
    }
    const char *pattern = argv[1];

    int fd;
    if (argc >= 3) {
        fd = open(argv[2], 0);
        if (fd < 0) {
            puts_rv("grep: not found: ");
            puts_rv(argv[2]);
            puts_rv("\r\n");
            exit(1);
        }
    } else {
        fd = 0; /* stdin - реальный fd, не нужен open() */
    }

    int linelen = 0;
    long n;
    while ((n = read(fd, buf, sizeof(buf))) > 0) {
        for (long i = 0; i < n; i++) {
            char c = buf[i];
            if (c == '\n' || linelen >= 126) {
                line[linelen] = '\0';
                if (contains(line, pattern)) { write(1, line, (long)linelen); write(1, "\r\n", 2); }
                linelen = 0;
            } else if (c != '\r') {
                line[linelen++] = c;
            }
        }
    }
    if (linelen > 0) {
        line[linelen] = '\0';
        if (contains(line, pattern)) { write(1, line, (long)linelen); write(1, "\r\n", 2); }
    }

    if (fd != 0) close(fd);
    exit(0);
    return 0;
}
