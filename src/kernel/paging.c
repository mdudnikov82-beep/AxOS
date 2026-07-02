// =================================================================
//  Paging: PAE mode + W^X (Write XOR Execute)
// =================================================================
//
// PAE (Physical Address Extension) - 3-уровневые таблицы с 8-байтными
// PTE. Структура для первых 4 МБ:
//   CR3 → PDPT[0..3]                 (0x9C000, 4 × 8Б, 32Б-выровн.)
//   PDPT[0] → PD                     (0x9D000, 512 × 8Б)
//   PD[0]   → PT0                    (0x9E000, VA 0..2МБ, 512 × 8Б)
//   PD[1]   → PT1                    (0x9F000, VA 2..4МБ, 512 × 8Б)
//
// W^X: бит 63 PTE = XD (Execute-Disable) при EFER.NXE=1.
//   Страницы кода пользователя: Present|User, без R/W, без XD → R+X
//   Страницы данных/стека:      Present|User|R/W|XD             → RW+NX
//   Spin-страница (15):         Present|User|R/W                 → RW+X
//
// Ядро: .text → R+X (без записи); данные → RW+NX.

#include "paging.h"
#include "tasking.h"

#define PAE_P    (1ULL)        // Present
#define PAE_RW   (1ULL << 1)  // Read/Write
#define PAE_USER (1ULL << 2)  // User/Supervisor
#define PAE_XD   (1ULL << 63) // Execute-Disable (NX)

#define PAGE_SIZE 0x1000u

typedef unsigned long long pae_t;

extern void print_string(char* str);
extern char _text_end[];

// 1 если ЦП поддерживает NX/XD, определяется в init_paging()
static int g_nx = 0;
// 1 если ЦП поддерживает SMEP (CR4[20]), определяется в init_paging()
static int g_smep = 0;
// 1 если ЦП поддерживает SMAP (CR4[21]), определяется в init_paging()
static int g_smap = 0;

void init_paging() {
    pae_t* pdpt = GLOBAL_PDPT;
    pae_t* pd   = GLOBAL_PD;
    pae_t* pt0  = GLOBAL_PT0;
    pae_t* pt1  = GLOBAL_PT1;

    // Проверяем поддержку NX через CPUID.80000001H:EDX[20]
    unsigned int max_ext = 0, edx_ext = 0;
    __asm__ volatile("cpuid" : "=a"(max_ext) : "a"(0x80000000u) : "ebx", "ecx", "edx");
    if (max_ext >= 0x80000001u)
        __asm__ volatile("cpuid" : "=d"(edx_ext) : "a"(0x80000001u) : "ebx", "ecx");
    g_nx = (edx_ext >> 20) & 1;

    // Проверяем поддержку SMEP через CPUID.07H:EBX[7]
    unsigned int max_basic = 0, ebx7 = 0;
    __asm__ volatile("cpuid" : "=a"(max_basic) : "a"(0u) : "ebx", "ecx", "edx");
    if (max_basic >= 7u) {
        unsigned int eax7, ecx7, edx7;
        __asm__ volatile("cpuid"
            : "=a"(eax7), "=b"(ebx7), "=c"(ecx7), "=d"(edx7)
            : "a"(7u), "c"(0u));
        g_smep = (ebx7 >> 7) & 1;
        g_smap = (ebx7 >> 20) & 1;
    }

    unsigned int text_end = (unsigned int)_text_end & ~(PAGE_SIZE - 1u);

    // PT0: identity-map VA 0x000000-0x1FFFFF (512 страниц × 4КБ).
    // Ядро (.text, .data, .bss): без PAE_USER — ring3 не видит ядро, а при
    // SMEP ядро не может исполнять страницы с PAE_USER (= страницы юзера).
    // Окно пользователя [USER_WINDOW_BASE, +SIZE): PAE_USER сохраняем — туда
    // маппятся слоты программ; SMEP сработает, если ядро попробует туда прыгнуть.
    for (unsigned int i = 0; i < 512; i++) {
        unsigned int addr = i * PAGE_SIZE;
        pae_t flags = PAE_P;

        int in_user_window = (addr >= USER_WINDOW_BASE &&
                              addr <  USER_WINDOW_BASE + USER_WINDOW_SIZE);
        if (in_user_window) {
            // PAE_USER: ring3 видит окно; SMEP блокирует ядро от прыжка сюда.
            flags |= PAE_USER | PAE_RW;
        } else {
            // Ядровые страницы: без PAE_USER (SMEP), без PAE_XD.
            // PAE_XD не ставим: pe-i386 linker генерирует IAT-стабы за
            // пределами .text — точная граница исполняемого кода неизвестна.
            // NX для юзера обеспечивается per-task PT.
            int is_text = (addr >= 0x1000 && addr + PAGE_SIZE <= text_end);
            if (!is_text) flags |= PAE_RW; // .text = read-only (CR0.WP)
        }

        pt0[i] = (pae_t)addr | flags;
    }

    // Guard page: стек ядра растёт вниз от 0x90000; overflow глубже
    // 16КБ бьёт в 0x8C000 (NOT PRESENT) → #PF → halt.
    pt0[0x8C] = 0;

    // PT1: identity-map VA 0x200000-0x3FFFFF, RW без USER (ядро-only).
    for (unsigned int i = 0; i < 512; i++) {
        unsigned int addr = 0x200000u + i * PAGE_SIZE;
        pt1[i] = (pae_t)addr | PAE_P | PAE_RW;
    }

    // PD: [0] → PT0 (0-2МБ, USER=1 нужен для ring3-walk через pt0), [1] → PT1 (2-4МБ).
    pd[0] = (pae_t)(unsigned int)pt0 | PAE_P | PAE_RW | PAE_USER;
    pd[1] = (pae_t)(unsigned int)pt1 | PAE_P | PAE_RW;
    for (unsigned int i = 2; i < 512; i++) pd[i] = 0;

    // PDPT: [0] → PD (покрывает 0..3ГБ; остальные записи - 0).
    // PDPTE не имеет U/S и R/W битов, только P=1.
    pdpt[0] = (pae_t)(unsigned int)pd | PAE_P;
    pdpt[1] = pdpt[2] = pdpt[3] = 0;

    // CR4: бит 5 = PAE (обязателен для PAE-страниц и NX).
    //      бит 20 = SMEP: запрещает ring0 исполнять страницы с PAE_USER=1
    //      (= страницы пользователя). Защита от jump-to-user атак на ядро.
    unsigned int cr4_set = 0x20u;
    if (g_smep) cr4_set |= 0x100000u; // SMEP: CR4[20]
    if (g_smap) cr4_set |= 0x200000u; // SMAP: CR4[21]
    __asm__ volatile(
        "mov %%cr4, %%eax\n"
        "or %0, %%eax\n"
        "mov %%eax, %%cr4\n"
        :: "r"(cr4_set) : "eax"
    );
    // После включения SMAP сбрасываем AC, чтобы защита была активна с нуля.
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCA"); // clac

    // Если NX поддерживается: EFER.NXE = 1 (MSR 0xC0000080, бит 11).
    if (g_nx) {
        __asm__ volatile(
            "mov $0xC0000080, %%ecx\n"
            "rdmsr\n"
            "or $0x800, %%eax\n"
            "wrmsr\n"
            ::: "eax", "ecx", "edx"
        );
    }

    // Загружаем CR3 (адрес PDPT), включаем PG (бит 31) + WP (бит 16).
    __asm__ volatile(
        "mov %0, %%cr3\n"
        "mov %%cr0, %%eax\n"
        "or $0x80010000, %%eax\n"
        "mov %%eax, %%cr0\n"
        :: "r"((unsigned int)pdpt) : "eax"
    );

    print_string("[paging] NX=");
    print_string(g_nx   ? "on" : "off");
    print_string(" SMEP=");
    print_string(g_smep ? "on" : "off");
    print_string(" SMAP=");
    print_string(g_smap ? "on" : "off");
    print_string("\n");
}

