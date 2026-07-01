// ANSI SGR использует цвета 0-7 в порядке black,red,green,yellow,blue,magenta,cyan,white;
// в VGA-атрибуте те же восемь цветов лежат в другом порядке - таблица переводит один в другой.
static const unsigned char ansi_to_vga[8] = {0, 4, 2, 6, 1, 5, 3, 7};

// Состояние разбора escape-последовательности.
enum { ANSI_TEXT, ANSI_ESC, ANSI_BRACKET };

// Виртуальные консоли (TTY): у каждой свой буфер экрана, курсор, цвет и
// состояние ANSI-парсера - печать на одной никогда не задевает другую,
// даже если консоль не видна на экране в данный момент (например, фоновая
// задача печатает что-то на неактивной консоли). Только активная консоль
// зеркалится в реальную VGA-память (0xB8000); print_string_to() пишет
// одновременно и в буфер своей консоли, и (если она активна) в VGA.
#define TTY_COUNT  2
#define TTY_BUFSZ  (80 * 25 * 2)

struct tty_state {
    unsigned char buffer[TTY_BUFSZ];
    int cursor_x;
    int cursor_y;
    unsigned char attr;
    int ansi_state;
    int ansi_params[4];
    int ansi_param_count;
    int ansi_param_active;
};

// ВАЖНО: хранится по фиксированному физическому адресу, а НЕ как статический
// массив в .bss. Раньше (static struct tty_state ttys[TTY_COUNT]) .bss ядра
// разрастался настолько, что заезжал на 0x7C00-0x7DFF - память загрузочного
// сектора, где живёт GDT! init_ttys() тогда буквально затирал GDT пробелами,
// и первое же обращение к сегментному регистру (ltr/смена CS) роняло систему
// с #GP -> тройной сбой. См. тот же приём в paging.h (PAGE_DIRECTORY/
// PAGE_TABLE) и tss.c (TSS_BASE) - оба по той же причине лежат в свободном
// промежутке 0x130000+ (после пула PD/PT изолированных задач, kernel.c/
// paging.h: PT_POOL_BASE=0x124000 + 4*0x1000 = заканчивается на 0x128000),
// а не в .bss.
#define TTYS_BASE 0x158000
static struct tty_state* const ttys = (struct tty_state*) TTYS_BASE;
static int active_tty = 0;

int tty_active() {
    return active_tty;
}

// Переключение консоли - это просто "что показываем" (active_tty + копия
// буфера новой консоли в VGA). Буфер консоли всегда актуален независимо от
// того, активна она или нет (см. tty_putc выше), так что сохранять старую
// консоль перед переключением не нужно - в отличие от первой версии этой
// фичи, где переключение делало memcpy и в обе стороны.
void tty_switch(int n) {
    if (n < 0 || n >= TTY_COUNT || n == active_tty) return;
    active_tty = n;
    unsigned char* vidmem = (unsigned char*) 0xB8000;
    for (int i = 0; i < TTY_BUFSZ; i++) vidmem[i] = ttys[n].buffer[i];
}

// Пишет один символ+атрибут в буфер консоли tty и, если она сейчас активна,
// тем же движением - в реальную VGA-память. Через эту функцию проходит весь
// вывод (print_string_to/clear_screen_tty/backspace_tty/scroll_tty) - так
// буфер неактивной консоли и видимый экран активной никогда не расходятся.
static void tty_putc(int tty, int offset, unsigned char ch, unsigned char attr) {
    ttys[tty].buffer[offset] = ch;
    ttys[tty].buffer[offset + 1] = attr;
    if (tty == active_tty) {
        unsigned char* vidmem = (unsigned char*) 0xB8000;
        vidmem[offset] = ch;
        vidmem[offset + 1] = attr;
    }
}

void clear_screen_tty(int tty) {
    for (int i = 0; i < TTY_BUFSZ; i += 2) tty_putc(tty, i, ' ', ttys[tty].attr);
    ttys[tty].cursor_x = 0;
    ttys[tty].cursor_y = 0;
}

