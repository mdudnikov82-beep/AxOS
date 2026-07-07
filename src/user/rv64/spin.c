#include "syscall.h"

int main(void) {
    puts_rv("spin: pure CPU loop, no yield() - kill <PID> to stop\r\n");
    volatile unsigned long counter = 0;
    while (1) {
        counter++;
    }
    return 0;
}
