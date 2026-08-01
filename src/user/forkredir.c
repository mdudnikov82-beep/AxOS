#include "axiom.h"

/* Тест наследования redirect-pipe через fork() (см. sys_fork_impl,
 * kernel.c): потомок пишет и СРАЗУ выходит, родитель ждёт и пишет
 * ПОЗЖЕ. Если бы потомок (просто унаследовавший доступ к пайпу, не
 * владелец) сигналил читателю EOF на своём раннем выходе, "child-line"
 * оказалась бы последней строкой, которую видит "cat" - "parent-line"
 * пришла бы уже после EOF и была бы потеряна. */
int main(int argc, char** argv) {
    (void)argc; (void)argv;

    int pid = ax_fork();
    if (pid == 0) {
        ax_print("child-line\n");
        return 0; /* потомок выходит первым - не должен рвать пайп родителю */
    }

    ax_sleep_ms(300); /* дать потомку реально прогнаться и выйти */
    ax_print("parent-line\n");
    return 0;
}
