#include "syscall.h"

/* Тест zombie-DoS фикса (см. proc_reap_children/proc_count_zombie_children,
 * proc.h): форкает 5 раз подряд, каждый потомок СРАЗУ же exit()'ит, родитель
 * НИКОГДА не вызывает wait() - ровно сценарий, который раньше мог забить
 * все MAX_PROCS слоты навсегда. Ожидаем: первые 2 fork() проходят (кэп),
 * остальные 3 отказаны (-1), после чего собственный exit() этого процесса
 * должен подмести оба оставшихся зомби-потомка. */

static void print_digit(int n) {
    char c = (char)('0' + (n % 10));
    write(1, &c, 1);
}

int main(void) {
    puts_rv("zombietest: forking 5x, никогда не wait()...\r\n");

    int forked = 0, refused = 0;
    for (int i = 0; i < 5; i++) {
        int pid = fork();
        if (pid == 0) {
            exit(0); /* потомок: сразу же выходит -> станет зомби до реапа */
        }
        if (pid < 0) {
            puts_rv("  fork() REFUSED\r\n");
            refused++;
        } else {
            puts_rv("  fork() ok\r\n");
            forked++;
        }
        yield(); /* даём потомку реально прогнаться и exit()нуть -> зомби */
        yield();
    }

    puts_rv("zombietest: forked="); print_digit(forked);
    puts_rv(" refused="); print_digit(refused);
    puts_rv("\r\n");

    puts_rv("zombietest: exiting - мои непожатые зомби-потомки должны подместись\r\n");
    exit(0);
    return 0;
}
