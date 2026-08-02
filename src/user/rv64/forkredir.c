#include "syscall.h"

/* Тест наследования stdout_pipe_id через fork() (SYS_FORK, syscall.c):
 * потомок пишет и СРАЗУ выходит, родитель ждёт и пишет ПОЗЖЕ. Если бы
 * потомок (просто унаследовавший pipe_id, не единственный писатель)
 * сигналил читателю EOF на своём раннем выходе, "child-line" оказалась
 * бы последней строкой, которую видит читатель - "parent-line" пришла
 * бы уже после EOF и была бы потеряна (см. pipe_mark_writer_done's
 * "кто-то ещё жив" проверку). */
int main(int argc, char** argv) {
    (void)argc; (void)argv;

    int pid = fork();
    if (pid == 0) {
        puts_rv("child-line\r\n");
        return 0; /* потомок выходит первым - не должен рвать пайп родителю */
    }

    sleep_ms(300); /* дать потомку реально прогнаться и выйти */
    puts_rv("parent-line\r\n");
    return 0;
}
