// gfx_shell.c — AxOS Graphical Desktop Shell
// 32-bit protected mode, VBE linear framebuffer: 800x600, 32bpp truecolor
// (see src/boot/boot_shell.asm for the real-mode VBE mode search/set).
// No stdlib. Entry point: void gfx_main(void)   (via kernel_gfx_entry.asm)
//
// Was VGA Mode 13h (320x200, 256-color palette, fixed @ 0xA0000). Upgraded
// to truecolor: boot_shell.asm finds an 800x600x32bpp VBE mode by walking
// the controller's OWN mode list (not a guessed mode number - those vary
// by BIOS), switches to it with the linear-framebuffer bit set, and drops
// the physical framebuffer address + scanline pitch + resolution at a
// fixed low address (0x0600) that this code reads directly (paging is off,
// physical == linear here).

#include "../drivers/mouse.h"
#include "../fs/fat12.h"

/* ── Framebuffer info, written by boot_shell.asm before the kernel loads ── */
typedef struct {
    unsigned int   phys_base;   /* LFB physical address (VBE PhysBasePtr) */
    unsigned short xres;
    unsigned short yres;
    unsigned short pitch;       /* bytes per scanline - may exceed xres*4 */
    unsigned char  bpp;
} __attribute__((packed)) fb_info_t;
#define FB_INFO ((const fb_info_t *)0x0600)

#define SW  800
#define SH  600

/* Back buffer: tightly packed (no pitch padding), draw here, blit to the
 * real (possibly padded) LFB atomically to avoid tearing/flicker. Fixed
 * physical address, NOT a .bss array: 800*600*4 = ~1.9MB is far more than
 * this minimal boot environment's default ESP=0x90000 leaves room for
 * below the stack, so it lives well up in extended memory instead, at an
 * address nothing else in this standalone image ever touches. */
#define BACKBUF ((unsigned int *)0x200000)

typedef unsigned int color_t;

/* Truecolor equivalents of the old fixed 16-color VGA palette (0x00RRGGBB) */
#define C_BLACK  0x000000u
#define C_NAVY   0x0000AAu
#define C_DGREEN 0x00AA00u
#define C_TEAL   0x00AAAAu
#define C_MAROON 0xAA0000u
#define C_GRAY   0xAAAAAAu
#define C_DGRAY  0x555555u
#define C_BLUE   0x5555FFu
#define C_GREEN  0x55FF55u
#define C_CYAN   0x55FFFFu
#define C_RED    0xFF5555u
#define C_YELLOW 0xFFFF55u
#define C_WHITE  0xFFFFFFu

/* Extra shades for gradients/cards - cheap to have now, plain palette
 * indices couldn't afford in-between tones like these. */
#define C_NAVY_LT  0x2A4E8Cu   /* lighter navy, gradient top          */
#define C_NAVY_DK  0x0A1A33u   /* darker navy,  gradient bottom        */
#define C_CARD_BG  0x0C1424u   /* near-black card body (terminal/about)*/
#define C_CARD_BRD 0x2A3A55u   /* card border                          */
#define C_GRAY_LT  0xC8C8C8u   /* taskbar gradient top                 */

/* Layout */
#define TBAR_H   24
#define BBAR_Y   (SH - 24)
#define BBAR_H   24
#define AREA_Y   TBAR_H
#define AREA_H   (BBAR_Y - TBAR_H)

/* Corner radius + inner padding shared by window chrome and window
 * content (Terminal/About) - used to be a full-screen "floating card"
 * panel's own margin/size too (CARD_X/Y/W/H), now dead since Terminal/
 * About are real movable windows with their own x/y/w/h (see win_t). */
#define CARD_R   16
#define CARD_PAD 16

/* ── I/O ─────────────────────────────────────────────────────────── */
static unsigned char inb(unsigned short p) {
    unsigned char r;
    __asm__ volatile("inb %%dx,%%al":"=a"(r):"d"(p));
    return r;
}
static void outb(unsigned short p, unsigned char v) {
    __asm__ volatile("outb %%al,%%dx"::"a"(v),"d"(p));
}
static unsigned short inw(unsigned short p) {
    unsigned short r;
    __asm__ volatile("inw %%dx,%%ax":"=a"(r):"d"(p));
    return r;
}
static void outw(unsigned short p, unsigned short v) {
    __asm__ volatile("outw %%ax,%%dx"::"a"(v),"d"(p));
}

/* ── IDE (polled — no IRQ14/PIT here, unlike src/drivers/ide.c, which
 * needs both and can't be reused as-is) ─────────────────────────────
 * Primary bus, master, LBA28, PIO, single-threaded (this mini-kernel's
 * main loop is the only thing that ever touches these ports, so no
 * lock needed). AxFiles (the file manager window) can now delete
 * files, so both read and write are needed - resolves fat12_shell.o's
 * extern ide_read_sector()/ide_write_sector() at link time (see
 * build.bat's Graphical Shell section). */
#define IDE_REG_DATA       0x1F0
#define IDE_REG_SECCOUNT   0x1F2
#define IDE_REG_LBA_LOW    0x1F3
#define IDE_REG_LBA_MID    0x1F4
#define IDE_REG_LBA_HIGH   0x1F5
#define IDE_REG_DRIVE_HEAD 0x1F6
#define IDE_REG_STATUS     0x1F7
#define IDE_REG_COMMAND    0x1F7
#define IDE_STATUS_ERR 0x01
#define IDE_STATUS_DRQ 0x08
#define IDE_STATUS_BSY 0x80
#define IDE_CMD_READ_SECTORS  0x20
#define IDE_CMD_WRITE_SECTORS 0x30
#define IDE_WAIT_LIMIT 100000

int ide_read_sector(unsigned int lba, unsigned char *buffer) {
    unsigned char st = inb(IDE_REG_STATUS);
    if (st == 0xFF) return 0;   /* no controller (floating bus) - fail fast */

    int spins;
    for (spins = IDE_WAIT_LIMIT; spins && (inb(IDE_REG_STATUS) & IDE_STATUS_BSY); spins--);
    if (!spins) return 0;

    outb(IDE_REG_DRIVE_HEAD, 0xE0 | ((lba >> 24) & 0x0F));
    outb(IDE_REG_SECCOUNT, 1);
    outb(IDE_REG_LBA_LOW,  (unsigned char)(lba));
    outb(IDE_REG_LBA_MID,  (unsigned char)(lba >> 8));
    outb(IDE_REG_LBA_HIGH, (unsigned char)(lba >> 16));
    outb(IDE_REG_COMMAND,  IDE_CMD_READ_SECTORS);

    for (spins = IDE_WAIT_LIMIT; spins; spins--) {
        st = inb(IDE_REG_STATUS);
        if (st & IDE_STATUS_ERR) return 0;
        if (!(st & IDE_STATUS_BSY) && (st & IDE_STATUS_DRQ)) break;
    }
    if (!spins) return 0;

    unsigned short *dst = (unsigned short *)buffer;
    for (int i = 0; i < 256; i++) dst[i] = inw(IDE_REG_DATA);
    return 1;
}

/* Mirror of ide_read_sector() - same wait/fast-fail structure, WRITE
 * command and outw() instead of inw(). Resolves fat12_shell.o's extern
 * ide_write_sector() (fat12_delete() -> fat12_flush() -> this). */
int ide_write_sector(unsigned int lba, unsigned char *buffer) {
    unsigned char st = inb(IDE_REG_STATUS);
    if (st == 0xFF) return 0;   /* no controller (floating bus) - fail fast */

    int spins;
    for (spins = IDE_WAIT_LIMIT; spins && (inb(IDE_REG_STATUS) & IDE_STATUS_BSY); spins--);
    if (!spins) return 0;

    outb(IDE_REG_DRIVE_HEAD, 0xE0 | ((lba >> 24) & 0x0F));
    outb(IDE_REG_SECCOUNT, 1);
    outb(IDE_REG_LBA_LOW,  (unsigned char)(lba));
    outb(IDE_REG_LBA_MID,  (unsigned char)(lba >> 8));
    outb(IDE_REG_LBA_HIGH, (unsigned char)(lba >> 16));
    outb(IDE_REG_COMMAND,  IDE_CMD_WRITE_SECTORS);

    for (spins = IDE_WAIT_LIMIT; spins; spins--) {
        st = inb(IDE_REG_STATUS);
        if (st & IDE_STATUS_ERR) return 0;
        if (!(st & IDE_STATUS_BSY) && (st & IDE_STATUS_DRQ)) break;
    }
    if (!spins) return 0;

    unsigned short *src = (unsigned short *)buffer;
    for (int i = 0; i < 256; i++) outw(IDE_REG_DATA, src[i]);
    return 1;
}

/* Copy back buffer to the real LFB in one shot — eliminates tearing.
 * Row-by-row through `pitch`: the hardware scanline stride can exceed
 * xres*4 (alignment padding), so we can't just memcpy the whole thing. */
static void blit(void) {
    unsigned char *dst_base = (unsigned char *)(unsigned long)FB_INFO->phys_base;
    unsigned short pitch    = FB_INFO->pitch;
    for (int y = 0; y < SH; y++) {
        unsigned int *src = BACKBUF + y * SW;
        unsigned int *dst = (unsigned int *)(dst_base + (unsigned long)y * pitch);
        for (int x = 0; x < SW; x++) dst[x] = src[x];
    }
}

/* Wait for VGA vertical retrace — with timeout so QEMU doesn't hang.
 * Port 0x3DA (input status 1) still reflects retrace on Bochs/QEMU VBE
 * even once you're driving it through the DISPI/LFB interface. */
static void wait_vsync(void) {
    int i;
    for (i = 65535; i && (inb(0x3DA) & 8); i--);    /* wait for retrace end   */
    for (i = 65535; i && !(inb(0x3DA) & 8); i--);   /* wait for retrace start */
}

