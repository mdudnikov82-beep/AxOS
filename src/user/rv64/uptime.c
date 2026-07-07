#include "syscall.h"

static void print_udec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { write(1, "0", 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int a = 0, b = i-1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
    write(1, buf, i);
}

static void print_pad2(unsigned long v) {
    if (v < 10) write(1, "0", 1);
    print_udec(v);
}

/* CLINT `time` CSR ticks at 10 MHz on QEMU virt. */
#define TIMER_HZ 10000000UL

int main(void) {
    unsigned long ticks = (unsigned long)gettime();
    unsigned long secs  = ticks / TIMER_HZ;
    unsigned long mins  = secs / 60;
    unsigned long hours = mins / 60;
    mins %= 60;
    secs %= 60;

    puts_rv("Uptime: ");
    print_udec(hours);
    write(1, ":", 1);
    print_pad2(mins);
    write(1, ":", 1);
    print_pad2(secs);
    puts_rv("  (");
    print_udec(ticks);
    puts_rv(" ticks @ 10MHz)\r\n");

    exit(0);
    return 0;
}
