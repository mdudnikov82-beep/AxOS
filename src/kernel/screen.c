static int cursor_x = 0;
static int cursor_y = 0;

// Текущий атрибут текста (низкий нибл = foreground, высокий = background),
// меняется командой SGR (\033[...m) и применяется к каждому новому символу.
static unsigned char current_attr = 0x0F; // белый на чёрном (старое поведение по умолчанию)

// ANSI SGR использует цвета 0-7 в порядке black,red,green,yellow,blue,magenta,cyan,white;
// в VGA-атрибуте те же восемь цветов лежат в другом порядке - таблица переводит один в другой.
static const unsigned char ansi_to_vga[8] = {0, 4, 2, 6, 1, 5, 3, 7};

// Состояние разбора escape-последовательности. Статическое (не локальное
// внутри print_string), потому что программа может слать её по одному
// символу за вызов (см. ax_putchar) - разбор должен переживать между вызовами.
enum { ANSI_TEXT, ANSI_ESC, ANSI_BRACKET };
static int ansi_state = ANSI_TEXT;
static int ansi_params[4];
static int ansi_param_count = 0;
static int ansi_param_active = 0;

// Виртуальные консоли (TTY): только активная отражается в реальной VGA-
// памяти (0xB8000); неактивные хранят свой экран в обычной RAM и не видны,
// пока на них не переключатся (Ctrl+Alt+F1/F2, см. kernel.c). Курсор, цвет
// и состояние ANSI-парсера тоже отдельные на каждую консоль - иначе,
// например, печать команды на одной консоли продолжалась бы с цветом,
// оставшимся от другой.
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
#define TTYS_BASE 0x130000
static struct tty_state* const ttys = (struct tty_state*) TTYS_BASE;
static int active_tty = 0;

// Заполняет неактивные консоли пустым экраном при загрузке - иначе их
// буфер (нулевые байты) выглядел бы иначе, чем настоящий "пустой" экран
// (символ 0x00, а не пробел с обычным атрибутом).
void init_ttys() {
    for (int n = 1; n < TTY_COUNT; n++) {
        for (int i = 0; i < TTY_BUFSZ; i += 2) {
            ttys[n].buffer[i] = ' ';
            ttys[n].buffer[i + 1] = 0x0F;
        }
        ttys[n].cursor_x = 0;
        ttys[n].cursor_y = 0;
        ttys[n].attr = 0x0F;
        ttys[n].ansi_state = ANSI_TEXT;
        ttys[n].ansi_param_count = 0;
        ttys[n].ansi_param_active = 0;
    }
}

static void tty_save(int n) {
    unsigned char* vidmem = (unsigned char*) 0xB8000;
    for (int i = 0; i < TTY_BUFSZ; i++) ttys[n].buffer[i] = vidmem[i];
    ttys[n].cursor_x = cursor_x;
    ttys[n].cursor_y = cursor_y;
    ttys[n].attr = current_attr;
    ttys[n].ansi_state = ansi_state;
    ttys[n].ansi_param_count = ansi_param_count;
    ttys[n].ansi_param_active = ansi_param_active;
    for (int i = 0; i < 4; i++) ttys[n].ansi_params[i] = ansi_params[i];
}

static void tty_load(int n) {
    unsigned char* vidmem = (unsigned char*) 0xB8000;
    for (int i = 0; i < TTY_BUFSZ; i++) vidmem[i] = ttys[n].buffer[i];
    cursor_x = ttys[n].cursor_x;
    cursor_y = ttys[n].cursor_y;
    current_attr = ttys[n].attr;
    ansi_state = ttys[n].ansi_state;
    ansi_param_count = ttys[n].ansi_param_count;
    ansi_param_active = ttys[n].ansi_param_active;
    for (int i = 0; i < 4; i++) ansi_params[i] = ttys[n].ansi_params[i];
}

int tty_active() {
    return active_tty;
}

void tty_switch(int n) {
    if (n < 0 || n >= TTY_COUNT || n == active_tty) return;
    tty_save(active_tty);
    active_tty = n;
    tty_load(n);
}

void clear_screen() {
    char* vidmem = (char*) 0xB8000;
    for (int i = 0; i < 80 * 25 * 2; i += 2) {
        vidmem[i] = ' ';
        vidmem[i+1] = current_attr;
    }
    cursor_x = 0;
    cursor_y = 0;
}

// Стирает символ перед курсором (используется клавишей Backspace)
void backspace() {
    if (cursor_x == 0 && cursor_y == 0) return;

    if (cursor_x == 0) {
        cursor_x = 79;
        cursor_y--;
    } else {
        cursor_x--;
    }

    unsigned char* vidmem = (unsigned char*) 0xB8000;
    int offset = (cursor_y * 80 + cursor_x) * 2;
    vidmem[offset] = ' ';
    vidmem[offset + 1] = current_attr;
}

