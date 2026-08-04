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

typedef struct {
    unsigned int   sh_name;
    unsigned int   sh_type;
    unsigned long  sh_flags;
    unsigned long  sh_addr;
    unsigned long  sh_offset;
    unsigned long  sh_size;
    unsigned int   sh_link;
    unsigned int   sh_info;
    unsigned long  sh_addralign;
    unsigned long  sh_entsize;
} __attribute__((packed)) elf64_shdr_t;

typedef struct {
    unsigned long  r_offset;
    unsigned long  r_info;
    long           r_addend;
} __attribute__((packed)) elf64_rela_t;

#define ET_EXEC    2
#define EM_RISCV   0xF3
#define PT_LOAD    1
#define ELFCLASS64 2

#define SHT_RELA   4
#define SHF_ALLOC  0x2UL
#define ELF64_R_TYPE(info) ((unsigned int)((info) & 0xFFFFFFFFUL))

/* Relocation types actually emitted by this repo's toolchain (GCC and
 * rustc, both -mcmodel=medany) under --emit-relocs, confirmed empirically
 * across every shipped rv64 user program (both C and Rust-linked) - see
 * [[project_riscv_code_aslr]] for the readelf -r survey. R_RISCV_64 is
 * the ONLY absolute-address type this codegen produces in a loaded
 * section (literal pointers baked into .data/.rodata, e.g. axtaskb.c's
 * launch_item_t[] table) - everything else below is either PC-relative
 * (needs no fixup under a uniform load-address slide) or pure linker
 * bookkeeping (ADD/SUB/SET delta-pairs and RELAX/ALIGN hints, invariant
 * under a uniform slide by construction). */
#define R_RISCV_NONE          0
#define R_RISCV_64            2
#define R_RISCV_BRANCH        16
#define R_RISCV_JAL           17
#define R_RISCV_CALL          18
#define R_RISCV_CALL_PLT      19
#define R_RISCV_PCREL_HI20    23
#define R_RISCV_PCREL_LO12_I  24
#define R_RISCV_PCREL_LO12_S  25
#define R_RISCV_ADD8          33
#define R_RISCV_ADD16         34
#define R_RISCV_ADD32         35
#define R_RISCV_ADD64         36
#define R_RISCV_SUB8          37
#define R_RISCV_SUB16         38
#define R_RISCV_SUB32         39
#define R_RISCV_SUB64         40
#define R_RISCV_ALIGN         43
#define R_RISCV_RVC_BRANCH    44
#define R_RISCV_RVC_JUMP      45
#define R_RISCV_RELAX         51
#define R_RISCV_SET6          53
#define R_RISCV_SET8          54
#define R_RISCV_SET16         55
#define R_RISCV_SET32         56

/* Anything NOT in this list and not R_RISCV_64 (checked separately) is
 * treated as unrecognized -> fail-closed fallback (see elf_load()):
 * this program simply loads with code_slide=0 instead of risking a
 * silently-wrong pointer from a fixup this loader doesn't understand. */
static int reloc_is_skip_safe(unsigned int type) {
    switch (type) {
        case R_RISCV_NONE:
        case R_RISCV_BRANCH: case R_RISCV_JAL:
        case R_RISCV_CALL: case R_RISCV_CALL_PLT:
        case R_RISCV_PCREL_HI20:
        case R_RISCV_PCREL_LO12_I: case R_RISCV_PCREL_LO12_S:
        case R_RISCV_ADD8: case R_RISCV_ADD16:
        case R_RISCV_ADD32: case R_RISCV_ADD64:
        case R_RISCV_SUB8: case R_RISCV_SUB16:
        case R_RISCV_SUB32: case R_RISCV_SUB64:
        case R_RISCV_ALIGN:
        case R_RISCV_RVC_BRANCH: case R_RISCV_RVC_JUMP:
        case R_RISCV_RELAX:
        case R_RISCV_SET6: case R_RISCV_SET8:
        case R_RISCV_SET16: case R_RISCV_SET32:
            return 1;
        default:
            return 0;
    }
}

