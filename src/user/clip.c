#include "axiom.h"

static int streq(const char* a, const char* b) {
    while (*a && *b) if (*a++ != *b++) return 0;
    return *a == *b;
}

static unsigned int parse_uint(const char* s) {
    unsigned int v = 0;
    while (*s >= '0' && *s <= '9') v = v * 10 + (unsigned int)(*s++ - '0');
    return v;
}

// Записывает в буфер обмена текст из argv[from..argc), пробелы между
// аргументами восстанавливаются. Уровень содержимого - текущий MLS-уровень
// ВЫЗЫВАЮЩЕГО (ax_set_level выше, если был) - см. sys_clipboard_set.
static void do_set(int argc, char** argv, int from) {
    static char text[CLIPBOARD_MAX_SIZE];
    int len = 0;
    for (int i = from; i < argc; i++) {
        char* a = argv[i];
        while (*a && len < (int)sizeof(text) - 1) text[len++] = *a++;
        if (i < argc - 1 && len < (int)sizeof(text) - 1) text[len++] = ' ';
    }
    ax_clipboard_set((unsigned char*)text, (unsigned int)len);
    ax_printf("\033[32mclip: set %d bytes\033[0m\n", len);
}

// Читает буфер обмена на текущем MLS-уровне вызывающего; ax_clipboard_get
// вернёт 0 байт (и ядро напечатает "avc: denied ... no read up"), если
// уровень читателя ниже уровня, на котором буфер был заполнен.
static void do_get(void) {
    static unsigned char buf[CLIPBOARD_MAX_SIZE];
    unsigned int got = ax_clipboard_get(buf, sizeof(buf) - 1);
    buf[got] = '\0';
    ax_print((char*)buf);
    ax_putchar('\n');
}

int main(int argc, char** argv) {
    if (argc < 2 || (!streq(argv[1], "set") && !streq(argv[1], "get") &&
                     !streq(argv[1], "clear") && !streq(argv[1], "level"))) {
        ax_print("Usage: clip set <text>  |  clip get  |  clip clear\n"
                 "       clip level <0-15> set <text>  |  clip level <0-15> get\n"
                 "       clip level <0-15> idle <ms>\n");
        return 1;
    }

    // "level N set ..."/"level N get" - один процесс, поднимающий себе
    // MLS-уровень и СРАЗУ ЖЕ пишущий/читающий буфер обмена на этом уровне.
    // Раздельные "clip level N" + отдельный "clip get" не сработали бы:
    // каждый run/exec - новый процесс, который снова стартует на s0 (см.
    // task_set_current_mls_level, tasking.c) - уровень не переживает выход
    // из задачи, ровно как и сам контекст процесса в SELinux.
    if (streq(argv[1], "level")) {
        if (argc < 4 || (!streq(argv[3], "set") && !streq(argv[3], "get") && !streq(argv[3], "idle"))) {
            ax_print("Usage: clip level <0-15> set <text>  |  clip level <0-15> get\n"
                     "       clip level <0-15> idle <ms>\n");
            return 1;
        }
        unsigned int level = parse_uint(argv[2]);
        ax_set_level(level);
        if (streq(argv[3], "set")) {
            do_set(argc, argv, 4);
        } else if (streq(argv[3], "idle")) {
            // Держит процесс живым на повышенном уровне N миллисекунд - чтобы
            // успеть посмотреть его в `ps` ИЗ ДРУГОГО процесса (свежий "ps"
            // всегда стартует на s0 - см. ax_mls_dominates в kernel.c). Без
            // этого продемонстрировать MLS-редакцию ps было бы нечем: только
            // один уровень переживает между exec, и тот - текущего процесса.
            unsigned int ms = argc >= 5 ? parse_uint(argv[4]) : 5000;
            ax_printf("clip: idling at level s%u for %u ms (run 'ps' now)\n", level, ms);
            ax_sleep_ms(ms);
        } else {
            do_get();
        }
        return 0;
    }

    if (streq(argv[1], "set")) {
        do_set(argc, argv, 2);
        return 0;
    }

    if (streq(argv[1], "clear")) {
        // size=0, но указатель всё равно должен лежать в окне задачи -
        // validate_user_ptr (kernel.c) не пропустит NULL/0, даже с size=0.
        static unsigned char dummy;
        ax_clipboard_set(&dummy, 0);
        ax_print("\033[32mclip: cleared\033[0m\n");
        return 0;
    }

    do_get();
    return 0;
}
