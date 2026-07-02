// =================================================================
//  Paging: 4-level (PML4) + W^X (Write XOR Execute)
// =================================================================
//
// boot.asm устанавливает временные 2МБ huge pages (PML4→PDPT→PD).
// init_paging() заменяет PD[0] (huge page) на PT0 (4КБ-страницы),
// настраивает NX/SMEP/SMAP и включает WP в CR0.
//
// Структура (после init_paging):
//   CR3 → PML4 (0x9C000) → PDPT (0x9D000) → PD (0x9E000)
//   PD[0] → PT0 (0x9F000): 4КБ-страницы VA 0..2МБ
//   PD[1] = 2МБ huge page: VA 2..4МБ (ядро-only)
//
// W^X: бит 63 PTE = XD (Execute-Disable) при EFER.NXE=1.

#include "paging.h"
#include "tasking.h"

#define PAE_P    (1ULL)
#define PAE_RW   (1ULL << 1)
#define PAE_USER (1ULL << 2)
#define PAE_PS   (1ULL << 7)   // Page Size (1 = 2МБ/1ГБ huge page)
#define PAE_XD   (1ULL << 63)  // Execute-Disable (NX)

#define PAGE_SIZE 0x1000u

typedef unsigned long long pae_t;

extern void print_string(char* str);
extern char _text_end[];

static int g_nx   = 0;
static int g_smep = 0;
static int g_smap = 0;

void init_paging() {
    pae_t* pml4 = GLOBAL_PML4;
    pae_t* pdpt = GLOBAL_PDPT;
    pae_t* pd   = GLOBAL_PD;
    pae_t* pt0  = GLOBAL_PT0;

    // Проверяем поддержку NX через CPUID.80000001H:EDX[20].
    unsigned int max_ext = 0, edx_ext = 0;
    __asm__ volatile("cpuid" : "=a"(max_ext) : "a"(0x80000000u) : "ebx", "ecx", "edx");
    if (max_ext >= 0x80000001u)
        __asm__ volatile("cpuid" : "=d"(edx_ext) : "a"(0x80000001u) : "ebx", "ecx");
    g_nx = (edx_ext >> 20) & 1;

    // Проверяем поддержку SMEP (CR4[20]) и SMAP (CR4[21]) через CPUID.07H:EBX.
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

    unsigned int text_end = (unsigned int)(unsigned long long)_text_end & ~(PAGE_SIZE - 1u);

    // PT0: 4КБ-страницы для VA 0x000000-0x1FFFFF (512 страниц).
    for (unsigned int i = 0; i < 512; i++) {
        unsigned int addr = i * PAGE_SIZE;
        pae_t flags = PAE_P;

        int in_user_window = (addr >= USER_WINDOW_BASE &&
                              addr <  USER_WINDOW_BASE + USER_WINDOW_SIZE);
        if (in_user_window) {
            flags |= PAE_USER | PAE_RW;
        } else {
            int is_text = (addr >= 0x1000 && addr + PAGE_SIZE <= text_end);
            if (!is_text) flags |= PAE_RW;
        }

        pt0[i] = (pae_t)addr | flags;
    }

    // Guard page: стек ядра растёт вниз от 0x90000; overflow → #PF → halt.
    pt0[0x8C] = 0;

    // PD[0] → PT0 (0-2МБ, USER=1 нужен для ring3 walk к USER_WINDOW).
    // Заменяет boot-huge-page тонкой 4КБ-таблицей.
    pd[0] = (pae_t)pt0 | PAE_P | PAE_RW | PAE_USER;
    // PD[1] = 2МБ huge page для 2-4МБ (ядро-only, без USER).
    pae_t pd1_flags = PAE_P | PAE_RW | PAE_PS;
    if (g_nx) pd1_flags |= PAE_XD;
    pd[1] = 0x200000ULL | pd1_flags;
    for (unsigned int i = 2; i < 512; i++) pd[i] = 0;

    // PDPT и PML4 уже настроены boot.asm; проверяем/обновляем флаги.
    // boot ставил US=1 на оба, что нам и нужно.
    pdpt[0] = (pae_t)pd | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) pdpt[i] = 0;

    pml4[0] = (pae_t)pdpt | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) pml4[i] = 0;

    // CR4: добавляем SMEP (бит 20) и SMAP (бит 21). PAE (бит 5) уже set boot.
    unsigned long long cr4_add = 0;
    if (g_smep) cr4_add |= 0x100000ULL;
    if (g_smap) cr4_add |= 0x200000ULL;
    if (cr4_add) {
        __asm__ volatile(
            "mov %%cr4, %%rax\n"
            "or %0, %%rax\n"
            "mov %%rax, %%cr4\n"
            :: "r"(cr4_add) : "rax"
        );
    }
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCA"); // clac: SMAP активна

    // EFER.NXE (бит 11) — если поддерживается.
    if (g_nx) {
        __asm__ volatile(
            "mov $0xC0000080, %%ecx\n"
            "rdmsr\n"
            "or $0x800, %%eax\n"
            "wrmsr\n"
            ::: "eax", "ecx", "edx"
        );
    }

    // Перезагружаем CR3 (TLB flush) и устанавливаем CR0.WP (бит 16).
    // CR0.PG уже = 1 (boot.asm). WP запрещает ring0 писать в read-only страницы.
    __asm__ volatile(
        "mov %0, %%cr3\n"
        "mov %%cr0, %%rax\n"
        "or $0x10000, %%rax\n"
        "mov %%rax, %%cr0\n"
        :: "r"((unsigned long long)pml4) : "rax"
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
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCB"); // stac
}