/* ── Keyboard (polled — no IRQ1, avoids GPF during PS/2 init) ───── */

/* Read one scancode if keyboard data is ready; return 1 on success.
 * Port 0x64 bit0=output-buffer-full, bit5=mouse-data. */
static int kbd_get(unsigned char *sc) {
    unsigned char st = inb(0x64);
    if ((st & 0x01) && !(st & 0x20)) { *sc = inb(0x60); return 1; }
    return 0;
}

/* Stub kept so idt_shell.asm external reference resolves without error. */
void keyboard_irq_handler(void) { (void)inb(0x60); }

/* US QWERTY scancode → ASCII (unshifted, make codes only) */
static const unsigned char sc2asc[89] = {
    0,0,
    '1','2','3','4','5','6','7','8','9','0','-','=','\b',
    '\t','q','w','e','r','t','y','u','i','o','p','[',']','\n',
    0,'a','s','d','f','g','h','j','k','l',';','\'','`',
    0,'\\','z','x','c','v','b','n','m',',','.','/',0,
    '*',0,' ',0,
    0,0,0,0,0,0,0,0,0,0,  /* F1-F10 */
    0,0,                   /* Num/Scroll lock */
    '7','8','9','-','4','5','6','+','1','2','3','0','.'
};

static char sc_to_char(unsigned char sc) {
    if (sc & 0x80) return 0;        /* key release */
    if (sc < 89 && sc2asc[sc]) return (char)sc2asc[sc];
    return 0;
}

/* ── IDT ─────────────────────────────────────────────────────────── */
struct idt_entry {
    unsigned short lo, sel;
    unsigned char  zero, type;
    unsigned short hi;
} __attribute__((packed));
static struct idt_entry IDT[256];

extern void keyboard_interrupt_handler(void);
extern void mouse_interrupt_handler(void);
extern void default_irq_handler(void);
extern void default_exc_handler(void);

static void set_gate(int n, unsigned long h) {
    IDT[n].lo   = (unsigned short)(h & 0xFFFF);
    IDT[n].sel  = 0x08;
    IDT[n].zero = 0;
    IDT[n].type = 0x8E;
    IDT[n].hi   = (unsigned short)(h >> 16);
}

static void init_idt_shell(void) {
    /* Fill all exception vectors (0x00-0x1F) with halt handler */
    for (int i = 0x00; i < 0x20; i++)
        set_gate(i, (unsigned long)default_exc_handler);
    /* Fill all PIC IRQ vectors (0x20-0x2F) with EOI-and-return stub */
    for (int i = 0x20; i < 0x30; i++)
        set_gate(i, (unsigned long)default_irq_handler);
    /* Override with real handlers */
    set_gate(0x21, (unsigned long)keyboard_interrupt_handler);
    set_gate(0x2C, (unsigned long)mouse_interrupt_handler);

    struct { unsigned short lim; unsigned long base; } __attribute__((packed))
        idtr = { 256*8-1, (unsigned long)IDT };
    __asm__("lidt %0"::"m"(idtr));

    /* Remap PIC: IRQ0-7 → INT 20h, IRQ8-15 → INT 28h */
    outb(0x20,0x11); outb(0xA0,0x11);
    outb(0x21,0x20); outb(0xA1,0x28);
    outb(0x21,0x04); outb(0xA1,0x02);
    outb(0x21,0x01); outb(0xA1,0x01);
    /* Keyboard polled, not interrupt-driven (IRQ1 masked to prevent GPF).
     * Open IRQ2 (cascade) so IRQ12 (mouse) can reach CPU via slave PIC. */
    outb(0x21, 0xFB);   /* 11111011: IRQ2 open, keyboard IRQ1 masked */
    outb(0xA1, 0xEF);   /* 11101111: IRQ12 open, rest masked */
    __asm__ volatile("sti");
}

/* ── CMOS RTC ────────────────────────────────────────────────────── */
#define UTC_OFFSET 5   /* UTC+5 (Yekaterinburg/Almaty) */
static unsigned char bcd(unsigned char b) { return (b>>4)*10 + (b&0xF); }
static void rtc_time(int *h, int *m, int *s) {
    outb(0x70,0x04); *h = bcd(inb(0x71));
    outb(0x70,0x02); *m = bcd(inb(0x71));
    outb(0x70,0x00); *s = bcd(inb(0x71));
    *h = (*h + UTC_OFFSET) % 24;
}

/* ── 8×8 bitmap font (ASCII 0x20–0x7F, public-domain VGA font) ───── */
static const unsigned char F[96][8] = {
    {0,0,0,0,0,0,0,0},              /* 20 spc */
    {0x18,0x18,0x18,0x18,0,0,0x18,0}, /* 21 !  */
    {0x66,0x66,0x24,0,0,0,0,0},     /* 22 "   */
    {0x6C,0x6C,0xFE,0x6C,0xFE,0x6C,0x6C,0}, /* 23 # */
    {0x18,0x7C,0x06,0x7C,0x60,0x7C,0x18,0}, /* 24 $ */
    {0xC6,0x66,0x30,0x18,0x0C,0x66,0xC6,0}, /* 25 % */
    {0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0}, /* 26 & */
    {0x18,0x18,0x18,0,0,0,0,0},     /* 27 '   */
    {0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0}, /* 28 ( */
    {0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0}, /* 29 ) */
    {0,0x66,0x3C,0xFF,0x3C,0x66,0,0},  /* 2A *  */
    {0,0x18,0x18,0x7E,0x18,0x18,0,0},  /* 2B +  */
    {0,0,0,0,0,0x18,0x18,0x30},        /* 2C ,  */
    {0,0,0,0x7E,0,0,0,0},             /* 2D -  */
    {0,0,0,0,0,0x18,0x18,0},           /* 2E .  */
    {0,0x60,0x30,0x18,0x0C,0x06,0,0},  /* 2F /  */
    {0x7C,0xC6,0xCE,0xDE,0xF6,0xC6,0x7C,0}, /* 30 0 */
    {0x18,0x1C,0x18,0x18,0x18,0x18,0x7E,0}, /* 31 1 */
    {0x7C,0xC6,0xC0,0x60,0x30,0x06,0xFE,0}, /* 32 2 */
    {0x7C,0xC6,0xC0,0x78,0xC0,0xC6,0x7C,0}, /* 33 3 */
    {0xC6,0xC6,0xC6,0xFE,0xC0,0xC0,0xC0,0}, /* 34 4 */
    {0xFE,0x06,0x06,0x7E,0xC0,0xC6,0x7C,0}, /* 35 5 */
    {0x7C,0x06,0x06,0x7E,0xC6,0xC6,0x7C,0}, /* 36 6 */
    {0xFE,0xC0,0x60,0x30,0x18,0x18,0x18,0}, /* 37 7 */
    {0x7C,0xC6,0xC6,0x7C,0xC6,0xC6,0x7C,0}, /* 38 8 */
    {0x7C,0xC6,0xC6,0xFC,0xC0,0xC0,0x7C,0}, /* 39 9 */
    {0,0x18,0x18,0,0,0x18,0x18,0},    /* 3A :  */
    {0,0x18,0x18,0,0,0x18,0x18,0x30}, /* 3B ;  */
    {0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0}, /* 3C < */
    {0,0,0x7E,0,0x7E,0,0,0},          /* 3D =  */
    {0x06,0x0C,0x18,0x30,0x18,0x0C,0x06,0}, /* 3E > */
    {0x7C,0xC6,0xC0,0x60,0x18,0,0x18,0},    /* 3F ? */
    {0x7C,0xC6,0xDE,0xDE,0xDE,0x06,0x7C,0}, /* 40 @ */
    {0x38,0x6C,0xC6,0xFE,0xC6,0xC6,0xC6,0}, /* 41 A */
    {0x7E,0xC6,0xC6,0x7E,0xC6,0xC6,0x7E,0}, /* 42 B */
    {0x7C,0xC6,0x06,0x06,0x06,0xC6,0x7C,0}, /* 43 C */
    {0x3E,0x66,0xC6,0xC6,0xC6,0x66,0x3E,0}, /* 44 D */
    {0xFE,0x06,0x06,0x7E,0x06,0x06,0xFE,0}, /* 45 E */
    {0xFE,0x06,0x06,0x7E,0x06,0x06,0x06,0}, /* 46 F */
    {0x7C,0xC6,0x06,0xF6,0xC6,0xC6,0x7C,0}, /* 47 G */
    {0xC6,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0}, /* 48 H */
    {0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0}, /* 49 I */
    {0x60,0x60,0x60,0x60,0xC6,0xC6,0x7C,0}, /* 4A J */
    {0xC6,0x66,0x36,0x1E,0x36,0x66,0xC6,0}, /* 4B K */
    {0x06,0x06,0x06,0x06,0x06,0x06,0xFE,0}, /* 4C L */
    {0xC6,0xEE,0xFE,0xD6,0xC6,0xC6,0xC6,0}, /* 4D M */
    {0xC6,0xCE,0xDE,0xFE,0xF6,0xE6,0xC6,0}, /* 4E N */
    {0x7C,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0}, /* 4F O */
    {0x7E,0xC6,0xC6,0x7E,0x06,0x06,0x06,0}, /* 50 P */
    {0x7C,0xC6,0xC6,0xC6,0xC6,0x6C,0xB8,0}, /* 51 Q */
    {0x7E,0xC6,0xC6,0x7E,0x36,0x66,0xC6,0}, /* 52 R */
    {0x7C,0xC6,0x06,0x7C,0xC0,0xC6,0x7C,0}, /* 53 S */
    {0xFF,0x18,0x18,0x18,0x18,0x18,0x18,0}, /* 54 T */
    {0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0}, /* 55 U */
    {0xC6,0xC6,0xC6,0x6C,0x38,0x10,0x10,0}, /* 56 V */
    {0xC6,0xC6,0xD6,0xFE,0xEE,0xC6,0xC6,0}, /* 57 W */
    {0xC6,0x6C,0x38,0x38,0x38,0x6C,0xC6,0}, /* 58 X */
    {0xCC,0xCC,0x78,0x30,0x30,0x30,0x30,0}, /* 59 Y */
    {0xFE,0x60,0x30,0x18,0x0C,0x06,0xFE,0}, /* 5A Z */
    {0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0}, /* 5B [ */
    {0,0x06,0x0C,0x18,0x30,0x60,0,0},        /* 5C \ */
    {0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0}, /* 5D ] */
    {0x10,0x38,0x6C,0xC6,0,0,0,0},          /* 5E ^ */
    {0,0,0,0,0,0,0,0xFF},                    /* 5F _ */
    {0x0C,0x18,0x30,0,0,0,0,0},             /* 60 ` */
    {0,0,0x7C,0xC0,0xFC,0xC6,0xFC,0},       /* 61 a */
    {0x06,0x06,0x7E,0xC6,0xC6,0xC6,0x7E,0}, /* 62 b */
    {0,0,0x7C,0xC6,0x06,0xC6,0x7C,0},       /* 63 c */
    {0xC0,0xC0,0xFC,0xC6,0xC6,0xC6,0xFC,0}, /* 64 d */
    {0,0,0x7C,0xC6,0xFE,0x06,0x7C,0},       /* 65 e */
    {0x70,0x18,0x7E,0x18,0x18,0x18,0x18,0}, /* 66 f */
    {0,0,0xFC,0xC6,0xC6,0xFC,0xC0,0x7C},    /* 67 g */
    {0x06,0x06,0x7E,0xC6,0xC6,0xC6,0xC6,0}, /* 68 h */
    {0x18,0,0x1E,0x18,0x18,0x18,0x7E,0},    /* 69 i */
    {0x30,0,0x30,0x30,0x30,0x36,0x1C,0},    /* 6A j */
    {0x06,0x06,0x66,0x36,0x1E,0x36,0x66,0}, /* 6B k */
    {0x1C,0x18,0x18,0x18,0x18,0x18,0x7E,0}, /* 6C l */
    {0,0,0xC6,0xEE,0xFE,0xD6,0xC6,0},       /* 6D m */
    {0,0,0x3E,0x66,0x66,0x66,0x66,0},       /* 6E n */
    {0,0,0x7C,0xC6,0xC6,0xC6,0x7C,0},       /* 6F o */
    {0,0,0x7E,0xC6,0xC6,0x7E,0x06,0x06},    /* 70 p */
    {0,0,0xFC,0xC6,0xC6,0xFC,0xC0,0xC0},    /* 71 q */
    {0,0,0x6E,0x76,0x06,0x06,0x06,0},       /* 72 r */
    {0,0,0x7C,0x06,0x7C,0xC0,0x7C,0},       /* 73 s */
    {0x18,0x18,0x7E,0x18,0x18,0x18,0x70,0}, /* 74 t */
    {0,0,0xC6,0xC6,0xC6,0xE6,0xDC,0},       /* 75 u */
    {0,0,0xC6,0xC6,0x6C,0x38,0x10,0},       /* 76 v */
    {0,0,0xC6,0xD6,0xFE,0xEE,0xC6,0},       /* 77 w */
    {0,0,0xC6,0x6C,0x38,0x6C,0xC6,0},       /* 78 x */
    {0,0,0xCC,0xCC,0x78,0x30,0x1E,0},       /* 79 y */
    {0,0,0xFE,0x60,0x30,0x18,0xFE,0},       /* 7A z */
    {0x38,0x0C,0x0C,0x06,0x0C,0x0C,0x38,0}, /* 7B { */
    {0x18,0x18,0x18,0,0x18,0x18,0x18,0},    /* 7C | */
    {0x0C,0x18,0x18,0x30,0x18,0x18,0x0C,0}, /* 7D } */
    {0x76,0xDC,0,0,0,0,0,0},                /* 7E ~ */
    {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF}, /* 7F   */
};

