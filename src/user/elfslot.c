#include "axiom.h"

/* Stale-physical-slot execution fix (see elf.c/kernel.c): USER_PROGRAM
 * slots are physically reused across successive run/exec invocations
 * with NO zeroing, and the ELF loader's entry-point check used to bound
 * e_entry against the WHOLE per-slot window instead of the real union
 * of copied PT_LOAD byte ranges. This program builds two minimal, raw
 * ELF32 files by hand (matching exactly what tools/make_elf.py itself
 * produces - see its own header-layout comments) and writes them to
 * disk via ax_writefile()/ax_exec(), a real "planted binary" attack:
 *
 *   A.BIN: one PT_LOAD segment, entry at offset 0 (a harmless HLT -
 *          faults immediately in ring3, fault-isolated, doesn't matter
 *          since the WHOLE flat file already got copied into the slot
 *          before A's own code ever ran). At offset POISON_OFF it
 *          contains a genuine x86 infinite loop (EB FE = jmp $-2) -
 *          real bytes A's OWN segment legitimately covers and writes.
 *
 *   B.BIN: a TINY, unrelated PT_LOAD segment (16 bytes) that never
 *          touches POISON_OFF at all - but its crafted e_entry points
 *          directly at that same slot offset anyway. Run immediately
 *          after A exits, B deterministically reuses the exact same
 *          physical slot (first-fit, lowest-index-wins allocation).
 *
 * Without the fix: B's exec() is ACCEPTED (entry only checked against
 * the whole window), and once scheduled it jumps straight into A's
 * leftover infinite loop - B never exits, confirmed by polling
 * ax_task_alive() staying 1 well past when a genuinely tiny/crashing
 * program would have already finished. With the fix: B's exec() is
 * REJECTED outright (ELF_ERR_BOUNDS) before it ever gets a chance to
 * run - exec() returns -3, no process is even created. */

#define LOAD_ADDR   0x100000u
#define EHDR_SIZE   52
#define PHDR_SIZE   32
#define ET_EXEC     2
#define EM_386      3
#define PT_LOAD     1
#define PF_RWX      7

/* Small on purpose - the RAM-disk is a tightly packed floppy-sized image
 * with dozens of pre-built programs already on it, so a large runtime
 * write can fail on disk space alone (confirmed live: an 8KB A.BIN made
 * fat12_alloc_chain() fail, unrelated to the fix being tested). All that
 * actually matters for the exploit is POISON_OFF > B's own segment size. */
#define POISON_OFF  64u
#define A_SIZE      (POISON_OFF + 2u)
#define B_SIZE      16u

static unsigned char a_file[EHDR_SIZE + PHDR_SIZE + A_SIZE];
static unsigned char b_file[EHDR_SIZE + PHDR_SIZE + B_SIZE];

static void put_u16(unsigned char *p, unsigned short v) { p[0] = (unsigned char)v; p[1] = (unsigned char)(v >> 8); }
static void put_u32(unsigned char *p, unsigned int v) {
    for (int i = 0; i < 4; i++) p[i] = (unsigned char)(v >> (8 * i));
}

/* Writes a 52-byte EHDR + one 32-byte PHDR at the start of buf, exactly
 * matching tools/make_elf.py's own layout (single PT_LOAD, no sections,
 * flat file = [ehdr][phdr][code] with p_offset == EHDR_SIZE+PHDR_SIZE). */
