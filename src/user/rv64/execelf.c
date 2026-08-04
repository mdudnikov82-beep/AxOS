#include "syscall.h"

/* elf_load() bounds-check fixes (see elf_loader.c): e_phoff/e_phnum/
 * e_phentsize used to be dereferenced with NO check against the actual
 * bytes read from disk, and a PT_LOAD segment's filesz/offset were never
 * checked against memsz or the file's real size either - both are the
 * exact same bug class as user_string_ok()'s missing NUL check (an
 * attacker-controlled offset dereferenced while S-mode is already mid-
 * syscall, faulting the KERNEL itself and hanging the whole machine).
 * This program crafts two minimal, otherwise-well-formed ELF64 files
 * that hit each gap and writes them to disk via writefile() before
 * exec()'ing them - a real "planted malicious binary" attack, not just
 * a crafted in-memory argument like the earlier SYS_EXEC fix's test. */

static void put_u16(unsigned char *p, unsigned short v) { p[0] = (unsigned char)v; p[1] = (unsigned char)(v >> 8); }
static void put_u32(unsigned char *p, unsigned int v) {
    for (int i = 0; i < 4; i++) p[i] = (unsigned char)(v >> (8 * i));
}
static void put_u64(unsigned char *p, unsigned long v) {
    for (int i = 0; i < 8; i++) p[i] = (unsigned char)(v >> (8 * i));
}

static void build_header(unsigned char *buf, unsigned long e_phoff,
                          unsigned short e_phnum, unsigned short e_phentsize) {
    for (int i = 0; i < 64; i++) buf[i] = 0;
    buf[0] = 0x7F; buf[1] = 'E'; buf[2] = 'L'; buf[3] = 'F'; buf[4] = 2; /* ELFCLASS64 */
    put_u16(buf + 16, 2);     /* e_type = ET_EXEC */
    put_u16(buf + 18, 0xF3);  /* e_machine = EM_RISCV */
    put_u32(buf + 20, 1);     /* e_version */
    put_u64(buf + 24, 0x40000000UL); /* e_entry */
    put_u64(buf + 32, e_phoff);
    put_u64(buf + 40, 0);     /* e_shoff = 0 - skip section parsing entirely */
    put_u32(buf + 48, 0);     /* e_flags */
    put_u16(buf + 52, 64);    /* e_ehsize */
    put_u16(buf + 54, e_phentsize);
    put_u16(buf + 56, e_phnum);
    put_u16(buf + 58, 0);     /* e_shentsize */
    put_u16(buf + 60, 0);     /* e_shnum */
    put_u16(buf + 62, 0);     /* e_shstrndx */
}

static void build_phdr(unsigned char *p, unsigned long vaddr, unsigned long offset,
                        unsigned long filesz, unsigned long memsz) {
    put_u32(p + 0, 1);  /* p_type = PT_LOAD */
    put_u32(p + 4, 5);  /* p_flags = R+X */
    put_u64(p + 8, offset);
    put_u64(p + 16, vaddr);
    put_u64(p + 24, vaddr); /* p_paddr, unused */
    put_u64(p + 32, filesz);
    put_u64(p + 40, memsz);
    put_u64(p + 48, 4096);  /* p_align */
}

int main(void) {
    unsigned char f1[64];
    /* RAM is identity-mapped as a single 1GB Sv39 L2 slot - an offset
     * has to clear that whole window (not just "look big") to actually
     * reach unmapped memory instead of just reading other kernel data
     * harmlessly. 4GB comfortably clears it regardless of buf's exact
     * position inside that 1GB region. */
    build_header(f1, 0x100000000UL /* e_phoff 4GB outside the file */, 1, 56);
    writefile("BADELF1.ELF", f1, 64);
    puts_rv("execelf: exec() with e_phoff pointing outside the file (should be rejected)...\r\n");
    long r1 = exec("BADELF1.ELF");
    puts_rv(r1 < 0 ? "execelf: DENIED as expected (bad phdr table)\r\n"
                   : "execelf: BUG - accepted bad e_phoff!\r\n");

    unsigned char f2[120];
    build_header(f2, 64, 1, 56);
    /* Likewise, filesz has to clear the loader's own 256KB staging
     * buffer capacity (not just the tiny real file size) to actually
     * walk off mapped memory instead of reading other, still-mapped
     * kernel bytes. */
    build_phdr(f2 + 64, 0x40000000UL, 120 /* offset == EOF, no bytes left */,
               0x10000000UL /* 256MB - clears the 256KB staging buffer */, 4096);
    writefile("BADELF2.ELF", f2, 120);
    puts_rv("execelf: exec() with filesz reaching past EOF (should be rejected)...\r\n");
    long r2 = exec("BADELF2.ELF");
    puts_rv(r2 < 0 ? "execelf: DENIED as expected (bad filesz/offset)\r\n"
                   : "execelf: BUG - accepted bad filesz!\r\n");

    puts_rv("execelf: still alive - kernel did not crash\r\n");
    return 0;
}