/* ── Drawing primitives ───────────────────────────────────────────── */
static void px(int x, int y, color_t c) {
    if ((unsigned)x < SW && (unsigned)y < SH) BACKBUF[y*SW+x] = c;
}
static void fill(int x, int y, int w, int h, color_t c) {
    for (int dy=0; dy<h; dy++)
        for (int dx=0; dx<w; dx++) px(x+dx, y+dy, c);
}
static void hline(int x, int y, int w, color_t c) {
    for (int i=0; i<w; i++) px(x+i,y,c);
}
static void vline(int x, int y, int h, color_t c) {
    for (int i=0; i<h; i++) px(x,y+i,c);
}
/* ── Alpha blending + gradients (only possible now that we have real
 * 32-bit RGB instead of an 8-bit palette) ──────────────────────────── */
static color_t blend(color_t bg, color_t fg, unsigned char alpha) {
    int br=(bg>>16)&0xFF, bg8=(bg>>8)&0xFF, bb=bg&0xFF;
    int fr=(fg>>16)&0xFF, fg8=(fg>>8)&0xFF, fb=fg&0xFF;
    int r = br + ((fr-br)*alpha)/255;
    int g = bg8 + ((fg8-bg8)*alpha)/255;
    int b = bb + ((fb-bb)*alpha)/255;
    return ((color_t)r<<16)|((color_t)g<<8)|(color_t)b;
}
static void blend_px(int x, int y, color_t fg, unsigned char alpha) {
    if ((unsigned)x>=SW || (unsigned)y>=SH) return;
    BACKBUF[y*SW+x] = blend(BACKBUF[y*SW+x], fg, alpha);
}
static void blend_fill(int x, int y, int w, int h, color_t c, unsigned char alpha) {
    for (int dy=0; dy<h; dy++) for (int dx=0; dx<w; dx++) blend_px(x+dx, y+dy, c, alpha);
}
/* Vertical gradient fill: c1 at the top row, c2 at the bottom row. */
static void vgrad(int x, int y, int w, int h, color_t c1, color_t c2) {
    for (int dy=0; dy<h; dy++) {
        unsigned char a = (h<=1) ? 255 : (unsigned char)((dy*255)/(h-1));
        hline(x, y+dy, w, blend(c1, c2, a));
    }
}

/* ── Rounded rectangles (drop shadows/cards below need these to not
 * look like plain 320x200-era boxes now that curves are affordable) ── */
static int in_rounded(int dx, int dy, int w, int h, int r) {
    if (dx >= r && dx < w-r) return 1;
    if (dy >= r && dy < h-r) return 1;
    int cx = (dx < r) ? r : w-r-1;
    int cy = (dy < r) ? r : h-r-1;
    int ddx = dx-cx, ddy = dy-cy;
    return (ddx*ddx + ddy*ddy) <= r*r;
}
static void fill_round(int x, int y, int w, int h, int r, color_t c) {
    for (int dy=0; dy<h; dy++) for (int dx=0; dx<w; dx++)
        if (in_rounded(dx, dy, w, h, r)) px(x+dx, y+dy, c);
}
/* Soft drop shadow: offset, blurred-ish via low alpha, blended into
 * whatever is already in the back buffer (desktop/gradient behind it). */
static void shadow_round(int x, int y, int w, int h, int r, int off) {
    for (int dy=0; dy<h; dy++) for (int dx=0; dx<w; dx++)
        if (in_rounded(dx, dy, w, h, r)) blend_px(x+dx+off, y+dy+off, C_BLACK, 90);
}
/* Rounded card with a thin border: outer rounded fill in border color,
 * inner rounded fill (inset 2px, radius-2) in the body color on top. */
static void card_round(int x, int y, int w, int h, int r, color_t body, color_t brd) {
    fill_round(x, y, w, h, r, brd);
    fill_round(x+2, y+2, w-4, h-4, r>2?r-2:1, body);
}

/* Embedded icon BMPs (см. tools/bmp_to_c.py - конвертируется из
 * src/kernel/term.bmp/about.bmp на этапе сборки, build.bat) + декодер
 * (bmp.h - тот же формат, что и RISC-V-стороны, но без файлового
 * ввода-вывода: gfx_shell.c не имеет доступа к диску вообще). */
#include "icons_data.h"
#include "bmp.h"

/* Font rendered at 2x: each 1x1 source bit becomes a FONT_SCALE x
 * FONT_SCALE block. At native 8x8 pixels, text would be tiny/hard to
 * read on an 800x600 canvas (previously 320x200 - 2.5x-3x smaller). */
#define FONT_SCALE  2
#define CHAR_W      (8*FONT_SCALE)

static void glyph(int x, int y, char ch, color_t fg) {
    unsigned char u = (unsigned char)ch;
    if (u < 0x20 || u > 0x7F) return;
    const unsigned char *g = F[u - 0x20];
    for (int r=0; r<8; r++) {
        unsigned char b = g[r];
        for (int c=0; c<8; c++)
            if (b & (1<<c))
                fill(x + c*FONT_SCALE, y + r*FONT_SCALE, FONT_SCALE, FONT_SCALE, fg);
    }
}
static void text(int x, int y, const char *s, color_t fg) {
    while (*s) { glyph(x, y, *s++, fg); x += CHAR_W; }
}
static int slen(const char *s) { int n=0; while(s[n]) n++; return n; }
static void text_center(int cx, int y, const char *s, color_t fg) {
    text(cx - slen(s)*(CHAR_W/2), y, s, fg);
}
static void draw_num2(int x, int y, int v, color_t fg) {
    char b[3]; b[0]='0'+v/10; b[1]='0'+v%10; b[2]=0;
    text(x, y, b, fg);
}

/* ── UI state ─────────────────────────────────────────────────────── */
typedef enum { SCR_DESKTOP = 0, SCR_TERMINAL, SCR_ABOUT, SCR_PAINT, SCR_FILES } Screen;
static Screen scr = SCR_DESKTOP;

