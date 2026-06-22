#include "axiom.h"

static int sh_streq(const char* a, const char* b) {
    while (*a && *b) if (*a++ != *b++) return 0;
    return *a == *b;
}

static int sh_strncmp(const char* a, const char* b, int n) {
    for (int i = 0; i < n; i++) {
        if (a[i] != b[i]) return a[i] - b[i];
        if (!a[i]) return 0;
    }
    return 0;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    ax_shell_claim(1);  // захватываем клавиатуру у kernel shell

    ax_print("\n\033[36mAxSH v0.1 - AxOS user shell\033[0m\n");
    ax_print("Run: <program> [args]  |  exit\n\n");

    char line[64];
    char current_dir[13] = ""; // Пусто = корневой каталог
        while (1) {
        // Внутри цикла while(1), перед ax_readline:
        if (current_dir[0] == '\0') {
            ax_print("\033[32m$\033[0m ");
        } else {
            ax_printf("\033[32m[%s]$\033[0m ", current_dir);
        }
        int len = ax_readline(line, sizeof(line));
        if (len == 0) continue;

        if (sh_streq(line, "exit")) {
            ax_print("\033[36mGoodbye.\033[0m\n");
            break;
        }

        if (sh_streq(line, "unlock")) {
            ax_disk_lock(0);
            ax_print("\033[32mdisk: unlocked\033[0m\n");
            continue;
        }

        if (sh_streq(line, "lock")) {
            ax_disk_lock(1);
            ax_print("\033[32mdisk: locked\033[0m\n");
            continue;
        }

        // "paste" - алиас "clip get" прямо в шелле: диск FAT12 (128 КБ)
        // уже заполнен инструментами, а свежий .bin стоит ~4.6 КБ только
        // на crt0/libaxiom (см. clip.c) - не на чём сэкономить, кроме
        // как не плодить отдельную программу под однострочный алиас.
        if (sh_streq(line, "paste")) {
            static unsigned char clip_buf[CLIPBOARD_MAX_SIZE];
            unsigned int got = ax_clipboard_get(clip_buf, sizeof(clip_buf) - 1);
            clip_buf[got] = '\0';
            ax_print((char*)clip_buf);
            ax_putchar('\n');
            continue;
        }

        // Логика команды cd
        if (sh_strncmp(line, "cd", 2) == 0 && (line[2] == ' ' || line[2] == '\0')) {
            if (sh_streq(line, "cd ..") || sh_streq(line, "cd /") || sh_streq(line, "cd")) {
                current_dir[0] = '\0'; // В корень
            } else {
                char* target = line + 3;
                // Trim trailing spaces
                int tlen = 0;
                while (target[tlen]) tlen++;
                while (tlen > 0 && target[tlen-1] == ' ') tlen--;
                // Конвертируем в uppercase
                char upper[13];
                int k = 0;
                while (k < tlen && k < 12) {
                    char c = target[k];
                    upper[k++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
                }
                upper[k] = '\0';
                // Проверяем, что директория реально существует
                struct readdir_args da;
                int found = 0;
                for (unsigned int i = 0; ; i++) {
                    da.index = i;
                    da.result = 0;
                    ax_readdir(&da);
                    if (!da.result) break;
                    if (da.is_dir) {
                        int match = 1;
                        for (int j = 0; upper[j] || da.name[j]; j++) {
                            if (upper[j] != da.name[j]) { match = 0; break; }
                        }
                        if (match) { found = 1; break; }
                    }
                }
                if (!found) {
                    ax_print("\033[31mcd: not found\033[0m\n");
                } else {
                    for (k = 0; upper[k]; k++) current_dir[k] = upper[k];
                    current_dir[k] = '\0';
                }
            }
            continue;
        }

        // Pipe: "cmd1 | cmd2". Планировщик здесь последовательный (см.
        // ax_task_alive ниже), настоящего потокового конвейера нет - это
        // "пакетный" pipe: cmd1 выполняется ПОЛНОСТЬЮ, его stdout целиком
        // оседает во временном файле PIPE.TMP (через тот же механизм, что
        // и обычный "> file"), и только после этого cmd2 запускается с
        // именем PIPE.TMP, дописанным последним аргументом - имитация
        // stdin без изменения ABI. Один уровень pipe, не цепочка.
        {
            int pipe_pos = -1;
            for (int i = 0; line[i]; i++) { if (line[i] == '|') { pipe_pos = i; break; } }
            if (pipe_pos >= 0) {
                char cmd1[64], cmd2[64];
                int k = 0;
                while (k < pipe_pos && k < 63) { cmd1[k] = line[k]; k++; }
                while (k > 0 && cmd1[k-1] == ' ') k--;
                cmd1[k] = '\0';

                int j = pipe_pos + 1;
                while (line[j] == ' ') j++;
                int m = 0;
                while (line[j] && m < 63) cmd2[m++] = line[j++];
                while (m > 0 && cmd2[m-1] == ' ') m--;
                cmd2[m] = '\0';

                int slot1 = ax_exec_redir(cmd1, "PIPE.TMP");
                if (slot1 < 0) {
                    ax_print("\033[31msh: pipe: left side not found\033[0m\n");
                } else {
                    ax_set_foreground(slot1);
                    while (ax_task_alive(slot1)) { ax_sleep_ms(10); }
                    ax_set_foreground(-1);

                    if (m > 0 && m < 54) {
                        cmd2[m] = ' ';
                        cmd2[m+1]='P'; cmd2[m+2]='I'; cmd2[m+3]='P'; cmd2[m+4]='E';
                        cmd2[m+5]='.'; cmd2[m+6]='T'; cmd2[m+7]='M'; cmd2[m+8]='P';
                        cmd2[m+9]='\0';
                    }
                    int slot2 = ax_exec(cmd2);
                    if (slot2 == -1) {
                        ax_print("\033[31msh: pipe: right side not found\033[0m\n");
                    } else if (slot2 == -2) {
                        ax_print("\033[31msh: no free slots\033[0m\n");
                    } else {
                        ax_set_foreground(slot2);
                        while (ax_task_alive(slot2)) { ax_sleep_ms(10); }
                        ax_set_foreground(-1);
                    }
                }
                ax_unlink("PIPE.TMP");
                continue;
            }
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
            ax_print("\033[31msh: not found\033[0m\n");
        } else if (slot == -2) {
            ax_print("\033[31msh: no free slots\033[0m\n");
        } else if (has_bg) {
            ax_printf("\033[33m[%d] bg\033[0m\n", slot);
        } else {
            ax_set_foreground(slot);
            while (ax_task_alive(slot)) { ax_sleep_ms(10); }
            ax_set_foreground(-1);
            if (has_redir && redir[0])
                ax_printf("\033[32m-> %s\033[0m\n", redir);
        }
    }

    ax_shell_claim(0);  // возвращаем клавиатуру kernel shell
    return 0;
}