#define ELF_ARGS_MAX 15 /* макс. число argv[] - см. запись в USER_ARGS_VA ниже */
#define MAX_LOAD_SEGS 8 /* больше, чем реально бывает PT_LOAD в любой текущей программе (обычно 2) */

/* Записи per-segment таблицы, построенной в Pass 1 - используется Pass 2
 * (relocation fixup) для перевода r_offset (оригинальный, link-time vaddr
 * из ELF) в физический адрес, и Pass 3 для повторного нахождения того же
 * сегмента при маппинге. Внутри одного сегмента физические страницы
 * гарантированно смежны (см. alloc_pages_raw - bump-аллокатор, без
 * чужих alloc_page() между страницами одного сегмента), так что перевод
 * offset->phys - обычная линейная арифметика, без постраничной таблицы. */
typedef struct {
    unsigned long orig_start; /* p_vaddr как в файле, ДО code_slide */
    unsigned long orig_end;   /* orig_start + p_memsz */
    unsigned long phys_base;
} seg_rec_t;

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
    // -1 страница снизу (существующий зазор) - ещё -1 страница, чтобы
    // никогда не попасть на USER_ARGS_VA (фиксированная страница argv
    // на самом верху, см. elf_loader.h) - span считается от
    // USER_ARGS_VA, а не от USER_VA_TOP.
    unsigned long span_pages = (USER_ARGS_VA - USER_HEAP_CEILING) / PAGE_SIZE - 1;
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
int elf_load(const char *cmdline) {
    /* Разбираем "FILENAME.ELF arg1 arg2..." - имя до первого пробела
     * идёт в vfs_load(), остаток запоминаем как есть (без учёта
     * регистра - см. USER_ARGS_VA ниже) для argv[1..] новой задачи. */
    char filename[64]; int fi = 0;
    const char *p = cmdline;
    while (*p && *p != ' ' && fi < 63) filename[fi++] = *p++;
    filename[fi] = '\0';
    while (*p == ' ') p++;
    const char *args_rest = p; /* может быть "" - тогда argc==1 */

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

    /* Program-header table itself must be fully inside the bytes
     * actually read - e_phoff/e_phnum/e_phentsize are attacker-
     * controlled file fields dereferenced by every pass below (Pass 0,
     * 1, 3). Without this check, a crafted ~64-byte file (planted via
     * SYS_WRITEFILE, then exec()'d) could point e_phoff anywhere in the
     * 64-bit space - `buf + e_phoff` would be dereferenced immediately,
     * almost certainly landing in unmapped memory (Sv39 only has 2 of
     * 512 possible L2 windows populated). That fault happens while
     * S-mode is already inside the SYS_EXEC syscall on this process's
     * behalf, which kernel_main.c's trap handler treats as fatal
     * (while(1) wfi) - the same bug class as user_string_ok()'s missing
     * NUL check, just one level deeper. Mirrors the e_shoff/e_shnum/
     * e_shentsize check already done below for the section header
     * table - that exact pattern just wasn't applied here too. */
    if (hdr->e_phnum == 0 || hdr->e_phentsize < sizeof(elf64_phdr_t) ||
        hdr->e_phoff > sz ||
        (unsigned long)hdr->e_phnum * hdr->e_phentsize > sz - hdr->e_phoff) {
        uart_puts("[elf] bad program header table\r\n"); return -1;
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

    /* Pass 0: scan PT_LOAD Phdrs (no allocation yet) to find the code's
     * total original footprint, needed to size the code-ASLR budget
     * before we pick a slide - see USER_HEAP_CEILING comment for why
     * the window is shared with the heap. */
    unsigned long footprint_end = USER_VA_BASE;
    for (int i = 0; i < hdr->e_phnum; i++) {
        elf64_phdr_t *ph = (elf64_phdr_t *)(buf + hdr->e_phoff
                           + (unsigned long)i * hdr->e_phentsize);
        if (ph->p_type != PT_LOAD || !ph->p_memsz) continue;
        unsigned long end = ph->p_vaddr + ph->p_memsz;
        if (end > footprint_end) footprint_end = end;
    }
    unsigned long footprint_size = footprint_end - USER_VA_BASE;

    /* Code-ASLR: случайный page-aligned сдвиг всех PT_LOAD-сегментов и
     * entry (ASLR для КОДА - см. project_riscv_code_aslr в памяти).
     * Бюджет = окно [USER_VA_BASE, USER_HEAP_CEILING) минус реальный
     * footprint минус тот же 64МБ heap-reserve, что и у сдвига кучи
     * ниже (heap растёт от footprint_end, а не от USER_VA_BASE, так что
     * heap-слайд сам адаптируется к сдвинутому коду без правок). */
    unsigned long code_slide = 0;
    {
        unsigned long t0;
        __asm__ volatile("csrr %0, time" : "=r"(t0));
        unsigned long total_window = USER_HEAP_CEILING - USER_VA_BASE;
        unsigned long heap_reserve = 64UL * 1024 * 1024;
        unsigned long budget = 0;
        if (total_window > footprint_size + heap_reserve)
            budget = total_window - footprint_size - heap_reserve;
        unsigned long slide_pages = budget / PAGE_SIZE;
        if (slide_pages > 0) {
            unsigned long seed = t0 ^ 0xD1B54A32D192ED03UL;
            code_slide = (seed % slide_pages) * PAGE_SIZE;
        }
    }

    /* Pass 1: allocate + copy every PT_LOAD segment at (original vaddr +
     * code_slide), building segs[] so Pass 2 can translate a
     * relocation's r_offset (an ORIGINAL, unslid vaddr - link-time
     * addresses baked into the ELF) to the physical page that now holds
     * it. No map_page_4k_pt yet - relocation fixups must land before
     * any of this becomes user-visible (though in practice the kernel
     * could write to it either way, since RAM is identity-mapped). */
    seg_rec_t segs[MAX_LOAD_SEGS];
    int nsegs = 0;
    for (int i = 0; i < hdr->e_phnum; i++) {
        elf64_phdr_t *ph = (elf64_phdr_t *)(buf + hdr->e_phoff
                           + (unsigned long)i * hdr->e_phentsize);
        if (ph->p_type != PT_LOAD || !ph->p_memsz) continue;

        unsigned long orig_vaddr = ph->p_vaddr;
        unsigned long vaddr      = orig_vaddr + code_slide;
        unsigned long filesz     = ph->p_filesz;
        unsigned long memsz      = ph->p_memsz;
        unsigned long foff       = ph->p_offset;

        /* Reject any segment outside the user code/heap window. Without
         * this, a crafted ELF (planted via SYS_WRITEFILE and exec()'d)
         * could point a PT_LOAD segment at kernel RAM, MMIO, or the
         * stack/argv/heap region above USER_HEAP_CEILING - map_page_4k_pt
         * would walk into the LIVE page-table sub-tree that
         * paging_create_user_pt() shares (by value) across every
         * process, letting a user-writable+executable mapping get
         * planted into the kernel's own, other processes' page tables.
         * Bounded by USER_HEAP_CEILING (not USER_VA_TOP) now that code
         * can slide - it must never reach the heap/stack/argv region. */
        if (vaddr < USER_VA_BASE || vaddr >= USER_HEAP_CEILING || memsz > USER_HEAP_CEILING - vaddr) {
            uart_puts("[elf] segment vaddr outside user VA range, rejected\r\n");
            return -1;
        }

        /* filesz must not exceed memsz (the copy below is sized from
         * filesz but the allocation from memsz - a larger filesz would
         * memcpy_s() past the allocated pages), and [foff, foff+filesz)
         * must lie entirely inside the bytes actually read from disk
         * (else the copy reads whatever physical memory happens to sit
         * past this loader's own 256KB staging buffer - kernel memory
         * disclosure into the new process at best, a straight OOB-read
         * crash at worst). Mirrors x86's elf.c (p_memsz<p_filesz and
         * p_offset+p_filesz>staging_size checks), which already gets
         * both of these right. */
        if (filesz > memsz || foff > sz || filesz > sz - foff) {
            uart_puts("[elf] segment filesz/offset out of bounds, rejected\r\n");
            return -1;
        }

        unsigned long npages = (memsz + PAGE_SIZE - 1) / PAGE_SIZE;

        uart_puts("[elf]  seg vaddr=0x");
        put_hex32(vaddr);
        uart_puts(" memsz=");
        put_udec(memsz);
        uart_puts(" flags=");
        if (ph->p_flags & 4) uart_putc('R');
        if (ph->p_flags & 2) uart_putc('W');
        if (ph->p_flags & 1) uart_putc('X');
        uart_puts("\r\n");

        void *phys = alloc_pages_raw((unsigned int)npages);
        if (!phys) { uart_puts("[elf] OOM for segment\r\n"); return -1; }
        if (filesz) memcpy_s((unsigned char *)phys, buf + foff, filesz);
        /* bytes beyond filesz (.bss) are already zero - alloc_page() zeroes */

        if (nsegs < MAX_LOAD_SEGS) {
            segs[nsegs].orig_start = orig_vaddr;
            segs[nsegs].orig_end   = orig_vaddr + memsz;
            segs[nsegs].phys_base  = (unsigned long)phys;
            nsegs++;
        } else {
            uart_puts("[elf] too many PT_LOAD segments for reloc table\r\n");
            return -1;
        }
    }

    /* Pass 2: parse the section header table (not needed by Pass 1/3,
     * only for relocation fixup) - find SHT_RELA sections targeting an
     * SHF_ALLOC section (excludes debug-info/symtab-relative entries),
     * and dispatch each entry. Two sub-passes: first VALIDATE that every
     * type is either the one fixup type (R_RISCV_64) or on the
     * skip-safe whitelist; only if that holds do we APPLY the R_RISCV_64
     * fixups. This avoids ever having to unwind a partially-patched
     * program - if validation finds anything unexpected, code_slide is
     * zeroed below and Pass 3 simply maps the (still pristine, since
     * nothing was patched) segments at their original addresses -
     * fail-closed: this ONE program loses code-ASLR, boot doesn't. */
    int unsupported_reloc = 0;
    if (hdr->e_shoff && hdr->e_shnum &&
        hdr->e_shoff + (unsigned long)hdr->e_shnum * hdr->e_shentsize <= sz) {
        elf64_shdr_t *shdrs = (elf64_shdr_t *)(buf + hdr->e_shoff);

        for (int s = 0; s < hdr->e_shnum && !unsupported_reloc; s++) {
            if (shdrs[s].sh_type != SHT_RELA) continue;
            if (shdrs[s].sh_info >= hdr->e_shnum) continue;
            if (!(shdrs[shdrs[s].sh_info].sh_flags & SHF_ALLOC)) continue;
            /* sh_offset/sh_size are attacker-controlled too - the outer
             * check above only bounds the SECTION HEADER TABLE itself,
             * not what an individual entry's fields point at. Without
             * this, a well-formed shdr table (passes the outer check)
             * could still name an SHT_RELA payload anywhere in the 64-
             * bit space - the exact same class of bug as e_phoff above,
             * reachable through a completely different field. Skip just
             * this section rather than aborting the whole load. */
            if (shdrs[s].sh_offset > sz || shdrs[s].sh_size > sz - shdrs[s].sh_offset) continue;

            unsigned long nrela = shdrs[s].sh_size / sizeof(elf64_rela_t);
            elf64_rela_t *relas = (elf64_rela_t *)(buf + shdrs[s].sh_offset);
            for (unsigned long r = 0; r < nrela; r++) {
                unsigned int rtype = ELF64_R_TYPE(relas[r].r_info);
                if (rtype == R_RISCV_64 || reloc_is_skip_safe(rtype)) continue;
                uart_puts("[elf] unrecognized relocation type ");
                put_udec(rtype);
                uart_puts(", disabling code-ASLR for this program\r\n");
                unsupported_reloc = 1;
                break;
            }
        }

        if (!unsupported_reloc && code_slide) {
            for (int s = 0; s < hdr->e_shnum; s++) {
                if (shdrs[s].sh_type != SHT_RELA) continue;
                if (shdrs[s].sh_info >= hdr->e_shnum) continue;
                if (!(shdrs[shdrs[s].sh_info].sh_flags & SHF_ALLOC)) continue;
                if (shdrs[s].sh_offset > sz || shdrs[s].sh_size > sz - shdrs[s].sh_offset) continue;

                unsigned long nrela = shdrs[s].sh_size / sizeof(elf64_rela_t);
                elf64_rela_t *relas = (elf64_rela_t *)(buf + shdrs[s].sh_offset);
                for (unsigned long r = 0; r < nrela; r++) {
                    if (ELF64_R_TYPE(relas[r].r_info) != R_RISCV_64) continue;

                    unsigned long off = relas[r].r_offset;
                    for (int i = 0; i < nsegs; i++) {
                        if (off >= segs[i].orig_start && off < segs[i].orig_end) {
                            unsigned long phys = segs[i].phys_base + (off - segs[i].orig_start);
                            *(unsigned long *)phys += code_slide;
                            break;
                        }
                    }
                }
            }
        }
    }

    unsigned long final_slide = unsupported_reloc ? 0 : code_slide;

    /* Pass 3: map every PT_LOAD segment's already-allocated physical
     * pages at its final (possibly slid) virtual address. heap_end
     * tracks the highest byte used by any segment - the heap starts on
     * the next page boundary above it. */
    unsigned long heap_end = 0;
    for (int i = 0; i < hdr->e_phnum; i++) {
        elf64_phdr_t *ph = (elf64_phdr_t *)(buf + hdr->e_phoff
                           + (unsigned long)i * hdr->e_phentsize);
        if (ph->p_type != PT_LOAD || !ph->p_memsz) continue;

        unsigned long vaddr = ph->p_vaddr + final_slide;
        unsigned long memsz = ph->p_memsz;
        unsigned int  pflags = ph->p_flags;

        unsigned long pte_flags = PTE_V | PTE_U | PTE_A | PTE_D;
        if (pflags & 4) pte_flags |= PTE_R;
        if (pflags & 2) pte_flags |= PTE_W;
        if (pflags & 1) pte_flags |= PTE_X;

        unsigned long phys_base = 0;
        for (int j = 0; j < nsegs; j++) {
            if (segs[j].orig_start == ph->p_vaddr) { phys_base = segs[j].phys_base; break; }
        }

        unsigned long npages = (memsz + PAGE_SIZE - 1) / PAGE_SIZE;
        for (unsigned long p = 0; p < npages; p++) {
            unsigned long off = p * PAGE_SIZE;
            map_page_4k_pt(pt, vaddr + off, phys_base + off, pte_flags);
        }

        unsigned long seg_end = vaddr + memsz;
        if (seg_end > heap_end) heap_end = seg_end;
    }

    if (final_slide) {
        uart_puts("[elf] code_slide=0x");
        put_hex32(final_slide);
        uart_puts("\r\n");
    }

    /* User stack: one page, случайный адрес (ASLR) внутри
     * [USER_HEAP_CEILING, USER_VA_TOP) - см. pick_stack_va(). */
    unsigned long stack_va = pick_stack_va();
    void *stack_phys = alloc_page();
    if (!stack_phys) { uart_puts("[elf] OOM for stack\r\n"); return -1; }
    map_page_4k_pt(pt, stack_va, (unsigned long)stack_phys,
                   PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D);

    unsigned long entry = hdr->e_entry + final_slide;
    unsigned long usp   = stack_va + PAGE_SIZE - 16;

    /* Derive a short process name from the filename (strip extension). */
    char name[13]; int ni = 0;
    while (ni < 12 && filename[ni] && filename[ni] != '.') {
        name[ni] = filename[ni]; ni++;
    }
    name[ni] = '\0';

    int pid = proc_create(name, entry, pt, usp);
    if (pid < 0) { uart_puts("[elf] no free process slot\r\n"); return -1; }

    procs[pid].stack_va   = stack_va;
    procs[pid].code_slide = final_slide;

    /* argv: одна страница на USER_ARGS_VA - массив указателей (argv[]),
     * NULL-terminated, в начале страницы, сами строки следом. argv[0] =
     * имя файла (filename, уже без пробелов), argv[1..] = args_rest,
     * разбитый по пробелам - БЕЗ приведения регистра (пользовательские
     * данные вроде паттерна grep не должны портиться). */
    {
        char full_args[192]; int fai = 0;
        { const char *s = filename; while (*s && fai < 191) full_args[fai++] = *s++; }
        if (args_rest[0]) {
            full_args[fai++] = ' ';
            const char *s = args_rest;
            while (*s && fai < 191) full_args[fai++] = *s++;
        }
        full_args[fai] = '\0';

        void *args_phys = alloc_page();
        if (!args_phys) { uart_puts("[elf] OOM for argv\r\n"); return -1; }
        unsigned long *argv_ptrs  = (unsigned long *)args_phys;
        unsigned long  ptrs_bytes = (unsigned long)(ELF_ARGS_MAX + 1) * 8UL;
        char          *str_area   = (char *)args_phys + ptrs_bytes;
        unsigned long  str_va     = USER_ARGS_VA + ptrs_bytes;
        unsigned int   str_off    = 0;
        unsigned int   str_cap    = (unsigned int)(PAGE_SIZE - ptrs_bytes);
        int argc = 0;

        const char *q = full_args;
        while (*q == ' ') q++;
        while (*q && argc < ELF_ARGS_MAX) {
            unsigned int start = str_off;
            while (*q && *q != ' ' && str_off < str_cap - 1) str_area[str_off++] = *q++;
            str_area[str_off++] = '\0';
            argv_ptrs[argc++] = str_va + start;
            while (*q == ' ') q++;
        }
        argv_ptrs[argc] = 0;

        map_page_4k_pt(pt, USER_ARGS_VA, (unsigned long)args_phys,
                       PTE_V | PTE_R | PTE_U | PTE_A);
        procs[pid].regs[10] = (unsigned long)argc; /* a0 = argc */
        procs[pid].regs[11] = USER_ARGS_VA;        /* a1 = argv */
    }

    /* Heap starts on the page right after the highest loaded segment,
     * plus случайный сдвиг (ASLR, тот же приём, что и у x86 heap-slide в
     * kernel.c). */
    unsigned long brk0 = (heap_end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    unsigned long t2;
    __asm__ volatile("csrr %0, time" : "=r"(t2));
    // Расширяем диапазон сдвига почти на весь зазор до USER_HEAP_CEILING
    // (было хардкоженных 64 страницы/256КБ) - чисто виртуальный офсет,
    // физические страницы кучи выделяются по требованию через SYS_SBRK
    // (см. syscall.c - уже сверяется с фиксированным USER_HEAP_CEILING,
    // этой правки не касается), так что тут нет риска "current_task на
    // смещённой куче" из kernel_main.c/paging.c - тот риск был про
    // КЕРНЕЛЬНУЮ кучу, а не про пользовательскую. Резервируем reserve_min
    // гарантированного места под реальный рост кучи после сдвига.
    unsigned long reserve_min = 64UL * 1024 * 1024;   // с большим запасом для любой текущей программы
    unsigned long gap = (brk0 < USER_HEAP_CEILING) ? (USER_HEAP_CEILING - brk0) : 0;
    unsigned long max_slide_pages = (gap > reserve_min) ? (gap - reserve_min) / PAGE_SIZE : 0;
    unsigned long slide = max_slide_pages ? ((t2 ^ 0x9E3779B97F4A7C15UL) % max_slide_pages) * PAGE_SIZE : 0;
    brk0 += slide;
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
