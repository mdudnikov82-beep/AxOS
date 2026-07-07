#include "syscall.h"

int main(void) {
    puts_rv("Hello from U-mode userspace!\r\n");
    puts_rv("AxOS/RV64 syscalls: write() and exit() work.\r\n");

    long t = gettime();
    puts_rv("Timer value: ");
    /* print decimal */
    char buf[24];
    int i = 0;
    unsigned long n = (unsigned long)t;
    if (!n) { buf[i++] = '0'; }
    else { while (n) { buf[i++] = '0' + (n % 10); n /= 10; } }
    /* reverse */
    for (int a = 0, b = i-1; a < b; a++, b--) {
        char tmp = buf[a]; buf[a] = buf[b]; buf[b] = tmp;
    }
    buf[i] = '\r'; buf[i+1] = '\n'; buf[i+2] = '\0';
    puts_rv(buf);

    return 0;
}