void smap_allow(void) {
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCB"); // stac: AC=1, ring0 может читать user-страницы
}

void smap_deny(void) {
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCA"); // clac: AC=0, SMAP снова активна
}


unsigned int paging_create_user_directory(int user_slot_index,
                                           unsigned int phys_slot_base,
                                           unsigned int wx_delta,
                                           unsigned int wx_data_off) {
    // Per-task pool (slot = 0..3):
    //   PDPT: PDPT_POOL_BASE + slot*32  (32Б, выровнено на 32Б)
    //   PD:   PD_POOL_BASE   + slot*4КБ (4КБ, выровнено на 4КБ)
    //   PT:   PT_POOL_BASE   + slot*4КБ (512 × 8Б)
    pae_t* dst_pdpt = (pae_t*)(PDPT_POOL_BASE + (unsigned int)user_slot_index * 32u);
    pae_t* dst_pd   = (pae_t*)(PD_POOL_BASE   + (unsigned int)user_slot_index * PAGE_SIZE);
    pae_t* dst_pt   = (pae_t*)(PT_POOL_BASE   + (unsigned int)user_slot_index * PAGE_SIZE);

    // Копируем глобальную PT0 в dst_pt, сбрасывая USER (кольцо 3 по
    // умолчанию не видит ничего ядра).
    pae_t* src_pt = GLOBAL_PT0;
    for (unsigned int i = 0; i < 512; i++)
        dst_pt[i] = src_pt[i] & ~PAE_USER;

    // Окно [USER_WINDOW_BASE, +USER_WINDOW_SIZE): 16 страниц пользователя.
    // W^X: data_start = wx_delta + wx_data_off - байт в слоте, с которого
    // начинаются writable данные (.bss и выше).
    unsigned int first_page = USER_WINDOW_BASE / PAGE_SIZE; // = 256
    unsigned int data_start = wx_delta + wx_data_off;
    int has_boundary = (wx_data_off > 0);

    for (unsigned int i = 0; i < USER_WINDOW_PAGES; i++) {
        unsigned int phys = phys_slot_base + i * PAGE_SIZE;
        pae_t entry = (pae_t)phys | PAE_P | PAE_USER;

        int is_spin = (i == USER_WINDOW_PAGES - 1u);

        if (!has_boundary || is_spin) {
            // Нет границы W^X или spin-страница: RW (исполняемо).
            entry |= PAE_RW;
        } else {
            // Slot byte range этой страницы: [i*0x1000 .. i*0x1000+0xFFF]
            unsigned int byte_end = i * PAGE_SIZE + PAGE_SIZE - 1u;
            if (byte_end < data_start) {
                // Страница целиком до data_start → код: R+X (без записи)
                // PAE_RW не устанавливаем → write-protected всегда
            } else {
                // Страница содержит данные → данные: RW + (NX если ЦП поддерживает)
                entry |= PAE_RW;
                if (g_nx) entry |= PAE_XD;
            }
        }

        dst_pt[first_page + i] = entry;
    }

    // PD: [0] → dst_pt (0-2МБ, с USER; пользователь видит только своё окно),
    //     [1] → глобальная PT1 без USER (2-4МБ: ядро-only).
    pae_t* src_pd = GLOBAL_PD;
    for (unsigned int i = 0; i < 512; i++)
        dst_pd[i] = src_pd[i];
    dst_pd[0] = (pae_t)(unsigned int)dst_pt | PAE_P | PAE_RW | PAE_USER;
    dst_pd[1] = src_pd[1] & ~PAE_USER;  // 2-4МБ: ядро-only

    // PDPT: [0] → dst_pd, остальные 0.
    dst_pdpt[0] = (pae_t)(unsigned int)dst_pd | PAE_P;
    dst_pdpt[1] = dst_pdpt[2] = dst_pdpt[3] = 0;

    return (unsigned int)dst_pdpt;
}

