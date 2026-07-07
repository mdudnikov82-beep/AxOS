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

/* Читает строку с эхом и обработкой Backspace.
   Возвращает длину без '\0'. */
static int readline(char *buf, int max) {
    int i = 0;
    while (i < max - 1) {
        char c = getchar_rv();
        if (c == '\r' || c == '\n') {
            write(1, "\r\n", 2);
            break;
        }
        if (c == '\b' || c == 127) {   /* Backspace */
            if (i > 0) { i--; write(1, "\b \b", 3); }
            continue;
        }
        if (c < 0x20) continue;        /* ignore other control chars */
        buf[i++] = c;
        write(1, &c, 1);               /* echo */
    }
    buf[i] = '\0';
    return i;
}

/* ---- Встроенные команды ---- */

static void cmd_help(void) {
    print("\r\nAxSH/RV64 built-in commands:\r\n");
    print("  ls              list files on disk\r\n");
    print("  cat <FILE>      print file contents\r\n");
    print("  run <FILE>      run program (foreground, waits for exit)\r\n");
    print("  run <FILE> &    run program in background\r\n");
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
        write(1, name, nlen);
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

    /* Upcase filename */
    char fname[14]; int fi = 0;
    const char *p = tmp;
    while (*p && fi < 13) {
        char c = *p++;
        fname[fi++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
    }
    fname[fi] = '\0';

    if (!fname[0]) { print("Usage: run <FILE> [&]\r\n"); return; }

    int pid = exec(fname);
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
