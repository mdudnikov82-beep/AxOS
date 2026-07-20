#include "syscall.h"
#include <stdarg.h>

/* This fully freestanding (-nostdlib, no libc) RV64 userspace has no
 * memcpy anywhere - GCC at -Os still silently lowers small local-array
 * initializers-from-a-literal-list (e.g. `int ys[8] = {0,1,1,...}`
 * below) into a call to memcpy(), a completely separate mechanism from
 * the array-fill-LOOP lowering build_riscv.bat's own
 * -fno-tree-loop-distribute-patterns guards against (see
 * src/user/rv64/malloc.h's own memcpy for that other case) - one flag
 * doesn't cover both. Caught by the linker (`undefined reference to
 * memcpy`), not silently, this time - no stale-artifact risk. MUST be
 * non-static, see malloc.h's own comment for why. */
void *memcpy(void *dst, const void *src, unsigned long n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    for (unsigned long i = 0; i < n; i++) d[i] = s[i];
    return dst;
}

// =================================================================
//  Игрушечная нейросеть: учится предсказывать ЛЮБУЮ булеву функцию
//  ТРЁХ аргументов прямо в шелле. RISC-V-порт src/user/ai.c (x86) -
//  тот же fixed-point Q16.16 движок и та же логика "ai ask", но с
//  двумя платформенными отличиями:
//
//  1. Нет ax_printf() - RISC-V userspace никогда не имел variadic
//     printf. Новый ai_printf() ниже поддерживает ровно то же
//     подмножество, что реально использует этот файл (%d, %Nd с
//     шириной, %s, %%) - специально не общий/переносимый в отдельный
//     заголовок, как и остальные RISC-V-хелперы этой сессии (malloc.h/
//     tcp.h/udp.h) - каждый .c получает свою приватную копию.
//  2. Рамки/прогресс-бар x86-версии рисуются CP437-байтами (0xDA/0xC4/
//     0xB3/0xDB/...) - это работает ТОЛЬКО потому что x86 читает их
//     через аппаратный VGA-текстовый режим, у которого CP437 всегда
//     встроен в шрифт ПЗУ. AxSH/RV64 - чистый UART/serial поток без
//     какого-либо терминального режима на стороне ядра; байт 0xDA сам
//     по себе не валиден в UTF-8 и на большинстве современных
//     терминалов дал бы "битую" кракозябру, а не рамку. Поэтому здесь -
//     обычный ASCII (+/-/|/#) вместо CP437. ANSI SGR-коды (\033[36m и
//     т.п.) НЕ заменены - это уже проверено рабочим на RV64 (see
//     AxSH's own colored banner), они не codepage-зависимы.
// =================================================================

#define FX_BITS  16
#define FX_SCALE (1 << FX_BITS)      // 1.0 в Q16.16
#define FX_HALF  (FX_SCALE / 2)      // 0.5
#define LR_FX    FX_HALF             // learning rate = 0.5

#define INPUTS   3
#define ROWS     8              // 1 << INPUTS - строк в таблице истинности
#define HIDDEN   6
#define EPOCHS   8000
#define PRINT_INTERVAL 800

static int fx_mul(int a, int b) {
    long long r = (long long)a * (long long)b;
    return (int)(r >> FX_BITS);
}

// Таблица сигмоиды: домен [-8.0, 8.0), 512 точек, шаг 1/32 - Q16.16.
// Байт-идентична x86-версии (та же LUT, тот же посчитанный заранее
// массив) - никакой платформенной разницы в самой математике.
#define LUT_SIZE   512
#define LUT_MIN_FX (-8 * FX_SCALE)
#define LUT_SHIFT  11  // 2048 == 1 << 11

