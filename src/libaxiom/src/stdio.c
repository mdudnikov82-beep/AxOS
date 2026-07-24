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
        int left_align = (*p == '-');
        if (left_align) p++;
        int zero_pad = (*p == '0');
        if (zero_pad) p++;
        int width = 0;
        while (*p >= '1' && *p <= '9') { width = width * 10 + (*p++ - '0'); }
        switch (*p) {
            case 's': {
                char* _s = va_arg(ap, char*);
                int _len = 0; for (char* _q = _s; *_q; _q++) _len++;
                int _pad = (width > _len) ? width - _len : 0;
                if (!left_align) while (_pad-- > 0) ax_putchar(' ');
                ax_print(_s);
                if (left_align)  while (_pad-- > 0) ax_putchar(' ');
                break;
            }
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

// Автодополнение по Tab - необязательный хук вместо жёсткой зависимости
// ax_readline() (общая библиотечная функция - её вызывает и ai.c) от
// FAT12/readdir. sh.c подключает свой через ax_set_complete_hook();
// ai.c его не трогает - Tab там просто ничего не делает, как и раньше.
// Хук получает буфер/длину/позицию курсора и сам отвечает за собственную
// перерисовку экрана (тем же приёмом, что и остальной readline).
static int (*ax_complete_hook)(char *buf, int *len, int *pos, int max) = 0;
void ax_set_complete_hook(int (*fn)(char *buf, int *len, int *pos, int max)) {
    ax_complete_hook = fn;
}

// x86's own kernel console (screen.c) makes '\b' DESTRUCTIVE - backspace_tty()
// moves the cursor back AND writes a blank there in one step (unlike RISC-V's
// raw UART, where '\b' is just a byte whose meaning depends on whatever real
// terminal is attached, normally non-destructive). Found live: redraw_tail's
// old "print tail, then N backspaces to return the cursor" trick used '\b'
// for the return-trip too, which silently ERASED the very characters it had
// just printed (confirmed via a debug dump showing the internal buffer was
// correctly "hellzo" while the SCREEN showed "hellz" - a pure display bug,
// dispatch was never actually broken). Fixed by adding non-destructive
// cursor-left/right ('\033[nC'/'\033[nD') to screen.c's existing ANSI
// dispatcher and using those for all pure navigation; '\b' now appears only
// where erasing really is the intent (the Delete/Backspace keys' own space-fill).
static void cursor_left(int n)  { if (n > 0) ax_printf("\033[%dD", n); }
static void cursor_right(int n) { if (n > 0) ax_printf("\033[%dC", n); }

// Дописывает buf[pos..len) на экран, затирает `erase` "хвостовых" старых
// символов пробелами (нужно только когда строка стала короче - backspace/
// Delete/более короткая запись истории), затем возвращает курсор к pos
// НЕ-разрушающим перемещением (см. cursor_left выше - обычный backspace
// тут стёр бы то, что сам только что напечатал). Тот же приём, которым
// уже пользовался старый код истории здесь, обобщённый на любую позицию
// курсора - заодно исправляет реальный баг старой версии: она не затирала
// хвост при переключении на БОЛЕЕ КОРОТКУЮ запись истории.
static void redraw_tail(const char *buf, int pos, int len, int erase) {
    for (int i = pos; i < len; i++) ax_putchar(buf[i]);
    for (int i = 0; i < erase; i++) ax_putchar(' ');
    cursor_left((len - pos) + erase);
}

// 0x11/0x12 = вверх/вниз (история), 0x13/0x14 = влево/вправо (курсор),
// 0x15/0x16 = Home/End, 0x17 = Delete-вперёд - все уже декодируются ядром
// из scancode'ов в kernel.c's keyboard_handler_main() (тем же приёмом,
// что уже сделан для истории) - здесь не нужен ANSI/CSI-парсер на ВХОДЕ,
// просто ещё несколько однобайтовых псевдокодов (ANSI на ВЫХОДЕ, для
// самого перемещения курсора, добавлен в screen.c - см. cursor_left выше).
int ax_readline(char* buf, int max) {
    int len = 0, pos = 0;
    int hist_pos = hist_len;   // hist_len = «текущий ввод» (за пределами истории)
    char saved[HIST_LEN];
    saved[0] = '\0';

    while (1) {
        char c;
        do { c = ax_readkey(); } while (!c);

        if (c == '\n') { ax_putchar('\n'); break; }

        if (c == '\b') {
            if (pos > 0) {
                pos--;
                for (int i = pos; i < len - 1; i++) buf[i] = buf[i + 1];
                len--;
                cursor_left(1);
                redraw_tail(buf, pos, len, 1);
            }
            continue;
        }
        if (c == '\x13') { if (pos > 0) { pos--; cursor_left(1); } continue; }         // Left
        if (c == '\x14') { if (pos < len) { pos++; cursor_right(1); } continue; }      // Right
        if (c == '\x15') { if (pos > 0) { cursor_left(pos); pos = 0; } continue; }     // Home
        if (c == '\x16') { if (pos < len) { cursor_right(len - pos); pos = len; } continue; } // End
        if (c == '\x17') {   // Delete (вперёд)
            if (pos < len) {
                for (int i = pos; i < len - 1; i++) buf[i] = buf[i + 1];
                len--;
                redraw_tail(buf, pos, len, 1);
            }
            continue;
        }

        if (c == '\x11' || c == '\x12') {
            int new_pos = hist_pos + (c == '\x11' ? -1 : 1);
            if (new_pos >= 0 && new_pos <= hist_len) {
                if (hist_pos == hist_len) {
                    int si;
                    for (si = 0; si < len && si < HIST_LEN - 1; si++) saved[si] = buf[si];
                    saved[si] = '\0';
                }
                cursor_left(pos);
                int old_len = len;
                hist_pos = new_pos;
                const char* entry = (hist_pos == hist_len) ? saved : hist[hist_pos];
                int i; for (i = 0; entry[i] && i < max - 1; i++) { buf[i] = entry[i]; ax_putchar(buf[i]); }
                len = i; pos = i;
                int erase = (old_len > len) ? (old_len - len) : 0;
                for (int k = 0; k < erase; k++) ax_putchar(' ');
                cursor_left(erase);
            }
            continue;
        }

        if (c == '\t') {
            if (ax_complete_hook) ax_complete_hook(buf, &len, &pos, max);
            continue;
        }

        if ((unsigned char)c >= 32) {
            if (len < max - 1) {
                for (int i = len; i > pos; i--) buf[i] = buf[i - 1];
                buf[pos] = c; len++; pos++;
                ax_putchar(c);
                redraw_tail(buf, pos, len, 0);
            }
        }
    }
    buf[len] = '\0';

    // Добавляем в историю (непустые команды; если буфер полон — сдвигаем)
    if (len > 0) {
        if (hist_len == HIST_CAP) {
            int k, j;
            for (k = 0; k < HIST_CAP - 1; k++)
                for (j = 0; j < HIST_LEN; j++) hist[k][j] = hist[k+1][j];
            hist_len--;
        }
        int j;
        for (j = 0; j < len && j < HIST_LEN - 1; j++) hist[hist_len][j] = buf[j];
        hist[hist_len][j] = '\0';
        hist_len++;
    }
    return len;
}
