#include "syscall.h"
#include "malloc.h"

static void print_hex(unsigned long v) {
    char buf[16];
    for (int i = 15; i >= 0; i--) { buf[i] = "0123456789abcdef"[v & 0xF]; v >>= 4; }
    write(1, buf, 16);
}

int main(void) {
    puts_rv("malloctest: hardened heap on AxOS/RV64\r\n\r\n");

    void *p1 = malloc(64);
    void *p2 = malloc(128);
    void *p3 = malloc(32);
    puts_rv("p1(64)=0x");  print_hex((unsigned long)p1); puts_rv("\r\n");
    puts_rv("p2(128)=0x"); print_hex((unsigned long)p2); puts_rv("\r\n");
    puts_rv("p3(32)=0x");  print_hex((unsigned long)p3); puts_rv("\r\n");

    if (!p1 || !p2 || !p3) { puts_rv("FAIL: malloc returned NULL\r\n"); exit(1); }

    /* Write/read through p1 without touching the canary right after it. */
    unsigned char *b = (unsigned char *)p1;
    for (int i = 0; i < 64; i++) b[i] = (unsigned char)i;
    int ok = 1;
    for (int i = 0; i < 64; i++) if (b[i] != (unsigned char)i) { ok = 0; break; }
    puts_rv(ok ? "write/read p1: OK\r\n" : "write/read p1: FAIL\r\n");

    free(p2);
    puts_rv("freed p2 (now in quarantine, not yet reusable)\r\n");

    /* Quarantine means an immediate same-size malloc must NOT hand back
     * the address we just freed — a naive free-list allocator would. */
    void *p4 = malloc(128);
    puts_rv("p4(128)=0x"); print_hex((unsigned long)p4);
    puts_rv((p4 != p2) ? "  (different address - quarantine works)\r\n"
                       : "  (FAIL: same address, quarantine bypassed!)\r\n");

    free(p1);
    free(p3);
    free(p4);
    puts_rv("\r\nmalloctest: done\r\n");

    exit((ok && p4 != p2) ? 0 : 1);
    return 0;
}
