#include "../include/axiom.h"

// Hardened heap: shadow memory + 144-bit generation tags + redzones + quarantine.
//
// Тег прошёл путь 32→64→144 бит (см. тот же приём в src/kernel/heap.c и
// src/user/rv64/malloc.h). 144 бита (tag144_t, объявлен в axiom.h - он уже
// общий заголовок для этого файла и его вызывающего кода, поэтому тип не
// дублируется независимо, в отличие от полностью изолированных 4 аллокаторов
// ядра) шире родного 32-битного регистра -m32 кода вдвойне сильнее, чем было
// с 64-битным тегом - сравнение тега теперь честных три сравнения полей
// (lo/mid/hi) вместо одного, сознательный компромисс скорости.
//
// Макет каждого блока:
//   [struct block : HDR]
//   [левая redzone : RZONE_SIZE байт, 0xBE]   ← shadow RZONE
//   [пользовательские данные : N байт, 0x00]  ← shadow OK + 144-bit тег
//   [правая redzone : RZONE_SIZE байт, 0xBE]  ← shadow RZONE
//   [канарейка : CANARY_SIZE байт, BASE^tag]
//
// Shadow-массивы (гранула SHADOW_GRANULE = 8 байт):
//   shadow_state[i]  — OK / RZONE / FREED
//   shadow_tag[i]    — 144-бит тег поколения (ненулевой; нулевой = rzone/freed)
//
// 144 бита → коллизия поколений при переиспользовании адреса ≈ 1/2^144
// (было 1/2^64) - не криптографическая гарантия (тег не секрет, если
// атакующий уже читает память процесса), а снижение шанса случайного
// совпадения при UAF ещё на много порядков (хотя при 64 битах она и так уже
// была практически недостижима - выигрыш скорее академический).
//
// Что ловится:
//   heap underflow     → left redzone 0xBE испорчен при free()
//   heap overflow      → right redzone 0xBE испорчен при free()
//   heap overflow+     → канарейка BASE^tag не совпала
//   use-after-free     → shadow FREED; ax_check_tag() возвращает 0
//   double-free        → magic == QUARANTINE при повторном free()
//   stale ptr (reuse)  → новое поколение = новый 32-бит тег; ax_check_tag() = 0
//   данные прошлого    → zero-on-alloc: всегда 0x00 при выдаче
//
// API:
//   ax_alloc_tag(ptr)              — тег текущего поколения (0 если freed).
//   ax_check(ptr, size)            — доступен ли диапазон (state == OK).
//   ax_check_tag(ptr, tag, size)   — доступен И тег совпадает.

#define ALIGN8(n) (((unsigned int)(n) + 7u) & ~7u)

#define MAGIC_ALLOC      0x4C41434Bu
#define MAGIC_QUARANTINE 0x51524E54u
#define MAGIC_FREE       0x46524545u

#define RZONE_SIZE   8u
#define RZONE_BYTE   0xBEu
// CANARY_SIZE - зарезервированное место под канарейку, 24 байта, НЕ
// sizeof(tag144_t) (18). Shadow-память индексируется 8-байтными гранулами
// (SHADOW_GRANULE) и МОЛЧА считает, что каждая граница
// header/lzone/user/rzone/canary в блоке кратна 8 байтам от heap_base -
// раньше (8-байтный tag, естественное выравнивание long long на -m32 = 4)
// это выполнялось "бесплатно" (HDR=24, +RZONE=32 - кратно 8). С
// tag144_t (18 байт, упакован, выравнивание 1) сумма header+rzone+canary
// перестала быть кратной 8 - соседний user-data и right-redzone граничили
// ВНУТРИ одной гранулы, и shadow_fill() для redzone тихо затирал последний
// гранул уже помеченных как OK пользовательских данных (реальный баг,
// пойманный live через memtest.c: "FAIL: ax_check live" - см.
// tag144_t-секцию README). 24 = ALIGN8(18) восстанавливает инвариант без
// изменения самого tag144_t (он по-прежнему ровно 18 байт/144 бита) -
// лишние 6 байт просто зарезервированы и никогда не читаются/не пишутся.
#define CANARY_SIZE  24u
#define CANARY_BASE_LO  (0xACACACACu | ((unsigned long long)0xACACACACu << 32))
#define CANARY_BASE_MID (0xACACACACu | ((unsigned long long)0xACACACACu << 32))
#define CANARY_BASE_HI  ((unsigned short)0xACACu)
#define QUARANTINE_N 8u

