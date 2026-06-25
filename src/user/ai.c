#include "axiom.h"

// =================================================================
//  Игрушечная нейросеть: учится предсказывать ЛЮБУЮ булеву функцию
//  ТРЁХ аргументов прямо в шелле.
// =================================================================
//
// Никакого float/double - в этом freestanding-окружении FPU не
// инициализирован (нет fninit, CR0.EM не сброшен) и вектор #NM (7) не
// обработан в IDT (kernel.c::init_idt), так что любая x87-инструкция
// тут же положила бы систему тройным сбоем. Вся арифметика - fixed-point
// Q16.16 (FX_SCALE = 2^16); сигмоида - через таблицу (LUT), посчитанную
// заранее (см. tools/, генератор не входит в сборку - таблица просто
// вкомпилирована как константа), а не через exp() в рантайме.
//
// Архитектура: 3 входа -> 6 скрытых нейронов (сигмоида) -> 1 выход
// (сигмоида), обучение - обратное распространение ошибки. Таблица
// истинности (8 бит - выходы для входов 000,001,010,011,100,101,110,111)
// задаётся пользователем: аргументом командной строки ("ai 01101001")
// или интерактивно через ax_readline, по умолчанию - parity (XOR трёх
// входов). У 3 входов 2^8=256 различных булевых функций - в отличие от
// версии на 2 входа (16 функций, помещались в exhaustive-таблицу
// целиком), здесь именами покрыты только несколько "известных" (см.
// KNOWN_FNS) - остальные печатаются просто как "custom". Parity/XOR3 и
// XNOR3 - самые сложные из известных: не линейно разделимы (обобщение
// контрпримера Минского/Паперта на 3 входа), отсюда и скрытый слой. С 4
// скрытыми нейронами (как в 2-входовой версии) parity иногда не
// сходилась за отведённые эпохи - 6 нейронов и больше эпох дают
// устойчивую сходимость.
//
// Веса переживают выход из программы: после успешного обучения (только
// если all_ok - несошедшуюся модель сохранять бессмысленно) пишутся на
// FAT12 в AI.WTS (см. save_weights/load_weights) вместе с обученным ys,
// чтобы следующий запуск с ТЕМ ЖЕ паттерном просто загрузил готовые
// веса и сразу показал таблицу, без повторного обучения. Запись требует
// разблокированного диска (fat12.c: fat12_locked=1 по умолчанию,
// команда "unlock" в AxSH) - если диск заблокирован, просто
// предупреждаем и работаем как раньше (без сохранения); чтение не
// требует unlock вообще.
//
// "ai ask" - отдельный режим, не имеющий отношения к MLP выше: жёстко
// заданная база вопрос/ответ про сам AxOS (см. QA_DB) с поиском
// подстроки по ключевым словам. Никакого обучения тут нет - это просто
// lookup, "ИИ" в названии относится к программе в целом, а не к этому
// конкретному режиму.

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
    // 32x32->64 - один аппаратный imul, без вызовов libgcc (проверено
    // линковкой - не должно тянуть __muldi3/__ashrdi3 на константный сдвиг).
    long long r = (long long)a * (long long)b;
    return (int)(r >> FX_BITS);
}

// Таблица сигмоиды: домен [-8.0, 8.0), 512 точек, шаг 1/32 - в Q16.16
// шаг точно равен 2048 (степень двойки), поэтому индекс считается сдвигом,
// без деления. Посчитана заранее (Python: 1/(1+exp(-x)) * 65536).
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

// xorshift32, как ASLR-генератор в tasking.c (тот static и кернельный,
// своя копия для userspace) - сидится ax_get_ticks(), поэтому веса
// разные при каждом запуске.
static unsigned int rng_state;