static const int sigmoid_lut[LUT_SIZE] = {
    22, 23, 23, 24, 25, 26, 27, 27, 28, 29,
    30, 31, 32, 33, 34, 35, 36, 37, 39, 40,
    41, 42, 44, 45, 47, 48, 50, 51, 53, 54,
    56, 58, 60, 62, 64, 66, 68, 70, 72, 74,
    77, 79, 82, 84, 87, 90, 92, 95, 98, 101,
    105, 108, 111, 115, 119, 122, 126, 130, 134, 139,
    143, 148, 152, 157, 162, 167, 172, 178, 184, 189,
    195, 202, 208, 215, 221, 228, 236, 243, 251, 259,
    267, 275, 284, 293, 302, 312, 321, 332, 342, 353,
    364, 376, 387, 400, 412, 425, 439, 452, 467, 481,
    497, 512, 528, 545, 562, 580, 598, 617, 636, 656,
    677, 698, 720, 743, 766, 790, 815, 840, 867, 894,
    922, 951, 980, 1011, 1042, 1075, 1109, 1143, 1179, 1215,
    1253, 1292, 1333, 1374, 1417, 1461, 1506, 1553, 1601, 1650,
    1701, 1754, 1808, 1864, 1921, 1980, 2041, 2104, 2168, 2235,
    2303, 2374, 2446, 2521, 2598, 2677, 2758, 2842, 2928, 3017,
    3108, 3202, 3298, 3398, 3500, 3605, 3713, 3824, 3938, 4055,
    4176, 4299, 4427, 4557, 4692, 4830, 4971, 5117, 5266, 5420,
    5577, 5739, 5904, 6074, 6249, 6428, 6611, 6799, 6992, 7190,
    7392, 7600, 7812, 8030, 8252, 8481, 8714, 8953, 9197, 9447,
    9702, 9964, 10230, 10503, 10782, 11066, 11357, 11653, 11955, 12264,
    12579, 12899, 13226, 13559, 13898, 14243, 14595, 14952, 15316, 15686,
    16062, 16444, 16832, 17226, 17625, 18031, 18442, 18859, 19282, 19710,
    20143, 20582, 21025, 21474, 21928, 22386, 22849, 23316, 23788, 24263,
    24743, 25226, 25712, 26202, 26695, 27191, 27689, 28190, 28693, 29198,
    29705, 30213, 30723, 31233, 31744, 32256, 32768, 33280, 33792, 34303,
    34813, 35323, 35831, 36338, 36843, 37346, 37847, 38345, 38841, 39334,
    39824, 40310, 40793, 41273, 41748, 42220, 42687, 43150, 43608, 44062,
    44511, 44954, 45393, 45826, 46254, 46677, 47094, 47505, 47911, 48310,
    48704, 49092, 49474, 49850, 50220, 50584, 50941, 51293, 51638, 51977,
    52310, 52637, 52957, 53272, 53581, 53883, 54179, 54470, 54754, 55033,
    55306, 55572, 55834, 56089, 56339, 56583, 56822, 57055, 57284, 57506,
    57724, 57936, 58144, 58346, 58544, 58737, 58925, 59108, 59287, 59462,
    59632, 59797, 59959, 60116, 60270, 60419, 60565, 60706, 60844, 60979,
    61109, 61237, 61360, 61481, 61598, 61712, 61823, 61931, 62036, 62138,
    62238, 62334, 62428, 62519, 62608, 62694, 62778, 62859, 62938, 63015,
    63090, 63162, 63233, 63301, 63368, 63432, 63495, 63556, 63615, 63672,
    63728, 63782, 63835, 63886, 63935, 63983, 64030, 64075, 64119, 64162,
    64203, 64244, 64283, 64321, 64357, 64393, 64427, 64461, 64494, 64525,
    64556, 64585, 64614, 64642, 64669, 64696, 64721, 64746, 64770, 64793,
    64816, 64838, 64859, 64880, 64900, 64919, 64938, 64956, 64974, 64991,
    65008, 65024, 65039, 65055, 65069, 65084, 65097, 65111, 65124, 65136,
    65149, 65160, 65172, 65183, 65194, 65204, 65215, 65224, 65234, 65243,
    65252, 65261, 65269, 65277, 65285, 65293, 65300, 65308, 65315, 65321,
    65328, 65334, 65341, 65347, 65352, 65358, 65364, 65369, 65374, 65379,
    65384, 65388, 65393, 65397, 65402, 65406, 65410, 65414, 65417, 65421,
    65425, 65428, 65431, 65435, 65438, 65441, 65444, 65446, 65449, 65452,
    65454, 65457, 65459, 65462, 65464, 65466, 65468, 65470, 65472, 65474,
    65476, 65478, 65480, 65482, 65483, 65485, 65486, 65488, 65489, 65491,
    65492, 65494, 65495, 65496, 65497, 65499, 65500, 65501, 65502, 65503,
    65504, 65505, 65506, 65507, 65508, 65509, 65509, 65510, 65511, 65512,
    65513, 65513,
};

static int sigmoid_fx(int x) {
    if (x <= LUT_MIN_FX) return sigmoid_lut[0];
    int idx = (x - LUT_MIN_FX) >> LUT_SHIFT;
    if (idx >= LUT_SIZE) idx = LUT_SIZE - 1;
    return sigmoid_lut[idx];
}

// xorshift32, приватная копия (как и net_rand32() в tcp.h/dns.h/udp.h -
// каждый .c свою) - сидится gettime(), поэтому веса разные при каждом запуске.
static unsigned int rng_state;