void smap_deny(void) {
    if (g_smap) __asm__ volatile(".byte 0x0F,0x01,0xCA"); // clac
}


unsigned long long paging_create_user_directory(int user_slot_index,
                                                 unsigned int phys_slot_base,
                                                 unsigned int wx_delta,
                                                 unsigned int wx_data_off) {
    // Пул: каждый слот (0..3) получает по одной 4КБ-странице на уровень.
    pae_t* dst_pml4 = (pae_t*)(PML4_POOL_BASE + (unsigned int)user_slot_index * PAGE_SIZE);
    pae_t* dst_pdpt = (pae_t*)(PDPT_POOL_BASE + (unsigned int)user_slot_index * PAGE_SIZE);
    pae_t* dst_pd   = (pae_t*)(PD_POOL_BASE   + (unsigned int)user_slot_index * PAGE_SIZE);
    pae_t* dst_pt   = (pae_t*)(PT_POOL_BASE   + (unsigned int)user_slot_index * PAGE_SIZE);

    // Копируем GLOBAL_PT0 в dst_pt, убирая USER (ring3 не видит ядро).
    pae_t* src_pt = GLOBAL_PT0;
    for (unsigned int i = 0; i < 512; i++)
        dst_pt[i] = src_pt[i] & ~PAE_USER;

    // Переотображаем USER_WINDOW на физический слот задачи.
    unsigned int first_page = USER_WINDOW_BASE / PAGE_SIZE; // = 0x100
    unsigned int data_start = wx_delta + wx_data_off;
    int has_boundary = (wx_data_off > 0);

    for (unsigned int i = 0; i < USER_WINDOW_PAGES; i++) {
        unsigned int phys = phys_slot_base + i * PAGE_SIZE;
        pae_t entry = (pae_t)phys | PAE_P | PAE_USER;

        int is_spin = (i == USER_WINDOW_PAGES - 1u);

        if (!has_boundary || is_spin) {
            entry |= PAE_RW;
        } else {
            unsigned int byte_end = i * PAGE_SIZE + PAGE_SIZE - 1u;
            if (byte_end < data_start) {
                // Код: R+X (без PAE_RW)
            } else {
                // Данные: RW + NX
                entry |= PAE_RW;
                if (g_nx) entry |= PAE_XD;
            }
        }

        dst_pt[first_page + i] = entry;
    }

    // dst_pd: [0] → dst_pt (0-2МБ с USER), [1] = 2МБ huge page ядра-only.
    pae_t pd1 = GLOBAL_PD[1] & ~PAE_USER;
    dst_pd[0] = (pae_t)dst_pt | PAE_P | PAE_RW | PAE_USER;
    dst_pd[1] = pd1;
    for (unsigned int i = 2; i < 512; i++) dst_pd[i] = 0;

    // dst_pdpt: [0] → dst_pd.
    dst_pdpt[0] = (pae_t)dst_pd | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) dst_pdpt[i] = 0;

    // dst_pml4: [0] → dst_pdpt.
    dst_pml4[0] = (pae_t)dst_pdpt | PAE_P | PAE_RW | PAE_USER;
    for (unsigned int i = 1; i < 512; i++) dst_pml4[i] = 0;

    return (unsigned long long)dst_pml4;
}

