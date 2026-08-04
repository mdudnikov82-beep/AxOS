#include "syscall.h"

/* user_string_ok() NUL-termination fix (see syscall.c). Before this fix,
 * user_string_ok() only proved a pointer's 256-byte worst-case window
 * was inside legal user VA space - it never confirmed a NUL actually
 * appeared in it. exec()'s cmdline argument goes straight into
 * elf_load()'s parser: a first, correctly-bounded loop copies up to 63
 * non-space/non-NUL bytes into filename[64], then a SECOND loop
 * ("while (*p == ' ') p++;") skips any run of literal space bytes that
 * follows - genuinely unbounded, tied to nothing but finding a non-space
 * byte. 63 'A's (fills filename[], stopping the first loop WITHOUT ever
 * seeing a space or NUL) followed by a long run of real space bytes
 * makes the second loop walk far past the 256-byte checked window,
 * across this single-page user stack's own boundary into the unmapped
 * gap beyond it - faulting the KERNEL itself mid-syscall and hanging the
 * whole machine (kernel_main.c's SPP=1 fault path is `while(1) wfi`). */
int main(void) {
    static __attribute__((aligned(4096))) char buf[3 * 4096];
    int i = 0;
    for (; i < 63; i++) buf[i] = 'A';
    for (; i < 3 * 4096; i++) buf[i] = ' ';

    puts_rv("execstr: calling exec() with a crafted non-NUL-terminated string (63 'A' + 3KB of spaces, should be rejected, not crash the kernel)...\r\n");
    long r = exec((const char *)buf);
    if (r < 0) {
        puts_rv("execstr: DENIED as expected\r\n");
    } else {
        puts_rv("execstr: BUG - exec() should have rejected this!\r\n");
    }
    puts_rv("execstr: still alive - kernel did not crash\r\n");
    return 0;
}
