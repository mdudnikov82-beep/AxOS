#pragma once

// sv39: 39-битное виртуальное адресное пространство, 3 уровня таблиц страниц.
// VA[38:30] = VPN[2]  →  индекс в корневой (L2) таблице (512 записей)
// VA[29:21] = VPN[1]  →  индекс в L1-таблице
// VA[20:12] = VPN[0]  →  индекс в L0-таблице
// VA[11:0]  = смещение внутри 4KB страницы
//
// Запись PTE (64-bit):
//  [63:54] зарезервировано
//  [53:10] PPN — физический номер страницы (44 бита)
//  [ 9: 8] RSW  — для ОС
//  [    7] D    — Dirty (запись)
//  [    6] A    — Accessed (чтение/запись/fetch)
//  [    5] G    — Global (пропускает ASID-сравнение)
//  [    4] U    — User (доступно из U-mode)
//  [    3] X    — Execute
//  [    2] W    — Write
//  [    1] R    — Read
//  [    0] V    — Valid
//
// Лист (leaf PTE): R|W|X != 0  →  адресует физическую страницу/мегастр/гигастр.
// Ветка (branch PTE): R=W=X=0  →  указывает на следующий уровень таблицы.

#define PTE_V   (1UL << 0)
#define PTE_R   (1UL << 1)
#define PTE_W   (1UL << 2)
#define PTE_X   (1UL << 3)
#define PTE_U   (1UL << 4)
#define PTE_G   (1UL << 5)
#define PTE_A   (1UL << 6)
#define PTE_D   (1UL << 7)

// Удобная маска: «ядерная» страница R+W+X, помечена A+D (чтобы не ловить fault)
#define PTE_KERN_RWX  (PTE_V | PTE_R | PTE_W | PTE_X | PTE_G | PTE_A | PTE_D)
#define PTE_KERN_RW   (PTE_V | PTE_R | PTE_W         | PTE_G | PTE_A | PTE_D)
#define PTE_KERN_RX   (PTE_V | PTE_R |         PTE_X | PTE_G | PTE_A | PTE_D)
#define PTE_KERN_R    (PTE_V | PTE_R                 | PTE_G | PTE_A | PTE_D)

// Формирует поле PPN в PTE из физического адреса
#define PA_TO_PPN(pa)     ((pa) >> 12)
#define PTE_FROM_PA(pa, flags)  ((PA_TO_PPN(pa) << 10) | (flags))

// SATP: режим sv39 = 8 в битах [63:60], PPN корневой таблицы в [43:0]
#define SATP_SV39         (8UL << 60)
#define MAKE_SATP(root_pa) (SATP_SV39 | ((root_pa) >> 12))

#define PAGE_SIZE   4096UL
#define PT_ENTRIES  512         // записей в одной таблице страниц

/* Флаги для пользовательских страниц */
#define PTE_USER_RX   (PTE_V | PTE_R |         PTE_X | PTE_U | PTE_A | PTE_D)
#define PTE_USER_RW   (PTE_V | PTE_R | PTE_W         | PTE_U | PTE_A | PTE_D)
#define PTE_USER_RWX  (PTE_V | PTE_R | PTE_W | PTE_X | PTE_U | PTE_A | PTE_D)

void paging_init(void);

/* Replaces the kernel RAM identity gigapage (root_pt[2]) — set up by
 * paging_init() as one coarse R+W+X mapping just to get through early boot
 * — with a fine-grained W^X layout: kernel .text/.rodata R+X, kernel
 * .data/.bss/stack and the rest of the free-memory pool R+W (never both).
 * Must be called after pmem_init() (needs alloc_page()) and before the
 * first paging_create_user_pt() (which copies root_pt[2] by value). */
void paging_harden_kernel(void);

/* Maps a single 4KB page VA→PA into the kernel root page table.
 * Creates intermediate L1/L0 tables via alloc_page() as needed. */
void map_page_4k(unsigned long va, unsigned long pa, unsigned long flags);

/* Same as map_page_4k but into an arbitrary root page table.
 * Use this for per-process user page tables. */
void map_page_4k_pt(unsigned long *root, unsigned long va,
                    unsigned long pa, unsigned long flags);

/* Allocates a fresh sv39 root page table and copies the two kernel
 * gigapage entries (MMIO L2[0], kernel RAM L2[2]) into it.
 * L2[1] (user VA 0x40000000–0x7FFFFFFF) is left zeroed. */
unsigned long *paging_create_user_pt(void);

/* fork(): walks src_root's user address space (L2[1] - the only root
 * entry elf_loader.c ever populates, always as 4KB L0 leaves, never
 * mega/gigapages) and, for every present page, allocates a fresh
 * physical page, copies its contents, and maps it into dst_root at the
 * SAME virtual address with the SAME PTE flags. dst_root must already
 * exist (see paging_create_user_pt()) with L2[1] still zeroed.
 * Returns 1 on success, 0 on OOM (partially-populated dst_root is left
 * as-is - the bump allocator can't unwind individual pages anyway, and
 * the caller abandons the whole fork attempt on failure). */
int paging_fork_user_pages(unsigned long *src_root, unsigned long *dst_root);