// Сдвигает содержимое экрана на одну строку вверх и очищает последнюю
// строку — вызывается, когда курсор выходит за нижнюю границу (25 строк).
static void scroll() {
    unsigned char* vidmem = (unsigned char*) 0xB8000;

    for (int i = 0; i < 80 * 24 * 2; i++) {
        vidmem[i] = vidmem[i + 80 * 2];
    }

    for (int i = 80 * 24 * 2; i < 80 * 25 * 2; i += 2) {
        vidmem[i] = ' ';
        vidmem[i + 1] = current_attr;
    }

    cursor_y--;
}

static void ansi_reset_params() {
    for (int i = 0; i < 4; i++) ansi_params[i] = 0;
    ansi_param_count = 0;
    ansi_param_active = 0;
}

// SGR (Select Graphic Rendition) - \033[<params>m - меняет текущий цвет.
static void ansi_apply_sgr() {
    if (ansi_param_count == 0) { current_attr = 0x0F; return; }

    for (int i = 0; i < ansi_param_count; i++) {
        int p = ansi_params[i];
        unsigned char fg = current_attr & 0x0F;
        unsigned char bg = (current_attr >> 4) & 0x0F;

        if (p == 0) {
            current_attr = 0x0F;                                            // reset
        } else if (p == 1) {
            current_attr = (unsigned char)((bg << 4) | (fg | 0x08));         // bold -> яркий foreground
        } else if (p >= 30 && p <= 37) {
            current_attr = (unsigned char)((bg << 4) | ((fg & 0x08) | ansi_to_vga[p - 30]));
        } else if (p >= 40 && p <= 47) {
            current_attr = (unsigned char)((ansi_to_vga[p - 40] << 4) | fg);
        } else if (p >= 90 && p <= 97) {
            current_attr = (unsigned char)((bg << 4) | (0x08 | ansi_to_vga[p - 90]));
        } else if (p >= 100 && p <= 107) {
            current_attr = (unsigned char)(((0x08 | ansi_to_vga[p - 100]) << 4) | fg);
        }
        // остальные коды (2 - dim, 4 - underline, 7 - reverse...) у VGA не
        // имеют аналога в атрибуте символа - молча игнорируются.
    }
}

// Финальный байт CSI-последовательности (буква после параметров) решает,
// какую команду выполнить. Поддержаны только реально нужные шеллу: цвет,
// очистка экрана и позиционирование курсора.
static void ansi_dispatch(char final) {
    switch (final) {
        case 'm':
            ansi_apply_sgr();
            break;
        case 'J':
            // Поддерживается только полная очистка (\033[2J); вариантов
            // "очистить от курсора" (\033[0J/\033[1J) пока нет.
            if (ansi_param_count == 0 || ansi_params[0] == 2) clear_screen();
            break;
        case 'H':
        case 'f': {
            int row = ansi_param_count > 0 ? ansi_params[0] : 1;
            int col = ansi_param_count > 1 ? ansi_params[1] : 1;
            if (row < 1) row = 1;
            if (row > 25) row = 25;
            if (col < 1) col = 1;
            if (col > 80) col = 80;
            cursor_y = row - 1;
            cursor_x = col - 1;
            break;
        }
        default:
            break; // неизвестная команда - игнорируем, не ломая остальной вывод
    }
}

void print_string(char* str) {
    unsigned char* vidmem = (unsigned char*) 0xB8000;
    int i = 0;
    while (str[i] != '\0') {
        char c = str[i];

        if (ansi_state == ANSI_ESC) {
            if (c == '[') {
                ansi_state = ANSI_BRACKET;
                ansi_reset_params();
            } else {
                ansi_state = ANSI_TEXT; // не CSI - отбрасываем одинокий ESC
            }
            i++;
            continue;
        }

        if (ansi_state == ANSI_BRACKET) {
            if (c >= '0' && c <= '9') {
                ansi_params[ansi_param_count] = ansi_params[ansi_param_count] * 10 + (c - '0');
                ansi_param_active = 1;
            } else if (c == ';') {
                if (ansi_param_count < 3) ansi_param_count++;
                ansi_param_active = 0;
            } else {
                if (ansi_param_active && ansi_param_count < 4) ansi_param_count++;
                ansi_dispatch(c);
                ansi_state = ANSI_TEXT;
            }
            i++;
            continue;
        }

        if (c == '\033') { ansi_state = ANSI_ESC; i++; continue; }

        if (c == '\n') {
            cursor_x = 0;
            cursor_y++;
            if (cursor_y >= 25) scroll();
            i++;
            continue;
        }

        if (c == '\b') {
            backspace();
            i++;
            continue;
        }

        int offset = (cursor_y * 80 + cursor_x) * 2;
        vidmem[offset] = c;
        vidmem[offset + 1] = current_attr;

        cursor_x++;
        if (cursor_x >= 80) {
            cursor_x = 0;
            cursor_y++;
            if (cursor_y >= 25) scroll();
        }
        i++;
    }
}
