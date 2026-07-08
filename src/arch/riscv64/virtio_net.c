#include "virtio_net.h"
#include "pmem.h"
#include "drivers/uart.h"

// VirtIO-net — тот же MMIO virtqueue-каркас, что и virtio_blk.c/virtio_input.c,
// но, в отличие от них, устройству нужны ДВЕ независимых очереди сразу:
//   queue 0 (receiveq) — работает как в virtio_input.c: мы заранее кладём
//     пустые device-writable буферы в avail-ring, устройство само заполняет
//     их входящими кадрами по мере поступления.
//   queue 1 (transmitq) — работает как в virtio_blk.c: мы кладём
//     driver-writable буфер (готовый кадр) и ждём, пока устройство его заберёт
//     (по used-ring, поллингом).
// Обе очереди настраиваются одним и тем же кодом init_v1/init_v2, просто
// вызванным дважды с REG(R_QUEUE_SEL) = 0 и = 1.
//
// Перед каждым кадром (RX и TX) устройство ожидает virtio_net_hdr (10 байт
// без num_buffers, т.к. VIRTIO_NET_F_MRG_RXBUF не запрашивается) — драйвер
// прячет его от вызывающего кода (virtio_net_send/recv работают с чистым
// Ethernet-кадром, без этого заголовка).

#define VIRTIO_MMIO_BASE  0x10001000UL
#define VIRTIO_MMIO_STEP  0x1000UL
#define VIRTIO_MMIO_SLOTS 8

#define NET_DEVICE_ID 1

#define QUEUE_SIZE  8
#define PAGE_SHIFT  12

#define RXQ 0
#define TXQ 1

#define MAX_FRAME 1514
#define NET_HDR_SIZE 10          // virtio_net_hdr без num_buffers
#define BUF_SIZE (NET_HDR_SIZE + MAX_FRAME)   // помещается в одну 4КБ-страницу

static unsigned long net_base = 0;

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
#define R_CONFIG          0x100   // mac[6] at +0, status(u16) at +6

#define REG(off)  (*(volatile unsigned int *)(net_base + (off)))
#define CFGB(off) (*(volatile unsigned char *)(net_base + R_CONFIG + (off)))

#define S_ACK       1
#define S_DRIVER    2
#define S_DRIVER_OK 4
#define S_FEAT_OK   8

#define DESC_NEXT  1
#define DESC_WRITE 2

#define VIRTIO_NET_F_MAC 5

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

// Одна очередь (desc+avail+used) — держим RX и TX как две независимые копии
// этого же набора указателей, вместо двух параллельных наборов static-переменных.
typedef struct {
    vdesc_t  *desc;
    vavail_t *avail;
    vused_t  *used;
    unsigned short last_used;
} vqueue_t;

static vqueue_t rxq, txq;
static unsigned char *rx_bufs[QUEUE_SIZE];   // по одной странице на буфер
static unsigned char *tx_scratch;            // один переиспользуемый TX-буфер
static unsigned char mac[6];
static int ready = 0;

