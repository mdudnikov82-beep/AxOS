#include "virtio_blk.h"
#include "pmem.h"
#include "drivers/uart.h"

// VirtIO MMIO — поддержка v1 (legacy) и v2 (modern).
// QEMU virt: первый MMIO-слот по адресу 0x10001000.
//
// Разница v1/v2 только в инициализации:
//   v1: GUEST_PAGE_SIZE + QUEUE_PFN (одна смежная область памяти)
//   v2: QUEUE_DESC/DRV/DEV LO+HI (три независимых страницы)
// do_io() одинаков: дескриптор, avail-ring, used-ring — одинаковый формат.

// QEMU virt выставляет до 8 VirtIO MMIO слотов: 0x10001000..0x10008000 (шаг 0x1000).
// Устройства занимают слоты в порядке добавления; блочное может быть не первым.
#define VIRTIO_MMIO_BASE  0x10001000UL
#define VIRTIO_MMIO_STEP  0x1000UL
#define VIRTIO_MMIO_SLOTS 8

#define QUEUE_SIZE      8
#define PAGE_SHIFT      12

static unsigned long blk_base = 0;  // найденный адрес блочного устройства

// ---- MMIO регистры ----
#define R_MAGIC           0x000  // (R)  0x74726976
#define R_VERSION         0x004  // (R)  1=legacy, 2=modern
#define R_DEVICE_ID       0x008  // (R)  2=block
#define R_DEV_FEAT        0x010  // (R)  feature bits
#define R_DEV_FEAT_SEL    0x014  // (W)  v2 only
#define R_DRV_FEAT        0x020  // (W)  accepted features
#define R_DRV_FEAT_SEL    0x024  // (W)  v2 only
#define R_GUEST_PAGE_SIZE 0x028  // (W)  v1 only: guest page size
#define R_QUEUE_SEL       0x030
#define R_QUEUE_NUM_MAX   0x034
#define R_QUEUE_NUM       0x038
#define R_QUEUE_ALIGN     0x03C  // (W)  v1 only: queue alignment
#define R_QUEUE_PFN       0x040  // (RW) v1 only: queue PFN
#define R_QUEUE_READY     0x044  // (RW) v2 only
#define R_QUEUE_NOTIFY    0x050
#define R_INT_STATUS      0x060
#define R_INT_ACK         0x064
#define R_STATUS          0x070
#define R_QUEUE_DESC_LO   0x080  // (W) v2
#define R_QUEUE_DESC_HI   0x084
#define R_QUEUE_DRV_LO    0x090
#define R_QUEUE_DRV_HI    0x094
#define R_QUEUE_DEV_LO    0x0A0
#define R_QUEUE_DEV_HI    0x0A4
#define R_CONFIG          0x100  // device config: [0..7] = capacity (u64)

// REG использует blk_base, который устанавливается при сканировании
#define REG(off) (*(volatile unsigned int *)(blk_base + (off)))

// ---- Status bits ----
#define S_ACK       1
#define S_DRIVER    2
#define S_DRIVER_OK 4
#define S_FEAT_OK   8

// ---- Descriptor flags ----
#define DESC_NEXT  1
#define DESC_WRITE 2

// ---- Block request types ----
#define BLK_T_IN  0
#define BLK_T_OUT 1

// ---- Virtqueue structures ----
typedef struct {
    unsigned long  addr;
    unsigned int   len;
    unsigned short flags;
    unsigned short next;
} __attribute__((packed)) vdesc_t;      // 16 bytes

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
    unsigned int  type;
    unsigned int  reserved;
    unsigned long sector;
} __attribute__((packed)) blk_req_t;    // 16 bytes

// ---- Driver state ----
static vdesc_t  *desc;
static vavail_t *avail;
static vused_t  *used;
static void     *req_page;
static unsigned short last_used = 0;
static unsigned long  capacity  = 0;
static int            ready     = 0;

static void put_dec(unsigned long v) {
    char b[20]; int i = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { b[i++] = '0' + (v % 10); v /= 10; }
    for (int j = i - 1; j >= 0; j--) uart_putc(b[j]);
}

