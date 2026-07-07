#include "syscall.h"

static void print_hex(unsigned long v) {
    char buf[16];
    for (int i = 15; i >= 0; i--) { buf[i] = "0123456789abcdef"[v & 0xF]; v >>= 4; }
    write(1, buf, 16);
}

int main(void) {
    puts_rv("sbrktest: initial brk = 0x");
    long brk0 = sbrk(0);
    print_hex((unsigned long)brk0);
    puts_rv("\r\n");

    /* Grow the heap by one page and write/read a pattern through it. */
    long base = sbrk(4096);
    if (base < 0) { puts_rv("sbrktest: FAIL - sbrk(4096) returned -1\r\n"); exit(1); }

    puts_rv("sbrktest: sbrk(4096) -> 0x");
    print_hex((unsigned long)base);
    puts_rv("\r\n");

    volatile unsigned char *p = (volatile unsigned char *)base;
    for (int i = 0; i < 256; i++) p[i] = (unsigned char)i;

    int ok = 1;
    for (int i = 0; i < 256; i++) if (p[i] != (unsigned char)i) { ok = 0; break; }
    puts_rv(ok ? "sbrktest: write/read pattern OK\r\n"
               : "sbrktest: FAIL - readback mismatch\r\n");

    /* brk should have advanced by exactly one page. */
    long brk1 = sbrk(0);
    puts_rv("sbrktest: new brk = 0x");
    print_hex((unsigned long)brk1);
    puts_rv((brk1 - base == 4096) ? "  (advanced correctly)\r\n"
                                  : "  (FAIL: unexpected advance)\r\n");

    exit(ok ? 0 : 1);
    return 0;
}
