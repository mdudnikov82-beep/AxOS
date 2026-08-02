#include "syscall.h"

/* Тест фикса "PIPE:N без владения/эксклюзивности" на RISC-V
 * (SYS_EXEC_PIPE, syscall.c):
 *   w2 - второй писатель на УЖЕ занятый pipe 0 - должен получить -1
 *        (на RISC-V отказ полный: процесс даже не создаётся, в отличие
 *        от x86, где cmd1 всё равно exec'ится, просто без редиректа).
 *   r2 - второй читатель на pipe 0, пока r1 (другой процесс) ещё жив -
 *        должен получить -1.
 */
static void print_int(int v) {
    if (v < 0) { char c = '-'; write(1, &c, 1); v = -v; }
    char buf[12]; int i = 0;
    if (!v) { char c = '0'; write(1, &c, 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    for (int j = i - 1; j >= 0; j--) write(1, &buf[j], 1);
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    int w1 = exec_pipe("PIPEW.ELF 1", 0, -1);
    puts_rv("pipehog: w1="); print_int(w1); puts_rv("\r\n");
    sleep_ms(200);

    int w2 = exec_pipe("PIPEW.ELF 2", 0, -1);
    puts_rv("pipehog: w2="); print_int(w2); puts_rv(" (expect -1, busy pipe)\r\n");
    sleep_ms(400);

    int r1 = exec_pipe("PIPER.ELF", -1, 0);
    puts_rv("pipehog: r1="); print_int(r1); puts_rv("\r\n");
    sleep_ms(50);

    int r2 = exec_pipe("PIPER.ELF", -1, 0);
    puts_rv("pipehog: r2="); print_int(r2); puts_rv(" (expect -1, reader already attached)\r\n");

    sleep_ms(700);
    return 0;
}