static unsigned int rng_next(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

static int rnd_weight_fx(void) {
    // диапазон [-1.0, 1.0] в Q16.16
    return (int)(rng_next() % (unsigned int)(2 * FX_SCALE + 1)) - FX_SCALE;
}

// Пишет "[-]D.DDDD" в buf (с '\0') вместо печати - нужно для таблицы
// предсказаний ниже, где значение должно влезть в выровненную ячейку.
static void fixed_to_str(int v, char* buf) {
    unsigned int uv;
    int i = 0;
    if (v < 0) { buf[i++] = '-'; uv = (unsigned int)(-v); }
    else uv = (unsigned int)v;
    unsigned int ip = uv >> FX_BITS;
    unsigned int frac = uv & (FX_SCALE - 1);
    unsigned int dec = (frac * 10000u) >> FX_BITS;  // frac/65536 * 10000

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
    ax_printf("%s", buf);
}

// ASCII-art UI ниже - коробки/таблицы/прогресс-бар через CP437
// box-drawing/block-элементы (аппаратный VGA-текстовый шрифт всегда
// содержит CP437, независимо от настроек ОС, так что эти байты рисуются
// как линии/блоки, а не мусор). \xB3/\xC4/... ниже - это именно эти
// глифы, не control-коды.

static int slen(const char* s) { int n = 0; while (s[n]) n++; return n; }

static int append_str(char* buf, int pos, const char* s) {
    while (*s) buf[pos++] = *s++;
    return pos;
}

// Левосторонне выравнивает text в поле шириной width пробелами - аналог
// "%-Ns", но с шириной из переменной (ax_printf понимает только
// литеральную ширину в самой строке формата).
static void print_padded(const char* text, int width) {
    int i = 0;
    while (text[i] && i < width) { ax_putchar(text[i]); i++; }
    while (i < width) { ax_putchar(' '); i++; }
}

// Рисует рамку вокруг text (однострочный текст, ширина по содержимому)
// в цвете color (ANSI SGR-код типа "\033[36m") - замена старому "=== ... ===".
static void print_boxed(const char* text, const char* color) {
    int len = slen(text);
    ax_printf("%s", color);

    ax_putchar('\xDA');
    for (int i = 0; i < len + 2; i++) ax_putchar('\xC4');
    ax_putchar('\xBF');
    ax_putchar('\n');

    ax_putchar('\xB3');
    ax_putchar(' ');
    ax_printf("%s", text);
    ax_putchar(' ');
    ax_putchar('\xB3');
    ax_putchar('\n');

    ax_putchar('\xC0');
    for (int i = 0; i < len + 2; i++) ax_putchar('\xC4');
    ax_putchar('\xD9');
    ax_putchar('\n');

    ax_printf("\033[0m");
}

// Живой прогресс-бар обучения вместо плоского списка "epoch N: err=...".
// Цвет полосы по величине ошибки - чисто косметика, ошибка и так печатается
// числом рядом.
static void print_progress_bar(int epoch, int total_epochs, int err_fx) {
    const int BAR_WIDTH = 20;
    int filled = (epoch + 1) * BAR_WIDTH / total_epochs;
    if (filled > BAR_WIDTH) filled = BAR_WIDTH;
    int pct = (epoch + 1) * 100 / total_epochs;

    const char* color;
    if (err_fx > FX_SCALE) color = "\033[31m";            // err > 1.0 - красный
    else if (err_fx > FX_SCALE / 5) color = "\033[33m";    // 0.2-1.0 - желтый
    else color = "\033[32m";                                // < 0.2 - зелёный

    ax_printf("epoch %5d/%d %s[", epoch, total_epochs, color);
    int i = 0;
    for (; i < filled; i++) ax_putchar('\xDB');
    for (; i < BAR_WIDTH; i++) ax_putchar('\xB0');
    ax_printf("]\033[0m %3d%%  err=", pct);
    print_fixed(err_fx);
    ax_putchar('\n');
}

static int w1[INPUTS][HIDDEN];   // вход i -> скрытый j
static int b1[HIDDEN];
static int w2[HIDDEN];           // скрытый j -> выход
static int b2;

// Прямой проход: возвращает выход сети, заполняет hidden_out[HIDDEN]
// (нужны backprop'у, чтобы не пересчитывать дважды).
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

// Парсит ровно ROWS символов '0'/'1' из s (и завершающий '\0' сразу
// после них) в out[0..ROWS-1]. Возвращает 1 при успехе, 0 иначе - нет
// ни strlen, ни atoi в этом freestanding-окружении, так что проверяем
// вручную.
static int parse_bits(const char* s, int* out) {
    int i;
    for (i = 0; i < ROWS; i++) {
        char c = s[i];
        if (c != '0' && c != '1') return 0;
        out[i] = c - '0';
    }
    return s[ROWS] == '\0';
}

// Из 256 булевых функций трёх аргументов именами покрыты только
// несколько "известных" - в отличие от 2-входовой версии, где таблица
// была исчерпывающей (16 функций = 16 записей), здесь lookup может не
// найти совпадение - тогда name_for() возвращает generic-строку.
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
//  Сохранение/загрузка обученных весов на FAT12 (AI.WTS) - сеть не
//  забывает выученное после выхода. Файл - "банк" из BANK_SIZE слотов
//  (а не одни веса под одну функцию): можно обучить parity, потом
//  majority, потом AND - каждая своя, без переобучения при переключении
//  между уже выученными паттернами. used=0 - слот свободен. Когда банк
//  полон и совпадения нет, next_slot задаёт round-robin вытеснение
//  (циклически переписываем слоты по порядку, простейшая FIFO-замена
//  без реального учёта времени последнего использования).
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
    int next_slot;               // round-robin индекс для вытеснения
    bank_entry_t entries[BANK_SIZE];
} weights_bank_t;

