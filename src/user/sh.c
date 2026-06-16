#include "axiom.h"

static int sh_streq(const char* a, const char* b) {
    while (*a && *b) if (*a++ != *b++) return 0;
    return *a == *b;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    ax_shell_claim(1);  // захватываем клавиатуру у kernel shell

    ax_print("\nAxSH v0.1 - AxOS user shell\n");
    ax_print("Run: <program> [args]  |  exit\n\n");

    char line[64];
    while (1) {
        ax_print("$ ");
        int len = ax_readline(line, sizeof(line));
        if (len == 0) continue;

        if (sh_streq(line, "exit")) {
            ax_print("Goodbye.\n");
            break;
        }

        int slot = ax_exec(line);
        if (slot == -1) {
            ax_print("sh: not found\n");
        } else if (slot == -2) {
            ax_print("sh: no free slots\n");
        } else {
            ax_set_foreground(slot);          // Ctrl+C теперь убьёт эту задачу
            while (ax_task_alive(slot)) {}    // busy-wait; таймер даёт дочерней CPU
            ax_set_foreground(-1);            // задача завершена — Ctrl+C сброшен
        }
    }

    ax_shell_claim(0);  // возвращаем клавиатуру kernel shell
    return 0;
}
