#include "syscall.h"

static void print_udec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { write(1, "0", 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int a = 0, b = i-1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
    write(1, buf, i);
}

int main(void) {
    unsigned long before = (unsigned long)gettime();
    puts_rv("sleeptest: ticks before = ");
    print_udec(before);
    puts_rv("\r\nsleeping 2 seconds...\r\n");

    sleep_ms(2000);

    unsigned long after = (unsigned long)gettime();
    puts_rv("ticks after  = ");
    print_udec(after);
    puts_rv("\r\nelapsed      = ");
    print_udec(after - before);
    puts_rv(" ticks (~");
    print_udec((after - before) / 10000000UL);
    puts_rv(" sec)\r\n");

    exit(0);
    return 0;
}
