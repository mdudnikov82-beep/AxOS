#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    ax_print("forkdemo: calling ax_fork()...\n");

    int pid = ax_fork();
    if (pid == 0) {
        ax_print("forkdemo: I am the CHILD\n");
    } else if (pid > 0) {
        ax_printf("forkdemo: I am the PARENT, child pid=%d\n", pid);
    } else {
        ax_print("forkdemo: fork failed\n");
    }
    return 0;
}
