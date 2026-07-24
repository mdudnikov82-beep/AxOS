#include "syscall.h"

/* ---- мини-libc ---- */

static long slen(const char *s) { long n = 0; while (s[n]) n++; return n; }

static int seq(const char *a, const char *b) {
    while (*a && *b) if (*a++ != *b++) return 0;
    return *a == *b;
}

static int sncmp(const char *a, const char *b, int n) {
    for (int i = 0; i < n; i++) {
        if (!a[i] && !b[i]) return 0;
        if (a[i] != b[i])   return (unsigned char)a[i] - (unsigned char)b[i];
    }
    return 0;
}

static void print(const char *s) { write(1, s, slen(s)); }

static void print_udec(unsigned long v) {
    char buf[20]; int i = 0;
    if (!v) { write(1, "0", 1); return; }
    while (v) { buf[i++] = '0' + (v % 10); v /= 10; }
    /* reverse */
    for (int a = 0, b = i-1; a < b; a++, b--) { char t = buf[a]; buf[a] = buf[b]; buf[b] = t; }
    write(1, buf, i);
}

/* Вернуть указатель на первый символ после пробелов */
static const char *skip_spaces(const char *p) {
    while (*p == ' ') p++;
    return p;
}

/* История команд - кольцевой буфер, тот же дизайн, что и у x86
 * (src/libaxiom/src/stdio.c's hist[HIST_CAP][HIST_LEN]), просто прямо
 * в axsh.c - тут нет общей библиотеки. */
#define HIST_CAP 8
#define HIST_LEN 80
static char hist[HIST_CAP][HIST_LEN];
static int  hist_count = 0;

/* Дописывает buf[pos..len) на экран, затирает `erase` "хвостовых"
 * старых символов пробелами (нужно только когда строка стала короче -
 * backspace/delete/более короткая запись истории), затем возвращает
 * курсор обратно к pos через backspace'ы. Один переиспользуемый
 * помощник вместо трёх разных мест, которые раньше стирали строку
 * по-разному (и x86-версия с историей всё ещё имеет тут реальный баг -
 * не затирает "хвост" при подстановке БОЛЕЕ КОРОТКОЙ записи истории). */
static void redraw_tail(const char *buf, int pos, int len, int erase) {
    for (int i = pos; i < len; i++) write(1, &buf[i], 1);
    for (int i = 0; i < erase; i++) write(1, " ", 1);
    int back = (len - pos) + erase;
    for (int i = 0; i < back; i++) write(1, "\b", 1);
}

/* Читает строку с полным редактированием: History (Up/Down через ESC[A/B),
   курсор (Left/Right/Home/End/Delete через ESC[C/D/H или F/1~/4~/3~),
   вставка/удаление в середине строки, Tab-автодополнение имён файлов.
   Возвращает длину без '\0'. */
