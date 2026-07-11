#include "syscall.h"

/* Integration test - CFI + seccomp interaction. CFI's kill path
 * (cfi.c's __cyg_profile_func_exit) calls exit(139) when it detects a
 * hijacked return address. What happens if a seccomp filter EXCLUDES
 * SYS_EXIT before the corruption happens - does CFI's own exit() call
 * get blocked by the seccomp gate, and does the process still safely
 * terminate (via the seccomp-kill path instead), or does something
 * worse happen (hang, double-kill, crash)? */

static void vuln(void) {
    puts_rv("vuln: corrupting return address with 0xDEADBEEF...\r\n");
    register unsigned long cur_s0 __asm__("s0");
    *(unsigned long *)(cur_s0 - 8) = 0xDEADBEEF;
    puts_rv("vuln: done. CFI exit hook should fire before ret.\r\n");
}

int main(void) {
    puts_rv("cfisectest: installing filter WITHOUT SC_EXIT...\r\n");
    seccomp(SC_WRITE | SC_READ | SC_SBRK | SC_GETTIME | SC_SLEEP);
    puts_rv("cfisectest: filter active (no exit!). calling vuln()...\r\n");
    vuln();
    puts_rv("cfisectest: ERROR - returned from vuln, CFI did NOT fire!\r\n");
    return 1;
}
