#include "syscall.h"

/* Integration test - fork() + seccomp + MLS combined, all three
 * mechanisms from this session's security round. Not a permanent demo,
 * a one-off probe: does the CHILD's inherited syscall_mask/mls_level
 * actually get enforced against the CHILD's own current_pid at runtime,
 * not just copied-but-unused data? */

int main(void) {
    puts_rv("sectest: set_level(7), seccomp(STDIO|FORK|WAIT|GETPID)...\r\n");
    set_level(7);
    seccomp(SC_STDIO | SC_FORK | SC_WAIT | SC_GETPID);

    int pid = fork();
    if (pid == 0) {
        puts_rv("sectest[child]: alive. getpid (allowed, inherited mask)...\r\n");
        getpid();
        puts_rv("sectest[child]: attempting exec (should be forbidden - inherited filter)\r\n");
        exec("HELLO.ELF");
        puts_rv("sectest[child]: ERROR - reached here, inheritance did NOT enforce!\r\n");
        exit(1);
    } else {
        puts_rv("sectest[parent]: waiting for child...\r\n");
        wait(pid);
        puts_rv("sectest[parent]: child reaped, done\r\n");
    }
    return 0;
}
