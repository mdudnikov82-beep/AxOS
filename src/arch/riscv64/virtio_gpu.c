#include "virtio_gpu.h"
#include "pmem.h"
#include "drivers/uart.h"

// VirtIO-GPU 2D (без 3D/virgl) по MMIO — та же схема, что и virtio_blk.c:
// сканируем 8 MMIO-слотов QEMU virt, поднимаем ОДНУ control-очередь (queue 0),
// шлём команды создания ресурса/scanout, а сами пиксели пишем напрямую в
// linear framebuffer (guest RAM), никакой virtqueue на каждый пиксель не
// нужен — только на управляющие команды (create/attach/scanout/flush).

#define VIRTIO_MMIO_BASE  0x10001000UL
#define VIRTIO_MMIO_STEP  0x1000UL
#define VIRTIO_MMIO_SLOTS 8

#define QUEUE_SIZE   8
#define PAGE_SHIFT   12

#define GPU_DEVICE_ID 16

static unsigned long gpu_base = 0;

// ---- MMIO регистры (идентичны virtio_blk.c — общий virtio-mmio layout) ----
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

#define REG(off) (*(volatile unsigned int *)(gpu_base + (off)))

#define S_ACK       1
#define S_DRIVER    2
#define S_DRIVER_OK 4
#define S_FEAT_OK   8

#define DESC_NEXT  1
#define DESC_WRITE 2

// ---- Virtqueue-структуры (как в virtio_blk.c) ----
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

static vdesc_t  *desc;
static vavail_t *avail;
static vused_t  *used;
static unsigned short last_used = 0;
static int ready = 0;

// Cursor plane: SEPARATE virtqueue (queue 1, "cursorq" per the virtio-gpu
// spec) from the controlq (queue 0) above. The host compositor overlays
// this cursor image on top of our scanout independently — no need to
// save/restore framebuffer pixels under it ourselves.
static vdesc_t  *cdesc;
static vavail_t *cavail;
static vused_t  *cused;
static unsigned short clast_used = 0;
static int cursor_ready = 0;

static void *cmd_buf;   // scratch: команда на offset 0, ответ на offset 512
static void *fb;        // linear framebuffer, GPU_FB_WIDTH*GPU_FB_HEIGHT*4 байт

// ---- VirtIO-GPU протокол (2D-подмножество) ----
#define GPU_CMD_GET_DISPLAY_INFO        0x0100
#define GPU_CMD_RESOURCE_CREATE_2D      0x0101
#define GPU_CMD_SET_SCANOUT             0x0103
#define GPU_CMD_RESOURCE_FLUSH          0x0104
#define GPU_CMD_TRANSFER_TO_HOST_2D     0x0105
#define GPU_CMD_RESOURCE_ATTACH_BACKING 0x0106
#define GPU_CMD_UPDATE_CURSOR           0x0300
#define GPU_CMD_MOVE_CURSOR             0x0301

#define GPU_RESP_OK_NODATA       0x1100
#define GPU_RESP_OK_DISPLAY_INFO 0x1101

#define GPU_FORMAT_B8G8R8A8_UNORM 1

typedef struct {
    unsigned int  type;
    unsigned int  flags;
    unsigned long fence_id;
    unsigned int  ctx_id;
    unsigned int  padding;
} __attribute__((packed)) gpu_ctrl_hdr_t;                       // 24 bytes

typedef struct { unsigned int x, y, width, height; } __attribute__((packed)) gpu_rect_t;

typedef struct {
    gpu_ctrl_hdr_t hdr;
    unsigned int   resource_id;
    unsigned int   format;
    unsigned int   width;
    unsigned int   height;
} __attribute__((packed)) gpu_resource_create_2d_t;

typedef struct { unsigned long addr; unsigned int length, padding; } __attribute__((packed)) gpu_mem_entry_t;

typedef struct {
    gpu_ctrl_hdr_t  hdr;
    unsigned int    resource_id;
    unsigned int    nr_entries;
    gpu_mem_entry_t entries[1];
} __attribute__((packed)) gpu_attach_backing_t;

typedef struct {
    gpu_ctrl_hdr_t hdr;
    gpu_rect_t     r;
    unsigned int   scanout_id;
    unsigned int   resource_id;
} __attribute__((packed)) gpu_set_scanout_t;

