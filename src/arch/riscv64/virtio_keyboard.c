#include "virtio_keyboard.h"
#include "pmem.h"
#include "drivers/uart.h"

// VirtIO-keyboard — same MMIO virtqueue framework as virtio_input.c's
// tablet driver (eventq, receive-ring-via-polling), but translates
// EV_KEY press events into ASCII (via the same scancode table x86's
// gfx_shell.c already has, since Linux's KEY_* numbering for the base
// US layout is bit-for-bit the AT Set-1 make codes) instead of tracking
// a cursor/button state.

#define VIRTIO_MMIO_BASE  0x10001000UL
#define VIRTIO_MMIO_STEP  0x1000UL
#define VIRTIO_MMIO_SLOTS 8

#define QUEUE_SIZE 16
#define PAGE_SHIFT 12

#define INPUT_DEVICE_ID 18

static unsigned long input_base = 0;

#define R_MAGIC           0x000
#define R_VERSION         0x004
#define R_DEVICE_ID       0x008
#define R_DEV_FEAT        0x010
#define R_DEV_FEAT_SEL    0x014
#define R_DRV_FEAT        0x020
#define R_DRV_FEAT_SEL    0x024
#define R_GUEST_PAGE_SIZE 0x028
#define R_QUEUE_SEL       0x030
#define R_QUEUE_NUM_MAX   0x034
#define R_QUEUE_NUM       0x038
#define R_QUEUE_ALIGN     0x03C
#define R_QUEUE_PFN       0x040
#define R_QUEUE_READY     0x044
#define R_QUEUE_NOTIFY    0x050
#define R_INT_STATUS      0x060
#define R_INT_ACK         0x064
#define R_STATUS          0x070
#define R_QUEUE_DESC_LO   0x080
#define R_QUEUE_DESC_HI   0x084
#define R_QUEUE_DRV_LO    0x090
#define R_QUEUE_DRV_HI    0x094
#define R_QUEUE_DEV_LO    0x0A0
#define R_QUEUE_DEV_HI    0x0A4
#define R_CONFIG          0x100

#define REG(off) (*(volatile unsigned int *)(input_base + (off)))
#define CFGB(off) (*(volatile unsigned char *)(input_base + R_CONFIG + (off)))

#define S_ACK       1
#define S_DRIVER    2
#define S_DRIVER_OK 4
#define S_FEAT_OK   8

#define DESC_NEXT  1
#define DESC_WRITE 2

typedef struct {
    unsigned long  addr;
    unsigned int   len;
    unsigned short flags;
    unsigned short next;
} __attribute__((packed)) vdesc_t;

typedef struct {
    unsigned short flags;
    unsigned short idx;
    unsigned short ring[QUEUE_SIZE];
} __attribute__((packed)) vavail_t;

typedef struct { unsigned int id, len; } vused_elem_t;

typedef struct {
    unsigned short flags;
    unsigned short idx;
    vused_elem_t   ring[QUEUE_SIZE];
} __attribute__((packed)) vused_t;

typedef struct {
    unsigned short type;
    unsigned short code;
    unsigned int   value;
} __attribute__((packed)) input_event_t;   /* 8 bytes */

static vdesc_t  *desc;
static vavail_t *avail;
static vused_t  *used;
static unsigned short last_used = 0;
static int ready = 0;

static input_event_t *events;  /* QUEUE_SIZE slots, one page */

/* ---- linux/input-event-codes.h subset we need ---- */
#define EV_KEY 0x01
#define EV_ABS 0x03
#define KEY_LEFTSHIFT  42
#define KEY_RIGHTSHIFT 54

#define CFG_EV_BITS 0x11

static int shift_l = 0, shift_r = 0;

/* US QWERTY scancode -> ASCII (unshifted, make codes only) - copied
 * verbatim from src/kernel/gfx_shell.c's sc2asc[89] (x86's PS/2 table).
 * Linux's KEY_* constants for the base US layout use the exact same
 * numbering as AT keyboard Set-1 make codes, so this table is reusable
 * as-is - confirmed by hand-checking KEY_A=30->'a', KEY_ENTER=28->'\n',
 * KEY_LEFTSHIFT=42->0 (correctly unmapped, it's a modifier). */
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

