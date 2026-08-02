#include "syscall.h"

/* Вспомогательная программа для pipehog.c - читает stdin (привязан к
 * pipe_bufs[N] через SYS_EXEC_PIPE's stdin_pipe_id), печатает что
 * получила, и остаётся живой ещё немного - чтобы pipehog успел
 * попробовать ВТОРОГО читателя, пока этот процесс ещё жив. */
int main(int argc, char** argv) {
    (void)argc; (void)argv;
    char buf[64];
    long n = read(0, buf, sizeof(buf) - 1);
    if (n < 0) n = 0;
    buf[n] = '\0';
    puts_rv("R[");
    puts_rv(buf);
    puts_rv("]\r\n");
    sleep_ms(500);
    return 0;
}