typedef struct {
    gpu_ctrl_hdr_t hdr;
    gpu_rect_t     r;
    unsigned long  offset;
    unsigned int   resource_id;
    unsigned int   padding;
} __attribute__((packed)) gpu_transfer_to_host_2d_t;

typedef struct {
    gpu_ctrl_hdr_t hdr;
    gpu_rect_t     r;
    unsigned int   resource_id;
    unsigned int   padding;
} __attribute__((packed)) gpu_resource_flush_t;

typedef struct { unsigned int scanout_id, x, y, padding; } __attribute__((packed)) gpu_cursor_pos_t;

typedef struct {
    gpu_ctrl_hdr_t   hdr;
    gpu_cursor_pos_t pos;
    unsigned int     resource_id;   /* ignored by MOVE_CURSOR */
    unsigned int     hot_x, hot_y;  /* ignored by MOVE_CURSOR */
    unsigned int     padding;
} __attribute__((packed)) gpu_update_cursor_t;

static void put_dec(unsigned long v) {
    char b[20]; int i = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { b[i++] = '0' + (v % 10); v /= 10; }
    for (int j = i - 1; j >= 0; j--) uart_putc(b[j]);
}

static void hdr_init(gpu_ctrl_hdr_t *h, unsigned int type) {
    h->type = type; h->flags = 0; h->fence_id = 0; h->ctx_id = 0; h->padding = 0;
}

// ---- Инициализация virtqueue (v1/v2) — идентично virtio_blk.c ----
static int init_v1(void) {
    uart_puts("[gpu] using legacy v1 MMIO\r\n");
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
        uart_puts("[gpu] v1: pages not adjacent!\r\n");
        return -1;
    }

    desc  = (vdesc_t  *)p0;
    avail = (vavail_t *)((unsigned long)p0 + QUEUE_SIZE * sizeof(vdesc_t));
    used  = (vused_t  *)p1;

    REG(R_QUEUE_PFN) = (unsigned int)((unsigned long)p0 >> PAGE_SHIFT);

    /* Queue 1: cursorq — must be configured before DRIVER_OK too. */
    REG(R_QUEUE_SEL) = 1;
    qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;
    REG(R_QUEUE_ALIGN) = PAGE_SIZE;

    void *p2 = alloc_page();
    void *p3 = alloc_page();
    if (!p2 || !p3) return -1;
    if ((unsigned long)p3 != (unsigned long)p2 + PAGE_SIZE) {
        uart_puts("[gpu] v1: cursor pages not adjacent!\r\n");
        return -1;
    }
    cdesc  = (vdesc_t  *)p2;
    cavail = (vavail_t *)((unsigned long)p2 + QUEUE_SIZE * sizeof(vdesc_t));
    cused  = (vused_t  *)p3;
    REG(R_QUEUE_PFN) = (unsigned int)((unsigned long)p2 >> PAGE_SHIFT);

    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

