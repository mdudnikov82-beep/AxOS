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

        // Отрезаем trailing '&' (фоновый запуск)
        int has_bg = 0;
        int linelen = 0;
        while (line[linelen]) linelen++;
        int last = linelen - 1;
        while (last >= 0 && line[last] == ' ') last--;
        if (last >= 0 && line[last] == '&') {
            has_bg = 1;
            line[last] = '\0';
            while (last > 0 && line[last-1] == ' ') line[--last] = '\0';
        }

        // Парсим перенаправление: "cmd > file.txt"
        char cmd[64];
        char redir[13];
        int  has_redir = 0;
        int  ci = 0;
        for (int i = 0; line[i]; i++) {
            if (line[i] == '>') {
                has_redir = 1;
                while (ci > 0 && cmd[ci-1] == ' ') ci--;
                cmd[ci] = '\0';
                i++;
                while (line[i] == ' ') i++;
                int ri = 0;
                while (line[i] && line[i] != ' ' && ri < 12) {
                    char c = line[i++];
                    redir[ri++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
                }
                redir[ri] = '\0';
                break;
            }
            if (ci < 63) cmd[ci++] = line[i];
        }
        if (!has_redir) cmd[ci] = '\0';

        int slot = has_redir ? ax_exec_redir(cmd, redir) : ax_exec(cmd);
        if (slot == -1) {
            ax_print("sh: not found\n");
        } else if (slot == -2) {
            ax_print("sh: no free slots\n");
        } else if (has_bg) {
            ax_printf("[%d] bg\n", slot);
        } else {
            ax_set_foreground(slot);
            while (ax_task_alive(slot)) { ax_sleep_ms(10); }
            ax_set_foreground(-1);
            if (has_redir && redir[0])
                ax_printf("-> %s\n", redir);
        }
    }

    ax_shell_claim(0);  // возвращаем клавиатуру kernel shell
    return 0;
}