/* Shifted variant: uppercase letters + the common shifted digit/punctuation
 * pairs. Real virtio-input reports genuine press/release, so unlike x86's
 * PS/2 polling demo (which never bothers with shift at all), tracking it
 * here is cheap and correct. */
static char shift_ch(char c) {
    if (c >= 'a' && c <= 'z') return (char)(c - 32);
    switch (c) {
        case '1': return '!'; case '2': return '@'; case '3': return '#';
        case '4': return '$'; case '5': return '%'; case '6': return '^';
        case '7': return '&'; case '8': return '*'; case '9': return '(';
        case '0': return ')'; case '-': return '_'; case '=': return '+';
        case '[': return '{'; case ']': return '}'; case ';': return ':';
        case '\'': return '"'; case '`': return '~'; case '\\': return '|';
        case ',': return '<'; case '.': return '>'; case '/': return '?';
        default: return c;
    }
}

/* ---- small ASCII FIFO, drained by virtio_keyboard_getc() ---- */
#define KBD_QUEUE_SIZE 16
static char kbd_queue[KBD_QUEUE_SIZE];
static unsigned int kbd_head = 0, kbd_tail = 0, kbd_count = 0;

static void kbd_push(char c) {
    if (kbd_count == KBD_QUEUE_SIZE) return;  /* drop if the reader isn't keeping up */
    kbd_queue[kbd_tail] = c;
    kbd_tail = (kbd_tail + 1) % KBD_QUEUE_SIZE;
    kbd_count++;
}

static int kbd_pop(void) {
    if (!kbd_count) return -1;
    char c = kbd_queue[kbd_head];
    kbd_head = (kbd_head + 1) % KBD_QUEUE_SIZE;
    kbd_count--;
    return (unsigned char)c;
}

static void cfg_select(unsigned char select, unsigned char subsel) {
    CFGB(0) = select;
    CFGB(1) = subsel;
}

/* 1 if the device at the currently-selected input_base reports ANY
 * EV_ABS support (absolute axes) - true for the tablet, false for a
 * real keyboard. Used to skip the wrong id-18 device during the scan. */
static int supports_ev_abs(void) {
    cfg_select(CFG_EV_BITS, EV_ABS);
    return CFGB(0) != 0;   /* CFGB(0) after select = reported bitmap size in bytes */
}

static int init_v1(void) {
    uart_puts("[kbd] using legacy v1 MMIO\r\n");
    REG(R_STATUS) = 0;
    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) = S_ACK | S_DRIVER;
    REG(R_DRV_FEAT) = 0;
    REG(R_GUEST_PAGE_SIZE) = PAGE_SIZE;

    REG(R_QUEUE_SEL) = 0;
    unsigned int qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;
    REG(R_QUEUE_ALIGN) = PAGE_SIZE;

    void *p0 = alloc_page();
    void *p1 = alloc_page();
    if (!p0 || !p1) return -1;
    if ((unsigned long)p1 != (unsigned long)p0 + PAGE_SIZE) {
        uart_puts("[kbd] v1: pages not adjacent!\r\n");
        return -1;
    }
    desc  = (vdesc_t  *)p0;
    avail = (vavail_t *)((unsigned long)p0 + QUEUE_SIZE * sizeof(vdesc_t));
    used  = (vused_t  *)p1;

    REG(R_QUEUE_PFN) = (unsigned int)((unsigned long)p0 >> PAGE_SHIFT);
    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

static int init_v2(void) {
    uart_puts("[kbd] using modern v2 MMIO\r\n");
    REG(R_STATUS) = 0;
    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) = S_ACK | S_DRIVER;

    REG(R_DRV_FEAT_SEL) = 1; REG(R_DRV_FEAT) = 1;
    REG(R_DRV_FEAT_SEL) = 0; REG(R_DRV_FEAT) = 0;

    REG(R_STATUS) |= S_FEAT_OK;
    __asm__ volatile("fence" ::: "memory");
    if (!(REG(R_STATUS) & S_FEAT_OK)) return -1;

    REG(R_QUEUE_SEL) = 0;
    unsigned int qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;

    desc  = (vdesc_t  *)alloc_page();
    avail = (vavail_t *)alloc_page();
    used  = (vused_t  *)alloc_page();
    if (!desc || !avail || !used) return -1;

    unsigned long pa;
    pa = (unsigned long)desc;
    REG(R_QUEUE_DESC_LO) = (unsigned int)pa; REG(R_QUEUE_DESC_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)avail;
    REG(R_QUEUE_DRV_LO) = (unsigned int)pa;  REG(R_QUEUE_DRV_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)used;
    REG(R_QUEUE_DEV_LO) = (unsigned int)pa;  REG(R_QUEUE_DEV_HI) = (unsigned int)(pa >> 32);

    REG(R_QUEUE_READY) = 1;
    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