static int ys_equal(const int* a, const int* b) {
    for (int i = 0; i < ROWS; i++) if (a[i] != b[i]) return 0;
    return 1;
}

// Читает банк с диска в bank; если файла нет/не того размера - чистый
// банк (все слоты свободны), как при самом первом запуске. Чтение не
// требует unlock - fat12_read_file() не проверяет блокировку, в
// отличие от записи (см. save_weights).
static void load_bank(weights_bank_t* bank) {
    unsigned int n = ax_readfile(WEIGHTS_FILE, (unsigned char*)bank, sizeof(*bank));
    if (n != sizeof(*bank)) {
        bank->next_slot = 0;
        for (int i = 0; i < BANK_SIZE; i++) bank->entries[i].used = 0;
    }
}

// Возвращает 1 и загружает w1/b1/w2/b2, если в банке есть слот именно
// для этого ys; иначе 0 (веса не трогает - обучение пойдёт как обычно).
static int load_weights(const int* ys) {
    weights_bank_t bank;
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

// ax_writefile() отказывает, пока диск заблокирован (fat12_locked=1 по
// умолчанию - см. fat12.c) - тогда просто предупреждаем и не падаем,
// как и write.bin в этом же случае. Слот выбирается в порядке:
// существующий слот с тем же ys (перезапись) -> первый свободный ->
// next_slot по кругу (банк полон, вытесняем по FIFO).
static void save_weights(const int* ys) {
    weights_bank_t bank;
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

    if (ax_writefile(WEIGHTS_FILE, (unsigned char*)&bank, sizeof(bank))) {
        if (evicted) {
            ax_printf("\033[32mSaved trained weights to %s\033[0m (bank was full - "
                      "evicted the oldest slot). Run 'ai list' to see what's stored.\n",
                      WEIGHTS_FILE);
        } else {
            ax_printf("\033[32mSaved trained weights to %s\033[0m - next run with this "
                      "pattern will skip training. Run 'ai list' to see what's stored.\n",
                      WEIGHTS_FILE);
        }
    } else {
        ax_printf("\033[33mCould not save weights (disk locked - run 'unlock' first "
                  "to persist).\033[0m\n");
    }
}

// "ai list" - показывает, какие функции уже обучены и лежат в банке,
// без обучения чего-либо.
static void list_bank(void) {
    weights_bank_t bank;
    load_bank(&bank);

    int any = 0;
    for (int i = 0; i < BANK_SIZE; i++) {
        if (!bank.entries[i].used) continue;
        any = 1;
        char pattern[ROWS + 1];
        for (int j = 0; j < ROWS; j++) pattern[j] = (char)('0' + bank.entries[i].ys[j]);
        pattern[ROWS] = '\0';
        ax_printf("  [%d] %s - %s\n", i, pattern, name_for(bank.entries[i].ys));
    }
    if (!any) {
        ax_printf("%s is empty - nothing trained and saved yet (need 'unlock' before "
                  "training to persist).\n", WEIGHTS_FILE);
    }
}

// Уверенность сети в своём предсказании - не то же самое, что
// правильность (OK/FAIL сравнивает с target, эта величина смотрит
// только на то, насколько output далёк от неопределённых 0.5).
// |output - 0.5| * 2: 0% на самой границе принятия решения (output
// ровно 0.5 - сеть совсем не уверена, в какую сторону), 100% на
// выходах, прижатых сигмоидой к самым 0 или 1.
static int confidence_pct(int o_out) {
    int diff = (o_out > FX_HALF) ? (o_out - FX_HALF) : (FX_HALF - o_out);
    int conf_fx = diff << 1;  // *2 в Q16.16 - просто сдвиг, не fx_mul
    int pct = (conf_fx * 100) >> FX_BITS;
    if (pct > 100) pct = 100;  // на случай округления у самой границы
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

// Таблица финальных предсказаний - колонки A/B/C/predicted/target/
// status/conf; ширина каждой включает рамки и оба окружающих content
// пробела (см. print_cell). Те же ширины используются для
// горизонтальных линий, иначе рамка не совпадёт со столбцами.
#define PRED_TABLE_COLS 7
static const int PRED_TABLE_WIDTHS[PRED_TABLE_COLS] = { 3, 3, 3, 11, 8, 8, 8 };

static void print_table_border(char left, char mid, char right) {
    ax_putchar(left);
    for (int c = 0; c < PRED_TABLE_COLS; c++) {
        for (int i = 0; i < PRED_TABLE_WIDTHS[c]; i++) ax_putchar('\xC4');
        ax_putchar(c < PRED_TABLE_COLS - 1 ? mid : right);
    }
    ax_putchar('\n');
}

static void print_cell(int width, const char* text) {
    ax_putchar('\xB3');
    ax_putchar(' ');
    print_padded(text, width - 2);
    ax_putchar(' ');
}

// Цвет применяется отдельными ax_printf-вызовами вокруг print_padded, а
// не внутри её аргумента - иначе невидимые ANSI-байты посчитались бы в
// ширину поля и таблица бы "поехала".
static void print_cell_colored(int width, const char* text, const char* color) {
    ax_putchar('\xB3');
    ax_putchar(' ');
    ax_printf("%s", color);
    print_padded(text, width - 2);
    ax_printf("\033[0m");
    ax_putchar(' ');
}

// =================================================================
//  "ai ask" - жёстко заданная база вопрос/ответ про сам AxOS.
//  Никакого ML тут нет - просто поиск подстроки по ключевым словам
//  (см. QA_DB ниже), первое совпадение побеждает. Клавиатурный драйвер
//  (kernel.c: scancode_to_char[]) понимает только ASCII/US-layout, так
//  что вопросы и ответы - на английском, как и весь остальной UI ai.c.
// =================================================================

// Копирует src в dst в нижнем регистре (только A-Z), максимум max-1
// символов + '\0' - своя версия strlen/tolower, их тут нет.
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

// needle ненулевой, ищет его как подстроку в hay - оба уже в нижнем
// регистре (lower_copy), сравнение тут чисто посимвольное.
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
      "AxOS is a small 32-bit x86 OS: own bootloader, kernel, FAT12 "
      "filesystem, MAC/MLS security, and ELF32 user programs." },
    { { "hidden layer", "perceptron", "neuron" },
      "This network is a 3-6-1 MLP: 3 inputs, 6 hidden neurons, 1 output, "
      "trained by backpropagation." },
    { { "xor" },
      "XOR (parity) is the classic function a single-layer perceptron "
      "cannot learn (Minsky/Papert) - that's why this MLP has a hidden layer." },
    { { "fpu", "float", "double" },
      "AxOS never initializes the FPU, so all math here (including this "
      "network) is fixed-point Q16.16, not float." },
    { { "syscall", "system call" },
      "User programs talk to the kernel via int 0x80, dispatched by "
      "syscall_dispatch() in kernel.c." },
    { { "fat12", "filesystem", "disk" },
      "AxOS uses a FAT12 filesystem on a raw IDE disk image (build/disk.img)." },
    { { "mac", "selinux", "type enforcement" },
      "AxOS has a SELinux-style Type Enforcement MAC layer: domains x "
      "classes, denials logged as 'avc: denied'." },
    { { "mls", "clearance", "sensitivity level" },
      "AxOS supports MLS sensitivity levels s0-s15 with a no-read-up "
      "dominance check on the clipboard." },
    { { "elf", "loader" },
      "User programs are real ELF32 executables, parsed by src/kernel/elf.c "
      "- not flat binaries." },
    { { "axos" },
      "AxOS is a small 32-bit x86 OS written from scratch - see 'what is axos'." },
    { { "help", "what can you do", "commands" },
      "Ask me about axos, xor, fpu, syscalls, fat12, mac, mls, elf, or "
      "neurons - or run 'ai <8 bits>' to train a 3-input boolean function, "
      "or 'ai list' to see saved weights." },
};
#define QA_COUNT (int)(sizeof(QA_DB) / sizeof(QA_DB[0]))

