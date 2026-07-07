#include "syscall.h"

/* Deliberately passes a KERNEL address (not this process's own memory) as
 * the buffer pointer to write() and read() — proves the kernel rejects
 * out-of-range pointers instead of leaking/corrupting kernel memory on
 * the calling process's behalf. */
int main(void) {
    puts_rv("kptrtest: calling write(1, (void*)0x80200000, 16)...\r\n");
    long r1 = write(1, (const void *)0x80200000UL, 16);
    puts_rv(r1 < 0 ? "  rejected (correct)\r\n" : "  FAIL: kernel memory was readable!\r\n");

    puts_rv("kptrtest: calling read(0, (void*)0x80200000, 16)...\r\n");
    long r2 = read(0, (void *)0x80200000UL, 16);
    puts_rv(r2 < 0 ? "  rejected (correct)\r\n" : "  FAIL: kernel memory was writable!\r\n");

    puts_rv("kptrtest: calling write() with a valid ptr but huge len (would spill into kernel VA)...\r\n");
    long r3 = write(1, (const void *)0x40000000UL, 0x7FFFFFFFFFFFFFFFUL);
    puts_rv(r3 < 0 ? "  rejected (correct)\r\n" : "  FAIL: oversized length accepted!\r\n");

    puts_rv("kptrtest: done\r\n");
    exit((r1 < 0 && r2 < 0 && r3 < 0) ? 0 : 1);
    return 0;
}
