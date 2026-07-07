#include "syscall.h"
#include "malloc.h"

/* Deliberately writes past the end of a 32-byte allocation, into the right
 * redzone. free() must detect the corrupted redzone and abort instead of
 * silently accepting a heap that's already been smashed. */
int main(void) {
    puts_rv("mteoverfl: writing 4 bytes past a 32-byte allocation...\r\n");

    unsigned char *p = (unsigned char *)malloc(32);
    if (!p) { puts_rv("mteoverfl: malloc failed\r\n"); exit(1); }

    for (int i = 0; i < 32; i++) p[i] = 0x41;
    p[32] = 0xFF;  /* first byte of the right redzone — should still be 0xBE */
    p[33] = 0xFF;
    p[34] = 0xFF;
    p[35] = 0xFF;

    puts_rv("mteoverfl: calling free() — expecting redzone detection...\r\n");
    free(p);  /* must trigger heap_abort() and never return */

    puts_rv("mteoverfl: FAIL - overflow was not caught!\r\n");
    exit(1);
    return 1;
}