static int init_v2(void) {
    uart_puts("[gpu] using modern v2 MMIO\r\n");
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

    /* Queue 1: cursorq — must be configured before DRIVER_OK too. */
    REG(R_QUEUE_SEL) = 1;
    qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;

    cdesc  = (vdesc_t  *)alloc_page();
    cavail = (vavail_t *)alloc_page();
    cused  = (vused_t  *)alloc_page();
    if (!cdesc || !cavail || !cused) return -1;

    pa = (unsigned long)cdesc;
    REG(R_QUEUE_DESC_LO) = (unsigned int)pa; REG(R_QUEUE_DESC_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)cavail;
    REG(R_QUEUE_DRV_LO) = (unsigned int)pa;  REG(R_QUEUE_DRV_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)cused;
    REG(R_QUEUE_DEV_LO) = (unsigned int)pa;  REG(R_QUEUE_DEV_HI) = (unsigned int)(pa >> 32);
    REG(R_QUEUE_READY) = 1;

    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

// ---- Отправка одной control-команды: desc0 (device-readable, cmd) ->
// desc1 (device-writable, resp). Синхронный polling, как do_io в virtio_blk.c. ----
static int send_cmd(void *cmd, unsigned int cmd_len, void *resp, unsigned int resp_len) {
    if (!ready && !desc) return -1;   /* allow calling during init before `ready` is set */

    desc[0].addr = (unsigned long)cmd;
    desc[0].len  = cmd_len;
    desc[0].flags = DESC_NEXT; desc[0].next = 1;

    desc[1].addr = (unsigned long)resp;
    desc[1].len  = resp_len;
    desc[1].flags = DESC_WRITE; desc[1].next = 0;

    unsigned short ai = avail->idx;
    avail->ring[ai % QUEUE_SIZE] = 0;
    __asm__ volatile("fence ow, ow" ::: "memory");
    avail->idx = (unsigned short)(ai + 1);
    __asm__ volatile("fence ow, ow" ::: "memory");

    REG(R_QUEUE_NOTIFY) = 0;

    for (unsigned int spin = 0; ; spin++) {
        __asm__ volatile("fence ir, ir" ::: "memory");
        if (used->idx != last_used) break;
        if (spin > 20000000U) { uart_puts("[gpu] command timeout\r\n"); return -1; }
    }
    last_used++;
    REG(R_INT_ACK) = REG(R_INT_STATUS);
    return 0;
}

// ---- Cursorq equivalent of send_cmd — separate ring, notified as queue 1. ----
static int send_cursor_cmd(void *cmd, unsigned int cmd_len, void *resp, unsigned int resp_len) {
    if (!cdesc) return -1;

    cdesc[0].addr = (unsigned long)cmd;
    cdesc[0].len  = cmd_len;
    cdesc[0].flags = DESC_NEXT; cdesc[0].next = 1;

    cdesc[1].addr = (unsigned long)resp;
    cdesc[1].len  = resp_len;
    cdesc[1].flags = DESC_WRITE; cdesc[1].next = 0;

    unsigned short ai = cavail->idx;
    cavail->ring[ai % QUEUE_SIZE] = 0;
    __asm__ volatile("fence ow, ow" ::: "memory");
    cavail->idx = (unsigned short)(ai + 1);
    __asm__ volatile("fence ow, ow" ::: "memory");

    REG(R_QUEUE_NOTIFY) = 1;   /* queue index 1 = cursorq */

    for (unsigned int spin = 0; ; spin++) {
        __asm__ volatile("fence ir, ir" ::: "memory");
        if (cused->idx != clast_used) break;
        if (spin > 20000000U) { uart_puts("[gpu] cursor command timeout\r\n"); return -1; }
    }
    clast_used++;
    REG(R_INT_ACK) = REG(R_INT_STATUS);
    return 0;
}

static int check_resp_ok(gpu_ctrl_hdr_t *resp, const char *what) {
    if (resp->type != GPU_RESP_OK_NODATA && resp->type != GPU_RESP_OK_DISPLAY_INFO) {
        uart_puts("[gpu] "); uart_puts(what); uart_puts(" failed, resp type=0x");
        for (int s = 28; s >= 0; s -= 4) uart_putc("0123456789abcdef"[(resp->type >> s) & 0xF]);
        uart_puts("\r\n");
        return -1;
    }
    return 0;
}

#define CURSOR_RESOURCE_ID 2
#define CURSOR_DIM         64

/* Simple white crosshair with a 1px black outline (visible against any
 * background), rest fully transparent (alpha=0). B8G8R8A8: alpha is the
 * top byte, so BGRA(0,0,0,0) is transparent black, BGRA(255,255,255,255)
 * opaque white. */
static void build_cursor_bitmap(unsigned int *buf) {
    for (int i = 0; i < CURSOR_DIM * CURSOR_DIM; i++) buf[i] = 0;

    int c = CURSOR_DIM / 2;
    for (int d = -10; d <= 10; d++) {
        for (int t = -1; t <= 1; t++) {
            unsigned int color = (t == 0) ? 0xFFFFFFFFu : 0xFF000000u;
            int vx = c + t, vy = c + d;   /* vertical stroke   */
            int hx = c + d, hy = c + t;   /* horizontal stroke */
            if (vx >= 0 && vx < CURSOR_DIM && vy >= 0 && vy < CURSOR_DIM)
                buf[vy * CURSOR_DIM + vx] = color;
            if (hx >= 0 && hx < CURSOR_DIM && hy >= 0 && hy < CURSOR_DIM)
                buf[hy * CURSOR_DIM + hx] = color;
        }
    }
}

/* Creates a 64x64 cursor resource, uploads the crosshair bitmap, and shows
 * it via UPDATE_CURSOR (cursorq). Non-fatal on failure — the main
 * framebuffer/scanout already works regardless. */
static int cursor_setup(void) {
    void *cmd  = cmd_buf;
    void *resp = (unsigned char *)cmd_buf + 512;

    {
        gpu_resource_create_2d_t *c = (gpu_resource_create_2d_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_RESOURCE_CREATE_2D);
        c->resource_id = CURSOR_RESOURCE_ID;
        c->format      = GPU_FORMAT_B8G8R8A8_UNORM;
        c->width       = CURSOR_DIM;
        c->height      = CURSOR_DIM;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "cursor RESOURCE_CREATE_2D")) return -1;
    }

    unsigned int cbytes = CURSOR_DIM * CURSOR_DIM * 4;
    unsigned int cpages = (cbytes + PAGE_SIZE - 1) / PAGE_SIZE;
    void *cbuf = alloc_page();
    if (!cbuf) return -1;
    for (unsigned int i = 1; i < cpages; i++) {
        void *p = alloc_page();
        if ((unsigned long)p != (unsigned long)cbuf + (unsigned long)i * PAGE_SIZE) {
            uart_puts("[gpu] cursor buffer not contiguous!\r\n");
            return -1;
        }
    }
    build_cursor_bitmap((unsigned int *)cbuf);

    {
        gpu_attach_backing_t *c = (gpu_attach_backing_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_RESOURCE_ATTACH_BACKING);
        c->resource_id = CURSOR_RESOURCE_ID;
        c->nr_entries  = 1;
        c->entries[0].addr    = (unsigned long)cbuf;
        c->entries[0].length  = cbytes;
        c->entries[0].padding = 0;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "cursor RESOURCE_ATTACH_BACKING")) return -1;
    }

    {
        gpu_transfer_to_host_2d_t *c = (gpu_transfer_to_host_2d_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_TRANSFER_TO_HOST_2D);
        c->r.x = 0; c->r.y = 0; c->r.width = CURSOR_DIM; c->r.height = CURSOR_DIM;
        c->offset = 0;
        c->resource_id = CURSOR_RESOURCE_ID;
        c->padding = 0;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "cursor TRANSFER_TO_HOST_2D")) return -1;
    }

    {
        gpu_update_cursor_t *c = (gpu_update_cursor_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_UPDATE_CURSOR);
        c->pos.scanout_id = 0;
        c->pos.x = GPU_FB_WIDTH / 2;
        c->pos.y = GPU_FB_HEIGHT / 2;
        c->pos.padding = 0;
        c->resource_id = CURSOR_RESOURCE_ID;
        c->hot_x = CURSOR_DIM / 2;
        c->hot_y = CURSOR_DIM / 2;
        c->padding = 0;
        /* Cursor commands don't reliably return a checkable response type
         * across implementations — send it but don't hard-fail on the reply. */
        send_cursor_cmd(c, sizeof(*c), resp, 512);
    }

    cursor_ready = 1;
    return 0;
}