/* Icon hit-boxes (desktop) */
struct icon { int x,y,w,h; Screen dst; const char *label; color_t color; };
static const struct icon icons[] = {
    { 40, 60, 112, 96, SCR_TERMINAL, "TERM",  C_BLUE   },
    { 192, 60, 112, 96, SCR_ABOUT,    "ABOUT", C_MAROON },
    { 344, 60, 112, 96, SCR_PAINT,    "PAINT", C_DGREEN },
    { 496, 60, 112, 96, SCR_FILES,    "FILES", C_TEAL   },
};
#define N_ICONS 4

/* ── Window manager (Terminal + About only - see plan/memory for why
 * Paint stays a full-screen mode, matching the RISC-V reference's own
 * axpaint.c, which also doesn't use its window.h) ──────────────────────
 *
 * gfx_shell.c already rebuilds the ENTIRE back buffer from scratch every
 * frame (no dirty-rect/partial-redraw concept at all - see blit()/the
 * main loop) - real overlapping, z-ordered windows are basically free
 * here: draw the desktop, then iterate windows back-to-front, each one
 * at full quality every frame, cursor last. No RISC-V-style cheap
 * "ghost" render during drag needed, no manual "erase old footprint"
 * logic needed - full redraw already handles both for free. Not
 * resizable (matches RISC-V's own window.h scope too), just movable. */
typedef struct {
    int x, y;   /* top-left, draggable */
    int w, h;   /* fixed size */
    int open;
} win_t;

#define WIN_TERM  0
#define WIN_ABOUT 1
#define WIN_FILES 2
#define N_WINDOWS 3

/* Sizes fit each screen's existing content (TROWS x TCOLS grid for
 * Terminal, the logo+info+feature-list block for About) plus the
 * window's own titlebar+padding. Positions offset diagonally so opening
 * both at once doesn't perfectly overlap them - and deliberately start
 * BELOW the icon row (icons occupy y 60-156): a default position
 * covering the icons would make About/Paint unreachable the moment
 * Terminal opens, found live via screendump (About's icon sat directly
 * under Terminal's default footprint, its click never got through). */
static win_t windows[N_WINDOWS] = {
    { 70,  170, 660, 340, 0 },   /* WIN_TERM  */
    { 230, 180, 560, 380, 0 },   /* WIN_ABOUT */
    { 120, 165, 620, 380, 0 },   /* WIN_FILES */
};
static int win_order[N_WINDOWS] = { WIN_TERM, WIN_ABOUT, WIN_FILES };  /* [0]=back .. [N-1]=front/focused */

static int dragging_win = -1;
static int drag_off_x = 0, drag_off_y = 0;

#define WIN_TITLE_H  28
#define WIN_CLOSE_SZ 16

static int win_hit_titlebar(int idx, int mx, int my) {
    win_t *w = &windows[idx];
    if (my < w->y || my >= w->y + WIN_TITLE_H) return 0;
    if (mx < w->x || mx >= w->x + w->w) return 0;
    if (mx >= w->x + w->w - WIN_CLOSE_SZ - 8) return 0;   /* excludes the close button */
    return 1;
}
static int win_hit_close(int idx, int mx, int my) {
    win_t *w = &windows[idx];
    int bx = w->x + w->w - WIN_CLOSE_SZ - 6;
    int by = w->y + (WIN_TITLE_H - WIN_CLOSE_SZ) / 2;
    return mx >= bx && mx < bx + WIN_CLOSE_SZ && my >= by && my < by + WIN_CLOSE_SZ;
}
/* Front-to-back so an on-top window wins the hit test over one it overlaps. */
static int win_topmost_at(int mx, int my) {
    for (int i = N_WINDOWS - 1; i >= 0; i--) {
        int idx = win_order[i];
        win_t *w = &windows[idx];
        if (!w->open) continue;
        if (mx >= w->x && mx < w->x + w->w && my >= w->y && my < w->y + w->h) return idx;
    }
    return -1;
}
static void win_raise(int idx) {
    int pos = -1;
    for (int i = 0; i < N_WINDOWS; i++) if (win_order[i] == idx) { pos = i; break; }
    for (int i = pos; i < N_WINDOWS - 1; i++) win_order[i] = win_order[i+1];
    win_order[N_WINDOWS - 1] = idx;
}
static void win_open(int idx) {
    windows[idx].open = 1;
    win_raise(idx);
}
static void win_close(int idx) {
    windows[idx].open = 0;
    if (dragging_win == idx) dragging_win = -1;
}
/* win_order tracks z-order, not open/closed state - after the front
 * window closes, win_order[N_WINDOWS-1] still names it. Callers that
 * need "the window the user is actually looking at" (ESC-to-close,
 * keyboard focus routing) must skip closed entries, not read the raw
 * top slot. */
static int win_focused(void) {
    for (int i = N_WINDOWS - 1; i >= 0; i--) {
        int idx = win_order[i];
        if (windows[idx].open) return idx;
    }
    return -1;
}
/* Content area = inside the window, below its mini titlebar. Shared by
 * the render loop and content-click hit-testing (AxFiles' row/button
 * geometry) so the two can't drift apart. */
static void win_content_rect(int idx, int *cx0, int *cy0, int *cw, int *ch) {
    win_t *w = &windows[idx];
    *cx0 = w->x + 2;
    *cy0 = w->y + 2 + WIN_TITLE_H;
    *cw  = w->w - 4;
    *ch  = w->h - 4 - WIN_TITLE_H;
}

/* ── Paint state ──────────────────────────────────────────────────────
 * Draw-only (no save/load) - unrelated to AxFiles' read-only disk
 * access below (fat12_shell.o + ide_read_sector()); adding a save path
 * here would still need fat12_write, which is compiled out of this
 * image (FAT12_NO_WRITE, see build.bat) to avoid pulling in the main
 * kernel's print_string/print_uint at link time - out of scope for
 * this round. Canvas lives in its own fixed-address buffer, NOT in BACKBUF -
 * BACKBUF gets fully overwritten every frame by whichever screen's
 * render function runs (this file has no dirty-rect/partial-redraw
 * concept), so painted pixels can't persist there across frames. Address
 * chosen clear of BACKBUF's own range (0x200000..~0x3D4C00) - same
 * "fixed address, not .bss" reasoning as BACKBUF itself: nothing else in
 * this standalone image ever touches it. */
#define PAINT_TOOLBAR_H 36
#define PAINT_CANVAS_H  (AREA_H - PAINT_TOOLBAR_H)
#define PAINT_CANVAS ((unsigned int *)0x400000)
#define PAINT_BRUSH  6   /* matches RISC-V AxPaint's own BRUSH=6 square dab */

static int     paint_ready = 0;   /* canvas white-filled once, not on every screen switch - drawing persists */
static color_t paint_color = C_RED;
static const color_t paint_palette[6] = { C_BLACK, C_RED, C_YELLOW, C_GREEN, C_BLUE, C_WHITE };
static int     paint_sel = 1;     /* index into paint_palette - starts on C_RED, matching paint_color above */
static int     paint_prev_mx = -1, paint_prev_my = -1;   /* last painted point, for drag line-interpolation */

/* Terminal state */
#define TROWS 16
#define TCOLS 38
static char tlines[TROWS][TCOLS+1];
static int  trow = 0;
static char tinput[TCOLS+1];
static int  tinlen = 0;
static unsigned long blink_timer = 0;

static void tscroll(void) {
    for (int r=0; r<TROWS-1; r++) {
        int c;
        for (c=0; c<=TCOLS; c++) tlines[r][c] = tlines[r+1][c];
    }
    for (int c=0; c<=TCOLS; c++) tlines[TROWS-1][c] = 0;
    trow = TROWS-1;
}

static void tputs(const char *s) {
    if (trow >= TROWS) tscroll();
    int col = 0;
    while (*s && col < TCOLS) tlines[trow][col++] = *s++;
    tlines[trow][col] = 0;
    trow++;
}

static int cmd_eq(const char *buf, int blen, const char *s, int slen) {
    if (blen != slen) return 0;
    for (int i = 0; i < slen; i++) if (buf[i] != s[i]) return 0;
    return 1;
}

static void trun(void) {
    /* echo the command */
    char buf[TCOLS+1];
    int bi=0;
    const char *pr = "> ";
    while (*pr && bi < TCOLS) buf[bi++] = *pr++;
    for (int i=0; i<tinlen && bi<TCOLS; i++) buf[bi++] = tinput[i];
    buf[bi] = 0;
    tputs(buf);

    /* parse command (simple exact matches) */
    int l = tinlen;
    char *in = tinput;
    /* Manual exact-match: compare all chars */
    #define CMD(s) cmd_eq(in, l, s, sizeof(s)-1)

    if (l == 0) { /* empty */ }
    else if (CMD("help")) {
        tputs("Commands: help  date  ver  cls  exit");
    }
    else if (CMD("cls") || CMD("clear")) {
        for (int r=0; r<TROWS; r++) { tlines[r][0]=0; }
        trow = 0;
    }
    else if (CMD("date")) {
        int h,m,s; rtc_time(&h,&m,&s);
        char tb[17];
        tb[0]='T'; tb[1]='i'; tb[2]='m'; tb[3]='e'; tb[4]=':'; tb[5]=' ';
        tb[6]='0'+h/10; tb[7]='0'+h%10; tb[8]=':';
        tb[9]='0'+m/10; tb[10]='0'+m%10; tb[11]=':';
        tb[12]='0'+s/10; tb[13]='0'+s%10; tb[14]=0;
        tputs(tb);
    }
    else if (CMD("ver")) {
        tputs("AxOS v0.1  x86 Protected Mode");
        tputs("Graphical Shell v2.0 - VBE truecolor");
    }
    else if (CMD("exit")) {
        win_close(WIN_TERM);
    }
    else {
        tputs("Unknown. Try: help");
    }

    /* clear input */
    for (int i=0; i<=TCOLS; i++) tinput[i] = 0;
    tinlen = 0;
}