static int readline(char *buf, int max) {
    int len = 0, pos = 0;
    int hist_pos = hist_count;   /* hist_count = "текущий ввод", за пределами истории */
    char saved[HIST_LEN];
    saved[0] = '\0';

    /* Автодополнение: контекст сбрасывается любой НЕ-Tab правкой, так что
     * повторный Tab после ввода новых символов пересканирует диск заново;
     * повторный Tab БЕЗ других правок между ними листает совпадения. */
    char comp_buf[16][14];
    int comp_count = 0, comp_idx = 0, comp_word_start = -1, comp_last_pos = -1;

    for (;;) {
        char c = getchar_rv();

        if (c == '\r' || c == '\n') {
            write(1, "\r\n", 2);
            break;
        }

        if (c == 0x1B) {   /* ESC - возможно начало CSI-последовательности от реального терминала */
            char c1 = getchar_rv();
            if (c1 != '[') continue;   /* непонятная escape-последовательность - молча игнорируем */
            char final = getchar_rv();
            if (final >= '1' && final <= '9') {
                getchar_rv();   /* ожидаем завершающий '~', сам код уже есть в final */
            }

            int hist_dir = 0;
            if (final == 'A') hist_dir = -1;        /* Up */
            else if (final == 'B') hist_dir = 1;    /* Down */
            else if (final == 'C') {                /* Right */
                if (pos < len) { write(1, &buf[pos], 1); pos++; }
                comp_word_start = -1;
                continue;
            } else if (final == 'D') {              /* Left */
                if (pos > 0) { pos--; write(1, "\b", 1); }
                comp_word_start = -1;
                continue;
            } else if (final == 'H' || final == '1') {   /* Home */
                while (pos > 0) { pos--; write(1, "\b", 1); }
                comp_word_start = -1;
                continue;
            } else if (final == 'F' || final == '4') {   /* End */
                while (pos < len) { write(1, &buf[pos], 1); pos++; }
                comp_word_start = -1;
                continue;
            } else if (final == '3') {   /* Delete (forward) */
                if (pos < len) {
                    for (int i = pos; i < len - 1; i++) buf[i] = buf[i + 1];
                    len--;
                    redraw_tail(buf, pos, len, 1);
                }
                comp_word_start = -1;
                continue;
            } else {
                continue;   /* неизвестный код CSI - игнорируем */
            }

            /* hist_dir != 0 отсюда - общая логика перелистывания истории */
            int new_pos = hist_pos + hist_dir;
            if (new_pos >= 0 && new_pos <= hist_count) {
                if (hist_pos == hist_count) {
                    int si; for (si = 0; si < len && si < HIST_LEN - 1; si++) saved[si] = buf[si];
                    saved[si] = '\0';
                }
                while (pos > 0) { pos--; write(1, "\b", 1); }
                int old_len = len;
                hist_pos = new_pos;
                const char *entry = (hist_pos == hist_count) ? saved : hist[hist_pos];
                int i = 0;
                for (; entry[i] && i < max - 1; i++) { buf[i] = entry[i]; write(1, &buf[i], 1); }
                len = i; pos = i;
                int erase = (old_len > len) ? (old_len - len) : 0;
                for (int k = 0; k < erase; k++) write(1, " ", 1);
                for (int k = 0; k < erase; k++) write(1, "\b", 1);
            }
            comp_word_start = -1;
            continue;
        }

        if (c == '\b' || c == 127) {   /* Backspace */
            if (pos > 0) {
                pos--;
                for (int i = pos; i < len - 1; i++) buf[i] = buf[i + 1];
                len--;
                write(1, "\b", 1);
                redraw_tail(buf, pos, len, 1);
            }
            comp_word_start = -1;
            continue;
        }

        if (c == '\t') {   /* Tab - автодополнение имени файла (только в конце строки) */
            if (pos != len) continue;
            int start = len;
            while (start > 0 && buf[start - 1] != ' ') start--;

            /* Повтор (циклический переход к следующему совпадению) только
             * если ни курсор, ни начало слова не изменились с прошлого
             * Tab - если пользователь дописал ещё символы между двумя
             * нажатиями (тем самым сузив префикс), это НЕ повтор и нужно
             * пересканировать диск заново, а не листать старые совпадения. */
            int is_repeat = (comp_word_start == start && comp_last_pos == pos);
            if (!is_repeat) {
                comp_word_start = start;
                comp_count = 0;
                comp_idx = 0;
                char prefix[14]; int pl = 0;
                for (int i = start; i < len && pl < 13; i++) {
                    char ch = buf[i];
                    prefix[pl++] = (ch >= 'a' && ch <= 'z') ? (char)(ch - 32) : ch;   /* FAT12 имена - верхний регистр */
                }
                prefix[pl] = '\0';

                char name[16]; unsigned int size;
                for (unsigned int i = 0; comp_count < 16; i++) {
                    name[0] = '\0';
                    if (!readdir(i, name, &size)) break;
                    if (sncmp(name, prefix, pl) == 0) {
                        int k = 0; while (name[k] && k < 13) { comp_buf[comp_count][k] = name[k]; k++; }
                        comp_buf[comp_count][k] = '\0';
                        comp_count++;
                    }
                }
            }
            if (comp_count == 0) continue;

            const char *match = comp_buf[comp_idx];
            comp_idx = (comp_idx + 1) % comp_count;

            int old_len = len;
            while (len > start) { len--; write(1, "\b", 1); }
            int i = 0;
            for (; match[i] && start + i < max - 1; i++) { buf[start + i] = match[i]; write(1, &buf[start + i], 1); }
            len = start + i; pos = len;
            int erase = (old_len > len) ? (old_len - len) : 0;
            for (int k = 0; k < erase; k++) write(1, " ", 1);
            for (int k = 0; k < erase; k++) write(1, "\b", 1);
            comp_last_pos = pos;
            continue;
        }

        if ((unsigned char)c < 0x20) continue;   /* прочие управляющие символы игнорируем */

        comp_word_start = -1;
        if (len < max - 1) {
            for (int i = len; i > pos; i--) buf[i] = buf[i - 1];
            buf[pos] = c; len++; pos++;
            write(1, &c, 1);
            redraw_tail(buf, pos, len, 0);
        }
    }
    buf[len] = '\0';

    if (len > 0) {
        if (hist_count == HIST_CAP) {
            for (int k = 0; k < HIST_CAP - 1; k++)
                for (int j = 0; j < HIST_LEN; j++) hist[k][j] = hist[k + 1][j];
            hist_count--;
        }
        int j; for (j = 0; j < len && j < HIST_LEN - 1; j++) hist[hist_count][j] = buf[j];
        hist[hist_count][j] = '\0';
        hist_count++;
    }
    return len;
}

