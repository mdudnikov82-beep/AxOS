#include "paging.h"
#include "pmem.h"
#include "drivers/uart.h"

// Корневая таблица sv39 (L2) — 512 × 8 байт = 4096 байт = 1 страница.
// static → попадёт в BSS (обнулена в entry.S до вызова kernel_main).
static unsigned long root_pt[PT_ENTRIES] __attribute__((aligned(PAGE_SIZE)));

// Вспомогательная функция: создаём гигастраницу 1GB в L2-таблице.
// VA и PA должны быть выровнены на 1GB (биты [29:0] == 0).
// При VA == PA получается identity mapping — удобно для ядра.
static void map_gigapage(unsigned long va, unsigned long pa, unsigned long flags) {
    unsigned long vpn2 = (va >> 30) & 0x1FF;   // биты VA[38:30]
    root_pt[vpn2] = PTE_FROM_PA(pa, flags);
}

void paging_init(void) {
    uart_puts("[paging] setting up sv39 page tables...\r\n");

    // --- Регион 0x00000000 – 0x3FFFFFFF (1 GB) ---
    // Покрывает UART (0x10000000) и другие MMIO устройств QEMU virt.
    // R+W: нет исполнения из устройств; A+D предотвращают access fault.
    map_gigapage(0x00000000UL, 0x00000000UL, PTE_KERN_RW);

    // --- Регион 0x80000000 – 0xBFFFFFFF (1 GB) ---
    // Покрывает OpenSBI (0x80000000), AxOS kernel (0x80200000) и всю RAM.
    // R+W+X: код ядра должен быть исполняемым.
    // (Позже разделим на R+X для .text и R+W для .data/BSS/heap.)
    map_gigapage(0x80000000UL, 0x80000000UL, PTE_KERN_RWX);

    // Печатаем адрес корневой таблицы для верификации
    uart_puts("[paging] root_pt PA = 0x");
    unsigned long pa = (unsigned long)root_pt;
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(pa >> s) & 0xF]);
    uart_puts("\r\n");
    uart_puts("[paging] root_pt[0] = 0x");
    unsigned long pte0 = root_pt[0];
    for (int s = 60; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(pte0 >> s) & 0xF]);
    uart_puts("\r\n");
    uart_puts("[paging] root_pt[2] = 0x");
    unsigned long pte2 = root_pt[2];
    for (int s = 60; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(pte2 >> s) & 0xF]);
    uart_puts("\r\n");

    // --- Включаем sv39 ---
    // После csrw satp:
    //   • все последующие адреса (включая fetch PC) проходят через MMU
    //   • identity mapping гарантирует VA=PA → продолжение работы без сбоев
    unsigned long satp = MAKE_SATP((unsigned long)root_pt);

    uart_puts("[paging] enabling sv39, satp = 0x");
    for (int s = 60; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(satp >> s) & 0xF]);
    uart_puts("\r\n");

    __asm__ volatile(
        "sfence.vma\n"          // сбрасываем TLB перед включением
        "csrw satp, %0\n"       // включаем sv39
        "sfence.vma\n"          // сбрасываем TLB после
        :: "r"(satp) : "memory"
    );

    uart_puts("[paging] sv39 enabled! Virtual memory is ON.\r\n");

    /* sstatus.SUM is intentionally left OFF here (SMAP-equivalent hardening).
     * It's toggled on only for the duration of syscall_dispatch() — see
     * user_access_enable()/user_access_disable() in syscall.c — so a stray
     * kernel dereference of a user pointer outside that window (e.g. in the
     * timer ISR or a fault handler) still page-faults instead of silently
     * succeeding. */
}

void map_page_4k_pt(unsigned long *root, unsigned long va,
                    unsigned long pa, unsigned long flags) {
    unsigned long l2_idx = (va >> 30) & 0x1FF;
    unsigned long l1_idx = (va >> 21) & 0x1FF;
    unsigned long l0_idx = (va >> 12) & 0x1FF;

    /* L2 → L1 */
    unsigned long *l1_pt;
    unsigned long l2e = root[l2_idx];

    if (!(l2e & PTE_V)) {
        l1_pt = (unsigned long *)alloc_page();
        root[l2_idx] = PTE_FROM_PA((unsigned long)l1_pt, PTE_V);
    } else if (l2e & (PTE_R | PTE_W | PTE_X)) {
        uart_puts("[paging] map_page_4k_pt: gigapage exists, can't subdivide\r\n");
        return;
    } else {
        l1_pt = (unsigned long *)(((l2e >> 10) << 12));
    }

    /* L1 → L0 */
    unsigned long *l0_pt;
    unsigned long l1e = l1_pt[l1_idx];

    if (!(l1e & PTE_V)) {
        l0_pt = (unsigned long *)alloc_page();
        l1_pt[l1_idx] = PTE_FROM_PA((unsigned long)l0_pt, PTE_V);
    } else if (l1e & (PTE_R | PTE_W | PTE_X)) {
        uart_puts("[paging] map_page_4k_pt: megapage exists, can't subdivide\r\n");
        return;
    } else {
        l0_pt = (unsigned long *)(((l1e >> 10) << 12));
    }

    l0_pt[l0_idx] = PTE_FROM_PA(pa, flags);
    __asm__ volatile("sfence.vma zero, zero" ::: "memory");
}