/* ── Rendering ─────────────────────────────────────────────────────── */

static void draw_titlebar(const char *title) {
    vgrad(0, 0, SW, TBAR_H, C_NAVY_LT, C_NAVY);
    hline(0, TBAR_H-1, SW, C_BLUE);  /* bright bottom line */
    /* AxOS logo (left) */
    text(8, 4, "AxOS", C_CYAN);
    /* vertical separator */
    glyph(72, 4, '|', C_DGRAY);
    /* title (center) */
    text_center(SW/2, 4, title, C_WHITE);
    /* time (right): HH:MM:SS = 8 chars x CHAR_W px */
    int h,m,s; rtc_time(&h,&m,&s);
    int cx = SW - 16 - 8*CHAR_W;
    draw_num2(cx, 4, h, C_YELLOW);
    glyph(cx+2*CHAR_W, 4, ':', C_YELLOW);
    draw_num2(cx+3*CHAR_W, 4, m, C_YELLOW);
    glyph(cx+5*CHAR_W, 4, ':', C_YELLOW);
    draw_num2(cx+6*CHAR_W, 4, s, C_YELLOW);
}

static void draw_taskbar(const char *mode) {
    vgrad(0, BBAR_Y, SW, BBAR_H, C_GRAY, C_DGRAY);
    hline(0, BBAR_Y, SW, C_GRAY_LT);   /* bright top highlight */
    text(8, BBAR_Y+4, "AxOS", C_CYAN);
    glyph(72, BBAR_Y+4, '|', C_WHITE);
    text(88, BBAR_Y+4, mode, C_WHITE);
}

/* ── Desktop ─────────────────────────────────────────────────────── */

#define ICON_R 14   /* corner radius */

/* Draw one icon; highlight if mouse hovers over it */
static void draw_icon(const struct icon *ic, int mx, int my) {
    int hover = (mx >= ic->x && mx < ic->x+ic->w &&
                 my >= ic->y && my < ic->y+ic->h);
    color_t bg  = hover ? C_CYAN  : ic->color;
    color_t fg  = hover ? C_BLACK : C_WHITE;
    color_t brd = hover ? C_WHITE : C_BLUE;

    /* Soft drop shadow first (into the gradient behind), then the
     * rounded card on top - hovering lifts the shadow further out to
     * read as "this one's raised/active". */
    shadow_round(ic->x, ic->y, ic->w, ic->h, ICON_R, hover ? 8 : 5);
    card_round(ic->x, ic->y, ic->w, ic->h, ICON_R, bg, brd);

    /* Inner symbol: настоящая BMP-иконка (см. icons_data.h/bmp.h) вместо
     * ASCII-символов ">"/"?", что рисовались тут раньше. Декодируется
     * один раз (кэш в static bmp_image_t) - не при каждом кадре. */
    static bmp_image_t icon_term_img, icon_about_img, icon_paint_img;
    static int icons_ready = 0;
    if (!icons_ready) {
        bmp_decode(term_bmp_data, term_bmp_size, &icon_term_img);
        bmp_decode(about_bmp_data, about_bmp_size, &icon_about_img);
        bmp_decode(paint_bmp_data, paint_bmp_size, &icon_paint_img);
        icons_ready = 1;
    }
    /* AxFiles (SCR_FILES) has no BMP asset - card + label only, no
     * pixel art in scope for this feature. */
    const bmp_image_t *icon_img = (ic->dst == SCR_TERMINAL) ? &icon_term_img :
                                   (ic->dst == SCR_ABOUT)    ? &icon_about_img :
                                   (ic->dst == SCR_PAINT)    ? &icon_paint_img :
                                                                0;
    if (icon_img) bmp_draw(icon_img, ic->x + (ic->w - icon_img->width)/2, ic->y + 16);

    /* Label below icon */
    text_center(ic->x + ic->w/2, ic->y + ic->h - 20, ic->label, fg);
}

static void render_desktop(int mx, int my) {
    /* Background: navy gradient (was flat - a palette couldn't afford
     * in-between shades, truecolor can) with a subtle dot pattern */
    vgrad(0, AREA_Y, SW, AREA_H, C_NAVY, C_NAVY_DK);
    /* Dot grid (decorative), faded in via low-alpha blend instead of a
     * flat opaque color - softer against the gradient than a hard dot */
    for (int y = AREA_Y+16; y < BBAR_Y-16; y += 32)
        for (int x = 16; x < SW-16; x += 32)
            blend_px(x, y, C_WHITE, 40);

    draw_titlebar("Desktop");

    for (int i=0; i<N_ICONS; i++)
        draw_icon(&icons[i], mx, my);

    /* Hint text */
    text_center(SW/2, BBAR_Y-36, "Click an icon to open it", C_DGRAY);

    draw_taskbar("Desktop Mode");
}

/* ── Terminal screen ─────────────────────────────────────────────── */
/* (cx0,cy0,cw,ch) is the CONTENT area - inside the window, below its own
 * mini titlebar (drawn separately by render_window_chrome()). Used to be
 * a full-screen mode with its own screen-wide backdrop/titlebar/taskbar -
 * now just draws into whatever rect the window manager hands it. */
static void render_terminal(int cx0, int cy0, int cw, int ch) {
    (void)ch;
    int tx = cx0 + CARD_PAD;
    int ty = cy0 + CARD_PAD;

    /* Text area: one row per CHAR_W*2 (font height) px */
    for (int r=0; r<TROWS; r++) {
        if (tlines[r][0])
            text(tx, ty + r*CHAR_W, tlines[r], C_GREEN);
    }

    /* Input line (below the text block), spans the window's own width */
    int inpy = ty + TROWS*CHAR_W;
    int inx0 = cx0 + 3, inw = cw - 6;
    fill(inx0, inpy, inw, CHAR_W+2, C_DGRAY);
    hline(inx0, inpy, inw, C_GRAY);
    text(tx, inpy+2, ">", C_YELLOW);
    if (tinlen > 0) text(tx+2*CHAR_W, inpy+2, tinput, C_WHITE);

    /* Blinking cursor */
    blink_timer++;
    if ((blink_timer >> 14) & 1)
        fill(tx+2*CHAR_W + tinlen*CHAR_W, inpy+2, CHAR_W-4, CHAR_W, C_WHITE);

    /* "[exit]" hint, right-aligned within the window */
    text(cx0+cw-CARD_PAD - 6*CHAR_W, inpy+2, "[exit]", C_DGRAY);
}

/* ── About screen ─────────────────────────────────────────────────── */
static void render_about(int cx0, int cy0, int cw, int ch) {
    (void)ch;
    int cxmid = cx0 + cw/2;
    int y = cy0 + CARD_PAD;

    /* ASCII art logo */
    text_center(cxmid, y,    " _  _ ", C_CYAN);   y += CHAR_W;
    text_center(cxmid, y,    "/_\\\\\\  ___", C_CYAN); y += CHAR_W;
    text_center(cxmid, y,    "/ _ \\\\/ __ \\\\", C_CYAN); y += CHAR_W;
    text_center(cxmid, y,    "/_/ \\\\_\\\\____/", C_CYAN); y += CHAR_W;
    y += CHAR_W/2;

    text_center(cxmid, y, "AxOS  v0.1", C_WHITE);   y += CHAR_W+4;
    text_center(cxmid, y, "x86 Protected Mode", C_GRAY); y += CHAR_W+4;
    text_center(cxmid, y, "VBE LFB  800x600x32  truecolor", C_GRAY); y += CHAR_W+4;
    text_center(cxmid, y, "Graphical Shell  v2.0", C_GRAY); y += CHAR_W+10;

    text_center(cxmid, y, "Made by Maxim", C_YELLOW); y += CHAR_W+4;
    text_center(cxmid, y, "Age 11", C_YELLOW); y += CHAR_W+10;

    /* Feature list */
    int fx = cx0 + CARD_PAD + 26;
    text(fx, y, "+ Preemptive multitasking",  C_GREEN);  y += CHAR_W+2;
    text(fx, y, "+ ELF32 loader + FAT12 FS",  C_GREEN);  y += CHAR_W+2;
    text(fx, y, "+ SMEP / SMAP / W^X / CFI",  C_GREEN);  y += CHAR_W+2;
    text(fx, y, "+ User shell (sh.c) + GUI",   C_GREEN);  y += CHAR_W+2;
}

/* ── Files (AxFiles) state ────────────────────────────────────────────
 * File manager window: lists FAT12 root-directory files
 * (fat12_readdir), previews one file's raw content as text
 * (fat12_load), and can delete a file (fat12_delete, with a confirm
 * step) - no rename/edit/write-new-content, that's still out of scope
 * (see FAT12_NO_WRITE in build.bat's Graphical Shell section, which
 * still compiles fat12_write/mkdir/list/cat out of fat12_shell.o;
 * fat12_delete itself is NOT under that guard, see src/fs/fat12.c). */
#define FILES_MAX 64   /* FAT12 root-directory entry cap, see make_fat12.py */
static int  fat12_ok;
static int  files_count;
static char files_names[FILES_MAX][13];
static unsigned int files_sizes[FILES_MAX];
static int  files_scroll;
static int  files_preview_mode;
static int  files_confirm_delete;   /* showing "Delete FOO.BIN? [Yes] [No]" for files_preview_name */

static void files_scan(void) {
    files_count = 0;
    int is_dir;
    while (files_count < FILES_MAX &&
           fat12_readdir((unsigned int)files_count, files_names[files_count],
                          &files_sizes[files_count], &is_dir))
        files_count++;
}

#define FILES_PREVIEW_MAX 4096
static char          files_preview_name[13];
static unsigned char files_preview_buf[FILES_PREVIEW_MAX];
static unsigned int  files_preview_len;
static int           files_preview_truncated;
static int           files_preview_scroll;

