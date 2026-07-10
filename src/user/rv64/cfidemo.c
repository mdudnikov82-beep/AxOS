#include "syscall.h"

/* CFI demo - mirrors src/user/cfidemo.c (x86). Intentionally corrupts
 * its own saved return address; the CFI exit hook (cfi.c) should catch
 * it before the real `ret` executes. */

static void vuln(void) {
    puts_rv("vuln: corrupting return address with 0xDEADBEEF...\r\n");
    register unsigned long cur_s0 __asm__("s0");
    *(unsigned long *)(cur_s0 - 8) = 0xDEADBEEF;   /* corrupt OWN saved ra */
    puts_rv("vuln: done. CFI exit hook should fire before ret.\r\n");
}

int main(void) {
    puts_rv("CFI demo: calling vuln() which corrupts its own return addr\r\n");
    puts_rv("Expected: CFI hijack message, NOT 'returned from vuln'\r\n");
    vuln();
    puts_rv("ERROR: returned from vuln - CFI did NOT fire!\r\n");
    return 1;
}