// COVER уменьшен ещё раз (16КБ -> 4КБ) вслед за расширением тега 64->144
// бита (tag144_t, 18 байт вместо 8): при старом COVER=16КБ shadow_tag
// вырос бы с 16КБ до 36КБ на КАЖДУЮ программу, слинкованную с libaxiom
// (~30 штук в fs/) - суммарный прирост (+20КБ * 30 ≈ +600КБ) не влезал в
// 1МБ FAT12-образ (build.bat реально падал на TCPSERVE.BIN: "не хватило
// свободного места"). При COVER=4КБ футпринт shadow_tag+shadow_state снова
// ~9.5КБ на бинарник - меньше, чем было даже при 64-битном теге (18КБ) -
// подтверждено успешной сборкой. Меньшее окно отслеживания не влияет на
// magic/redzone/канарейку/карантин (они не зависят от SHADOW_COVER) -
// только на ax_check()/ax_check_tag() за пределами первых 4КБ кучи, где
// они честно вернут "не отслеживается" вместо "живо/мертво".
#define SHADOW_GRANULE     8u
#define SHADOW_COVER       (8u * 1024u)
#define SHADOW_SIZE        (SHADOW_COVER / SHADOW_GRANULE)

#define SHADOW_STATE_OK    0x00u
#define SHADOW_STATE_RZONE 0xFAu
#define SHADOW_STATE_FREED 0xFDu

struct block {
    unsigned int  size;
    struct block* next;
    unsigned int  free;
    unsigned int  magic;
    tag144_t      tag;      // 144-битный тег поколения (см. axiom.h)
    unsigned char _pad[6];  // округляет sizeof(struct block) 34->40 (кратно 8) -
                             // см. комментарий у CANARY_SIZE, тот же инвариант.
};

#define HDR sizeof(struct block)

static struct block*  free_list        = 0;
static struct block*  quarantine[QUARANTINE_N];
static unsigned int   quarantine_pos   = 0;
static unsigned int   quarantine_count = 0;
static unsigned long long prng_state   = 0;

static unsigned char  shadow_state[SHADOW_SIZE];     // OK / RZONE / FREED  (4 KB)
static tag144_t        shadow_tag[SHADOW_SIZE];      // 144-бит тег поколения
static unsigned char* heap_base = 0;

// --- Shadow ---

static int shadow_idx(void* p) {
    if (!heap_base) return -1;
    int off = (int)((unsigned char*)p - heap_base);
    if (off < 0 || (unsigned int)off >= SHADOW_COVER) return -1;
    return off / (int)SHADOW_GRANULE;
}

static void shadow_fill(void* start, unsigned int nbytes,
                        unsigned char state, tag144_t tag) {
    int i0 = shadow_idx(start);
    int i1 = shadow_idx((unsigned char*)start + nbytes - 1);
    if (i0 < 0 || i1 < 0 || i0 > i1) return;
    for (int i = i0; i <= i1; i++) {
        shadow_state[i] = state;
        shadow_tag[i]   = tag;
    }
}

// 1 если весь диапазон в состоянии OK (тег не проверяется).
int ax_check(void* ptr, unsigned int size) {
    if (!ptr || size == 0) return 0;
    int i0 = shadow_idx(ptr);
    int i1 = shadow_idx((unsigned char*)ptr + size - 1);
    if (i0 < 0 || i1 < 0) return 0;
    for (int i = i0; i <= i1; i++)
        if (shadow_state[i] != SHADOW_STATE_OK) return 0;
    return 1;
}

// Тег текущего поколения блока. Нулевой tag144_t если freed или не выделен.
tag144_t ax_alloc_tag(void* ptr) {
    int idx = shadow_idx(ptr);
    if (idx < 0) return tag144_zero();
    if (shadow_state[idx] != SHADOW_STATE_OK) return tag144_zero();
    return shadow_tag[idx];
}