void clear_screen() {
    clear_screen_tty(active_tty);
}

// Стирает символ перед курсором (используется клавишей Backspace)
void backspace_tty(int tty) {
    if (ttys[tty].cursor_x == 0 && ttys[tty].cursor_y == 0) return;

    if (ttys[tty].cursor_x == 0) {
        ttys[tty].cursor_x = 79;
        ttys[tty].cursor_y--;
    } else {
        ttys[tty].cursor_x--;
    }

    int offset = (ttys[tty].cursor_y * 80 + ttys[tty].cursor_x) * 2;
    tty_putc(tty, offset, ' ', ttys[tty].attr);
}

void backspace() {
    backspace_tty(active_tty);
}

// Сдвигает содержимое консоли на одну строку вверх и очищает последнюю -
// вызывается, когда курсор выходит за нижнюю границу (25 строк).
static void scroll_tty(int tty) {
    unsigned char* buf = ttys[tty].buffer;

    for (int i = 0; i < 80 * 24 * 2; i++) buf[i] = buf[i + 80 * 2];
    for (int i = 80 * 24 * 2; i < 80 * 25 * 2; i += 2) {
        buf[i] = ' ';
        buf[i + 1] = ttys[tty].attr;
    }
    ttys[tty].cursor_y--;

    if (tty == active_tty) {
        unsigned char* vidmem = (unsigned char*) 0xB8000;
        for (int i = 0; i < TTY_BUFSZ; i++) vidmem[i] = buf[i];
    }
}

static void ansi_reset_params(int tty) {
    for (int i = 0; i < 4; i++) ttys[tty].ansi_params[i] = 0;
    ttys[tty].ansi_param_count = 0;
    ttys[tty].ansi_param_active = 0;
}

// SGR (Select Graphic Rendition) - \033[<params>m - меняет текущий цвет.
static void ansi_apply_sgr(int tty) {
    if (ttys[tty].ansi_param_count == 0) { ttys[tty].attr = 0x0F; return; }

    for (int i = 0; i < ttys[tty].ansi_param_count; i++) {
        int p = ttys[tty].ansi_params[i];
        unsigned char fg = ttys[tty].attr & 0x0F;
        unsigned char bg = (ttys[tty].attr >> 4) & 0x0F;

        if (p == 0) {
            ttys[tty].attr = 0x0F;                                            // reset
        } else if (p == 1) {
            ttys[tty].attr = (unsigned char)((bg << 4) | (fg | 0x08));         // bold -> яркий foreground
        } else if (p >= 30 && p <= 37) {
            ttys[tty].attr = (unsigned char)((bg << 4) | ((fg & 0x08) | ansi_to_vga[p - 30]));
        } else if (p >= 40 && p <= 47) {
            ttys[tty].attr = (unsigned char)((ansi_to_vga[p - 40] << 4) | fg);
        } else if (p >= 90 && p <= 97) {
            ttys[tty].attr = (unsigned char)((bg << 4) | (0x08 | ansi_to_vga[p - 90]));
        } else if (p >= 100 && p <= 107) {
            ttys[tty].attr = (unsigned char)(((0x08 | ansi_to_vga[p - 100]) << 4) | fg);
        }
        // остальные коды (2 - dim, 4 - underline, 7 - reverse...) у VGA не
        // имеют аналога в атрибуте символа - молча игнорируются.
    }
}

// Финальный байт CSI-последовательности (буква после параметров) решает,
// какую команду выполнить. Поддержаны только реально нужные шеллу: цвет,
// очистка экрана и позиционирование курсора.
static void ansi_dispatch(int tty, char final) {
    switch (final) {
        case 'm':
            ansi_apply_sgr(tty);
            break;
        case 'J':
            // Поддерживается только полная очистка (\033[2J); вариантов
            // "очистить от курсора" (\033[0J/\033[1J) пока нет.
            if (ttys[tty].ansi_param_count == 0 || ttys[tty].ansi_params[0] == 2) clear_screen_tty(tty);
            break;
        case 'H':
        case 'f': {
            int row = ttys[tty].ansi_param_count > 0 ? ttys[tty].ansi_params[0] : 1;
            int col = ttys[tty].ansi_param_count > 1 ? ttys[tty].ansi_params[1] : 1;
            if (row < 1) row = 1;
            if (row > 25) row = 25;
            if (col < 1) col = 1;
            if (col > 80) col = 80;
            ttys[tty].cursor_y = row - 1;
            ttys[tty].cursor_x = col - 1;
            break;
        }
        default:
            break; // неизвестная команда - игнорируем, не ломая остальной вывод
    }
}