static void print_hex(unsigned int val) {
    char hex_digits[] = "0123456789ABCDEF";
    char buf[9]; buf[8] = '\0';
    for (int i = 7; i >= 0; i--) { buf[i] = hex_digits[val & 0xF]; val >>= 4; }
    print_string(buf);
}

#define PF_FRAME_ERR 8   // код ошибки CPU (P/W/U/I bits)
#define PF_FRAME_EIP 9
#define PF_FRAME_CS  10

void page_fault_handler_main(unsigned int faulting_address, unsigned int* frame) {
    unsigned int cs = frame[PF_FRAME_CS];

    if ((cs & 3) == 3 && task_current_is_isolated()) {
        unsigned int err = frame[PF_FRAME_ERR];
        print_string("\n\033[33m*** PAGE FAULT in '");
        print_string(task_current_name());
        print_string("' at 0x");
        print_hex(faulting_address);
        if (err & (1u << 4))
            print_string(" [NX execute violation]");
        else if (err & (1u << 1))
            print_string(" [W^X write violation]");
        print_string(" - task killed ***\033[0m\n");
        task_mark_current_exiting();
        frame[PF_FRAME_EIP] = USER_SPIN_ADDR;
        return;
    }

    unsigned int eip = frame[PF_FRAME_EIP];
    unsigned int err2 = frame[PF_FRAME_ERR];
    // Бит 4 (I/D) + ring0 (U/S=0) = instruction fetch в ядре.
    // Причина: NX на странице ядра (баг в paging) ИЛИ SMEP (ядро прыгнуло
    // на страницу юзера). Различить без walk-PT-таблицы невозможно.
    int is_kernel_exec_fault = (err2 & (1u << 4)) && !(err2 & (1u << 2));
    // SMAP: P=1, U/S=0 (ring0), I/D=0 (data access), адрес в окне юзера.
    // SMAP-фолт = ядро обратилось к user-странице без stac (AC=0).
    int is_smap_fault = (err2 & 1u) && !(err2 & (1u << 2)) && !(err2 & (1u << 4))
                     && (faulting_address >= USER_WINDOW_BASE)
                     && (faulting_address <  USER_WINDOW_BASE + USER_WINDOW_SIZE);
    if (is_kernel_exec_fault) {
        print_string("\n\033[41;37m[SMEP/NX] kernel exec fault addr=0x");
        print_hex(faulting_address);
        print_string(" eip=0x");
        print_hex(eip);
        print_string("\033[0m\n");
    } else if (is_smap_fault) {
        print_string("\n\033[41;37m[SMAP] kernel data access to user page addr=0x");
        print_hex(faulting_address);
        print_string(" eip=0x");
        print_hex(eip);
        print_string(" (missing stac?)\033[0m\n");
    } else {
        print_string("\n\033[31m*** PAGE FAULT at 0x");
        print_hex(faulting_address);
        print_string(" from EIP=0x");
        print_hex(eip);
        print_string(" cs=0x");
        print_hex(cs);
        print_string(" ***\033[0m\n");
    }
    print_string("System halted.\n");
    while (1) { __asm__("hlt"); }
}