// 1 если OK И тег совпадает с expected_tag.
int ax_check_tag(void* ptr, tag144_t expected_tag, unsigned int size) {
    if (!ptr || size == 0 || tag144_is_zero(expected_tag)) return 0;
    int i0 = shadow_idx(ptr);
    int i1 = shadow_idx((unsigned char*)ptr + size - 1);
    if (i0 < 0 || i1 < 0) return 0;
    for (int i = i0; i <= i1; i++)
        if (shadow_state[i] != SHADOW_STATE_OK || !tag144_eq(shadow_tag[i], expected_tag)) return 0;
    return 1;
}

// "Software TBI" stand-in: снимок (addr, поколение) в момент вызова -
// resolve() позже перепроверяет тег против ТЕКУЩЕГО поколения блока,
// программный аналог того, что настоящий MTE делает аппаратно на каждом
// load/store (ни x86-64, ни RISC-V sv39 здесь этого не умеют - нет
// LAM/Zjpm, тег в старших битах указателя железо бы просто не проигнорировало).
ax_handle_t ax_handle(void* ptr) {
    ax_handle_t h;
    h.addr = ptr;
    h.tag  = ax_alloc_tag(ptr);
    return h;
}

// Указатель, если блок всё ещё того же поколения, что было при
// ax_handle(); иначе 0 (freed / переиспользован / никогда не был живым).
void* ax_resolve(ax_handle_t h, unsigned int size) {
    if (tag144_is_zero(h.tag)) return 0;
    return ax_check_tag(h.addr, h.tag, size) ? h.addr : 0;
}

// --- PRNG: xorshift64, никогда не возвращает 0 ---
// Канонические сдвиги для 64-битного слова (13, 7, 17) - не та тройка
// (13, 17, 5), что была тут для 32-битной версии: она подобрана под 32
// бита и на 64 давала бы более слабую/короткую последовательность.
// "long long" арифметика в -m32 коде компилируется в пару 32-битных
// регистров - дороже одного regis­тра, но не требует -m64.

static unsigned long long xorshift64_step(void) {
    if (prng_state == 0) {
        unsigned int sp;
        __asm__("mov %%esp, %0" : "=r"(sp));
        prng_state = (unsigned long long)sp ^ 0x9E3779B97F4A7C15ull;
        if (prng_state == 0) prng_state = 1ull;
    }
    prng_state ^= prng_state << 13;
    prng_state ^= prng_state >> 7;
    prng_state ^= prng_state << 17;
    return prng_state ? prng_state : 1ull;
}

static tag144_t next_tag(void) {
    tag144_t t;
    t.lo  = xorshift64_step();
    t.mid = xorshift64_step();
    t.hi  = (unsigned short)(xorshift64_step() & 0xFFFFu);
    if (tag144_is_zero(t)) t.lo = 1;
    return t;
}

static tag144_t tagged_canary(tag144_t tag) {
    tag144_t c;
    c.lo  = CANARY_BASE_LO  ^ tag.lo;
    c.mid = CANARY_BASE_MID ^ tag.mid;
    c.hi  = (unsigned short)(CANARY_BASE_HI ^ tag.hi);
    return c;
}

// --- Heap corruption ---

static void heap_corrupted(char* why) {
    ax_print("\n*** HEAP CORRUPTION: ");
    ax_print(why);
    ax_print(" ***\n");
    while (1) {}
}

// --- Quarantine / free list ---

static void release_to_free_list(struct block* b) {
    unsigned char* payload   = (unsigned char*)b + HDR + RZONE_SIZE;
    unsigned int   user_size = b->size - RZONE_SIZE - CANARY_SIZE;
    for (unsigned int i = 0; i < user_size; i++) payload[i] = 0xDDu;

    b->free  = 1;
    b->magic = MAGIC_FREE;
    b->tag   = tag144_zero();

    struct block* next_adj = (struct block*)((char*)b + HDR + b->size);
    struct block* prev = 0, *cur = free_list;
    while (cur) {
        if (cur == next_adj) {
            b->size += HDR + cur->size;
            if (prev) prev->next = cur->next;
            else      free_list  = cur->next;
            break;
        }
        prev = cur; cur = cur->next;
    }

    prev = 0; cur = free_list;
    while (cur) {
        if ((char*)cur + HDR + cur->size == (char*)b) {
            cur->size += HDR + b->size;
            return;
        }
        prev = cur; cur = cur->next;
    }

    b->next   = free_list;
    free_list = b;
}

