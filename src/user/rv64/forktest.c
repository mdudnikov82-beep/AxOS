#include "syscall.h"

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    puts_rv("forktest: calling fork()...\r\n");

    int pid = fork();
    if (pid == 0) {
        puts_rv("forktest: I am the CHILD\r\n");
    } else if (pid > 0) {
        puts_rv("forktest: I am the PARENT, child pid=");
        char buf[12]; int i = 0;
        unsigned int n = (unsigned int)pid;
        if (!n) { buf[i++] = '0'; }
        else { while (n) { buf[i++] = '0' + (n % 10); n /= 10; } }
        for (int a = 0, b = i - 1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
        buf[i] = '\0';
        puts_rv(buf);
        puts_rv("\r\n");
    } else {
        puts_rv("forktest: fork failed\r\n");
    }

    exit(0);
    return 0;
}
