#include "kcfi.h"
#include "tasking.h"

// =================================================================
//  Kernel CFI: 1-to-1 shadow table + cookie authentication
// =================================================================
//
// Улучшение над GrapheneOS LLVM CFI:
//   GrapheneOS: тип-классовая проверка (1 из N функций с той же сигнатурой)
//   AxOS:       1-to-1 binding (ровно одна разрешённая функция на слот)
//               + cookie = master_key ^ fn ^ slot*prime (32-bit auth)
//
// Примечание: page-seal (paging_mark_kernel_ro) не применяется — ld PE
// не гарантирует выравнивание .bss объектов > section-alignment (0x200).
// Защита строится на cookie-аутентификации: угадать master_key = 2^-32.

#define KCFI_SLOTS   64u
#define KCFI_PRIME   0x9E3779B9u  // golden-ratio Knuth prime

extern void print_string(char*);
extern volatile unsigned long timer_ticks;

static void*        cfi_fn[KCFI_SLOTS];
static unsigned int cfi_cookie[KCFI_SLOTS];
static unsigned int cfi_master_key;
static unsigned int cfi_n;

static void kcfi_print_hex(unsigned int val) {
    const char hx[16] = "0123456789ABCDEF";
    char buf[9]; buf[8] = 0;
    for (int i = 7; i >= 0; i--) { buf[i] = hx[val & 0xF]; val >>= 4; }
    print_string(buf);
}
static void kcfi_print_hex_byte(unsigned char val) {
    const char hx[16] = "0123456789ABCDEF";
    char buf[3]; buf[2] = 0;
    buf[0] = hx[val >> 4]; buf[1] = hx[val & 0xF];
    print_string(buf);
}

static unsigned int kcfi_entropy(void) {
    unsigned int lo, hi, sp;
    __asm__ volatile("rdtsc"        : "=a"(lo), "=d"(hi));
    __asm__ volatile("mov %%esp,%0" : "=r"(sp));
    unsigned int r = lo ^ (hi * KCFI_PRIME) ^ sp ^ (unsigned int)timer_ticks;
    r = (r ^ (r >> 16)) * 0x45D9F3Bu;
    r = (r ^ (r >> 16)) * 0x45D9F3Bu;
    return r ^ (r >> 16);
}

void kcfi_init(void** fn_table, unsigned int n) {
    if (n > KCFI_SLOTS) n = KCFI_SLOTS;
    cfi_n = n;

    cfi_master_key = kcfi_entropy();
    volatile unsigned int waste = 0;
    for (unsigned int i = 0; i < 1000; i++) waste += i;
    cfi_master_key ^= kcfi_entropy() ^ waste;

    print_string("[CFI] key=0x"); kcfi_print_hex(cfi_master_key);

    unsigned int valid = 0;
    for (unsigned int i = 0; i < n; i++) {
        cfi_fn[i]     = fn_table[i];
        cfi_cookie[i] = cfi_master_key ^ (unsigned int)fn_table[i] ^ (i * KCFI_PRIME);
        if (fn_table[i]) valid++;
    }

    print_string(" slots=");
    char tmp[4]; int ti = 3; tmp[ti] = 0;
    unsigned int v = valid;
    do { tmp[--ti] = '0' + (v % 10); v /= 10; } while (v && ti > 0);
    print_string(tmp + ti);
    print_string(" active\n");
}

void kcfi_check(unsigned char slot, void* fn) {
    if (slot >= cfi_n) goto fault;
    if (!fn) return;

    if (fn != cfi_fn[slot]) goto fault;

    {
        unsigned int expected = cfi_master_key ^ (unsigned int)fn ^ (slot * KCFI_PRIME);
        if (cfi_cookie[slot] != expected) goto fault;
    }
    return;

fault:
    print_string("\n\033[31m[CFI] forward-edge violation! slot=0x");
    kcfi_print_hex_byte(slot);
    print_string(" fn=0x");
    kcfi_print_hex((unsigned int)fn);
    if (cfi_n && slot < cfi_n) {
        print_string(" expected=0x");
        kcfi_print_hex((unsigned int)cfi_fn[slot]);
    }
    print_string("\033[0m\n");

    if (task_current_is_isolated()) {
        task_mark_current_exiting();
    } else {
        __asm__ volatile("cli; hlt");
    }
}
