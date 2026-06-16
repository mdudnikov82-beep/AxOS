#include "../include/axiom.h"
#include <stdarg.h>

// MinGW вставляет вызов __main() в начало main() для инициализации рантайма.
// В нашей freestanding среде он не нужен — пустая заглушка убирает undefined reference.
void __main(void) {}

void ax_putchar(char c) {
    char s[2] = {c, '\0'};
    ax_print(s);
}

void ax_print_uint(unsigned int n) {
    if (n == 0) { ax_putchar('0'); return; }
    char buf[10];
    int i = 0;
    while (n > 0) { buf[i++] = '0' + (n % 10); n /= 10; }
    while (i > 0) ax_putchar(buf[--i]);
}

static void print_uint_padded(unsigned int n, int width, int zero_pad) {
    char buf[10];
    int i = 0;
    if (n == 0) buf[i++] = '0';
    else { unsigned int v = n; while (v > 0) { buf[i++] = '0' + v % 10; v /= 10; } }
    char pad = zero_pad ? '0' : ' ';
    while (i < width) ax_putchar(pad), width--;
    while (i > 0) ax_putchar(buf[--i]);
}

static void print_hex_padded(unsigned int n, int width, int zero_pad) {
    char buf[8];
    int i = 0;
    if (n == 0) buf[i++] = '0';
    else { unsigned int v = n; while (v > 0) { int d = v & 0xF; buf[i++] = d < 10 ? '0'+d : 'a'+d-10; v >>= 4; } }
    char pad = zero_pad ? '0' : ' ';
    while (i < width) ax_putchar(pad), width--;
    while (i > 0) ax_putchar(buf[--i]);
}

void ax_printf(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    for (const char* p = fmt; *p; p++) {
        if (*p != '%') { ax_putchar(*p); continue; }
        p++;
        int zero_pad = (*p == '0');
        if (zero_pad) p++;
        int width = 0;
        while (*p >= '1' && *p <= '9') { width = width * 10 + (*p++ - '0'); }
        switch (*p) {
            case 's': ax_print(va_arg(ap, char*));                              break;
            case 'd': { int n = va_arg(ap, int);
                        if (n < 0) { ax_putchar('-'); print_uint_padded((unsigned int)(-n), width, zero_pad); }
                        else print_uint_padded((unsigned int)n, width, zero_pad); break; }
            case 'u': print_uint_padded(va_arg(ap, unsigned int), width, zero_pad); break;
            case 'x': print_hex_padded(va_arg(ap, unsigned int), width, zero_pad);  break;
            case 'c': ax_putchar((char)va_arg(ap, int));                        break;
            case '%': ax_putchar('%');                                           break;
            case '\0': ax_putchar('%'); va_end(ap); return;
            default:  ax_putchar('%'); ax_putchar(*p);                          break;
        }
    }
    va_end(ap);
}

// История команд (кольцевой буфер, 8 записей по 64 байта)
#define HIST_CAP 8
#define HIST_LEN 64
static char hist[HIST_CAP][HIST_LEN];
static int  hist_len = 0;

// 0x11 = стрелка вверх, 0x12 = стрелка вниз (задаются ядром из E0 48/50).
int ax_readline(char* buf, int max) {
    int i = 0;
    int hist_pos = hist_len;   // hist_len = «текущий ввод» (за пределами истории)
    char saved[HIST_LEN];
    saved[0] = '\0';

    while (i < max - 1) {
        char c;
        do { c = ax_readkey(); } while (!c);

        if (c == '\n') {
            ax_putchar('\n');
            break;
        }
        if (c == '\b') {
            if (i > 0) { i--; ax_putchar('\b'); }
        } else if (c == '\x11' || c == '\x12') {
            int new_pos = hist_pos + (c == '\x11' ? -1 : 1);
            if (new_pos >= 0 && new_pos <= hist_len) {
                // Сохраняем текущий ввод перед первым уходом в историю
                if (hist_pos == hist_len) {
                    int si;
                    for (si = 0; si < i && si < HIST_LEN - 1; si++) saved[si] = buf[si];
                    saved[si] = '\0';
                }
                hist_pos = new_pos;
                // Стираем текущую строку с экрана
                while (i > 0) { ax_putchar('\b'); i--; }
                // Выводим выбранную запись (или сохранённый ввод)
                const char* entry = (hist_pos == hist_len) ? saved : hist[hist_pos];
                for (i = 0; entry[i] && i < max - 1; i++) {
                    buf[i] = entry[i];
                    ax_putchar(buf[i]);
                }
            }
        } else if ((unsigned char)c >= 32) {
            buf[i++] = c;
            ax_putchar(c);
        }
    }
    buf[i] = '\0';

    // Добавляем в историю (непустые команды; если буфер полон — сдвигаем)
    if (i > 0) {
        if (hist_len == HIST_CAP) {
            int k, j;
            for (k = 0; k < HIST_CAP - 1; k++)
                for (j = 0; j < HIST_LEN; j++) hist[k][j] = hist[k+1][j];
            hist_len--;
        }
        int j;
        for (j = 0; j < i && j < HIST_LEN - 1; j++) hist[hist_len][j] = buf[j];
        hist[hist_len][j] = '\0';
        hist_len++;
    }
    return i;
}