// ---- Инициализация v1 (legacy) ----
static int init_v1(void) {
    uart_puts("[virtio] using legacy v1 MMIO\r\n");

    REG(R_STATUS) = 0;
    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) = S_ACK | S_DRIVER;

    // Принимаем фичи как есть (32-bit, без SEL в v1)
    REG(R_DRV_FEAT) = 0;

    // Обязательно для v1: установить guest page size
    REG(R_GUEST_PAGE_SIZE) = PAGE_SIZE;

    // Настраиваем очередь
    REG(R_QUEUE_SEL) = 0;
    unsigned int qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;
    REG(R_QUEUE_ALIGN) = PAGE_SIZE;

    // v1: всё в одной смежной области памяти.
    // Страница 0: desc + avail (128 + 22 = 150 байт → влезают в PAGE_SIZE)
    // Страница 1: used ring (начинается на смещении PAGE_SIZE = QUEUE_ALIGN)
    void *p0 = alloc_page();
    void *p1 = alloc_page();    // смежная — bump-аллокатор даёт следующий адрес
    if (!p0 || !p1) return -1;

    // alloc_page() уже обнулила страницы; проверяем смежность
    if ((unsigned long)p1 != (unsigned long)p0 + PAGE_SIZE) {
        uart_puts("[virtio] v1: pages not adjacent!\r\n");
        return -1;
    }

    desc  = (vdesc_t  *)p0;
    avail = (vavail_t *)((unsigned long)p0 + QUEUE_SIZE * sizeof(vdesc_t));
    used  = (vused_t  *)p1;   // на смещении PAGE_SIZE от начала

    // PFN = PA / PAGE_SIZE
    REG(R_QUEUE_PFN) = (unsigned int)((unsigned long)p0 >> PAGE_SHIFT);
    __asm__ volatile("fence" ::: "memory");

    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

// ---- Инициализация v2 (modern) ----
static int init_v2(void) {
    uart_puts("[virtio] using modern v2 MMIO\r\n");

    REG(R_STATUS) = 0;
    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) = S_ACK | S_DRIVER;

    // VIRTIO_F_VERSION_1 = бит 32 → SEL=1, бит 0
    REG(R_DRV_FEAT_SEL) = 1; REG(R_DRV_FEAT) = 1;
    REG(R_DRV_FEAT_SEL) = 0; REG(R_DRV_FEAT) = 0;

    REG(R_STATUS) |= S_FEAT_OK;
    __asm__ volatile("fence" ::: "memory");
    if (!(REG(R_STATUS) & S_FEAT_OK)) return -1;

    REG(R_QUEUE_SEL) = 0;
    unsigned int qmax = REG(R_QUEUE_NUM_MAX);
    if (!qmax || (unsigned int)QUEUE_SIZE > qmax) return -1;
    REG(R_QUEUE_NUM) = QUEUE_SIZE;

    desc     = (vdesc_t  *)alloc_page();
    avail    = (vavail_t *)alloc_page();
    used     = (vused_t  *)alloc_page();
    if (!desc || !avail || !used) return -1;

    unsigned long pa;
    pa = (unsigned long)desc;
    REG(R_QUEUE_DESC_LO) = (unsigned int)pa;
    REG(R_QUEUE_DESC_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)avail;
    REG(R_QUEUE_DRV_LO) = (unsigned int)pa;
    REG(R_QUEUE_DRV_HI) = (unsigned int)(pa >> 32);
    pa = (unsigned long)used;
    REG(R_QUEUE_DEV_LO) = (unsigned int)pa;
    REG(R_QUEUE_DEV_HI) = (unsigned int)(pa >> 32);

    REG(R_QUEUE_READY) = 1;
    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");
    return 0;
}