static void print_hex(unsigned int val) {
    char hex_digits[] = "0123456789ABCDEF";
    char buf[9]; buf[8] = '\0';
    for (int i = 7; i >= 0; i--) { buf[i] = hex_digits[val & 0xF]; val >>= 4; }
    print_string(buf);
}

// Индексы в 64-битном кадре исключения #PF.
// Кадр (от RSP = нижнего адреса):
//   [0..14]  = RAX..R15  (15 GPR из SAVE_REGS в idt.asm)
//   [15]     = Error code (CPU-pushed)
//   [16]     = RIP
//   [17]     = CS
//   [18]     = RFLAGS
//   [19]     = RSP_old
//   [20]     = SS
#define PF_FRAME_ERR 15
#define PF_FRAME_RIP 16
#define PF_FRAME_CS  17

void page_fault_handler_main(unsigned long long faulting_address,
                              unsigned long long* frame) {
    unsigned long long cs = frame[PF_FRAME_CS];

    if ((cs & 3) == 3 && task_current_is_isolated()) {
        unsigned long long err = frame[PF_FRAME_ERR];
        print_string("\n\033[33m*** PAGE FAULT in '");
        print_string(task_current_name());
        print_string("' at 0x");
        print_hex((unsigned int)faulting_address);
        if (err & (1ULL << 4))
            print_string(" [NX execute violation]");
        else if (err & (1ULL << 1))
            print_string(" [W^X write violation]");
        print_string(" - task killed ***\033[0m\n");
        task_mark_current_exiting();
        frame[PF_FRAME_RIP] = USER_SPIN_ADDR;
        return;
    }

    unsigned long long rip  = frame[PF_FRAME_RIP];
    unsigned long long err2 = frame[PF_FRAME_ERR];
    int is_kernel_exec_fault = (err2 & (1ULL << 4)) && !(err2 & (1ULL << 2));
    int is_smap_fault = (err2 & 1ULL) && !(err2 & (1ULL << 2)) && !(err2 & (1ULL << 4))
                     && (faulting_address >= USER_WINDOW_BASE)
                     && (faulting_address <  USER_WINDOW_BASE + USER_WINDOW_SIZE);
    if (is_kernel_exec_fault) {
        print_string("\n\033[41;37m[SMEP/NX] kernel exec fault addr=0x");
        print_hex((unsigned int)faulting_address);
        print_string(" rip=0x");
        print_hex((unsigned int)rip);
        print_string("\033[0m\n");
    } else if (is_smap_fault) {
        print_string("\n\033[41;37m[SMAP] kernel data access to user page addr=0x");
        print_hex((unsigned int)faulting_address);
        print_string(" rip=0x");
        print_hex((unsigned int)rip);
        print_string(" (missing stac?)\033[0m\n");
    } else {
        print_string("\n\033[31m*** PAGE FAULT at 0x");
        print_hex((unsigned int)faulting_address);
        print_string(" from RIP=0x");
        print_hex((unsigned int)rip);
        print_string(" cs=0x");
        print_hex((unsigned int)cs);
        print_string(" ***\033[0m\n");
    }
    print_string("System halted.\n");
    while (1) { __asm__("hlt"); }
}