void virtio_gpu_cursor_move(unsigned int x, unsigned int y) {
    if (!cursor_ready) return;
    void *cmd  = cmd_buf;
    void *resp = (unsigned char *)cmd_buf + 512;

    gpu_update_cursor_t *c = (gpu_update_cursor_t *)cmd;
    hdr_init(&c->hdr, GPU_CMD_MOVE_CURSOR);
    c->pos.scanout_id = 0;
    c->pos.x = x;
    c->pos.y = y;
    c->pos.padding = 0;
    c->resource_id = 0;
    c->hot_x = 0; c->hot_y = 0;
    c->padding = 0;
    send_cursor_cmd(c, sizeof(*c), resp, 512);
}

int virtio_gpu_init(void) {
    gpu_base = 0;
    for (int i = 0; i < VIRTIO_MMIO_SLOTS; i++) {
        unsigned long base = VIRTIO_MMIO_BASE + (unsigned long)i * VIRTIO_MMIO_STEP;
        volatile unsigned int *magic_reg = (volatile unsigned int *)(base + R_MAGIC);
        volatile unsigned int *id_reg    = (volatile unsigned int *)(base + R_DEVICE_ID);
        if (*magic_reg == 0x74726976 && *id_reg == GPU_DEVICE_ID) {
            gpu_base = base;
            break;
        }
    }
    if (!gpu_base) {
        uart_puts("[gpu] virtio-gpu device not found (scanned 8 MMIO slots)\r\n");
        return -1;
    }
    uart_puts("[gpu] found @ 0x1000");
    uart_putc('0' + (char)((gpu_base - VIRTIO_MMIO_BASE) / VIRTIO_MMIO_STEP + 1));
    uart_puts("000\r\n");

    cmd_buf = alloc_page();
    if (!cmd_buf) { uart_puts("[gpu] OOM cmd_buf\r\n"); return -1; }

    unsigned int ver = REG(R_VERSION);
    int rc = (ver == 1) ? init_v1() : init_v2();
    if (rc != 0) { uart_puts("[gpu] queue init failed\r\n"); return -1; }

    void *cmd  = cmd_buf;
    void *resp = (unsigned char *)cmd_buf + 512;

    /* GET_DISPLAY_INFO — просто для лога; конкретное разрешение сканаута
     * не обязано совпадать с тем, что мы создадим ниже (QEMU не проверяет). */
    {
        gpu_ctrl_hdr_t *c = (gpu_ctrl_hdr_t *)cmd;
        hdr_init(c, GPU_CMD_GET_DISPLAY_INFO);
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        gpu_ctrl_hdr_t *r = (gpu_ctrl_hdr_t *)resp;
        if (check_resp_ok(r, "GET_DISPLAY_INFO")) return -1;
    }

    /* RESOURCE_CREATE_2D: resource_id=1, B8G8R8A8, GPU_FB_WIDTH x GPU_FB_HEIGHT. */
    {
        gpu_resource_create_2d_t *c = (gpu_resource_create_2d_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_RESOURCE_CREATE_2D);
        c->resource_id = 1;
        c->format      = GPU_FORMAT_B8G8R8A8_UNORM;
        c->width       = GPU_FB_WIDTH;
        c->height      = GPU_FB_HEIGHT;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "RESOURCE_CREATE_2D")) return -1;
    }

    /* Framebuffer: linear guest RAM, GPU_FB_WIDTH*GPU_FB_HEIGHT*4 bytes.
     * alloc_page() bump-allocates contiguously, so N calls == one linear
     * range (same assumption virtio_blk.c's v1 init already relies on). */
    unsigned int fb_bytes = GPU_FB_WIDTH * GPU_FB_HEIGHT * 4;
    unsigned int fb_pages = (fb_bytes + PAGE_SIZE - 1) / PAGE_SIZE;
    fb = alloc_page();
    if (!fb) { uart_puts("[gpu] OOM framebuffer\r\n"); return -1; }
    for (unsigned int i = 1; i < fb_pages; i++) {
        void *p = alloc_page();
        if ((unsigned long)p != (unsigned long)fb + (unsigned long)i * PAGE_SIZE) {
            uart_puts("[gpu] framebuffer pages not contiguous!\r\n");
            return -1;
        }
    }

    /* RESOURCE_ATTACH_BACKING: один mem_entry покрывающий весь fb. */
    {
        gpu_attach_backing_t *c = (gpu_attach_backing_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_RESOURCE_ATTACH_BACKING);
        c->resource_id = 1;
        c->nr_entries  = 1;
        c->entries[0].addr    = (unsigned long)fb;
        c->entries[0].length  = fb_bytes;
        c->entries[0].padding = 0;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "RESOURCE_ATTACH_BACKING")) return -1;
    }

    /* SET_SCANOUT: показываем resource 1 на scanout 0, во весь его размер. */
    {
        gpu_set_scanout_t *c = (gpu_set_scanout_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_SET_SCANOUT);
        c->r.x = 0; c->r.y = 0; c->r.width = GPU_FB_WIDTH; c->r.height = GPU_FB_HEIGHT;
        c->scanout_id = 0;
        c->resource_id = 1;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "SET_SCANOUT")) return -1;
    }

    ready = 1;
    uart_puts("[gpu] ready: ");
    put_dec(GPU_FB_WIDTH);
    uart_putc('x');
    put_dec(GPU_FB_HEIGHT);
    uart_puts(" B8G8R8A8\r\n");

    if (cursor_setup() == 0) uart_puts("[gpu] cursor ready\r\n");
    else                     uart_puts("[gpu] cursor setup failed (no cursor shown)\r\n");

    return 0;
}

