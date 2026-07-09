#include "elf_loader.h"
#include "paging.h"
#include "pmem.h"
#include "vfs.h"
#include "proc.h"
#include "drivers/uart.h"

/* ---- ELF64 types ---- */
typedef struct {
    unsigned char  e_ident[16];
    unsigned short e_type;
    unsigned short e_machine;
    unsigned int   e_version;
    unsigned long  e_entry;
    unsigned long  e_phoff;
    unsigned long  e_shoff;
    unsigned int   e_flags;
    unsigned short e_ehsize;
    unsigned short e_phentsize;
    unsigned short e_phnum;
    unsigned short e_shentsize;
    unsigned short e_shnum;
    unsigned short e_shstrndx;
} __attribute__((packed)) elf64_hdr_t;

typedef struct {
    unsigned int   p_type;
    unsigned int   p_flags;
    unsigned long  p_offset;
    unsigned long  p_vaddr;
    unsigned long  p_paddr;
    unsigned long  p_filesz;
    unsigned long  p_memsz;
    unsigned long  p_align;
} __attribute__((packed)) elf64_phdr_t;

#define ET_EXEC    2
#define EM_RISCV   0xF3
#define PT_LOAD    1
#define ELFCLASS64 2

static void put_hex32(unsigned long v) {
    for (int s = 28; s >= 0; s -= 4)
        uart_putc("0123456789abcdef"[(v >> s) & 0xF]);
}
static void put_udec(unsigned long v) {
    char b[20]; int i = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { b[i++] = '0' + (v % 10); v /= 10; }
    for (int j = i-1; j >= 0; j--) uart_putc(b[j]);
}
static void memcpy_s(unsigned char *d, const unsigned char *s, unsigned long n) {
    for (unsigned long i = 0; i < n; i++) d[i] = s[i];
}

/* ASLR: случайная 4КБ-выровненная страница стека внутри
 * [USER_HEAP_CEILING, USER_VA_TOP) - см. подробный комментарий у
 * USER_HEAP_CEILING в elf_loader.h. Тот же `time` CSR, что и в heap.c
 * (тег-PRNG) и kernel_main.c (сдвиг pmem-старта) - единственный
 * доступный источник энтропии на этом этапе, без риска, что несёт
 * развязка VA/PA (см. комментарий в kernel_main.c за подробностями). */
static unsigned long pick_stack_va(void) {
    unsigned long t;
    __asm__ volatile("csrr %0, time" : "=r"(t));
    unsigned long seed = t ^ 0xC2B2AE3D27D4EB4FUL;
    unsigned long span_pages = (USER_VA_TOP - USER_HEAP_CEILING) / PAGE_SIZE - 1;
    unsigned long page_off = seed % span_pages;
    return USER_HEAP_CEILING + page_off * PAGE_SIZE;
}

/* Allocates n contiguous pages from the bump allocator. */
static void *alloc_pages_raw(unsigned int n) {
    void *first = alloc_page();
    if (!first) return 0;
    for (unsigned int i = 1; i < n; i++) {
        if (!alloc_page()) return 0;
    }
    return first;
}

/* Load ELF from FAT12, map into a fresh per-process page table,
 * create a PCB entry.  Returns pid (≥0) or -1 on error.
 * Does NOT jump to U-mode; caller is responsible for that. */
