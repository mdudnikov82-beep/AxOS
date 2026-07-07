#include "syscall.h"

static void print_int(int n) {
    char buf[12]; int i = 0;
    if (!n) { write(1, "0", 1); return; }
    while (n > 0) { buf[i++] = '0' + n % 10; n /= 10; }
    for (int j = i-1; j >= 0; j--) write(1, &buf[j], 1);
}

/* Yield repeatedly until at least `ms` milliseconds have passed.
 * Every yield gives the shell (or other processes) a chance to run. */
static void delay_ms(long ms) {
    long end = gettime() + ms * 10000L;  /* 10 MHz CLINT clock */
    while (gettime() < end) yield();
}

int main(void) {
    int pid = getpid();

    puts_rv("\r\n\033[33m[counter pid=");
    print_int(pid);
    puts_rv("]\033[0m started, printing 8 ticks (600 ms apart)\r\n");

    for (int i = 1; i <= 8; i++) {
        delay_ms(600);
        /* \r\033[K clears the shell's half-typed prompt before printing */
        puts_rv("\r\033[K\033[33m[counter]\033[0m tick ");
        print_int(i);
        puts_rv("/8\r\n");
    }

    puts_rv("\r\033[K\033[33m[counter]\033[0m all done! Exiting.\r\n");
    exit(0);
    return 0;
}
