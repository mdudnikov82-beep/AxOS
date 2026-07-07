#include "virtio_input.h"
#include "virtio_gpu.h"
#include "pmem.h"
#include "drivers/uart.h"

// VirtIO-input — тот же MMIO virtqueue-каркас, что и virtio_blk.c/virtio_gpu.c,
// но eventq (queue 0) работает НАОБОРОТ: мы заранее выставляем пустые
// device-writable буферы в avail-ring, устройство само заполняет их
// событиями по мере их появления (клики/движение мыши), а мы читаем used-ring
// по мере поступления и сразу возвращаем тот же буфер обратно в avail —
// классическая "receive ring", просто опрашиваемая поллингом, как и весь
// остальной ввод-вывод в этом ядре.

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
#define CFGU32(off) (*(volatile unsigned int *)(input_base + R_CONFIG + (off)))

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

/* Scaled screen cursor + button state, updated as events are drained. */
static unsigned int cur_x = GPU_FB_WIDTH / 2;
static unsigned int cur_y = GPU_FB_HEIGHT / 2;
static unsigned int cur_buttons = 0;

/* Raw ABS_X/ABS_Y ranges reported by the device (queried from config space). */
static unsigned int abs_x_min = 0, abs_x_max = 0xFFFF;
static unsigned int abs_y_min = 0, abs_y_max = 0xFFFF;

/* ---- linux/input-event-codes.h subset we need ---- */
#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_ABS 0x03
#define ABS_X  0x00
#define ABS_Y  0x01
#define BTN_LEFT   0x110
#define BTN_RIGHT  0x111
#define BTN_MIDDLE 0x112

#define CFG_ABS_INFO 0x12

static void cfg_select(unsigned char select, unsigned char subsel) {
    CFGB(0) = select;
    CFGB(1) = subsel;
}

static int init_v1(void) {
    uart_puts("[input] using legacy v1 MMIO\r\n");
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
        uart_puts("[input] v1: pages not adjacent!\r\n");
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
    uart_puts("[input] using modern v2 MMIO\r\n");
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

/* Re-posts descriptor `i` (device-writable, one input_event_t) into the
 * avail ring so the device can fill it with a future event. */
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

int virtio_input_init(void) {
    input_base = 0;
    for (int i = 0; i < VIRTIO_MMIO_SLOTS; i++) {
        unsigned long base = VIRTIO_MMIO_BASE + (unsigned long)i * VIRTIO_MMIO_STEP;
        volatile unsigned int *magic_reg = (volatile unsigned int *)(base + R_MAGIC);
        volatile unsigned int *id_reg    = (volatile unsigned int *)(base + R_DEVICE_ID);
        if (*magic_reg == 0x74726976 && *id_reg == INPUT_DEVICE_ID) {
            input_base = base;
            break;
        }
    }
    if (!input_base) {
        uart_puts("[input] virtio-input device not found (scanned 8 MMIO slots)\r\n");
        return -1;
    }
    uart_puts("[input] found @ 0x1000");
    uart_putc('0' + (char)((input_base - VIRTIO_MMIO_BASE) / VIRTIO_MMIO_STEP + 1));
    uart_puts("000\r\n");

    events = (input_event_t *)alloc_page();
    if (!events) { uart_puts("[input] OOM events buffer\r\n"); return -1; }

    unsigned int ver = REG(R_VERSION);
    int rc = (ver == 1) ? init_v1() : init_v2();
    if (rc != 0) { uart_puts("[input] queue init failed\r\n"); return -1; }

    /* Query the device's reported ABS_X/ABS_Y ranges so we can scale raw
     * coordinates to screen pixels. */
    cfg_select(CFG_ABS_INFO, ABS_X);
    abs_x_min = CFGU32(8);
    abs_x_max = CFGU32(12);
    cfg_select(CFG_ABS_INFO, ABS_Y);
    abs_y_min = CFGU32(8);
    abs_y_max = CFGU32(12);
    if (abs_x_max <= abs_x_min) { abs_x_min = 0; abs_x_max = 0xFFFF; }
    if (abs_y_max <= abs_y_min) { abs_y_min = 0; abs_y_max = 0xFFFF; }

    /* Pre-post all QUEUE_SIZE buffers as empty device-writable receive
     * slots — the device fills them in as real events occur. */
    for (unsigned int i = 0; i < QUEUE_SIZE; i++) repost(i);
    __asm__ volatile("fence ow, ow" ::: "memory");
    REG(R_QUEUE_NOTIFY) = 0;

    last_used = 0;
    ready = 1;
    uart_puts("[input] ready (tablet mode)\r\n");
    return 0;
}

int virtio_input_ready(void) { return ready; }

static void handle_event(const input_event_t *ev) {
    if (ev->type == EV_ABS) {
        if (ev->code == ABS_X) {
            unsigned int range = abs_x_max - abs_x_min;
            unsigned int v = (ev->value < abs_x_min) ? abs_x_min :
                             (ev->value > abs_x_max) ? abs_x_max : ev->value;
            cur_x = range ? ((v - abs_x_min) * (GPU_FB_WIDTH - 1)) / range : 0;
        } else if (ev->code == ABS_Y) {
            unsigned int range = abs_y_max - abs_y_min;
            unsigned int v = (ev->value < abs_y_min) ? abs_y_min :
                             (ev->value > abs_y_max) ? abs_y_max : ev->value;
            cur_y = range ? ((v - abs_y_min) * (GPU_FB_HEIGHT - 1)) / range : 0;
        }
    } else if (ev->type == EV_KEY) {
        unsigned int bit = (ev->code == BTN_LEFT)   ? 1u :
                           (ev->code == BTN_RIGHT)  ? 2u :
                           (ev->code == BTN_MIDDLE) ? 4u : 0u;
        if (bit) {
            if (ev->value) cur_buttons |= bit; else cur_buttons &= ~bit;
        }
    }
    /* EV_SYN and anything else: no state to update. */
}

unsigned long virtio_input_state(void) {
    if (!ready) return 0;

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

    return ((unsigned long)(cur_x & 0xFFFF) << 32) |
           ((unsigned long)(cur_y & 0xFFFF) << 16) |
           (unsigned long)(cur_buttons & 0xFF);
}