// ---- Публичный init ----
int virtio_blk_init(void) {
    // Сканируем все 8 VirtIO MMIO слотов в поисках блочного устройства (ID=2)
    blk_base = 0;
    for (int i = 0; i < VIRTIO_MMIO_SLOTS; i++) {
        unsigned long base = VIRTIO_MMIO_BASE + (unsigned long)i * VIRTIO_MMIO_STEP;
        volatile unsigned int *magic_reg = (volatile unsigned int *)(base + R_MAGIC);
        volatile unsigned int *id_reg    = (volatile unsigned int *)(base + R_DEVICE_ID);
        if (*magic_reg == 0x74726976 && *id_reg == 2) {
            blk_base = base;
            break;
        }
    }
    if (!blk_base) {
        uart_puts("[virtio] block device not found (scanned 8 MMIO slots)\r\n");
        // Диагностика: покажем что есть в каждом слоте
        for (int i = 0; i < VIRTIO_MMIO_SLOTS; i++) {
            unsigned long base = VIRTIO_MMIO_BASE + (unsigned long)i * VIRTIO_MMIO_STEP;
            unsigned int magic = *(volatile unsigned int *)(base + R_MAGIC);
            unsigned int devid = *(volatile unsigned int *)(base + R_DEVICE_ID);
            if (magic == 0x74726976) {
                uart_puts("[virtio]   slot "); uart_putc('0' + i);
                uart_puts(" id="); uart_putc('0' + (devid & 0xF));
                uart_puts("\r\n");
            }
        }
        return -1;
    }
    uart_puts("[virtio] found blk @ 0x1000");
    uart_putc('0' + (char)((blk_base - VIRTIO_MMIO_BASE) / VIRTIO_MMIO_STEP + 1));
    uart_puts("000\r\n");

    req_page = alloc_page();
    if (!req_page) { uart_puts("[virtio] OOM req_page\r\n"); return -1; }

    unsigned int ver = REG(R_VERSION);
    uart_puts("[virtio] VERSION="); uart_putc('0' + (char)(ver & 0xF)); uart_puts("\r\n");

    // Печатаем реальные значения MAGIC/VERSION/DEVICE_ID для диагностики
    uart_puts("[virtio] MAGIC=0x");
    unsigned int magic = REG(R_MAGIC);
    for (int s = 28; s >= 0; s -= 4) uart_putc("0123456789abcdef"[(magic >> s) & 0xF]);
    uart_puts(" DEV_ID="); uart_putc('0' + (char)(REG(R_DEVICE_ID) & 0xF));
    uart_puts("\r\n");

    int rc;
    if (ver == 1) { rc = init_v1(); }
    else          { rc = init_v2(); }
    if (rc != 0) {
        uart_puts("[virtio] init failed\r\n");
        return -1;
    }

    // Ёмкость в конфиг-пространстве (u64 at offset 0)
    unsigned int clo = *(volatile unsigned int *)(blk_base + R_CONFIG + 0);
    unsigned int chi = *(volatile unsigned int *)(blk_base + R_CONFIG + 4);
    capacity = ((unsigned long)chi << 32) | clo;

    last_used = 0;
    ready = 1;
    uart_puts("[virtio] blk ready, ");
    put_dec(capacity);
    uart_puts(" sectors (");
    put_dec(capacity / 2);
    uart_puts(" KB)\r\n");
    return 0;
}

// ---- Синхронный I/O (polling) ----
static int do_io(unsigned int type, unsigned long sector, void *buf) {
    if (!ready) return -1;

    blk_req_t     *hdr    = (blk_req_t     *)req_page;
    unsigned char *data   = (unsigned char *)req_page + sizeof(blk_req_t);
    unsigned char *status = data + SECTOR_SIZE;

    hdr->type = type; hdr->reserved = 0; hdr->sector = sector;
    *status = 0xFF;

    if (type == BLK_T_OUT) {
        const unsigned char *s = (const unsigned char *)buf;
        for (unsigned int i = 0; i < SECTOR_SIZE; i++) data[i] = s[i];
    }

    desc[0].addr = (unsigned long)hdr;
    desc[0].len  = sizeof(blk_req_t);
    desc[0].flags = DESC_NEXT; desc[0].next = 1;

    desc[1].addr = (unsigned long)data;
    desc[1].len  = SECTOR_SIZE;
    desc[1].flags = (type == BLK_T_IN ? DESC_WRITE : 0) | DESC_NEXT;
    desc[1].next = 2;

    desc[2].addr = (unsigned long)status;
    desc[2].len  = 1;
    desc[2].flags = DESC_WRITE; desc[2].next = 0;

    unsigned short ai = avail->idx;
    avail->ring[ai % QUEUE_SIZE] = 0;
    __asm__ volatile("fence ow, ow" ::: "memory");
    avail->idx = (unsigned short)(ai + 1);
    __asm__ volatile("fence ow, ow" ::: "memory");

    REG(R_QUEUE_NOTIFY) = 0;

    for (unsigned int spin = 0; ; spin++) {
        __asm__ volatile("fence ir, ir" ::: "memory");
        if (used->idx != last_used) break;
        if (spin > 20000000U) { uart_puts("[virtio] timeout\r\n"); return -1; }
    }
    last_used++;
    REG(R_INT_ACK) = REG(R_INT_STATUS);

    if (*status != 0) {
        uart_puts("[virtio] error status=");
        uart_putc('0' + (*status & 0xF));
        uart_puts("\r\n");
        return -1;
    }

    if (type == BLK_T_IN) {
        unsigned char *dst = (unsigned char *)buf;
        for (unsigned int i = 0; i < SECTOR_SIZE; i++) dst[i] = data[i];
    }
    return 0;
}

int virtio_blk_read(unsigned long sector, void *buf) {
    return do_io(BLK_T_IN, sector, buf);
}
int virtio_blk_write(unsigned long sector, const void *buf) {
    return do_io(BLK_T_OUT, sector, (void *)buf);
}
unsigned long virtio_blk_capacity(void) { return capacity; }