/* Loads the file at files_names[idx] into the preview buffer and flips
 * into preview mode. Large files get a visible "(truncated)" marker
 * rather than growing the buffer - this is a preview, not a full
 * editor (v1 scope). idx comes straight from a row click, so the size
 * is already cached in files_sizes[] - no need to re-look-up by name. */
static void files_open_preview(int idx) {
    int i = 0;
    for (; files_names[idx][i] && i < 12; i++) files_preview_name[i] = files_names[idx][i];
    files_preview_name[i] = 0;
    files_preview_len = fat12_load(files_names[idx], files_preview_buf, FILES_PREVIEW_MAX);
    files_preview_truncated = (files_preview_len < files_sizes[idx]);
    files_preview_scroll = 0;
    files_preview_mode = 1;
}

static int udigits(unsigned int v) {
    int n = 1;
    while (v >= 10) { v /= 10; n++; }
    return n;
}
static void draw_uint(int x, int y, unsigned int v, color_t fg) {
    char buf[11];
    int n = udigits(v);
    buf[n] = 0;
    for (int i = n - 1; i >= 0; i--) { buf[i] = (char)('0' + v % 10); v /= 10; }
    text(x, y, buf, fg);
}
static void draw_uint_right(int x_right, int y, unsigned int v, color_t fg) {
    draw_uint(x_right - udigits(v) * CHAR_W, y, v, fg);
}

#define FILES_PAD   10
#define FILES_ROW_H CHAR_W
#define FILES_BTN_W (3*CHAR_W)   /* "[^]"/"[v]" */

/* List-mode row/button geometry - shared by render_files() and
 * handle_files_content_click() so hit-testing can't drift from what's
 * actually drawn (win_content_rect() plays the same role one level up,
 * for the window itself). */
static void files_layout(int cx0, int cy0, int cw, int ch,
                          int *list_y0, int *visible_rows,
                          int *up_x, int *down_x, int *btn_y, int *size_right) {
    int header_y = cy0 + FILES_PAD;
    *down_x = cx0 + cw - FILES_PAD - FILES_BTN_W;
    *up_x   = *down_x - FILES_BTN_W - 8;
    *btn_y  = header_y;
    *size_right = *up_x - 16;
    *list_y0 = header_y + FILES_ROW_H + 6;
    *visible_rows = (cy0 + ch - FILES_PAD - *list_y0) / FILES_ROW_H;
    if (*visible_rows < 0) *visible_rows = 0;
}

static void render_files_list(int cx0, int cy0, int cw, int ch) {
    int x = cx0 + FILES_PAD;
    int y = cy0 + FILES_PAD;

    if (!fat12_ok) { text(x, y, "Disk not ready", C_GRAY); return; }
    if (files_count == 0) { text(x, y, "(no files)", C_GRAY); return; }

    int list_y0, visible_rows, up_x, down_x, btn_y, size_right;
    files_layout(cx0, cy0, cw, ch, &list_y0, &visible_rows, &up_x, &down_x, &btn_y, &size_right);

    text(x, y, "NAME", C_CYAN);
    text(size_right - 4*CHAR_W, y, "SIZE", C_CYAN);
    text(up_x,   btn_y, "[^]", C_WHITE);
    text(down_x, btn_y, "[v]", C_WHITE);
    hline(x, list_y0 - 4, cw - 2*FILES_PAD, C_GRAY);

    int max_scroll = files_count - visible_rows;
    if (max_scroll < 0) max_scroll = 0;
    if (files_scroll > max_scroll) files_scroll = max_scroll;
    if (files_scroll < 0) files_scroll = 0;

    for (int i = 0; i < visible_rows && files_scroll + i < files_count; i++) {
        int idx = files_scroll + i;
        int ry = list_y0 + i * FILES_ROW_H;
        text(x, ry, files_names[idx], C_GREEN);
        draw_uint_right(size_right, ry, files_sizes[idx], C_GRAY);
    }
}

/* Preview-mode header/text-area geometry - shared with the click
 * handler's "[< Back]" hit-test, same reasoning as files_layout(). */
static void files_preview_layout(int cx0, int cy0, int cw, int ch,
                                  int *back_x, int *back_y,
                                  int *text_y0, int *visible_rows, int *max_cols) {
    *back_x = cx0 + FILES_PAD;
    *back_y = cy0 + FILES_PAD;
    *text_y0 = *back_y + FILES_ROW_H + 6;
    *visible_rows = (cy0 + ch - FILES_PAD - *text_y0) / FILES_ROW_H;
    if (*visible_rows < 0) *visible_rows = 0;
    *max_cols = (cw - 2*FILES_PAD) / CHAR_W;
    if (*max_cols > TCOLS) *max_cols = TCOLS;
    if (*max_cols < 1) *max_cols = 1;
}

static void render_files_preview(int cx0, int cy0, int cw, int ch) {
    int back_x, back_y, text_y0, visible_rows, max_cols;
    files_preview_layout(cx0, cy0, cw, ch, &back_x, &back_y, &text_y0, &visible_rows, &max_cols);

    text(back_x, back_y, "[< Back]", C_YELLOW);
    text(back_x + 9*CHAR_W, back_y, files_preview_name, C_WHITE);
    /* "[Delete]" is the same 8-char width as "[< Back]" - right-align it
     * in the same header row, same reasoning files_layout() already
     * uses for the list view's [^]/[v] buttons. */
    text(cx0 + cw - FILES_PAD - 8*CHAR_W, back_y, "[Delete]", C_RED);
    hline(cx0 + FILES_PAD, text_y0 - 4, cw - 2*FILES_PAD, C_GRAY);

    /* Walk the raw buffer from the start every frame (cheap - matches
     * this file's own full-redraw-every-frame philosophy, see the
     * window-manager comment up top), breaking on '\n' and hard-wrapping
     * long runs at max_cols, skipping files_preview_scroll lines. */
    int line = 0, drawn = 0, col = 0;
    char linebuf[TCOLS+1];
    unsigned int i = 0;
    while (i <= files_preview_len) {
        int is_end     = (i == files_preview_len);
        unsigned char c = is_end ? 0 : files_preview_buf[i];
        int is_newline = (!is_end) && (c == '\n');
        int is_wrap    = (!is_end) && (!is_newline) && (col >= max_cols);

        if (is_wrap) {
            linebuf[col] = 0;
            if (line >= files_preview_scroll && drawn < visible_rows) {
                text(cx0 + FILES_PAD, text_y0 + drawn*FILES_ROW_H, linebuf, C_GREEN);
                drawn++;
            }
            line++; col = 0;
            continue;   /* i unchanged - byte i starts the fresh line */
        }

        if (is_newline || is_end) {
            linebuf[col] = 0;
            if (line >= files_preview_scroll && drawn < visible_rows) {
                text(cx0 + FILES_PAD, text_y0 + drawn*FILES_ROW_H, linebuf, C_GREEN);
                drawn++;
            }
            line++; col = 0; i++;
            if (is_end) break;
            continue;
        }

        linebuf[col++] = (char)c;
        i++;
    }
    if (files_preview_truncated && drawn < visible_rows)
        text(cx0 + FILES_PAD, text_y0 + drawn*FILES_ROW_H, "(truncated)", C_YELLOW);
}

/* Delete-confirm geometry - shared with the click handler's [Yes]/[No]
 * hit-test, same reasoning as files_layout()/files_preview_layout(). */
static void files_confirm_layout(int cx0, int cy0, int *yes_x, int *no_x, int *btn_y) {
    *yes_x = cx0 + FILES_PAD;
    *no_x  = *yes_x + 6*CHAR_W + 16;
    *btn_y = cy0 + FILES_PAD + FILES_ROW_H + 10;
}

static void render_files_confirm_delete(int cx0, int cy0, int cw, int ch) {
    (void)ch;
    int yes_x, no_x, btn_y;
    files_confirm_layout(cx0, cy0, &yes_x, &no_x, &btn_y);

    char msg[13+10];
    int p = 0;
    const char *pre = "Delete ";
    while (pre[p]) { msg[p] = pre[p]; p++; }
    for (int i = 0; files_preview_name[i] && p < (int)sizeof(msg)-2; i++) msg[p++] = files_preview_name[i];
    msg[p++] = '?';
    msg[p] = 0;
    text(cx0 + FILES_PAD, cy0 + FILES_PAD, msg, C_YELLOW);

    text(yes_x, btn_y, "[Yes]", C_RED);
    text(no_x,  btn_y, "[No]",  C_WHITE);
}

static void render_files(int cx0, int cy0, int cw, int ch) {
    if (files_confirm_delete)      render_files_confirm_delete(cx0, cy0, cw, ch);
    else if (files_preview_mode)   render_files_preview(cx0, cy0, cw, ch);
    else                           render_files_list(cx0, cy0, cw, ch);
}

/* ── Window chrome (shared by Terminal + About) ─────────────────────
 * Shadow + rounded body (reusing the same card_round() the old
 * full-screen "cards" used) + a mini titlebar strip with a close button -
 * RISC-V's window.h equivalent, drawn at full quality every single frame
 * (see the file-top comment on why that's cheap here, unlike RISC-V). */
