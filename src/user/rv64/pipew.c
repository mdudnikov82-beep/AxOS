#include "syscall.h"

/* Вспомогательная программа для pipehog.c - пишет короткий маркер
 * (argv[1], если есть) после паузы и выходит. "Писатель" для проверки
 * эксклюзивности PIPE-редиректа (SYS_EXEC_PIPE, syscall.c). */
int main(int argc, char** argv) {
    sleep_ms(100);
    puts_rv("W");
    if (argc > 1) puts_rv(argv[1]);
    puts_rv(";");
    sleep_ms(400);
    return 0;
}