/* ---- Встроенные команды ---- */

static void cmd_help(void) {
    print("\r\nAxSH/RV64 built-in commands:\r\n");
    print("  ls              list files on disk\r\n");
    print("  cat <FILE>      print file contents\r\n");
    print("  run <FILE> [args]  run program (foreground, waits for exit)\r\n");
    print("  run <FILE> [args] &  run program in background\r\n");
    print("  cmd1 | cmd2     stream cmd1's output into cmd2's stdin\r\n");
    print("  kill <PID>      terminate a background process\r\n");
    print("  nice <PID> <N>  set a task's scheduler priority (1-10)\r\n");
    print("  ps              list all processes\r\n");
    print("  echo [text]     print text\r\n");
    print("  write <F> <t>   create/overwrite file F with text t\r\n");
    print("  rm <FILE>       delete file\r\n");
    print("  clear           clear the screen\r\n");
    print("  time            print current timer tick\r\n");
    print("  help            this message\r\n");
    print("  exit            shutdown\r\n");
    print("  reboot          restart the machine\r\n\r\n");
    print("Line editing: Up/Down=history, Left/Right/Home/End=cursor,\r\n");
    print("Delete=forward-delete, Tab=complete filename\r\n\r\n");
}

static void cmd_ls(void) {
    char name[16];
    unsigned int size;
    int found = 0;
    print("\r\n");
    for (unsigned int i = 0; ; i++) {
        name[0] = '\0';
        if (!readdir(i, name, &size)) break;
        /* Print name padded to 14 chars */
        int nlen = (int)slen(name);
        print("\033[32m");
        write(1, name, nlen);
        print("\033[0m");
        for (int s = nlen; s < 14; s++) write(1, " ", 1);
        print_udec(size);
        print(" B\r\n");
        found = 1;
    }
    if (!found) print("(empty)\r\n");
    print("\r\n");
}