static void render_window_chrome(int idx, const char *title) {
    win_t *w = &windows[idx];
    shadow_round(w->x, w->y, w->w, w->h, CARD_R, 6);
    card_round(w->x, w->y, w->w, w->h, CARD_R, C_CARD_BG, C_CARD_BRD);

    /* Titlebar strip inset 2px to match card_round()'s own border inset,
     * so it doesn't poke through the rounded corners. */
    vgrad(w->x+2, w->y+2, w->w-4, WIN_TITLE_H, C_NAVY_LT, C_NAVY);
    hline(w->x+2, w->y+2+WIN_TITLE_H-1, w->w-4, C_BLUE);
    text(w->x+10, w->y+2+(WIN_TITLE_H-CHAR_W)/2, title, C_WHITE);

    /* Close button: red square + white X, matching RISC-V's window.h
     * close-button visual convention for cross-platform consistency. */
    int bx = w->x + w->w - WIN_CLOSE_SZ - 6;
    int by = w->y + (WIN_TITLE_H - WIN_CLOSE_SZ) / 2;
    fill(bx, by, WIN_CLOSE_SZ, WIN_CLOSE_SZ, C_RED);
    hline(bx, by, WIN_CLOSE_SZ, C_WHITE);
    hline(bx, by+WIN_CLOSE_SZ-1, WIN_CLOSE_SZ, C_WHITE);
    vline(bx, by, WIN_CLOSE_SZ, C_WHITE);
    vline(bx+WIN_CLOSE_SZ-1, by, WIN_CLOSE_SZ, C_WHITE);
    for (int i = 2; i < WIN_CLOSE_SZ-2; i++) {
        px(bx+i, by+i, C_WHITE);
        px(bx+i, by+WIN_CLOSE_SZ-1-i, C_WHITE);
    }
}

/* ── Paint screen ────────────────────────────────────────────────── */

/* Swatch hit-box geometry - shared between drawing and click detection. */
#define SWATCH_SZ  24
#define SWATCH_GAP 4
#define SWATCH_X0  16
#define SWATCH_Y   (AREA_Y + (PAINT_TOOLBAR_H - SWATCH_SZ)/2)
static int swatch_x(int i) { return SWATCH_X0 + i*(SWATCH_SZ+SWATCH_GAP); }

/* CLEAR button hit-box - right-aligned text in the toolbar strip. */
#define CLEAR_LABEL   "CLEAR"
#define CLEAR_W       (5*CHAR_W)
#define CLEAR_X       (SW - 16 - CLEAR_W)
#define CLEAR_Y       (AREA_Y + (PAINT_TOOLBAR_H - CHAR_W)/2)

static void canvas_clear(void) {
    unsigned int *c = PAINT_CANVAS;
    for (int i = 0; i < SW*PAINT_CANVAS_H; i++) c[i] = C_WHITE;
}

/* One brush dab (filled PAINT_BRUSH x PAINT_BRUSH square), centered on
 * canvas-local (cx,cy). Writes straight into PAINT_CANVAS, not through
 * px()/fill() (those target BACKBUF, which gets discarded every frame). */
static void canvas_dot(int cx, int cy, color_t c) {
    int x0 = cx - PAINT_BRUSH/2, y0 = cy - PAINT_BRUSH/2;
    for (int dy = 0; dy < PAINT_BRUSH; dy++) {
        int y = y0+dy;
        if ((unsigned)y >= (unsigned)PAINT_CANVAS_H) continue;
        for (int dx = 0; dx < PAINT_BRUSH; dx++) {
            int x = x0+dx;
            if ((unsigned)x >= (unsigned)SW) continue;
            PAINT_CANVAS[y*SW+x] = c;
        }
    }
}

/* Steps brush dabs along the straight line from (x0,y0) to (x1,y1) -
 * the PS/2 mouse driver only reports position on an 80x25 grid, scaled
 * x10/x24 to screen coords (see gfx_main()), so consecutive frames during
 * a drag can be 10-24px apart - a single dab per frame would leave visible
 * gaps. Step size = PAINT_BRUSH/2 keeps dabs overlapping along the path. */
static void canvas_paint_line(int x0, int y0, int x1, int y1, color_t c) {
    int dx = x1-x0, dy = y1-y0;
    int dist = dx<0?-dx:dx; int ady = dy<0?-dy:dy;
    if (ady > dist) dist = ady;
    int steps = dist / (PAINT_BRUSH/2);
    if (steps < 1) steps = 1;
    for (int i = 0; i <= steps; i++) {
        int x = x0 + dx*i/steps;
        int y = y0 + dy*i/steps;
        canvas_dot(x, y, c);
    }
}

static void render_paint(void) {
    if (!paint_ready) { canvas_clear(); paint_ready = 1; }

    draw_titlebar("Paint");

    /* Blit the persistent canvas into the back buffer at its screen
     * offset - mirrors blit()'s own row-by-row shape. */
    int cy0 = AREA_Y + PAINT_TOOLBAR_H;
    for (int y = 0; y < PAINT_CANVAS_H; y++) {
        unsigned int *src = PAINT_CANVAS + y*SW;
        for (int x = 0; x < SW; x++) px(x, cy0+y, src[x]);
    }

    /* Toolbar drawn ON TOP of the blitted canvas each frame - never
     * written into PAINT_CANVAS itself, so this is safe (same reasoning
     * as the cursor being redrawn fresh over the back buffer every frame
     * instead of persisted). */
    vgrad(0, AREA_Y, SW, PAINT_TOOLBAR_H, C_GRAY_LT, C_GRAY);
    hline(0, AREA_Y+PAINT_TOOLBAR_H-1, SW, C_DGRAY);

    for (int i = 0; i < 6; i++) {
        int sx = swatch_x(i);
        int selected = (i == paint_sel);
        fill(sx, SWATCH_Y, SWATCH_SZ, SWATCH_SZ, paint_palette[i]);
        color_t brd = selected ? C_WHITE : C_DGRAY;
        hline(sx, SWATCH_Y, SWATCH_SZ, brd);
        hline(sx, SWATCH_Y+SWATCH_SZ-1, SWATCH_SZ, brd);
        vline(sx, SWATCH_Y, SWATCH_SZ, brd);
        vline(sx+SWATCH_SZ-1, SWATCH_Y, SWATCH_SZ, brd);
        if (selected) {
            hline(sx-2, SWATCH_Y-2, SWATCH_SZ+4, C_WHITE);
            hline(sx-2, SWATCH_Y+SWATCH_SZ+1, SWATCH_SZ+4, C_WHITE);
            vline(sx-2, SWATCH_Y-2, SWATCH_SZ+4, C_WHITE);
            vline(sx+SWATCH_SZ+1, SWATCH_Y-2, SWATCH_SZ+4, C_WHITE);
        }
    }

    text(CLEAR_X, CLEAR_Y, CLEAR_LABEL, C_WHITE);

    draw_taskbar("Paint  (right-click=clear, ESC=exit)");
}

/* ── Cursor ──────────────────────────────────────────────────────── */
/* 8x8 arrow cursor bitmap, tip at (0,0) top-left, rendered at 2x for
 * visibility on the bigger canvas (matches FONT_SCALE). */
#define CURSOR_SCALE 2
static const unsigned char cursor_bmp[8] = {
    0x80, /* 10000000  X....... */
    0xC0, /* 11000000  XX...... */
    0xE0, /* 11100000  XXX..... */
    0xF0, /* 11110000  XXXX.... */
    0xF8, /* 11111000  XXXXX... */
    0xFC, /* 11111100  XXXXXX.. */
    0xFE, /* 11111110  XXXXXXX. */
    0x00,
};
#define CURSOR_PX (8*CURSOR_SCALE)
static color_t cursor_save[CURSOR_PX*CURSOR_PX];

static void cursor_draw(int cx, int cy) {
    int i=0;
    for (int r=0; r<CURSOR_PX; r++) for (int c=0; c<CURSOR_PX; c++) {
        int xx=cx+c, yy=cy+r;
        cursor_save[i++] = ((unsigned)xx<SW && (unsigned)yy<SH) ? BACKBUF[yy*SW+xx] : 0;
        if (cursor_bmp[r/CURSOR_SCALE] & (0x80>>(c/CURSOR_SCALE))) px(xx, yy, C_WHITE);
    }
}
static void cursor_erase(int cx, int cy) {
    int i=0;
    for (int r=0; r<CURSOR_PX; r++) for (int c=0; c<CURSOR_PX; c++) px(cx+c, cy+r, cursor_save[i++]);
}

/* ── AxFiles content clicks (row select / [^]/[v] paging / [< Back]) ─
 * Reuses files_layout()/files_preview_layout() - the exact geometry
 * render_files() just drew - so hit-testing can never drift from what
 * the user sees. */
static void handle_files_content_click(int mx, int my) {
    int cx0, cy0, cw, ch;
    win_content_rect(WIN_FILES, &cx0, &cy0, &cw, &ch);

    if (files_confirm_delete) {
        int yes_x, no_x, btn_y;
        files_confirm_layout(cx0, cy0, &yes_x, &no_x, &btn_y);
        if (my >= btn_y && my < btn_y + FILES_ROW_H) {
            if (mx >= yes_x && mx < yes_x + 5*CHAR_W) {
                fat12_delete(files_preview_name);
                files_scan();   /* refresh from disk - the deleted file must actually disappear */
                files_confirm_delete = 0;
                files_preview_mode = 0;
            } else if (mx >= no_x && mx < no_x + 4*CHAR_W) {
                files_confirm_delete = 0;
            }
        }
        return;
    }

    if (files_preview_mode) {
        int back_x, back_y, text_y0, visible_rows, max_cols;
        files_preview_layout(cx0, cy0, cw, ch, &back_x, &back_y, &text_y0, &visible_rows, &max_cols);
        if (mx >= back_x && mx < back_x + 8*CHAR_W &&
            my >= back_y && my < back_y + FILES_ROW_H) {
            files_preview_mode = 0;
            return;
        }
        int del_x = cx0 + cw - FILES_PAD - 8*CHAR_W;
        if (mx >= del_x && mx < del_x + 8*CHAR_W &&
            my >= back_y && my < back_y + FILES_ROW_H) {
            files_confirm_delete = 1;
        }
        return;
    }

    if (!fat12_ok || files_count == 0) return;

    int list_y0, visible_rows, up_x, down_x, btn_y, size_right;
    files_layout(cx0, cy0, cw, ch, &list_y0, &visible_rows, &up_x, &down_x, &btn_y, &size_right);

    if (my >= btn_y && my < btn_y + FILES_ROW_H) {
        if (mx >= up_x && mx < up_x + FILES_BTN_W) {
            files_scroll -= visible_rows;
            if (files_scroll < 0) files_scroll = 0;
            return;
        }
        if (mx >= down_x && mx < down_x + FILES_BTN_W) {
            files_scroll += visible_rows;   /* clamped in render_files_list() */
            return;
        }
    }

    if (my >= list_y0) {
        int row = (my - list_y0) / FILES_ROW_H;
        int idx = files_scroll + row;
        if (row < visible_rows && idx < files_count) files_open_preview(idx);
    }
}

