#include "syscall.h"

/* W^X test: the .text segment is mapped R+X (no W) since the user_rv64.ld
 * PHDRS split. Writing to it must trigger a store page fault, which the
 * kernel turns into "kill this process" rather than halting the system. */
/* __attribute__((used)): GCC's UB-based DCE otherwise notices target() is
 * never *called* (only its address is written through, which is itself UB)
 * and deletes the whole function body while leaving a dangling relocation. */
__attribute__((used))
static void target(void) {
    __asm__ volatile("nop");
}

int main(void) {
    puts_rv("wxtest: attempting to write to code page (.text)...\r\n");

    volatile unsigned char *p = (volatile unsigned char *)(unsigned long)target;
    *p = 0x00;

    /* Only reached if the write silently succeeded — W^X is broken. */
    puts_rv("wxtest: FAIL - code page was writable!\r\n");
    exit(1);
    return 1;
}