static int setup_queue_v1(unsigned int idx, vqueue_t *q) {
    REG(R_QUEUE_SEL) = idx;
    unsigned int qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;
    REG(R_QUEUE_ALIGN) = PAGE_SIZE;

    void *p0 = alloc_page();
    void *p1 = alloc_page();
    if (!p0 || !p1) return -1;
    if ((unsigned long)p1 != (unsigned long)p0 + PAGE_SIZE) {
        uart_puts("[net] v1: pages not adjacent!\r\n");
        return -1;
    }
    q->desc  = (vdesc_t  *)p0;
    q->avail = (vavail_t *)((unsigned long)p0 + QUEUE_SIZE * sizeof(vdesc_t));
    q->used  = (vused_t  *)p1;

    REG(R_QUEUE_PFN) = (unsigned int)((unsigned long)p0 >> PAGE_SHIFT);
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

static int setup_queue_v2(unsigned int idx, vqueue_t *q) {
    REG(R_QUEUE_SEL) = idx;
    unsigned int qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;

    q->desc  = (vdesc_t  *)alloc_page();
    q->avail = (vavail_t *)alloc_page();
    q->used  = (vused_t  *)alloc_page();
    if (!q->desc || !q->avail || !q->used) return -1;

    unsigned long pa;
    pa = (unsigned long)q->desc;
    REG(R_QUEUE_DESC_LO) = (unsigned int)pa; REG(R_QUEUE_DESC_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)q->avail;
    REG(R_QUEUE_DRV_LO) = (unsigned int)pa;  REG(R_QUEUE_DRV_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)q->used;
    REG(R_QUEUE_DEV_LO) = (unsigned int)pa;  REG(R_QUEUE_DEV_HI) = (unsigned int)(pa >> 32);

    REG(R_QUEUE_READY) = 1;
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

// Кладёт буфер rx_bufs[i] обратно в avail-ring очереди RX как пустой
// device-writable слот (устройство заполнит его следующим входящим кадром).
static void rx_repost(unsigned int i) {
    rxq.desc[i].addr  = (unsigned long)rx_bufs[i];
    rxq.desc[i].len   = BUF_SIZE;
    rxq.desc[i].flags = DESC_WRITE;
    rxq.desc[i].next  = 0;

    unsigned short ai = rxq.avail->idx;
    rxq.avail->ring[ai % QUEUE_SIZE] = (unsigned short)i;
    __asm__ volatile("fence ow, ow" ::: "memory");
    rxq.avail->idx = (unsigned short)(ai + 1);
}

int virtio_net_init(void) {
    net_base = 0;
    for (int i = 0; i < VIRTIO_MMIO_SLOTS; i++) {
        unsigned long base = VIRTIO_MMIO_BASE + (unsigned long)i * VIRTIO_MMIO_STEP;
        volatile unsigned int *magic_reg = (volatile unsigned int *)(base + R_MAGIC);
        volatile unsigned int *id_reg    = (volatile unsigned int *)(base + R_DEVICE_ID);
        if (*magic_reg == 0x74726976 && *id_reg == NET_DEVICE_ID) {
            net_base = base;
            break;
        }
    }
    if (!net_base) {
        uart_puts("[net] virtio-net device not found (scanned 8 MMIO slots)\r\n");
        return -1;
    }
    uart_puts("[net] found @ 0x1000");
    uart_putc('0' + (char)((net_base - VIRTIO_MMIO_BASE) / VIRTIO_MMIO_STEP + 1));
    uart_puts("000\r\n");

    for (int i = 0; i < QUEUE_SIZE; i++) {
        rx_bufs[i] = (unsigned char *)alloc_page();
        if (!rx_bufs[i]) { uart_puts("[net] OOM rx_bufs\r\n"); return -1; }
    }
    tx_scratch = (unsigned char *)alloc_page();
    if (!tx_scratch) { uart_puts("[net] OOM tx_scratch\r\n"); return -1; }

    unsigned int ver = REG(R_VERSION);

    REG(R_STATUS) = 0;
    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) = S_ACK | S_DRIVER;

    if (ver == 1) {
        uart_puts("[net] using legacy v1 MMIO\r\n");
        REG(R_DRV_FEAT) = (1u << VIRTIO_NET_F_MAC);
        REG(R_GUEST_PAGE_SIZE) = PAGE_SIZE;
    } else {
        uart_puts("[net] using modern v2 MMIO\r\n");
        REG(R_DRV_FEAT_SEL) = 0; REG(R_DRV_FEAT) = (1u << VIRTIO_NET_F_MAC);
        REG(R_DRV_FEAT_SEL) = 1; REG(R_DRV_FEAT) = 1;   // VIRTIO_F_VERSION_1 (bit 32)
        REG(R_STATUS) |= S_FEAT_OK;
        __asm__ volatile("fence" ::: "memory");
        if (!(REG(R_STATUS) & S_FEAT_OK)) { uart_puts("[net] FEATURES_OK rejected\r\n"); return -1; }
    }

    int (*setup)(unsigned int, vqueue_t *) = (ver == 1) ? setup_queue_v1 : setup_queue_v2;
    if (setup(RXQ, &rxq) != 0) { uart_puts("[net] rxq init failed\r\n"); return -1; }
    if (setup(TXQ, &txq) != 0) { uart_puts("[net] txq init failed\r\n"); return -1; }

    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");

    for (int i = 0; i < 6; i++) mac[i] = CFGB(i);

    rxq.last_used = 0;
    txq.last_used = 0;
    for (unsigned int i = 0; i < QUEUE_SIZE; i++) rx_repost(i);
    __asm__ volatile("fence ow, ow" ::: "memory");
    REG(R_QUEUE_NOTIFY) = RXQ;

    ready = 1;
    uart_puts("[net] ready, MAC=");
    for (int i = 0; i < 6; i++) {
        uart_putc("0123456789abcdef"[(mac[i] >> 4) & 0xF]);
        uart_putc("0123456789abcdef"[mac[i] & 0xF]);
        if (i < 5) uart_putc(':');
    }
    uart_puts("\r\n");
    return 0;
}

int virtio_net_ready(void) { return ready; }

void virtio_net_get_mac(unsigned char out[6]) {
    for (int i = 0; i < 6; i++) out[i] = mac[i];
}

int virtio_net_send(const void *frame, unsigned int len) {
    if (!ready) return -1;
    if (len > MAX_FRAME) return -1;

    // tx_scratch: virtio_net_hdr (10Б, все поля 0 — без checksum/GSO offload)
    // сразу перед кадром.
    for (int i = 0; i < NET_HDR_SIZE; i++) tx_scratch[i] = 0;
    const unsigned char *src = (const unsigned char *)frame;
    for (unsigned int i = 0; i < len; i++) tx_scratch[NET_HDR_SIZE + i] = src[i];

    txq.desc[0].addr  = (unsigned long)tx_scratch;
    txq.desc[0].len   = NET_HDR_SIZE + len;
    txq.desc[0].flags = 0;
    txq.desc[0].next  = 0;

    unsigned short ai = txq.avail->idx;
    txq.avail->ring[ai % QUEUE_SIZE] = 0;
    __asm__ volatile("fence ow, ow" ::: "memory");
    txq.avail->idx = (unsigned short)(ai + 1);
    __asm__ volatile("fence ow, ow" ::: "memory");

    REG(R_QUEUE_NOTIFY) = TXQ;

    for (unsigned int spin = 0; ; spin++) {
        __asm__ volatile("fence ir, ir" ::: "memory");
        if (txq.used->idx != txq.last_used) break;
        if (spin > 20000000U) { uart_puts("[net] tx timeout\r\n"); return -1; }
    }
    txq.last_used++;
    return 0;
}

unsigned int virtio_net_recv(void *buf, unsigned int max_len) {
    if (!ready) return 0;
    if (rxq.used->idx == rxq.last_used) return 0;   // ничего не пришло

    __asm__ volatile("fence ir, ir" ::: "memory");
    unsigned int slot = rxq.used->ring[rxq.last_used % QUEUE_SIZE].id;
    unsigned int total = rxq.used->ring[rxq.last_used % QUEUE_SIZE].len;
    rxq.last_used++;

    unsigned int frame_len = (total > NET_HDR_SIZE) ? (total - NET_HDR_SIZE) : 0;
    unsigned int copied = 0;
    if (frame_len > 0 && frame_len <= max_len) {
        unsigned char *dst = (unsigned char *)buf;
        unsigned char *src = rx_bufs[slot] + NET_HDR_SIZE;
        for (unsigned int i = 0; i < frame_len; i++) dst[i] = src[i];
        copied = frame_len;
    }

    rx_repost(slot);
    __asm__ volatile("fence ow, ow" ::: "memory");
    REG(R_QUEUE_NOTIFY) = RXQ;

    return copied;
}