#define ASK_FALLBACK_MSG "I don't know that one yet - try asking about axos, xor, " \
                          "fpu, syscalls, fat12, mac, mls, elf, or neurons."

// NULL, а не ASK_FALLBACK_MSG, на отсутствие совпадения - вызывающему
// (run_ask_mode) нужно отличить "правда не нашли" от "нашли", чтобы
// решить, предлагать ли обучение (см. ниже).
static const char* find_builtin_answer(const char* q) {
    for (int i = 0; i < QA_COUNT; i++) {
        for (int k = 0; k < QA_MAX_KEYWORDS && QA_DB[i].keywords[k]; k++) {
            if (contains(q, QA_DB[i].keywords[k])) return QA_DB[i].answer;
        }
    }
    return 0;
}

// =================================================================
//  "ai ask" учится: когда ни встроенная QA_DB, ни уже выученные
//  записи не дают ответа, предлагаем пользователю научить - вопрос
//  (целиком, как ключевая фраза) и ответ сохраняются на FAT12 в AI.QA,
//  тем же банковым механизмом, что и веса в AI.WTS (см. там) - тоже
//  round-robin вытеснение, тоже требует unlock для записи, чтение
//  тоже работает всегда. В памяти держим один банк на весь run_ask_mode
//  (a не перечитываем с диска на каждый вопрос) - выученное в этой
//  же сессии сразу доступно для повторного вопроса.
// =================================================================
#define LEARNED_FILE "AI.QA"
#define LEARNED_MAX 16
#define LEARNED_KEYWORD_LEN 64
#define LEARNED_ANSWER_LEN 160

