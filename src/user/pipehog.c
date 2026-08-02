#include "axiom.h"

/* Тест фикса "PIPE:N без владения/эксклюзивности" (sys_exec_redir/
 * sys_open, kernel.c). Таймлайн (PIPEW.BIN: спит 100мс, пишет маркер,
 * спит ещё 400мс = живёт ~500мс с момента своего старта):
 *   t=0    запускаем w1 -> PIPE:0
 *   t=200  запускаем w2 -> PIPE:0 (пайп ещё занят w1 - должен получить
 *          отказ и писать СВОЙ маркер на экран, а не в пайп)
 *   t=600  w1 уже мёртв (спал 100+400=500мс) - открываем PIPE:0 и
 *          читаем содержимое: должно быть РОВНО "W1;" (не "W2;", не
 *          обе строки вперемешку - если бы момент A не работал)
 *   t=900  w2 тоже уже мёртв - fork(), потомок (другой process slot)
 *          пытается ВТОРОЙ раз открыть PIPE:0, пока родитель (fd1) его
 *          ещё держит - должен получить отказ (-1)
 */
int main(int argc, char** argv) {
    (void)argc; (void)argv;

    int w1 = ax_exec_redir("PIPEW.BIN 1", "PIPE:0");
    ax_printf("pipehog: w1=%d\n", w1);
    ax_sleep_ms(200);

    int w2 = ax_exec_redir("PIPEW.BIN 2", "PIPE:0");
    ax_printf("pipehog: w2=%d (W2 marker should land on SCREEN, not in the pipe)\n", w2);
    ax_sleep_ms(400);

    int fd1 = ax_open("PIPE:0", O_RDONLY);
    ax_printf("pipehog: fd1=%d\n", fd1);
    char buf[64];
    int n = ax_fread(fd1, buf, sizeof(buf) - 1);
    buf[n > 0 ? n : 0] = '\0';
    ax_print("pipehog: pipe content=[");
    ax_print(buf);
    ax_print("] (expect exactly W1;)\n");

    ax_sleep_ms(300);
    int pid = ax_fork();
    ax_printf("pipehog: fork pid=%d\n", pid);
    if (pid == 0) {
        int fd2 = ax_open("PIPE:0", O_RDONLY);
        ax_printf("pipehog(child): fd2=%d (expect -1)\n", fd2);
        return 0;
    }

    ax_sleep_ms(400);
    return 0;
}