int elf_load(const char *filename) {
    /* Read ELF file into a temporary buffer (up to 256 KB). */
    unsigned int maxsz  = 256 * 1024;
    unsigned char *buf  = (unsigned char *)alloc_pages_raw(maxsz / PAGE_SIZE);
    if (!buf) { uart_puts("[elf] OOM for file buffer\r\n"); return -1; }

    unsigned int sz = vfs_load((char *)filename, buf, maxsz);
    if (sz < sizeof(elf64_hdr_t)) {
        uart_puts("[elf] file not found or too small\r\n"); return -1;
    }

    elf64_hdr_t *hdr = (elf64_hdr_t *)buf;

    if (hdr->e_ident[0] != 0x7F || hdr->e_ident[1] != 'E' ||
        hdr->e_ident[2] != 'L'  || hdr->e_ident[3] != 'F') {
        uart_puts("[elf] bad magic\r\n"); return -1;
    }
    if (hdr->e_ident[4] != ELFCLASS64) {
        uart_puts("[elf] not ELF64\r\n"); return -1;
    }
    if (hdr->e_machine != EM_RISCV) {
        uart_puts("[elf] not RISC-V (machine=0x");
        put_hex32(hdr->e_machine); uart_puts(")\r\n"); return -1;
    }
    if (hdr->e_type != ET_EXEC) {
        uart_puts("[elf] not ET_EXEC\r\n"); return -1;
    }

    /* Create a fresh page table for this process.
     * Kernel entries (MMIO L2[0], RAM L2[2]) are pre-filled;
     * user space L2[1] starts empty. */
    unsigned long *pt = paging_create_user_pt();
    if (!pt) { uart_puts("[elf] OOM for page table\r\n"); return -1; }

    uart_puts("[elf] loading ");
    uart_puts(filename);
    uart_puts(", entry=0x");
    put_hex32(hdr->e_entry);
    uart_puts(", phnum=");
    put_udec(hdr->e_phnum);
    uart_puts("\r\n");

    /* Map PT_LOAD segments into the new page table.
     * heap_end tracks the highest byte used by any segment — the heap
     * starts on the next page boundary above it. */
    unsigned long heap_end = 0;
    for (int i = 0; i < hdr->e_phnum; i++) {
        elf64_phdr_t *ph = (elf64_phdr_t *)(buf + hdr->e_phoff
                           + (unsigned long)i * hdr->e_phentsize);
        if (ph->p_type != PT_LOAD || !ph->p_memsz) continue;

        unsigned long vaddr  = ph->p_vaddr;
        unsigned long filesz = ph->p_filesz;
        unsigned long memsz  = ph->p_memsz;
        unsigned long foff   = ph->p_offset;
        unsigned int  pflags = ph->p_flags;

        unsigned long pte_flags = PTE_V | PTE_U | PTE_A | PTE_D;
        if (pflags & 4) pte_flags |= PTE_R;
        if (pflags & 2) pte_flags |= PTE_W;
        if (pflags & 1) pte_flags |= PTE_X;

        /* Reject any segment outside the user VA window. Without this,
         * a crafted ELF (planted via SYS_WRITEFILE and exec()'d) could
         * point a PT_LOAD segment at kernel RAM or MMIO — map_page_4k_pt
         * would walk into the LIVE page-table sub-tree that
         * paging_create_user_pt() shares (by value) across every
         * process, letting a user-writable+executable mapping get
         * planted into the kernel's own, other processes' page tables. */
        if (vaddr < USER_VA_BASE || vaddr >= USER_VA_TOP || memsz > USER_VA_TOP - vaddr) {
            uart_puts("[elf] segment vaddr outside user VA range, rejected\r\n");
            return -1;
        }

        unsigned long npages = (memsz + PAGE_SIZE - 1) / PAGE_SIZE;

        uart_puts("[elf]  seg vaddr=0x");
        put_hex32(vaddr);
        uart_puts(" memsz=");
        put_udec(memsz);
        uart_puts(" flags=");
        if (pflags & 4) uart_putc('R');
        if (pflags & 2) uart_putc('W');
        if (pflags & 1) uart_putc('X');
        uart_puts("\r\n");

        for (unsigned long p = 0; p < npages; p++) {
            void *phys = alloc_page();
            if (!phys) { uart_puts("[elf] OOM for segment\r\n"); return -1; }

            unsigned long off = p * PAGE_SIZE;
            if (off < filesz) {
                unsigned long copy_sz = filesz - off;
                if (copy_sz > PAGE_SIZE) copy_sz = PAGE_SIZE;
                memcpy_s((unsigned char *)phys, buf + foff + off, copy_sz);
            }

            map_page_4k_pt(pt, vaddr + off, (unsigned long)phys, pte_flags);
        }

        unsigned long seg_end = vaddr + memsz;
        if (seg_end > heap_end) heap_end = seg_end;
    }

    /* User stack: one page, случайный адрес (ASLR) внутри
     * [USER_HEAP_CEILING, USER_VA_TOP) - см. pick_stack_va(). */
    unsigned long stack_va = pick_stack_va();
    void *stack_phys = alloc_page();
    if (!stack_phys) { uart_puts("[elf] OOM for stack\r\n"); return -1; }
    map_page_4k_pt(pt, stack_va, (unsigned long)stack_phys,
                   PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D);

    unsigned long entry = hdr->e_entry;
    unsigned long usp   = stack_va + PAGE_SIZE - 16;

    /* Derive a short process name from the filename (strip extension). */
    char name[13]; int ni = 0;
    while (ni < 12 && filename[ni] && filename[ni] != '.') {
        name[ni] = filename[ni]; ni++;
    }
    name[ni] = '\0';

    int pid = proc_create(name, entry, pt, usp);
    if (pid < 0) { uart_puts("[elf] no free process slot\r\n"); return -1; }

    procs[pid].stack_va = stack_va;

    /* Heap starts on the page right after the highest loaded segment,
     * plus небольшой случайный сдвиг (ASLR, тот же приём, что и у x86
     * heap-slide в kernel.c) - до 64 страниц (256КБ), пока не вылезаем
     * за USER_HEAP_CEILING (иначе просто не сдвигаем - лучше без ASLR,
     * чем упереться в потолок у крошечных программ). */
    unsigned long brk0 = (heap_end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    unsigned long t2;
    __asm__ volatile("csrr %0, time" : "=r"(t2));
    unsigned long slide = ((t2 ^ 0x9E3779B97F4A7C15UL) % 64UL) * PAGE_SIZE;
    if (brk0 + slide < USER_HEAP_CEILING) brk0 += slide;
    procs[pid].heap_brk = brk0;

    uart_puts("[elf] process pid=");
    put_udec((unsigned long)pid);
    uart_puts(" name=");
    uart_puts(name);
    uart_puts("\r\n");

    return pid;
}

/* First-process launch: sets up sscratch + sstatus and does sret.
 * Never returns.  Caller must have already switched satp. */
void jump_to_umode(unsigned long entry, unsigned long usp) {
    extern char _stack_top[];
    __asm__ volatile("csrw sscratch, %0" :: "r"(_stack_top));
    __asm__ volatile("csrw sepc, %0"    :: "r"(entry));

    unsigned long sstatus;
    __asm__ volatile("csrr %0, sstatus" : "=r"(sstatus));
    sstatus &= ~(1UL << 8);   /* SPP=0  → return to U-mode */
    sstatus |=  (1UL << 5);   /* SPIE=1 → enable interrupts in U-mode */
    __asm__ volatile("csrw sstatus, %0" :: "r"(sstatus));

    __asm__ volatile("mv sp, %0\n sret\n" :: "r"(usp) : "memory");
    __builtin_unreachable();
}
