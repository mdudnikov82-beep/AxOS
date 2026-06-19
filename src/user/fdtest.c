#include "axiom.h"

// Диагностический инструмент: пытается читать/писать/закрыть фиксированные
// номера fd (0-3) БЕЗ собственного ax_open(). Если fd_table per-task
// (после fix'а), ядро должно отказать на каждом - даже если другая задача
// сейчас (или ранее) легитимно держит открытым fd с тем же номером.
int main(int argc, char** argv) {
    (void)argc; (void)argv;
    char buf[16] = {0};

    for (int fd = 0; fd < 4; fd++) {
        int n = ax_fread(fd, buf, sizeof(buf) - 1);
        ax_printf("ax_fread(%d, ...) without ax_open -> %d\n", fd, n);
    }
    return 0;
}
