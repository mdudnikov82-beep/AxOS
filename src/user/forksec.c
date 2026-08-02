#include "axiom.h"

/* Тест фикса "SYS_FORK обходил seccomp" (sys_fork_impl, kernel.c):
 * сужает себя до AX_SC_STDIO (сознательно БЕЗ AX_SC_FORK - см. коммент
 * у AX_SC_STDIO в axiom.h), затем зовёт ax_fork(). Если фикс работает,
 * процесс убивается ВНУТРИ ax_fork() - строка после неё никогда не
 * печатается (задача, помеченная на смерть, no-op'ит все syscall'ы,
 * включая сам print). Если "BUG" всё-таки напечаталась - fork() всё
 * ещё обходит seccomp. */
int main(int argc, char** argv) {
    (void)argc; (void)argv;
    ax_print("forksec: seccomp to AX_SC_STDIO (no fork bit)...\n");
    ax_seccomp(AX_SC_STDIO);
    ax_print("forksec: calling ax_fork() - should be killed, not return\n");
    int pid = ax_fork();
    ax_printf("forksec: BUG - fork() returned %d, should have been killed\n", pid);
    return 0;
}