void print_string_to(int tty, char* str) {
    int i = 0;
    while (str[i] != '\0') {
        char c = str[i];

        if (ttys[tty].ansi_state == ANSI_ESC) {
            if (c == '[') {
                ttys[tty].ansi_state = ANSI_BRACKET;
                ansi_reset_params(tty);
            } else {
                ttys[tty].ansi_state = ANSI_TEXT; // не CSI - отбрасываем одинокий ESC
            }
            i++;
            continue;
        }

        if (ttys[tty].ansi_state == ANSI_BRACKET) {
            if (c >= '0' && c <= '9') {
                ttys[tty].ansi_params[ttys[tty].ansi_param_count] =
                    ttys[tty].ansi_params[ttys[tty].ansi_param_count] * 10 + (c - '0');
                ttys[tty].ansi_param_active = 1;
            } else if (c == ';') {
                if (ttys[tty].ansi_param_count < 3) ttys[tty].ansi_param_count++;
                ttys[tty].ansi_param_active = 0;
            } else {
                if (ttys[tty].ansi_param_active && ttys[tty].ansi_param_count < 4) ttys[tty].ansi_param_count++;
                ansi_dispatch(tty, c);
                ttys[tty].ansi_state = ANSI_TEXT;
            }
            i++;
            continue;
        }

        if (c == '\033') { ttys[tty].ansi_state = ANSI_ESC; i++; continue; }

        if (c == '\n') {
            ttys[tty].cursor_x = 0;
            ttys[tty].cursor_y++;
            if (ttys[tty].cursor_y >= 25) scroll_tty(tty);
            i++;
            continue;
        }

        if (c == '\b') {
            backspace_tty(tty);
            i++;
            continue;
        }

        int offset = (ttys[tty].cursor_y * 80 + ttys[tty].cursor_x) * 2;
        tty_putc(tty, offset, c, ttys[tty].attr);

        ttys[tty].cursor_x++;
        if (ttys[tty].cursor_x >= 80) {
            ttys[tty].cursor_x = 0;
            ttys[tty].cursor_y++;
            if (ttys[tty].cursor_y >= 25) scroll_tty(tty);
        }
        i++;
    }
}

void print_string(char* str) {
    print_string_to(active_tty, str);
}

// Инициализирует ВСЕ консоли (включая активную - 0) одинаковым пустым
// экраном с обычным атрибутом и сбрасывает курсор/ANSI-состояние, а затем
// зеркалит активную в VGA. Вызывается один раз при загрузке, до этого
// ttys[] лежит по фиксированному адресу с произвольным мусором в памяти
// (не .bss - см. комментарий у TTYS_BASE), поэтому даже "своя" консоль 0
// нуждается в явной инициализации, а не только запасные 1..N-1.
void init_ttys() {
    for (int n = 0; n < TTY_COUNT; n++) {
        ttys[n].cursor_x = 0;
        ttys[n].cursor_y = 0;
        ttys[n].attr = 0x0F;
        ttys[n].ansi_state = ANSI_TEXT;
        ttys[n].ansi_param_count = 0;
        ttys[n].ansi_param_active = 0;
        for (int i = 0; i < TTY_BUFSZ; i += 2) {
            ttys[n].buffer[i] = ' ';
            ttys[n].buffer[i + 1] = 0x0F;
        }
    }

    unsigned char* vidmem = (unsigned char*) 0xB8000;
    for (int i = 0; i < TTY_BUFSZ; i++) vidmem[i] = ttys[active_tty].buffer[i];
}