void map_page_4k(unsigned long va, unsigned long pa, unsigned long flags) {
    map_page_4k_pt(root_pt, va, pa, flags);
}

/* Maps a single 2MB megapage (sv39 L1 leaf) into an arbitrary root table.
 * VA and PA must be 2MB-aligned. Same branch-allocation logic as
 * map_page_4k_pt, one level up. */
static void map_megapage_2m(unsigned long *root, unsigned long va,
                            unsigned long pa, unsigned long flags) {
    unsigned long l2_idx = (va >> 30) & 0x1FF;
    unsigned long l1_idx = (va >> 21) & 0x1FF;

    unsigned long *l1_pt;
    unsigned long l2e = root[l2_idx];

    if (!(l2e & PTE_V)) {
        l1_pt = (unsigned long *)alloc_page();
        root[l2_idx] = PTE_FROM_PA((unsigned long)l1_pt, PTE_V);
    } else if (l2e & (PTE_R | PTE_W | PTE_X)) {
        uart_puts("[paging] map_megapage_2m: gigapage exists, can't subdivide\r\n");
        return;
    } else {
        l1_pt = (unsigned long *)(((l2e >> 10) << 12));
    }

    l1_pt[l1_idx] = PTE_FROM_PA(pa, flags);
    __asm__ volatile("sfence.vma zero, zero" ::: "memory");
}

void paging_harden_kernel(void) {
    extern char _rx_end[], _kernel_end[];
    unsigned long krx_end    = (unsigned long)_rx_end;
    unsigned long kend       = (unsigned long)_kernel_end;
    unsigned long mega_start = (kend + 0x1FFFFFUL) & ~0x1FFFFFUL;   /* next 2MB */
    unsigned long mem_end    = 0x88000000UL;  /* must match kernel_main.c's pmem_init() call */

    uart_puts("[paging] hardening kernel W^X...\r\n");

    /* Build the new L2[2] sub-tree in a SCRATCH root first. We are
     * currently executing code that lives inside the very range being
     * remapped — root_pt[2] itself must stay a valid (coarse) mapping
     * until the new sub-tree is fully populated, otherwise the moment a
     * partially-built table gets installed, the next instruction fetch
     * for our own PC could fail to translate and fault mid-flight. */
    unsigned long *scratch_root = (unsigned long *)alloc_page();
    if (!scratch_root) { uart_puts("[paging] OOM building W^X tables\r\n"); return; }

    /* OpenSBI (M-mode firmware, 0x80000000-0x80200000, exactly 2MB): the
     * kernel's S-mode code never executes or writes it directly (M-mode
     * does its own physical-address instruction fetch, independent of
     * satp) — read-only is enough. */
    map_megapage_2m(scratch_root, 0x80000000UL, 0x80000000UL, PTE_KERN_R);

    /* Kernel .text + .rodata: R+X, no W. */
    for (unsigned long va = 0x80200000UL; va < krx_end; va += PAGE_SIZE)
        map_page_4k_pt(scratch_root, va, va, PTE_KERN_RX);

    /* Kernel .data + .bss + stack, plus whatever of the free-memory pool
     * falls before the next 2MB boundary: R+W, no X. */
    for (unsigned long va = krx_end; va < mega_start; va += PAGE_SIZE)
        map_page_4k_pt(scratch_root, va, va, PTE_KERN_RW);

    /* Bulk of the free-memory pool (heap, page tables, user process
     * backing pages): R+W, no X, via 2MB megapages. */
    for (unsigned long va = mega_start; va < mem_end; va += 0x200000UL)
        map_megapage_2m(scratch_root, va, va, PTE_KERN_RW);

    /* Atomic hot-swap: root_pt[2] flips from the old 1GB R+W+X gigapage to
     * the branch above in one store. The new sub-tree already has a valid
     * R+X entry covering our own currently-executing code page, so the
     * very next instruction after sfence.vma still translates. */
    root_pt[2] = scratch_root[2];
    __asm__ volatile("sfence.vma zero, zero" ::: "memory");

    uart_puts("[paging] kernel W^X active.\r\n");
}

unsigned long *paging_create_user_pt(void) {
    unsigned long *pt = (unsigned long *)alloc_page();  /* zeroed by alloc_page */
    if (!pt) return 0;
    pt[0] = root_pt[0];  /* MMIO gigapage (0x00000000–0x3FFFFFFF) */
    pt[2] = root_pt[2];  /* kernel RAM gigapage (0x80000000–0xBFFFFFFF) */
    /* pt[1] = 0: user space (0x40000000–0x7FFFFFFF) filled by ELF loader */
    return pt;
}