static void cmd_cat(const char *arg) {
    if (!arg || !*arg) { print("Usage: cat <FILENAME>\r\n"); return; }

    /* Upcase filename */
    char fname[14]; int fi = 0;
    while (*arg && fi < 13) {
        char c = *arg++;
        fname[fi++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    fname[fi] = '\0';

    int fd = open(fname, 0);
    if (fd < 0) { print("cat: file not found: "); print(fname); print("\r\n"); return; }

    char buf[64];
    long n;
    print("\r\n");
    while ((n = read(fd, buf, sizeof(buf))) > 0) {
        /* convert bare \n to \r\n */
        for (long k = 0; k < n; k++) {
            if (buf[k] == '\n') write(1, "\r\n", 2);
            else write(1, &buf[k], 1);
        }
    }
    close(fd);
    print("\r\n");
}

static void cmd_echo(const char *arg) {
    print("\r\n");
    if (arg && *arg) print(arg);
    print("\r\n");
}

/* "write <FILE> <text...>" — creates/overwrites FILE with text */
static void cmd_write(const char *arg) {
    print("\r\n");
    if (!arg || !*arg) { print("Usage: write <FILE> <text>\r\n\r\n"); return; }

    /* First token = filename, rest = text */
    char fname[14]; int fi = 0;
    const char *p = arg;
    while (*p && *p != ' ' && fi < 13) {
        char c = *p++;
        fname[fi++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    fname[fi] = '\0';
    p = skip_spaces(p);

    if (!fname[0] || !*p) { print("Usage: write <FILE> <text>\r\n\r\n"); return; }

    long len = slen(p);
    if (writefile(fname, p, len)) {
        print("Written.\r\n\r\n");
    } else {
        print("write: failed (disk locked or no space)\r\n\r\n");
    }
}

/* "rm <FILE>" */
static void cmd_rm(const char *arg) {
    print("\r\n");
    if (!arg || !*arg) { print("Usage: rm <FILE>\r\n\r\n"); return; }

    char fname[14]; int fi = 0;
    while (*arg && fi < 13) {
        char c = *arg++;
        fname[fi++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    fname[fi] = '\0';

    int result = unlink(fname);
    if (result == 1) {
        print("removed '"); print(fname); print("'\r\n\r\n");
    } else if (result == -1) {
        print("rm: no such file: "); print(fname); print("\r\n\r\n");
    } else {
        print("rm: failed (disk locked or not ready)\r\n\r\n");
    }
}

static void cmd_time(void) {
    print("\r\nTimer: ");
    print_udec((unsigned long)gettime());
    print(" ticks\r\n\r\n");
}

static void cmd_run(const char *arg) {
    if (!arg || !*arg) { print("Usage: run <FILE> [&]\r\n"); return; }

    /* Check for background flag (&) at the end */
    char tmp[80]; int ti = 0;
    while (*arg && ti < 79) { tmp[ti++] = *arg++; }
    tmp[ti] = '\0';
    /* Strip trailing spaces */
    while (ti > 0 && tmp[ti-1] == ' ') { tmp[--ti] = '\0'; }
    /* Detect & */
    int bg = 0;
    if (ti > 0 && tmp[ti-1] == '&') { bg = 1; tmp[--ti] = '\0'; }
    /* Strip spaces between filename and & */
    while (ti > 0 && tmp[ti-1] == ' ') { tmp[--ti] = '\0'; }

    /* Разбиваем на имя файла (до первого пробела, приводим к верхнему
     * регистру - FAT12) и остаток аргументов (БЕЗ приведения регистра -
     * это пользовательские данные, например паттерн grep, портить их
     * uppercase'ом нельзя). Раньше весь tmp целиком (включая любые
     * аргументы) грузился в 13-байтный fname с uppercase - многословный
     * run никогда не работал по-настоящему. */
    char fname[14]; int fi = 0;
    const char *p = tmp;
    while (*p && *p != ' ' && fi < 13) {
        char c = *p++;
        fname[fi++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    fname[fi] = '\0';
    while (*p == ' ') p++;

    if (!fname[0]) { print("Usage: run <FILE> [&]\r\n"); return; }

    char cmdline[80]; int ci = 0;
    { const char *s = fname; while (*s && ci < 79) cmdline[ci++] = *s++; }
    if (*p) {
        cmdline[ci++] = ' ';
        while (*p && ci < 79) cmdline[ci++] = *p++;
    }
    cmdline[ci] = '\0';

    int pid = exec(cmdline);
    if (pid < 0) {
        print("run: failed to load ");
        print(fname);
        print("\r\n");
        return;
    }

    if (bg) {
        print("[");
        print_udec((unsigned long)pid);
        print("] ");
        print(fname);
        print(" &\r\n");
        /* Return immediately — background process runs via scheduler */
    } else {
        print("\r\n[run] pid=");
        print_udec((unsigned long)pid);
        print(" started...\r\n");
        int code = wait(pid);
        print("[run] pid=");
        print_udec((unsigned long)pid);
        print(" exited, code=");
        print_udec((unsigned long)(unsigned int)code);
        print("\r\n\r\n");
    }
}

/* "cmd1 | cmd2" - настоящий потоковый конвейер (см. exec_pipe(),
 * syscall.h): оба запускаются СРАЗУ, cmd1's stdout течёт в pipe_bufs[0]
 * (ядро, syscall.c), cmd2's stdin читает оттуда же - блокируется, пока
 * пусто и cmd1 жив (см. PROC_WAITING_PIPE). foreground-ожидание только
 * на cmd2 - cmd1's собственный SYS_EXIT сам выставит writer_done. Один
 * уровень pipe, не цепочка - как и на x86. pipe_pos - индекс '|' в line. */
static void cmd_pipe(const char *line, int pipe_pos) {
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

    if (!cmd1[0] || !cmd2[0]) { print("Usage: cmd1 | cmd2\r\n"); return; }

    int pid1 = exec_pipe(cmd1, 0, -1);
    if (pid1 < 0) { print("sh: pipe: left side not found\r\n"); return; }

    int pid2 = exec_pipe(cmd2, -1, 0);
    if (pid2 < 0) { print("sh: pipe: right side not found\r\n"); return; }

    print("\r\n[pipe] pid=");
    print_udec((unsigned long)pid2);
    print(" started...\r\n");
    int code = wait(pid2);
    print("[pipe] pid=");
    print_udec((unsigned long)pid2);
    print(" exited, code=");
    print_udec((unsigned long)(unsigned int)code);
    print("\r\n\r\n");
}

static void cmd_kill(const char *arg) {
    if (!arg || !*arg) { print("Usage: kill <PID>\r\n"); return; }
    int pid = 0;
    const char *p = arg;
    while (*p >= '0' && *p <= '9') pid = pid * 10 + (*p++ - '0');
    if (kill(pid) < 0) {
        print("kill: no such process: ");
        print(arg);
        print("\r\n");
        return;
    }
    print("[kill] pid=");
    print_udec((unsigned long)pid);
    print(" terminated\r\n");
}

static void cmd_nice(const char *arg) {
    if (!arg || !*arg) { print("Usage: nice <PID> <1-10>\r\n"); return; }
    const char *p = arg;
    int pid = 0, prio = 0;
    while (*p >= '0' && *p <= '9') pid = pid * 10 + (*p++ - '0');
    while (*p == ' ') p++;
    while (*p >= '0' && *p <= '9') prio = prio * 10 + (*p++ - '0');
    set_priority(pid, prio);
    print("nice: pid=");
    print_udec((unsigned long)pid);
    print(" -> priority=");
    print_udec((unsigned long)prio);
    print("\r\n");
}

static void cmd_ps(void) {
    print("\r\n");
    ps();
    print("\r\n");
}

/* ---- Main ---- */

int main(void) {
    print("\r\n");
    print("\033[1;36m  AxOS/RV64  --  AxSH v0.1\033[0m\r\n");
    print("  Type 'help' for commands.\r\n\r\n");

    char line[80];

    while (1) {
        print("\033[32m[");
        print_udec((unsigned long)getpid());
        print("] AxOS>\033[0m ");

        int len = readline(line, sizeof(line));
        if (len == 0) continue;

        {
            int pipe_pos = -1;
            for (int i = 0; line[i]; i++) { if (line[i] == '|') { pipe_pos = i; break; } }
            if (pipe_pos >= 0) { cmd_pipe(line, pipe_pos); continue; }
        }

        if (seq(line, "exit") || seq(line, "quit")) {
            print("Goodbye.\r\n");
            shutdown();
        }
        if (seq(line, "reboot")) {
            print("Rebooting...\r\n");
            reboot();
        }
        if (seq(line, "help"))  { cmd_help(); continue; }
        if (seq(line, "ls"))    { cmd_ls();   continue; }
        if (seq(line, "ps"))    { cmd_ps();   continue; }
        if (seq(line, "clear")) { print("\033[2J\033[H"); continue; }
        if (seq(line, "time"))  { cmd_time(); continue; }

        if (sncmp(line, "cat ", 4) == 0) {
            cmd_cat(skip_spaces(line + 4));
            continue;
        }
        if (seq(line, "cat")) { cmd_cat(0); continue; }

        if (sncmp(line, "run ", 4) == 0) {
            cmd_run(skip_spaces(line + 4));
            continue;
        }
        if (seq(line, "run")) { cmd_run(0); continue; }

        if (sncmp(line, "kill ", 5) == 0) {
            cmd_kill(skip_spaces(line + 5));
            continue;
        }
        if (seq(line, "kill")) { cmd_kill(0); continue; }

        if (sncmp(line, "nice ", 5) == 0) {
            cmd_nice(skip_spaces(line + 5));
            continue;
        }
        if (seq(line, "nice")) { cmd_nice(0); continue; }

        if (sncmp(line, "echo ", 5) == 0) {
            cmd_echo(skip_spaces(line + 5));
            continue;
        }
        if (seq(line, "echo")) { cmd_echo(""); continue; }

        if (sncmp(line, "write ", 6) == 0) {
            cmd_write(skip_spaces(line + 6));
            continue;
        }
        if (seq(line, "write")) { cmd_write(0); continue; }

        if (sncmp(line, "rm ", 3) == 0) {
            cmd_rm(skip_spaces(line + 3));
            continue;
        }
        if (seq(line, "rm")) { cmd_rm(0); continue; }

        /* Unknown command */
        print("Unknown command: ");
        print(line);
        print("\r\n");
    }
    return 0;
}
