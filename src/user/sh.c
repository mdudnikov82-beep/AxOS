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

/* Tab-автодополнение имени файла - подключается в ax_readline() (см.
 * stdio.c) через ax_set_complete_hook(), только в конце строки. Тот же
 * дизайн, что и на RISC-V (axsh.c): повтор Tab листает совпадения, но
 * только если ни курсор, ни начало слова не изменились с прошлого раза -
 * если пользователь дописал ещё символы между двумя нажатиями, это не
 * повтор, а новый (более узкий) префикс, нужно пересканировать диск. */
static char sh_comp_buf[16][13];
static int  sh_comp_count = 0, sh_comp_idx = 0, sh_comp_word_start = -1, sh_comp_last_pos = -1;

static int sh_complete(char *buf, int *plen, int *ppos, int max) {
    if (*ppos != *plen) return 0;
    int len = *plen;
    int start = len;
    while (start > 0 && buf[start - 1] != ' ') start--;

    int is_repeat = (sh_comp_word_start == start && sh_comp_last_pos == *ppos);
    if (!is_repeat) {
        sh_comp_word_start = start;
        sh_comp_count = 0;
        sh_comp_idx = 0;
        char prefix[13]; int pl = 0;
        for (int i = start; i < len && pl < 12; i++) {
            char ch = buf[i];
            prefix[pl++] = (ch >= 'a' && ch <= 'z') ? (char)(ch - 32) : ch;
        }
        prefix[pl] = '\0';

        struct readdir_args da;
        for (unsigned int i = 0; sh_comp_count < 16; i++) {
            da.index = i; da.result = 0;
            ax_readdir(&da);
            if (!da.result) break;
            if (sh_strncmp(da.name, prefix, pl) == 0) {
                int k = 0; while (da.name[k] && k < 12) { sh_comp_buf[sh_comp_count][k] = da.name[k]; k++; }
                sh_comp_buf[sh_comp_count][k] = '\0';
                sh_comp_count++;
            }
        }
    }
    if (sh_comp_count == 0) return 0;

    const char *match = sh_comp_buf[sh_comp_idx];
    sh_comp_idx = (sh_comp_idx + 1) % sh_comp_count;

    int old_len = len;
    /* '\033[nD' not '\b' x N - x86's kernel console makes '\b' destructive
     * (backspace_tty() blanks the cell it moves onto), which would erase
     * the word we're about to reprint anyway - see stdio.c's ax_readline()
     * for the same fix and the live bug it was found from. */
    if (len > start) ax_printf("\033[%dD", len - start);
    len = start;
    int i = 0;
    for (; match[i] && start + i < max - 1; i++) { buf[start + i] = match[i]; ax_putchar(buf[start + i]); }
    len = start + i;
    int erase = (old_len > len) ? (old_len - len) : 0;
    for (int k = 0; k < erase; k++) ax_putchar(' ');
    if (erase > 0) ax_printf("\033[%dD", erase);
    *plen = len; *ppos = len;
    sh_comp_last_pos = len;
    return 1;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    ax_shell_claim(1);  // захватываем клавиатуру у kernel shell
    ax_set_complete_hook(sh_complete);

    ax_print("\n\033[36mAxSH v0.1 - AxOS user shell\033[0m\n");
    ax_print("Run: <program> [args]  |  exit  |  help\n\n");

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

        if (sh_streq(line, "clear")) {
            ax_clear();
            continue;
        }

        // current_dir (см. "cd" ниже) хранит путь без ведущего "/" (или
        // пусто для корня) - pwd просто восстанавливает привычный вид.
        if (sh_streq(line, "pwd")) {
            if (current_dir[0] == '\0') {
                ax_print("/\n");
            } else {
                ax_printf("/%s\n", current_dir);
            }
            continue;
        }

        if (sh_streq(line, "help")) {
            ax_print("Built-in commands:\n");
            ax_print("  cd <dir> | cd / | cd ..   change directory\n");
            ax_print("  pwd                       print current directory\n");
            ax_print("  clear                     clear the screen\n");
            ax_print("  unlock / lock             unlock/lock the disk for writing\n");
            ax_print("  paste                     print the clipboard (clip get)\n");
            ax_print("  nice <pid> <1-10>         set a task's scheduler priority\n");
            ax_print("  kill <pid>                terminate a task by pid\n");
            ax_print("  help                      show this message\n");
            ax_print("  exit                      quit AxSH\n");
            ax_print("\n");
            ax_print("Syntax:\n");
            ax_print("  <program> [args]          run a program (e.g. ls, cat, grep)\n");
            ax_print("  cmd1 | cmd2               pipe (cmd1's output -> cmd2, one level)\n");
            ax_print("  cmd > file                redirect output to file\n");
            ax_print("  cmd &                     run in background\n");
            ax_print("\n");
            ax_print("Run 'ls' to see available files/programs on disk.\n");
            ax_print("\n");
            ax_print("Line editing: Up/Down=history, Left/Right/Home/End=cursor,\n");
            ax_print("Delete=forward-delete, Tab=complete filename\n");
            continue;
        }

        // "paste" - алиас "clip get" прямо в шелле: свежий .bin стоит
        // ~4.6 КБ только на crt0/libaxiom (см. clip.c) - не оправдано
        // плодить отдельную программу под однострочный алиас, даже после
        // расширения FAT12-тома до 256 КБ.
        if (sh_streq(line, "paste")) {
            static unsigned char clip_buf[CLIPBOARD_MAX_SIZE];
            unsigned int got = ax_clipboard_get(clip_buf, sizeof(clip_buf) - 1);
            clip_buf[got] = '\0';
            ax_print((char*)clip_buf);
            ax_putchar('\n');
            continue;
        }

        // "nice <pid> <priority>" - см. ax_set_priority (SYS_SET_PRIORITY).
        // pid - как в колонке "ID" вывода `ps`, не user_slot ("user:N").
        if (sh_strncmp(line, "nice ", 5) == 0) {
            const char* p = line + 5;
            int pid = 0, prio = 0;
            while (*p == ' ') p++;
            while (*p >= '0' && *p <= '9') pid = pid*10 + (*p++ - '0');
            while (*p == ' ') p++;
            while (*p >= '0' && *p <= '9') prio = prio*10 + (*p++ - '0');
            ax_set_priority(pid, prio);
            ax_printf("\033[32mnice: pid %d -> priority %d\033[0m\n", pid, prio);
            continue;
        }

        // "kill <pid>" - см. ax_kill (SYS_KILL). pid - как в колонке "ID"
        // вывода `ps`, как и у nice. Может убить задачу с ЛЮБОЙ консоли,
        // не только foreground-задачу активной (в отличие от Ctrl+C).
        if (sh_strncmp(line, "kill ", 5) == 0) {
            const char* p = line + 5;
            int pid = 0;
            while (*p == ' ') p++;
            while (*p >= '0' && *p <= '9') pid = pid*10 + (*p++ - '0');
            if (ax_kill(pid) == 0) {
                ax_printf("\033[32mkill: pid %d terminated\033[0m\n", pid);
            } else {
                ax_printf("\033[31mkill: no such process: %d\033[0m\n", pid);
            }
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

        // Pipe: "cmd1 | cmd2" - настоящий потоковый конвейер. cmd1's
        // stdout течёт в pipe_bufs[0] (ядро, kernel.c) через тот же
        // редирект-механизм, что и обычный "> file" (ax_exec_redir с
        // "PIPE:0" вместо имени файла), cmd2 читает "PIPE:0" как обычное
        // имя файла (ax_open/ax_fread - без изменений в cat.c/grep.c) -
        // SYS_FREAD блокирует cmd2, пока данных нет и cmd1 ещё жив (см.
        // task_wait_pipe_current, tasking.c). Оба запускаются СРАЗУ,
        // работают конкурентно - foreground-ожидание только на cmd2,
        // cmd1's собственный on_task_exit() выставит EOF пайпу сам. Один
        // уровень pipe, не цепочка.
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

                int slot1 = ax_exec_redir(cmd1, "PIPE:0");
                if (slot1 < 0) {
                    ax_print("\033[31msh: pipe: left side not found\033[0m\n");
                } else {
                    if (m > 0 && m < 58) {
                        cmd2[m] = ' ';
                        cmd2[m+1]='P'; cmd2[m+2]='I'; cmd2[m+3]='P'; cmd2[m+4]='E';
                        cmd2[m+5]=':'; cmd2[m+6]='0'; cmd2[m+7]='\0';
                    }
                    int slot2 = ax_exec(cmd2);
                    if (slot2 == -1) {
                        ax_print("\033[31msh: pipe: right side not found\033[0m\n");
                    } else if (slot2 == -2) {
                        ax_print("\033[31msh: no free slots\033[0m\n");
                    } else if (slot2 == -3) {
                        ax_print("\033[31msh: pipe: right side not a valid executable\033[0m\n");
                    } else {
                        ax_set_foreground(slot2);
                        while (ax_task_alive(slot2)) { ax_sleep_ms(10); }
                        ax_set_foreground(-1);
                    }
                }
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
        } else if (slot == -3) {
            ax_print("\033[31msh: not a valid executable\033[0m\n");
        } else if (has_bg) {
            ax_printf("\033[33m[%d] bg\033[0m\n", slot);
        } else {
            ax_set_foreground(slot);
            while (ax_task_alive(slot)) { ax_sleep_ms(10); }
            ax_set_foreground(-1);
            ax_printf("\033[36m[exit code: %d]\033[0m\n", ax_exit_code(slot));
            if (has_redir && redir[0])
                ax_printf("\033[32m-> %s\033[0m\n", redir);
        }
    }

    ax_shell_claim(0);  // возвращаем клавиатуру kernel shell
    return 0;
}