/* ── Mouse click detection ───────────────────────────────────────── */
static int prev_btn = 0;

static void handle_click(int mx, int my) {
    int btn = mouse_get_buttons() & 0x01;
    if (btn && !prev_btn) {
        /* Left click: fire */
        if (scr == SCR_DESKTOP) {
            int hit = win_topmost_at(mx, my);
            if (hit >= 0) {
                /* Focus-follows-click - even a plain content click raises
                 * the window, matching conventional WM behavior. */
                win_raise(hit);
                if (win_hit_close(hit, mx, my)) {
                    win_close(hit);
                } else if (win_hit_titlebar(hit, mx, my)) {
                    dragging_win = hit;
                    drag_off_x = mx - windows[hit].x;
                    drag_off_y = my - windows[hit].y;
                } else if (hit == WIN_FILES) {
                    handle_files_content_click(mx, my);
                }
                /* else: click landed in the window's content - no
                 * per-content click handling needed for Terminal/About. */
            } else {
                for (int i=0; i<N_ICONS; i++) {
                    if (mx >= icons[i].x && mx < icons[i].x+icons[i].w &&
                        my >= icons[i].y && my < icons[i].y+icons[i].h) {
                        if (icons[i].dst == SCR_TERMINAL) {
                            int was_open = windows[WIN_TERM].open;
                            win_open(WIN_TERM);
                            if (!was_open) {
                                tputs("AxOS Terminal v1.0");
                                tputs("Type 'help' for commands.");
                                tputs("");
                            }
                        } else if (icons[i].dst == SCR_ABOUT) {
                            win_open(WIN_ABOUT);
                        } else if (icons[i].dst == SCR_PAINT) {
                            scr = SCR_PAINT;   /* unchanged - Paint stays full-screen */
                        } else if (icons[i].dst == SCR_FILES) {
                            int was_open = windows[WIN_FILES].open;
                            win_open(WIN_FILES);
                            if (!was_open) {
                                files_preview_mode = 0;
                                files_scroll = 0;
                            }
                        }
                    }
                }
            }
        } else if (scr == SCR_PAINT) {
            for (int i = 0; i < 6; i++) {
                int sx = swatch_x(i);
                if (mx >= sx && mx < sx+SWATCH_SZ &&
                    my >= SWATCH_Y && my < SWATCH_Y+SWATCH_SZ) {
                    paint_sel   = i;
                    paint_color = paint_palette[i];
                }
            }
            if (mx >= CLEAR_X && mx < CLEAR_X+CLEAR_W &&
                my >= CLEAR_Y && my < CLEAR_Y+CHAR_W) {
                canvas_clear();
            }
        }
    }
    prev_btn = btn;
}

/* ── Paint drag/clear (held-button, not click-edge - unlike handle_click
 * above) ─────────────────────────────────────────────────────────── */
static void handle_paint_drag(int mx, int my) {
    if (scr != SCR_PAINT) { paint_prev_mx = -1; paint_prev_my = -1; return; }

    int buttons = mouse_get_buttons();
    int in_canvas = (my >= AREA_Y + PAINT_TOOLBAR_H && my < BBAR_Y);

    if ((buttons & 0x02) && in_canvas) {   /* right button: clear */
        canvas_clear();
        paint_prev_mx = -1; paint_prev_my = -1;
        return;
    }

    if ((buttons & 0x01) && in_canvas) {
        int cx = mx, cy = my - (AREA_Y + PAINT_TOOLBAR_H);
        if (paint_prev_mx >= 0) {
            canvas_paint_line(paint_prev_mx, paint_prev_my, cx, cy, paint_color);
        } else {
            canvas_dot(cx, cy, paint_color);
        }
        paint_prev_mx = cx; paint_prev_my = cy;
    } else {
        paint_prev_mx = -1; paint_prev_my = -1;   /* stroke ended - next press starts fresh, no stale line-back */
    }
}

/* ── Window drag (held-button, mirrors handle_paint_drag's shape) ──── */
static void handle_window_drag(int mx, int my) {
    if (scr != SCR_DESKTOP || dragging_win < 0) return;
    int btn = mouse_get_buttons() & 0x01;
    if (!btn) { dragging_win = -1; return; }

    win_t *w = &windows[dragging_win];
    int nx = mx - drag_off_x, ny = my - drag_off_y;
    if (nx < 0) nx = 0;
    if (nx + w->w > SW) nx = SW - w->w;
    if (ny < AREA_Y) ny = AREA_Y;
    if (ny + w->h > BBAR_Y) ny = BBAR_Y - w->h;
    w->x = nx; w->y = ny;
}

/* ── Keyboard input (terminal only) ──────────────────────────────── */
static int esc_down = 0;   /* edge-detect: typematic repeat on a held ESC
                             * must not cascade-close more than one window
                             * per physical press, same idea as the mouse's
                             * prev_btn edge-detection above. */
static void handle_keys(void) {
    unsigned char sc;
    while (kbd_get(&sc)) {
        if (sc == 0x01) { /* ESC make (incl. typematic repeat) */
            if (!esc_down) {
                esc_down = 1;
                if (scr == SCR_PAINT) {
                    scr = SCR_DESKTOP;
                } else if (scr == SCR_DESKTOP) {
                    int top = win_focused();
                    if (top == WIN_FILES && files_preview_mode) {
                        /* Back out of preview first - closing outright
                         * would lose the "which file" context for no
                         * reason, matching the [< Back] button. */
                        files_preview_mode = 0;
                    } else if (top >= 0) {
                        /* Closes the focused window, matching its own
                         * close button - no-op if nothing is open. */
                        win_close(top);
                    }
                }
            }
            return;
        }
        if (sc == 0x81) { /* ESC break */
            esc_down = 0;
            return;
        }
        /* Character input only reaches Terminal when it's the focused
         * window - standard "only the focused window gets keyboard
         * input" behavior. */
        if (!(scr == SCR_DESKTOP && win_focused() == WIN_TERM)) continue;
        char ch = sc_to_char(sc);
        if (!ch) continue;
        if (ch == '\n') {
            trun();
        } else if (ch == '\b') {
            if (tinlen > 0) tinput[--tinlen] = 0;
        } else if (tinlen < TCOLS-1) {
            tinput[tinlen++] = ch;
            tinput[tinlen]   = 0;
        }
    }
}

/* ── Main ─────────────────────────────────────────────────────────── */
void gfx_main(void) {
    /* Defensive: boot_shell.asm already searched for exactly this mode,
     * but if VBE somehow granted something else, halt rather than draw
     * garbage into a framebuffer of the wrong shape/pitch. */
    const fb_info_t *fb = FB_INFO;
    if (fb->xres != SW || fb->yres != SH || fb->bpp != 32) {
        while (1) { }
    }

    init_idt_shell();
    init_mouse();

    /* AxFiles: one-time FAT12 mount + directory scan. The disk can't
     * change from outside this single-session shell, so scanning once
     * here (rather than on every window-open) is sufficient - see
     * files_scan(); a delete re-runs it explicitly to pick up the
     * change. render_files_list() shows "Disk not ready" if fat12_ok
     * is 0 (e.g. no IDE device attached). FAT12 defaults locked
     * (read-only) - unlock once here so AxFiles' delete can actually
     * write, matching there being no separate "unlock" affordance in
     * this GUI (unlike the text-mode shell's lock/unlock commands). */
    fat12_ok = fat12_init();
    fat12_set_locked(0);
    files_scan();

    /* Initialize terminal */
    for (int r=0; r<TROWS; r++) tlines[r][0] = 0;
    tinput[0] = 0;

    while (1) {
        wait_vsync();

        /* Mouse position: driver stores coords in an 80x25 grid; scale
         * to 800x600 (10x/24x - both exact, no rounding). */
        int mx = mouse_get_x() * 10;
        int my = mouse_get_y() * 24;

        handle_keys();
        handle_click(mx, my);
        handle_paint_drag(mx, my);
        handle_window_drag(mx, my);

        /* Draw scene to back buffer */
        switch (scr) {
            case SCR_DESKTOP:
                render_desktop(mx, my);
                /* Windows drawn back-to-front on top of the desktop -
                 * full quality every frame, see the window-manager
                 * comment up top for why that's cheap here. */
                for (int i = 0; i < N_WINDOWS; i++) {
                    int idx = win_order[i];
                    if (!windows[idx].open) continue;
                    const char *title = idx == WIN_TERM ? "AxTerminal" :
                                        idx == WIN_ABOUT ? "AxAbout" : "AxFiles";
                    render_window_chrome(idx, title);
                    int cx0, cy0, cw, ch;
                    win_content_rect(idx, &cx0, &cy0, &cw, &ch);
                    if (idx == WIN_TERM)       render_terminal(cx0, cy0, cw, ch);
                    else if (idx == WIN_ABOUT) render_about(cx0, cy0, cw, ch);
                    else                       render_files(cx0, cy0, cw, ch);
                }
                break;
            case SCR_TERMINAL: break;   /* scr never actually becomes this anymore - Terminal is a window now */
            case SCR_ABOUT:    break;   /* same */
            case SCR_FILES:    break;   /* same */
            case SCR_PAINT:    render_paint(); break;
        }

        /* Draw cursor on top, then blit back buffer → LFB atomically */
        cursor_draw(mx, my);
        blit();
    }
}