typedef struct {
    int used;
    char keyword[LEARNED_KEYWORD_LEN];  // вопрос целиком, как его ввёл пользователь (в нижнем регистре)
    char answer[LEARNED_ANSWER_LEN];
} learned_entry_t;

typedef struct {
    int next_slot;
    learned_entry_t entries[LEARNED_MAX];
} learned_bank_t;

static void load_learned_bank(learned_bank_t* bank) {
    unsigned int n = ax_readfile(LEARNED_FILE, (unsigned char*)bank, sizeof(*bank));
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

// Копирует ровно max-1 байт из src в dst (с '\0') - своя версия strncpy,
// её тут нет.
static void copy_truncated(char* dst, const char* src, int max) {
    int i;
    for (i = 0; i < max - 1 && src[i]; i++) dst[i] = src[i];
    dst[i] = '\0';
}

// ax_writefile() отказывает, пока диск заблокирован - см. save_weights
// (тот же случай, та же причина: fat12_locked=1 по умолчанию).
static int save_learned(const char* keyword, const char* answer) {
    // static, не локальная на стеке - sizeof(learned_bank_t) ~3.6 КБ,
    // вместе с другими локалами превышает порог, после которого gcc
    // вставляет вызов __chkstk_ms (проверка/рост стека большими кусками
    // на Windows) - в этом freestanding-окружении такого хелпера нет,
    // линковка падала с "undefined reference". Не реентерабельно, но
    // эта функция и так не вызывается рекурсивно/из нескольких потоков.
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

    return ax_writefile(LEARNED_FILE, (unsigned char*)&bank, sizeof(bank));
}

// "ai ask" -> "list" - печатает все выученные пары вопрос/ответ из AI.QA
// (in-memory копию, не перечитывая диск) - просто чтобы было видно, чему
// программа уже научена, без поиска по ключевому слову.
static void list_learned(const learned_bank_t* bank) {
    int any = 0;
    for (int i = 0; i < LEARNED_MAX; i++) {
        if (!bank->entries[i].used) continue;
        any = 1;
        ax_printf("  [%d] \"%s\" -> %s\n", i, bank->entries[i].keyword, bank->entries[i].answer);
    }
    if (!any) {
        ax_printf("Nothing learned yet - ask me something I don't know and teach me.\n");
    }
}

static void run_ask_mode(void) {
    print_boxed("AxOS AI: ask me something ('list' = learned, 'exit' = quit)", "\033[36m");

    static learned_bank_t learned;  // см. комментарий в save_learned()
    load_learned_bank(&learned);

    char line[64];
    char lower[64];
    for (;;) {
        ax_printf("\033[33m? \033[0m");
        ax_readline(line, sizeof(line));
        if (line[0] == '\0') continue;
        lower_copy(line, lower, sizeof(lower));
        if (streq(lower, "exit") || streq(lower, "quit")) break;
        if (streq(lower, "list")) { list_learned(&learned); continue; }

        const char* ans = find_builtin_answer(lower);
        if (!ans) ans = find_learned_answer(&learned, lower);

        if (ans) {
            ax_printf("\033[32mAI:\033[0m %s\n", ans);
            continue;
        }

        ax_printf("\033[32mAI:\033[0m " ASK_FALLBACK_MSG "\n");
        ax_printf("Teach me the answer? Type it now, or Enter to skip:\n");
        ax_printf("\033[33m> \033[0m");
        char teach[LEARNED_ANSWER_LEN];
        ax_readline(teach, sizeof(teach));
        if (teach[0] == '\0') continue;

        // "exit"/"quit" здесь - это попытка выйти, не буквальный текст
        // ответа (та же ловушка, что и в обычном "? "-промпте) - иначе
        // пользователь, по привычке набравший "exit", навсегда обучил
        // бы программу отвечать "exit" на этот вопрос.
        char teach_lower[LEARNED_ANSWER_LEN];
        lower_copy(teach, teach_lower, sizeof(teach_lower));
        if (streq(teach_lower, "exit") || streq(teach_lower, "quit")) break;

        if (save_learned(lower, teach)) {
            // обновляем И диск, И in-memory копию - повторный вопрос в
            // этой же сессии не должен снова просить научить.
            load_learned_bank(&learned);
            ax_printf("\033[32mAI:\033[0m Got it, thanks - I'll remember that.\n");
        } else {
            ax_printf("\033[33mAI:\033[0m Could not save (disk locked - run 'unlock' "
                      "first to persist), but I'll remember it for this session.\n");
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

    // дефолт: parity/XOR3 (0,1,1,0,1,0,0,1) - самая сложная из известных
    // функций, как и XOR был дефолтом в 2-входовой версии.
    int ys[ROWS] = { 0, 1, 1, 0, 1, 0, 0, 1 };
    int have_pattern = 0;

    if (argc > 1) {
        if (parse_bits(argv[1], ys)) {
            have_pattern = 1;
        } else {
            ax_printf("ai: invalid pattern \"%s\" (need 8 chars of 0/1, e.g. 01101001). "
                      "Defaulting to parity.\n", argv[1]);
            have_pattern = 1;  // ys уже = parity
        }
    }

    rng_state = ax_get_ticks() ^ 0x9E3779B9u;
    if (rng_state == 0) rng_state = 0x9E3779B9u;

    if (!have_pattern) {
        print_boxed("AxOS AI: 3-6-1 MLP learns any 3-input boolean function", "\033[36m");
        ax_printf("Enter the 8 outputs for inputs 000,001,010,011,100,101,110,111\n");
        ax_printf("as an 8-bit string (e.g. 01101001 = parity/XOR3, 00010111 =\n");
        ax_printf("majority, 00000001 = AND3), or Enter for parity.\n");
        ax_printf("(Run 'ai ask' for Q&A about AxOS, or 'ai list' to see saved weights.)\n");

        char line[16];
        for (int attempt = 0; attempt < 3 && !have_pattern; attempt++) {
            ax_printf("\033[33m> \033[0m");
            ax_readline(line, sizeof(line));
            if (line[0] == '\0') {
                have_pattern = 1;  // ys уже = parity
            } else if (parse_bits(line, ys)) {
                have_pattern = 1;
            } else {
                ax_printf("Invalid input, need exactly 8 chars of 0/1.\n");
            }
        }
        if (!have_pattern) {
            ax_printf("Giving up, defaulting to parity.\n");
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
        ax_putchar('\n');
        print_boxed(banner, "\033[36m");
    }

    if (loaded) {
        ax_printf("Found saved weights for this pattern in %s - skipping training.\n\n",
                  WEIGHTS_FILE);
    } else {
        ax_printf("fixed-point Q16.16, sigmoid LUT, backprop, %d epochs\n\n", EPOCHS);

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

                // backprop: delta = error * sigmoid'(out), sigmoid'(s) = s*(1-s)
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

    ax_printf("\n\033[36mFinal predictions:\033[0m\n");

    print_table_border('\xDA', '\xC2', '\xBF');
    print_cell(PRED_TABLE_WIDTHS[0], "A");
    print_cell(PRED_TABLE_WIDTHS[1], "B");
    print_cell(PRED_TABLE_WIDTHS[2], "C");
    print_cell(PRED_TABLE_WIDTHS[3], "predicted");
    print_cell(PRED_TABLE_WIDTHS[4], "target");
    print_cell(PRED_TABLE_WIDTHS[5], "status");
    print_cell(PRED_TABLE_WIDTHS[6], "conf");
    ax_putchar('\xB3');
    ax_putchar('\n');
    print_table_border('\xC3', '\xC5', '\xB4');

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
        ax_putchar('\xB3');
        ax_putchar('\n');
    }
    print_table_border('\xC0', '\xC1', '\xD9');

    // Сохраняем только то, что только что обучили и что реально сошлось -
    // переписывать уже сохранённые (loaded) веса самими же ними бессмысленно,
    // а сохранять несошедшуюся (all_ok=0) модель ещё хуже - следующий запуск
    // загрузил бы её и доложил "PASS" не пытаясь обучиться вообще.
    if (!loaded && all_ok) save_weights(ys);

    ax_printf("\n%s\n", all_ok ? "\033[32mPASS: network learned the function\033[0m"
                                : "\033[31mFAIL: network did not converge\033[0m");
    return all_ok ? 0 : 1;
}
