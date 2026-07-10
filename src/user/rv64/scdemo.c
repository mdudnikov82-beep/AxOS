#include "syscall.h"

/* Seccomp demo - mirrors src/user/scdemo.c (x86). Checks that a syscall
 * filter kills the process on a forbidden call.
 *
 * Usage:
 *   scdemo exec  -> STDIO filter + exec()  -> killed (seccomp)
 *   scdemo kill  -> STDIO filter + kill(0) -> killed (seccomp)
 *   scdemo ok    -> STDIO filter + write/narrow -> ALL PASS
 *   scdemo       -> usage hint
 *
 * No raw disk syscall exists on RV64 (VFS/FAT12 only via open/close), so
 * unlike x86's "disk" scenario this uses kill() as the second forbidden
 * capability - equally dangerous to demonstrate blocking. */

static void test_exec(void) {
    puts_rv("[seccomp exec] Installing STDIO-only filter...\r\n");
    seccomp(SC_STDIO);
    puts_rv("[seccomp exec] Filter active. Attempting exec...\r\n");
    /* Kernel should print "[seccomp] forbidden syscall 10" and kill us.
     * exit() IS in SC_STDIO, so if the kill somehow didn't happen we'd
     * still exit cleanly instead of falling through. */
    exec("HELLO.ELF");
    exit(0);
}

static void test_kill(void) {
    puts_rv("[seccomp kill] Installing STDIO-only filter...\r\n");
    seccomp(SC_STDIO);
    puts_rv("[seccomp kill] Filter active. Attempting kill(0)...\r\n");
    /* Kernel should print "[seccomp] forbidden syscall 14" and kill us. */
    kill(0);
    exit(0);
}

static void test_ok(void) {
    puts_rv("[seccomp ok] Installing STDIO-only filter...\r\n");
    seccomp(SC_STDIO);
    puts_rv("[seccomp ok] Filter active. write: PASS\r\n");
    /* Narrow again (AND) - only write+exit survive. Still alive after. */
    seccomp(SC_WRITE | SC_EXIT);
    puts_rv("[seccomp ok] Narrowed to WRITE+EXIT only - still alive: PASS\r\n");
    puts_rv("[seccomp ok] ALL PASS\r\n");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        puts_rv("Usage: scdemo exec|kill|ok\r\n");
        puts_rv("  exec - exec() after STDIO filter  (expect: killed)\r\n");
        puts_rv("  kill - kill() after STDIO filter  (expect: killed)\r\n");
        puts_rv("  ok   - allowed calls after filter (expect: ALL PASS)\r\n");
        return 0;
    }
    if      (argv[1][0] == 'e') test_exec();
    else if (argv[1][0] == 'k') test_kill();
    else if (argv[1][0] == 'o') test_ok();
    else puts_rv("Unknown test. Use exec, kill, or ok.\r\n");
    return 0;
}