static void repost(unsigned int i) {
    desc[i].addr = (unsigned long)&events[i];
    desc[i].len  = sizeof(input_event_t);
    desc[i].flags = DESC_WRITE;
    desc[i].next  = 0;

    unsigned short ai = avail->idx;
    avail->ring[ai % QUEUE_SIZE] = (unsigned short)i;
    __asm__ volatile("fence ow, ow" ::: "memory");
    avail->idx = (unsigned short)(ai + 1);
}

int virtio_keyboard_init(void) {
    input_base = 0;
    for (int i = 0; i < VIRTIO_MMIO_SLOTS; i++) {
        unsigned long base = VIRTIO_MMIO_BASE + (unsigned long)i * VIRTIO_MMIO_STEP;
        volatile unsigned int *magic_reg = (volatile unsigned int *)(base + R_MAGIC);
        volatile unsigned int *id_reg    = (volatile unsigned int *)(base + R_DEVICE_ID);
        if (*magic_reg == 0x74726976 && *id_reg == INPUT_DEVICE_ID) {
            input_base = base;
            if (!supports_ev_abs()) break;   /* no ABS axes -> real keyboard */
            input_base = 0;                  /* this one's the tablet, keep scanning */
        }
    }
    if (!input_base) {
        uart_puts("[kbd] virtio-keyboard device not found (scanned 8 MMIO slots)\r\n");
        return -1;
    }
    uart_puts("[kbd] found @ 0x1000");
    uart_putc('0' + (char)((input_base - VIRTIO_MMIO_BASE) / VIRTIO_MMIO_STEP + 1));
    uart_puts("000\r\n");

    events = (input_event_t *)alloc_page();
    if (!events) { uart_puts("[kbd] OOM events buffer\r\n"); return -1; }

    unsigned int ver = REG(R_VERSION);
    int rc = (ver == 1) ? init_v1() : init_v2();
    if (rc != 0) { uart_puts("[kbd] queue init failed\r\n"); return -1; }

    for (unsigned int i = 0; i < QUEUE_SIZE; i++) repost(i);
    __asm__ volatile("fence ow, ow" ::: "memory");
    REG(R_QUEUE_NOTIFY) = 0;

    last_used = 0;
    ready = 1;
    uart_puts("[kbd] ready\r\n");
    return 0;
}

int virtio_keyboard_ready(void) { return ready; }

static void handle_event(const input_event_t *ev) {
    if (ev->type != EV_KEY) return;   /* EV_SYN etc - no state to update */

    if (ev->code == KEY_LEFTSHIFT)  { shift_l = ev->value ? 1 : 0; return; }
    if (ev->code == KEY_RIGHTSHIFT) { shift_r = ev->value ? 1 : 0; return; }

    if (!ev->value) return;   /* only translate presses, not releases */
    if (ev->code >= 89) return;
    unsigned char ch = sc2asc[ev->code];
    if (!ch) return;
    if (shift_l || shift_r) ch = (unsigned char)shift_ch((char)ch);
    kbd_push((char)ch);
}

int virtio_keyboard_getc(void) {
    if (!ready) return -1;

    int any = 0;
    while (used->idx != last_used) {
        __asm__ volatile("fence ir, ir" ::: "memory");
        unsigned int slot = used->ring[last_used % QUEUE_SIZE].id;
        handle_event(&events[slot]);
        last_used++;
        repost(slot);
        any = 1;
    }
    if (any) {
        __asm__ volatile("fence ow, ow" ::: "memory");
        REG(R_QUEUE_NOTIFY) = 0;
    }

    return kbd_pop();
}