static void build(unsigned char *buf, unsigned int e_entry, unsigned int flat_size) {
    for (int i = 0; i < EHDR_SIZE; i++) buf[i] = 0;
    buf[0] = 0x7F; buf[1] = 'E'; buf[2] = 'L'; buf[3] = 'F';
    buf[4] = 1; buf[5] = 1; buf[6] = 1; /* ELFCLASS32, ELFDATA2LSB, EV_CURRENT */
    put_u16(buf + 16, ET_EXEC);
    put_u16(buf + 18, EM_386);
    put_u32(buf + 20, 1);           /* e_version */
    put_u32(buf + 24, e_entry);
    put_u32(buf + 28, EHDR_SIZE);   /* e_phoff */
    put_u32(buf + 32, 0);           /* e_shoff */
    put_u32(buf + 36, 0);           /* e_flags */
    put_u16(buf + 40, EHDR_SIZE);   /* e_ehsize */
    put_u16(buf + 42, PHDR_SIZE);   /* e_phentsize */
    put_u16(buf + 44, 1);           /* e_phnum */
    put_u16(buf + 46, 0);           /* e_shentsize */
    put_u16(buf + 48, 0);           /* e_shnum */
    put_u16(buf + 50, 0);           /* e_shstrndx */

    unsigned char *ph = buf + EHDR_SIZE;
    unsigned int p_offset = EHDR_SIZE + PHDR_SIZE;
    put_u32(ph + 0,  PT_LOAD);
    put_u32(ph + 4,  p_offset);
    put_u32(ph + 8,  LOAD_ADDR);   /* p_vaddr */
    put_u32(ph + 12, LOAD_ADDR);   /* p_paddr */
    put_u32(ph + 16, flat_size);   /* p_filesz */
    put_u32(ph + 20, flat_size);   /* p_memsz */
    put_u32(ph + 24, PF_RWX);
    put_u32(ph + 28, 0x1000);      /* p_align */
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;

    build(a_file, LOAD_ADDR, A_SIZE);
    unsigned char *a_code = a_file + EHDR_SIZE + PHDR_SIZE;
    for (unsigned int i = 0; i < A_SIZE; i++) a_code[i] = 0;
    /* A's own entry: xor esi,esi ; mov ah,6 ; int 0x80 - a clean
     * SYS_EXIT(0) (see syscall.h: AH=6, ESI=exit code direct value).
     * HLT was tried first and is WRONG here - it's privileged, so
     * executing it in ring3 raises #GP (vector 13), and this kernel's
     * fault handler (paging.c) only has graceful, per-process recovery
     * wired up for PAGE FAULT (vector 14) - confirmed by grepping for
     * any vector-13 handling and finding none. A real syscall exit
     * avoids the question entirely and is also more realistic (a
     * planted "innocent-looking" program would exit cleanly, not crash).
     */
    a_code[0] = 0x31; a_code[1] = 0xF6;             /* xor esi, esi */
    a_code[2] = 0xB4; a_code[3] = 0x06;             /* mov ah, 6 */
    a_code[4] = 0xCD; a_code[5] = 0x80;             /* int 0x80 */
    a_code[POISON_OFF]     = 0xEB;  /* jmp $-2 - real infinite loop, in A's OWN segment */
    a_code[POISON_OFF + 1] = 0xFE;

    build(b_file, LOAD_ADDR + POISON_OFF, B_SIZE);
    unsigned char *b_code = b_file + EHDR_SIZE + PHDR_SIZE;
    for (unsigned int i = 0; i < B_SIZE; i++) b_code[i] = 0xF4; /* B's OWN tiny, unrelated content */

    ax_print("elfslot: planting A.BIN (leaves an infinite loop at a known slot offset)...\n");
    int wa = ax_writefile("A.BIN", a_file, sizeof(a_file));
    ax_printf("elfslot: writefile(A.BIN, %d bytes) result=%d\n", (int)sizeof(a_file), wa);
    int pa = ax_exec("A.BIN");
    ax_printf("elfslot: A started (slot=%d), letting it fault/finish...\n", pa);
    ax_sleep_ms(300);

    ax_print("elfslot: writing B.BIN - tiny segment, e_entry points at A's leftover bytes...\n");
    ax_writefile("B.BIN", b_file, sizeof(b_file));
    int pb = ax_exec("B.BIN");
    if (pb < 0) {
        ax_printf("elfslot: DENIED as expected (exec result=%d)\n", pb);
    } else {
        ax_printf("elfslot: BUG - exec() accepted it (slot=%d), checking if it's stuck in the poison...\n", pb);
        ax_sleep_ms(500);
        int alive = ax_task_alive(pb);
        ax_printf("elfslot: B still alive after 500ms: %d (1 = confirmed stuck in A's leftover infinite loop)\n", alive);
    }

    ax_print("elfslot: still alive - kernel did not crash\n");
    return 0;
}