static unsigned int rng_next(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

static int rnd_weight_fx(void) {
    return (int)(rng_next() % (unsigned int)(2 * FX_SCALE + 1)) - FX_SCALE;
}

// --- ai_printf(): минимальный variadic printf, только %d/%Nd/%s/%% ---
// Собирает в локальный буфер, один write() на вызов - тот же принцип,
// что axsh.c's readline() уже использует для echo (write(1,...)).
static int ai_putchar(char c) {
    return (int)write(1, &c, 1);
}

static int ai_puts(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return (int)write(1, s, n);
}

static void buf_putc(char *buf, int *pos, int max, char c) {
    if (*pos < max - 1) buf[(*pos)++] = c;
}
static void buf_puts(char *buf, int *pos, int max, const char *s) {
    while (*s) buf_putc(buf, pos, max, *s++);
}
static void buf_putint(char *buf, int *pos, int max, int v, int width) {
    char digits[12];
    int n = 0;
    unsigned int uv;
    int neg = (v < 0);
    uv = neg ? (unsigned int)(-v) : (unsigned int)v;
    if (uv == 0) digits[n++] = '0';
    while (uv > 0) { digits[n++] = (char)('0' + uv % 10); uv /= 10; }
    int total = n + (neg ? 1 : 0);
    for (int i = total; i < width; i++) buf_putc(buf, pos, max, ' ');
    if (neg) buf_putc(buf, pos, max, '-');
    while (n > 0) buf_putc(buf, pos, max, digits[--n]);
}

static int ai_printf(const char *fmt, ...) {
    char out[512];
    int pos = 0;
    va_list ap;
    va_start(ap, fmt);
    for (int i = 0; fmt[i]; i++) {
        if (fmt[i] != '%') { buf_putc(out, &pos, (int)sizeof(out), fmt[i]); continue; }
        i++;
        if (fmt[i] == '%') { buf_putc(out, &pos, (int)sizeof(out), '%'); continue; }
        int width = 0;
        while (fmt[i] >= '0' && fmt[i] <= '9') { width = width * 10 + (fmt[i] - '0'); i++; }
        if (fmt[i] == 'd') {
            int v = va_arg(ap, int);
            buf_putint(out, &pos, (int)sizeof(out), v, width);
        } else if (fmt[i] == 's') {
            const char *s = va_arg(ap, const char *);
            buf_puts(out, &pos, (int)sizeof(out), s);
        } else if (!fmt[i]) {
            break;
        }
    }
    va_end(ap);
    return (int)write(1, out, pos);
}

// --- readline(): та же схема, что axsh.c's собственный readline() ---
static int readline(char *buf, int max) {
    int i = 0;
    while (i < max - 1) {
        char c = getchar_rv();
        if (c == '\r' || c == '\n') { ai_puts("\r\n"); break; }
        if (c == '\b' || c == 127) { if (i > 0) { i--; ai_puts("\b \b"); } continue; }
        if (c < 0x20) continue;
        buf[i++] = c;
        ai_putchar(c);
    }
    buf[i] = '\0';
    return i;
}

// Пишет "[-]D.DDDD" в buf - как в x86-версии.
static void fixed_to_str(int v, char* buf) {
    unsigned int uv;
    int i = 0;
    if (v < 0) { buf[i++] = '-'; uv = (unsigned int)(-v); }
    else uv = (unsigned int)v;
    unsigned int ip = uv >> FX_BITS;
    unsigned int frac = uv & (FX_SCALE - 1);
    unsigned int dec = (frac * 10000u) >> FX_BITS;

    char ip_digits[12];
    int n = 0;
    if (ip == 0) ip_digits[n++] = '0';
    while (ip > 0) { ip_digits[n++] = (char)('0' + ip % 10); ip /= 10; }
    while (n > 0) buf[i++] = ip_digits[--n];

    buf[i++] = '.';
    buf[i++] = (char)('0' + (dec / 1000) % 10);
    buf[i++] = (char)('0' + (dec / 100) % 10);
    buf[i++] = (char)('0' + (dec / 10) % 10);
    buf[i++] = (char)('0' + dec % 10);
    buf[i] = '\0';
}

static void print_fixed(int v) {
    char buf[16];
    fixed_to_str(v, buf);
    ai_printf("%s", buf);
}

static int slen(const char* s) { int n = 0; while (s[n]) n++; return n; }

static int append_str(char* buf, int pos, const char* s) {
    while (*s) buf[pos++] = *s++;
    return pos;
}

static void print_padded(const char* text, int width) {
    int i = 0;
    while (text[i] && i < width) { ai_putchar(text[i]); i++; }
    while (i < width) { ai_putchar(' '); i++; }
}

// Рамка вокруг text - ASCII (+/-), не CP437 (см. файловый комментарий сверху).
static void print_boxed(const char* text, const char* color) {
    int len = slen(text);
    ai_printf("%s", color);

    ai_putchar('+');
    for (int i = 0; i < len + 2; i++) ai_putchar('-');
    ai_putchar('+');
    ai_putchar('\n');

    ai_putchar('|');
    ai_putchar(' ');
    ai_printf("%s", text);
    ai_putchar(' ');
    ai_putchar('|');
    ai_putchar('\n');

    ai_putchar('+');
    for (int i = 0; i < len + 2; i++) ai_putchar('-');
    ai_putchar('+');
    ai_putchar('\n');

    ai_printf("\033[0m");
}

// Прогресс-бар - '#' закрашено / '.' пусто (ASCII, было DB/B0 CP437).
static void print_progress_bar(int epoch, int total_epochs, int err_fx) {
    const int BAR_WIDTH = 20;
    int filled = (epoch + 1) * BAR_WIDTH / total_epochs;
    if (filled > BAR_WIDTH) filled = BAR_WIDTH;
    int pct = (epoch + 1) * 100 / total_epochs;

    const char* color;
    if (err_fx > FX_SCALE) color = "\033[31m";
    else if (err_fx > FX_SCALE / 5) color = "\033[33m";
    else color = "\033[32m";

    ai_printf("epoch %5d/%d %s[", epoch, total_epochs, color);
    int i = 0;
    for (; i < filled; i++) ai_putchar('#');
    for (; i < BAR_WIDTH; i++) ai_putchar('.');
    ai_printf("]\033[0m %3d%%  err=", pct);
    print_fixed(err_fx);
    ai_putchar('\n');
}

static int w1[INPUTS][HIDDEN];
static int b1[HIDDEN];
static int w2[HIDDEN];
static int b2;

static int forward(int in0, int in1, int in2, int* hidden_out) {
    for (int j = 0; j < HIDDEN; j++) {
        int h_in = fx_mul(in0, w1[0][j]) + fx_mul(in1, w1[1][j]) +
                   fx_mul(in2, w1[2][j]) + b1[j];
        hidden_out[j] = sigmoid_fx(h_in);
    }
    int o_in = b2;
    for (int j = 0; j < HIDDEN; j++) o_in += fx_mul(hidden_out[j], w2[j]);
    return sigmoid_fx(o_in);
}

static const int xs[ROWS][INPUTS] = {
    { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 0 }, { 0, 1, 1 },
    { 1, 0, 0 }, { 1, 0, 1 }, { 1, 1, 0 }, { 1, 1, 1 },
};

static int parse_bits(const char* s, int* out) {
    int i;
    for (i = 0; i < ROWS; i++) {
        char c = s[i];
        if (c != '0' && c != '1') return 0;
        out[i] = c - '0';
    }
    return s[ROWS] == '\0';
}

static const struct { int bits[ROWS]; const char* name; } KNOWN_FNS[] = {
    { { 0, 0, 0, 0, 0, 0, 0, 0 }, "FALSE (always 0)" },
    { { 1, 1, 1, 1, 1, 1, 1, 1 }, "TRUE (always 1)" },
    { { 0, 0, 0, 0, 0, 0, 0, 1 }, "AND (A&B&C)" },
    { { 0, 1, 1, 1, 1, 1, 1, 1 }, "OR (A|B|C)" },
    { { 1, 1, 1, 1, 1, 1, 1, 0 }, "NAND" },
    { { 1, 0, 0, 0, 0, 0, 0, 0 }, "NOR" },
    { { 0, 1, 1, 0, 1, 0, 0, 1 }, "XOR/parity (odd # of 1s)" },
    { { 1, 0, 0, 1, 0, 1, 1, 0 }, "XNOR (even # of 1s)" },
    { { 0, 0, 0, 1, 0, 1, 1, 1 }, "MAJORITY (2 or more of 3)" },
};
#define KNOWN_FNS_COUNT (int)(sizeof(KNOWN_FNS) / sizeof(KNOWN_FNS[0]))

static const char* name_for(const int* ys) {
    for (int i = 0; i < KNOWN_FNS_COUNT; i++) {
        int match = 1;
        for (int j = 0; j < ROWS; j++) {
            if (KNOWN_FNS[i].bits[j] != ys[j]) { match = 0; break; }
        }
        if (match) return KNOWN_FNS[i].name;
    }
    return "custom (no common name)";
}

// =================================================================
//  Сохранение/загрузка весов (AI.WTS) - через writefile()/open()+
//  read()+close(), а не ax_writefile/ax_readfile (тех нет на RISC-V).
//  Все bank_entry_t/weights_bank_t локали объявлены static: RV64
//  userspace-стек - ОДНА 4КБ страница на весь call chain (см. память
//  проекта), а weights_bank_t сам по себе ~1.3КБ - на стеке легко
//  store-page-fault'нется, x86-версия себе такого не может позволить
//  проверить (там страничный стек намного щедрее), но здесь это
//  обязательно, не опционально.
// =================================================================
#define WEIGHTS_FILE "AI.WTS"
#define BANK_SIZE 8

typedef struct {
    int used;
    int ys[ROWS];
    int w1[INPUTS][HIDDEN];
    int b1[HIDDEN];
    int w2[HIDDEN];
    int b2;
} bank_entry_t;

typedef struct {
    int next_slot;
    bank_entry_t entries[BANK_SIZE];
} weights_bank_t;

static int ys_equal(const int* a, const int* b) {
    for (int i = 0; i < ROWS; i++) if (a[i] != b[i]) return 0;
    return 1;
}

// Читает файл целиком в один read() - sys_open() уже грузит весь файл в
// kernel-side буфер при открытии (см. src/arch/riscv64/syscall.c), так
// что один read() отдаёт min(размер файла, запрошенное) синхронно.
static unsigned int read_whole_file(const char *path, unsigned char *buf, unsigned int max) {
    int fd = open(path, 0);
    if (fd < 0) return 0;
    long n = read(fd, buf, (long)max);
    close(fd);
    return n < 0 ? 0 : (unsigned int)n;
}

static void load_bank(weights_bank_t* bank) {
    unsigned int n = read_whole_file(WEIGHTS_FILE, (unsigned char*)bank, (unsigned int)sizeof(*bank));
    if (n != sizeof(*bank)) {
        bank->next_slot = 0;
        for (int i = 0; i < BANK_SIZE; i++) bank->entries[i].used = 0;
    }
}

static int load_weights(const int* ys) {
    static weights_bank_t bank;
    load_bank(&bank);

    for (int i = 0; i < BANK_SIZE; i++) {
        bank_entry_t* e = &bank.entries[i];
        if (!e->used || !ys_equal(e->ys, ys)) continue;

        for (int a = 0; a < INPUTS; a++)
            for (int j = 0; j < HIDDEN; j++) w1[a][j] = e->w1[a][j];
        for (int j = 0; j < HIDDEN; j++) { b1[j] = e->b1[j]; w2[j] = e->w2[j]; }
        b2 = e->b2;
        return 1;
    }
    return 0;
}

static void save_weights(const int* ys) {
    static weights_bank_t bank;
    load_bank(&bank);

    int slot = -1;
    for (int i = 0; i < BANK_SIZE; i++) {
        if (bank.entries[i].used && ys_equal(bank.entries[i].ys, ys)) { slot = i; break; }
    }
    if (slot < 0) {
        for (int i = 0; i < BANK_SIZE; i++) {
            if (!bank.entries[i].used) { slot = i; break; }
        }
    }
    int evicted = (slot < 0);
    if (slot < 0) {
        slot = bank.next_slot;
        bank.next_slot = (bank.next_slot + 1) % BANK_SIZE;
    }

    bank_entry_t* e = &bank.entries[slot];
    e->used = 1;
    for (int i = 0; i < ROWS; i++) e->ys[i] = ys[i];
    for (int a = 0; a < INPUTS; a++)
        for (int j = 0; j < HIDDEN; j++) e->w1[a][j] = w1[a][j];
    for (int j = 0; j < HIDDEN; j++) { e->b1[j] = b1[j]; e->w2[j] = w2[j]; }
    e->b2 = b2;

    if (writefile(WEIGHTS_FILE, &bank, (long)sizeof(bank))) {
        if (evicted) {
            ai_printf("\033[32mSaved trained weights to %s\033[0m (bank was full - "
                      "evicted the oldest slot). Run 'ai list' to see what's stored.\n",
                      WEIGHTS_FILE);
        } else {
            ai_printf("\033[32mSaved trained weights to %s\033[0m - next run with this "
                      "pattern will skip training. Run 'ai list' to see what's stored.\n",
                      WEIGHTS_FILE);
        }
    } else {
        ai_printf("\033[33mCould not save weights.\033[0m\n");
    }
}

static void list_bank(void) {
    static weights_bank_t bank;
    load_bank(&bank);

    int any = 0;
    for (int i = 0; i < BANK_SIZE; i++) {
        if (!bank.entries[i].used) continue;
        any = 1;
        char pattern[ROWS + 1];
        for (int j = 0; j < ROWS; j++) pattern[j] = (char)('0' + bank.entries[i].ys[j]);
        pattern[ROWS] = '\0';
        ai_printf("  [%d] %s - %s\n", i, pattern, name_for(bank.entries[i].ys));
    }
    if (!any) {
        ai_printf("%s is empty - nothing trained and saved yet.\n", WEIGHTS_FILE);
    }
}

static int confidence_pct(int o_out) {
    int diff = (o_out > FX_HALF) ? (o_out - FX_HALF) : (FX_HALF - o_out);
    int conf_fx = diff << 1;
    int pct = (conf_fx * 100) >> FX_BITS;
    if (pct > 100) pct = 100;
    return pct;
}

static void pct_to_str(int pct, char* buf) {
    int i = 0;
    if (pct >= 100) { buf[i++] = '1'; buf[i++] = '0'; buf[i++] = '0'; }
    else {
        if (pct >= 10) buf[i++] = (char)('0' + pct / 10);
        buf[i++] = (char)('0' + pct % 10);
    }
    buf[i++] = '%';
    buf[i] = '\0';
}

// Таблица предсказаний - рамка ASCII ('+'/'-'/'|'), не CP437.
#define PRED_TABLE_COLS 7
static const int PRED_TABLE_WIDTHS[PRED_TABLE_COLS] = { 3, 3, 3, 11, 8, 8, 8 };

static void print_table_border(void) {
    ai_putchar('+');
    for (int c = 0; c < PRED_TABLE_COLS; c++) {
        for (int i = 0; i < PRED_TABLE_WIDTHS[c]; i++) ai_putchar('-');
        ai_putchar('+');
    }
    ai_putchar('\n');
}

static void print_cell(int width, const char* text) {
    ai_putchar('|');
    ai_putchar(' ');
    print_padded(text, width - 2);
    ai_putchar(' ');
}

static void print_cell_colored(int width, const char* text, const char* color) {
    ai_putchar('|');
    ai_putchar(' ');
    ai_printf("%s", color);
    print_padded(text, width - 2);
    ai_printf("\033[0m");
    ai_putchar(' ');
}

// =================================================================
//  "ai ask" - жёстко заданная база вопрос/ответ про сам AxOS/RV64.
//  Ответы адаптированы под RISC-V-факты (нет MinGW/x86-специфики).
// =================================================================
static void lower_copy(const char* src, char* dst, int max) {
    int i;
    for (i = 0; i < max - 1 && src[i]; i++) {
        char c = src[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        dst[i] = c;
    }
    dst[i] = '\0';
}

static int streq(const char* a, const char* b) {
    while (*a && *b && *a == *b) { a++; b++; }
    return *a == *b;
}

static int contains(const char* hay, const char* needle) {
    for (int i = 0; hay[i]; i++) {
        int j = 0;
        while (needle[j] && hay[i + j] == needle[j]) j++;
        if (needle[j] == '\0') return 1;
    }
    return 0;
}

#define QA_MAX_KEYWORDS 3

static const struct { const char* keywords[QA_MAX_KEYWORDS]; const char* answer; } QA_DB[] = {
    { { "who made you", "who wrote you", "author" },
      "Maxim wrote AxOS as a personal systems-programming project." },
    { { "what is axos", "what are you" },
      "AxOS is a small OS with two independent ports: an x86-64 kernel "
      "and this RISC-V (RV64) one - own bootloader/SBI handoff, FAT12 "
      "filesystem, MAC/MLS security, and ELF64 user programs." },
    { { "hidden layer", "perceptron", "neuron" },
      "This network is a 3-6-1 MLP: 3 inputs, 6 hidden neurons, 1 output, "
      "trained by backpropagation." },
    { { "xor" },
      "XOR (parity) is the classic function a single-layer perceptron "
      "cannot learn (Minsky/Papert) - that's why this MLP has a hidden layer." },
    { { "fpu", "float", "double" },
      "This RV64 build uses no hardware float extension (-march=rv64imac), "
      "so all math here (including this network) is fixed-point Q16.16." },
    { { "syscall", "system call" },
      "User programs talk to the kernel via ecall, dispatched by "
      "syscall_dispatch() in src/arch/riscv64/syscall.c." },
    { { "fat12", "filesystem", "disk" },
      "AxOS/RV64 uses a FAT12 filesystem over virtio-blk (rv64build/disk.img)." },
    { { "mac", "selinux", "type enforcement" },
      "AxOS has a SELinux-style Type Enforcement MAC layer: domains x "
      "classes, denials logged as 'avc: denied'." },
    { { "mls", "clearance", "sensitivity level" },
      "AxOS supports MLS sensitivity levels s0-s15 with a no-read-up "
      "dominance check on the clipboard." },
    { { "elf", "loader" },
      "User programs are real ELF64 executables, parsed by "
      "src/arch/riscv64/elf_loader.c - not flat binaries." },
    { { "axos" },
      "AxOS/RV64 is the RISC-V port of AxOS, written from scratch - see "
      "'what is axos'." },
    { { "help", "what can you do", "commands" },
      "Ask me about axos, xor, fpu, syscalls, fat12, mac, mls, elf, or "
      "neurons - or run 'ai <8 bits>' to train a 3-input boolean function, "
      "or 'ai list' to see saved weights." },
};
#define QA_COUNT (int)(sizeof(QA_DB) / sizeof(QA_DB[0]))

#define ASK_FALLBACK_MSG "I don't know that one yet - try asking about axos, xor, " \
                          "fpu, syscalls, fat12, mac, mls, elf, or neurons."

static const char* find_builtin_answer(const char* q) {
    for (int i = 0; i < QA_COUNT; i++) {
        for (int k = 0; k < QA_MAX_KEYWORDS && QA_DB[i].keywords[k]; k++) {
            if (contains(q, QA_DB[i].keywords[k])) return QA_DB[i].answer;
        }
    }
    return 0;
}

// =================================================================
//  "ai ask" учится - тот же банковый механизм, что и AI.WTS выше,
//  тоже через writefile()/read_whole_file(), тоже static-локали.
// =================================================================
#define LEARNED_FILE "AI.QA"
#define LEARNED_MAX 16
#define LEARNED_KEYWORD_LEN 64
#define LEARNED_ANSWER_LEN 160

typedef struct {
    int used;
    char keyword[LEARNED_KEYWORD_LEN];
    char answer[LEARNED_ANSWER_LEN];
} learned_entry_t;

typedef struct {
    int next_slot;
    learned_entry_t entries[LEARNED_MAX];
} learned_bank_t;

static void load_learned_bank(learned_bank_t* bank) {
    unsigned int n = read_whole_file(LEARNED_FILE, (unsigned char*)bank, (unsigned int)sizeof(*bank));
    if (n != sizeof(*bank)) {
        bank->next_slot = 0;
        for (int i = 0; i < LEARNED_MAX; i++) bank->entries[i].used = 0;
    }
}

static const char* find_learned_answer(const learned_bank_t* bank, const char* q) {
    for (int i = 0; i < LEARNED_MAX; i++) {
        if (bank->entries[i].used && contains(q, bank->entries[i].keyword))
            return bank->entries[i].answer;
    }
    return 0;
}

static void copy_truncated(char* dst, const char* src, int max) {
    int i;
    for (i = 0; i < max - 1 && src[i]; i++) dst[i] = src[i];
    dst[i] = '\0';
}

static int save_learned(const char* keyword, const char* answer) {
    static learned_bank_t bank;
    load_learned_bank(&bank);

    int slot = -1;
    for (int i = 0; i < LEARNED_MAX; i++) {
        if (bank.entries[i].used && streq(keyword, bank.entries[i].keyword)) { slot = i; break; }
    }
    if (slot < 0) {
        for (int i = 0; i < LEARNED_MAX; i++) {
            if (!bank.entries[i].used) { slot = i; break; }
        }
    }
    if (slot < 0) {
        slot = bank.next_slot;
        bank.next_slot = (bank.next_slot + 1) % LEARNED_MAX;
    }

    learned_entry_t* e = &bank.entries[slot];
    e->used = 1;
    copy_truncated(e->keyword, keyword, LEARNED_KEYWORD_LEN);
    copy_truncated(e->answer, answer, LEARNED_ANSWER_LEN);

    return writefile(LEARNED_FILE, &bank, (long)sizeof(bank));
}

static void list_learned(const learned_bank_t* bank) {
    int any = 0;
    for (int i = 0; i < LEARNED_MAX; i++) {
        if (!bank->entries[i].used) continue;
        any = 1;
        ai_printf("  [%d] \"%s\" -> %s\n", i, bank->entries[i].keyword, bank->entries[i].answer);
    }
    if (!any) {
        ai_printf("Nothing learned yet - ask me something I don't know and teach me.\n");
    }
}

static void run_ask_mode(void) {
    print_boxed("AxOS AI: ask me something ('list' = learned, 'exit' = quit)", "\033[36m");

    static learned_bank_t learned;
    load_learned_bank(&learned);

    char line[64];
    char lower[64];
    for (;;) {
        ai_printf("\033[33m? \033[0m");
        readline(line, sizeof(line));
        if (line[0] == '\0') continue;
        lower_copy(line, lower, sizeof(lower));
        if (streq(lower, "exit") || streq(lower, "quit")) break;
        if (streq(lower, "list")) { list_learned(&learned); continue; }

        const char* ans = find_builtin_answer(lower);
        if (!ans) ans = find_learned_answer(&learned, lower);

        if (ans) {
            ai_printf("\033[32mAI:\033[0m %s\n", ans);
            continue;
        }

        ai_printf("\033[32mAI:\033[0m " ASK_FALLBACK_MSG "\n");
        ai_printf("Teach me the answer? Type it now, or Enter to skip:\n");
        ai_printf("\033[33m> \033[0m");
        char teach[LEARNED_ANSWER_LEN];
        readline(teach, sizeof(teach));
        if (teach[0] == '\0') continue;

        char teach_lower[LEARNED_ANSWER_LEN];
        lower_copy(teach, teach_lower, sizeof(teach_lower));
        if (streq(teach_lower, "exit") || streq(teach_lower, "quit")) break;

        if (save_learned(lower, teach)) {
            load_learned_bank(&learned);
            ai_printf("\033[32mAI:\033[0m Got it, thanks - I'll remember that.\n");
        } else {
            ai_printf("\033[33mAI:\033[0m Could not save, but I'll remember it for "
                      "this session.\n");
            int slot = learned.next_slot;
            learned.next_slot = (learned.next_slot + 1) % LEARNED_MAX;
            for (int i = 0; i < LEARNED_MAX; i++) {
                if (!learned.entries[i].used) { slot = i; break; }
            }
            learned_entry_t* e = &learned.entries[slot];
            e->used = 1;
            copy_truncated(e->keyword, lower, LEARNED_KEYWORD_LEN);
            copy_truncated(e->answer, teach, LEARNED_ANSWER_LEN);
        }
    }
}

int main(int argc, char** argv) {
    if (argc > 1) {
        char arg_lower[16];
        lower_copy(argv[1], arg_lower, sizeof(arg_lower));
        if (streq(arg_lower, "ask")) {
            run_ask_mode();
            return 0;
        }
        if (streq(arg_lower, "list")) {
            list_bank();
            return 0;
        }
    }

    int ys[ROWS] = { 0, 1, 1, 0, 1, 0, 0, 1 };  // default: parity/XOR3
    int have_pattern = 0;

    if (argc > 1) {
        if (parse_bits(argv[1], ys)) {
            have_pattern = 1;
        } else {
            ai_printf("ai: invalid pattern \"%s\" (need 8 chars of 0/1, e.g. 01101001). "
                      "Defaulting to parity.\n", argv[1]);
            have_pattern = 1;
        }
    }

    rng_state = (unsigned int)gettime() ^ 0x9E3779B9u;
    if (rng_state == 0) rng_state = 0x9E3779B9u;

    if (!have_pattern) {
        print_boxed("AxOS AI: 3-6-1 MLP learns any 3-input boolean function", "\033[36m");
        ai_printf("Enter the 8 outputs for inputs 000,001,010,011,100,101,110,111\n");
        ai_printf("as an 8-bit string (e.g. 01101001 = parity/XOR3, 00010111 =\n");
        ai_printf("majority, 00000001 = AND3), or Enter for parity.\n");
        ai_printf("(Run 'ai ask' for Q&A about AxOS, or 'ai list' to see saved weights.)\n");

        char line[16];
        for (int attempt = 0; attempt < 3 && !have_pattern; attempt++) {
            ai_printf("\033[33m> \033[0m");
            readline(line, sizeof(line));
            if (line[0] == '\0') {
                have_pattern = 1;
            } else if (parse_bits(line, ys)) {
                have_pattern = 1;
            } else {
                ai_printf("Invalid input, need exactly 8 chars of 0/1.\n");
            }
        }
        if (!have_pattern) {
            ai_printf("Giving up, defaulting to parity.\n");
            int parity[ROWS] = { 0, 1, 1, 0, 1, 0, 0, 1 };
            for (int i = 0; i < ROWS; i++) ys[i] = parity[i];
        }
    }

    int loaded = load_weights(ys);

    {
        char banner[96];
        int pos = 0;
        pos = append_str(banner, pos, loaded ? "Loaded: " : "Training: ");
        pos = append_str(banner, pos, name_for(ys));
        pos = append_str(banner, pos, " (truth table ");
        for (int i = 0; i < ROWS; i++) banner[pos++] = (char)('0' + ys[i]);
        banner[pos++] = ')';
        banner[pos] = '\0';
        ai_putchar('\n');
        print_boxed(banner, "\033[36m");
    }

    if (loaded) {
        ai_printf("Found saved weights for this pattern in %s - skipping training.\n\n",
                  WEIGHTS_FILE);
    } else {
        ai_printf("fixed-point Q16.16, sigmoid LUT, backprop, %d epochs\n\n", EPOCHS);

        for (int j = 0; j < HIDDEN; j++) {
            w1[0][j] = rnd_weight_fx();
            w1[1][j] = rnd_weight_fx();
            w1[2][j] = rnd_weight_fx();
            b1[j]    = rnd_weight_fx();
            w2[j]    = rnd_weight_fx();
        }
        b2 = rnd_weight_fx();

        for (int epoch = 0; epoch < EPOCHS; epoch++) {
            int total_err = 0;

            for (int i = 0; i < ROWS; i++) {
                int in0 = xs[i][0] ? FX_SCALE : 0;
                int in1 = xs[i][1] ? FX_SCALE : 0;
                int in2 = xs[i][2] ? FX_SCALE : 0;
                int tgt = ys[i]    ? FX_SCALE : 0;

                int hidden[HIDDEN];
                int o_out = forward(in0, in1, in2, hidden);

                int err = tgt - o_out;
                total_err += (err < 0) ? -err : err;

                int o_delta = fx_mul(err, fx_mul(o_out, FX_SCALE - o_out));

                int h_delta[HIDDEN];
                for (int j = 0; j < HIDDEN; j++) {
                    h_delta[j] = fx_mul(fx_mul(o_delta, w2[j]),
                                         fx_mul(hidden[j], FX_SCALE - hidden[j]));
                }

                for (int j = 0; j < HIDDEN; j++) w2[j] += fx_mul(LR_FX, fx_mul(o_delta, hidden[j]));
                b2 += fx_mul(LR_FX, o_delta);

                for (int j = 0; j < HIDDEN; j++) {
                    w1[0][j] += fx_mul(LR_FX, fx_mul(h_delta[j], in0));
                    w1[1][j] += fx_mul(LR_FX, fx_mul(h_delta[j], in1));
                    w1[2][j] += fx_mul(LR_FX, fx_mul(h_delta[j], in2));
                    b1[j]    += fx_mul(LR_FX, h_delta[j]);
                }
            }

            if (epoch % PRINT_INTERVAL == 0 || epoch == EPOCHS - 1) {
                print_progress_bar(epoch, EPOCHS, total_err);
            }
        }
    }

    ai_printf("\n\033[36mFinal predictions:\033[0m\n");

    print_table_border();
    print_cell(PRED_TABLE_WIDTHS[0], "A");
    print_cell(PRED_TABLE_WIDTHS[1], "B");
    print_cell(PRED_TABLE_WIDTHS[2], "C");
    print_cell(PRED_TABLE_WIDTHS[3], "predicted");
    print_cell(PRED_TABLE_WIDTHS[4], "target");
    print_cell(PRED_TABLE_WIDTHS[5], "status");
    print_cell(PRED_TABLE_WIDTHS[6], "conf");
    ai_putchar('|');
    ai_putchar('\n');
    print_table_border();

    int all_ok = 1;
    for (int i = 0; i < ROWS; i++) {
        int in0 = xs[i][0] ? FX_SCALE : 0;
        int in1 = xs[i][1] ? FX_SCALE : 0;
        int in2 = xs[i][2] ? FX_SCALE : 0;
        int hidden[HIDDEN];
        int o_out = forward(in0, in1, in2, hidden);
        int pred = (o_out > FX_HALF) ? 1 : 0;
        int ok = (pred == ys[i]);
        all_ok &= ok;

        char a_str[2] = { (char)('0' + xs[i][0]), '\0' };
        char b_str[2] = { (char)('0' + xs[i][1]), '\0' };
        char c_str[2] = { (char)('0' + xs[i][2]), '\0' };
        char target_str[2] = { (char)('0' + ys[i]), '\0' };
        char pred_str[16];
        fixed_to_str(o_out, pred_str);

        int conf = confidence_pct(o_out);
        char conf_str[8];
        pct_to_str(conf, conf_str);
        const char* conf_color = (conf >= 80) ? "\033[32m" : (conf >= 50) ? "\033[33m" : "\033[31m";

        print_cell(PRED_TABLE_WIDTHS[0], a_str);
        print_cell(PRED_TABLE_WIDTHS[1], b_str);
        print_cell(PRED_TABLE_WIDTHS[2], c_str);
        print_cell(PRED_TABLE_WIDTHS[3], pred_str);
        print_cell(PRED_TABLE_WIDTHS[4], target_str);
        print_cell_colored(PRED_TABLE_WIDTHS[5], ok ? "OK" : "FAIL",
                            ok ? "\033[32m" : "\033[31m");
        print_cell_colored(PRED_TABLE_WIDTHS[6], conf_str, conf_color);
        ai_putchar('|');
        ai_putchar('\n');
    }
    print_table_border();

    if (!loaded && all_ok) save_weights(ys);

    ai_printf("\n%s\n", all_ok ? "\033[32mPASS: network learned the function\033[0m"
                                : "\033[31mFAIL: network did not converge\033[0m");
    return all_ok ? 0 : 1;
}