static void quarantine_push(struct block* b) {
    unsigned char* payload   = (unsigned char*)b + HDR + RZONE_SIZE;
    unsigned int   user_size = b->size - RZONE_SIZE - CANARY_SIZE;
    shadow_fill(payload, user_size, SHADOW_STATE_FREED, tag144_zero());

    if (quarantine_count == QUARANTINE_N)
        release_to_free_list(quarantine[quarantine_pos]);
    else
        quarantine_count++;
    quarantine[quarantine_pos] = b;
    quarantine_pos = (quarantine_pos + 1) % QUARANTINE_N;
}

// --- Public API ---

void* ax_malloc(unsigned int size) {
    if (size == 0) return 0;
    size = ALIGN8(size);
    // Макет: [lzone:RZONE_SIZE][user:size][rzone:RZONE_SIZE][canary:CANARY_SIZE]
    unsigned int total = RZONE_SIZE + size + RZONE_SIZE + CANARY_SIZE;

    struct block* b = 0;
    struct block* prev = 0, *cur = free_list;
    while (cur) {
        if (cur->size >= total) {
            if (prev) prev->next = cur->next;
            else      free_list  = cur->next;
            b = cur;
            break;
        }
        prev = cur; cur = cur->next;
    }

    if (!b) {
        b = (struct block*)ax_sbrk((int)(HDR + total));
        if ((unsigned int)b == (unsigned int)-1) return 0;
        if (!heap_base) heap_base = (unsigned char*)b;
        b->size = total;
    }

    // user_size = байты полезных данных (без обеих rzone и canary)
    unsigned int user_size = b->size - 2u * RZONE_SIZE - CANARY_SIZE;
    tag144_t tag = next_tag();

    b->free  = 0;
    b->next  = 0;
    b->magic = MAGIC_ALLOC;
    b->tag   = tag;

    // Левая redzone
    unsigned char* lzone = (unsigned char*)b + HDR;
    for (unsigned int i = 0; i < RZONE_SIZE; i++) lzone[i] = RZONE_BYTE;
    shadow_fill(lzone, RZONE_SIZE, SHADOW_STATE_RZONE, tag144_zero());

    // Пользовательские данные: zero-on-alloc + shadow OK
    void* ptr = (void*)(lzone + RZONE_SIZE);
    for (unsigned int i = 0; i < user_size; i++) ((unsigned char*)ptr)[i] = 0;
    shadow_fill(ptr, user_size, SHADOW_STATE_OK, tag);

    // Правая redzone
    unsigned char* rzone = (unsigned char*)ptr + user_size;
    for (unsigned int i = 0; i < RZONE_SIZE; i++) rzone[i] = RZONE_BYTE;
    shadow_fill(rzone, RZONE_SIZE, SHADOW_STATE_RZONE, tag144_zero());

    // Канарейка после правой rzone
    *(tag144_t*)(rzone + RZONE_SIZE) = tagged_canary(tag);

    return ptr;
}

void ax_free(void* ptr) {
    if (!ptr) return;
    struct block* b = (struct block*)((char*)ptr - RZONE_SIZE - HDR);

    if (b->magic == MAGIC_FREE || b->magic == MAGIC_QUARANTINE)
        heap_corrupted("double free");
    if (b->magic != MAGIC_ALLOC)
        heap_corrupted("free on invalid pointer");

    unsigned char* lzone = (unsigned char*)b + HDR;
    for (unsigned int i = 0; i < RZONE_SIZE; i++)
        if (lzone[i] != RZONE_BYTE) heap_corrupted("left redzone underflow");

    unsigned int user_size = b->size - 2u * RZONE_SIZE - CANARY_SIZE;

    // Правая redzone: overflow между концом данных и канарейкой
    unsigned char* rzone = (unsigned char*)ptr + user_size;
    for (unsigned int i = 0; i < RZONE_SIZE; i++)
        if (rzone[i] != RZONE_BYTE) heap_corrupted("right redzone overflow");

    if (!tag144_eq(*(tag144_t*)(rzone + RZONE_SIZE), tagged_canary(b->tag)))
        heap_corrupted("buffer overflow (canary)");

    b->magic = MAGIC_QUARANTINE;
    b->free  = 0;
    quarantine_push(b);
}