/* 8x8 bitmap font, ASCII 0x20-0x7F (public-domain VGA font), ported
 * verbatim from src/kernel/gfx_shell.c's `F` table — same byte layout
 * (one byte per row, bit0 = leftmost column) works regardless of pixel
 * format, since it's just a coverage mask. */
static const unsigned char font8x8[96][8] = {
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

/* Rendered at 2x: each 1x1 source bit becomes a GFX_FONT_SCALE x
 * GFX_FONT_SCALE block. Matches x86 gfx_shell.c's FONT_SCALE - at native
 * 8x8 pixels, text is tiny/hard to read on an 800x600 canvas. */
#define GFX_FONT_SCALE 2

void virtio_gpu_draw_char(unsigned int x, unsigned int y, char ch, unsigned int bgra) {
    unsigned char u = (unsigned char)ch;
    if (u < 0x20 || u > 0x7F) return;
    const unsigned char *g = font8x8[u - 0x20];
    for (unsigned int r = 0; r < 8; r++) {
        unsigned char row = g[r];
        for (unsigned int c = 0; c < 8; c++) {
            if (!(row & (1 << c))) continue;
            unsigned int px = x + c * GFX_FONT_SCALE, py = y + r * GFX_FONT_SCALE;
            for (unsigned int dy = 0; dy < GFX_FONT_SCALE; dy++)
                for (unsigned int dx = 0; dx < GFX_FONT_SCALE; dx++)
                    virtio_gpu_putpixel(px + dx, py + dy, bgra);
        }
    }
}

void virtio_gpu_draw_text(unsigned int x, unsigned int y, const char *s, unsigned int bgra) {
    while (*s) { virtio_gpu_draw_char(x, y, *s++, bgra); x += 8 * GFX_FONT_SCALE; }
}

void *virtio_gpu_fb(void) { return fb; }

int virtio_gpu_ready(void) { return ready; }

void virtio_gpu_putpixel(unsigned int x, unsigned int y, unsigned int bgra) {
    if (!ready || x >= GPU_FB_WIDTH || y >= GPU_FB_HEIGHT) return;
    ((unsigned int *)fb)[y * GPU_FB_WIDTH + x] = bgra;
}

void virtio_gpu_fill_rect(unsigned int x, unsigned int y,
                          unsigned int w, unsigned int h, unsigned int bgra) {
    if (!ready) return;
    unsigned int x1 = x + w, y1 = y + h;
    if (x1 > GPU_FB_WIDTH)  x1 = GPU_FB_WIDTH;
    if (y1 > GPU_FB_HEIGHT) y1 = GPU_FB_HEIGHT;
    if (x >= x1 || y >= y1) return;

    unsigned int *px = (unsigned int *)fb;
    for (unsigned int yy = y; yy < y1; yy++)
        for (unsigned int xx = x; xx < x1; xx++)
            px[yy * GPU_FB_WIDTH + xx] = bgra;
}

unsigned int virtio_gpu_getpixel(unsigned int x, unsigned int y) {
    if (!ready || x >= GPU_FB_WIDTH || y >= GPU_FB_HEIGHT) return 0;
    return ((unsigned int *)fb)[y * GPU_FB_WIDTH + x];
}

int virtio_gpu_flush(void) {
    if (!ready) return -1;
    void *cmd  = cmd_buf;
    void *resp = (unsigned char *)cmd_buf + 512;

    {
        gpu_transfer_to_host_2d_t *c = (gpu_transfer_to_host_2d_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_TRANSFER_TO_HOST_2D);
        c->r.x = 0; c->r.y = 0; c->r.width = GPU_FB_WIDTH; c->r.height = GPU_FB_HEIGHT;
        c->offset = 0;
        c->resource_id = 1;
        c->padding = 0;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "TRANSFER_TO_HOST_2D")) return -1;
    }
    {
        gpu_resource_flush_t *c = (gpu_resource_flush_t *)cmd;
        hdr_init(&c->hdr, GPU_CMD_RESOURCE_FLUSH);
        c->r.x = 0; c->r.y = 0; c->r.width = GPU_FB_WIDTH; c->r.height = GPU_FB_HEIGHT;
        c->resource_id = 1;
        c->padding = 0;
        if (send_cmd(c, sizeof(*c), resp, 512) != 0) return -1;
        if (check_resp_ok((gpu_ctrl_hdr_t *)resp, "RESOURCE_FLUSH")) return -1;
    }
    return 0;
}
