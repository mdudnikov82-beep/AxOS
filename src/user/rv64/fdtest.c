#include "syscall.h"

/* Tries to read fixed fd numbers 1-3 WITHOUT opening them first.
 * Since fds are per-process, every read on an un-opened fd must fail.
 * fd 0 (stdin) is skipped — reading it would block waiting for a keypress. */
int main(void) {
    puts_rv("fdtest: probing fd 1..3 without open()\r\n");

    for (int fd = 1; fd < 4; fd++) {
        char buf[16];
        long n = read(fd, buf, sizeof(buf));
        write(1, "  fd ", 5);
        char c = (char)('0' + fd);
        write(1, &c, 1);
        puts_rv(" without open() -> ");
        puts_rv((n < 0) ? "rejected (correct)\r\n" : "unexpected success!\r\n");
    }

    puts_rv("fdtest: done\r\n");
    exit(0);
    return 0;
}
