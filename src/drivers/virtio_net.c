// =================================================================
//  Драйвер virtio-net поверх LEGACY PCI-транспорта (I/O-порты)
// =================================================================
//
// В отличие от RISC-V порта (src/arch/riscv64/virtio_net.c, virtio-net
// поверх MMIO), на x86 у virtio-net-pci нет отдельного набора регистров
// на фиксированном физическом адресе - всё через BAR0, найденный
// перечислением PCI (pci.c), и через порты ввода-вывода, а не память.
// Сам протокол очередей (дескрипторы/avail/used ring) - тот же самый
// virtio, отличается только "как достучаться до регистров".
//
// QEMU по умолчанию делает virtio-net-pci "transitional" устройством
// (device_id=0x1000, поддерживает и legacy, и modern интерфейс) - этот
// драйвер сознательно использует ТОЛЬКО legacy-интерфейс (проще: нет
// capability list поверх PCI config space, нет отдельных modern-only
// регистров), достаточно `-netdev user,id=net0 -device
// virtio-net-pci,netdev=net0` без дополнительных флагов.
//
// ВАЖНО про Queue Size: у legacy PCI-транспорта размер очереди (offset
// 0x0C, 16 бит) - ТОЛЬКО ДЛЯ ЧТЕНИЯ, в отличие от MMIO-транспорта (там
// есть отдельный R_QUEUE_NUM_MAX не путать с записываемым R_QUEUE_NUM) -
// драйвер не может попросить очередь поменьше, макет памяти (desc+avail+
// used) обязан соответствовать РЕАЛЬНОМУ размеру, который вернуло
// устройство. QEMU у virtio-net-pci сообщает 256 - проверяем это
// явно при инициализации и отказываемся работать, если когда-нибудь
// станет иначе, вместо того чтобы тихо всё сломать неверным layout'ом.
// Сам драйвер при этом использует только первые NUM_ACTIVE=8 слотов
// дескрипторной таблицы (как и RISC-V версия) - остальные 248 просто не
// задействуются, экономя память на RX-буферах.

#include "pci.h"
#include "dma_pool.h"

// Тики PIT (kernel.c, 100 Гц) - для тайм-аута ожидания завершения TX (см.
// virtio_net_send) через sti+hlt вместо busy-spin, тот же приём, что и
// ide_wait_irq() в ide.c.
extern volatile unsigned long timer_ticks;

#define VIRTIO_VENDOR_ID   0x1AF4
#define VIRTIO_NET_DEV_ID  0x1000   // legacy/transitional virtio-net

#define QUEUE_SIZE  256   // фактический размер очереди - см. комментарий выше
#define NUM_ACTIVE  8     // сколько слотов реально используем (RX и TX)
#define PAGE_SIZE   4096

#define RXQ 0
#define TXQ 1

#define MAX_FRAME     1514
#define NET_HDR_SIZE  10             // virtio_net_hdr без num_buffers
#define BUF_SIZE      (NET_HDR_SIZE + MAX_FRAME)

// --- Регистры legacy virtio-pci (смещения от io_base) ---
#define R_HOST_FEATURES  0x00  // 32-bit R
#define R_GUEST_FEATURES 0x04  // 32-bit W
#define R_QUEUE_PFN      0x08  // 32-bit RW
#define R_QUEUE_SIZE     0x0C  // 16-bit R (см. комментарий выше - НЕ пишем сюда)
#define R_QUEUE_SELECT   0x0E  // 16-bit W
#define R_QUEUE_NOTIFY   0x10  // 16-bit W
#define R_STATUS         0x12  // 8-bit RW
#define R_ISR            0x13  // 8-bit R
#define R_CONFIG         0x14  // device config: mac[6] @+0, status u16 @+6

#define S_ACK       1
#define S_DRIVER    2
#define S_DRIVER_OK 4

#define VIRTIO_NET_F_MAC 5

#define DESC_NEXT  1
#define DESC_WRITE 2

static unsigned int io_base = 0;

static unsigned char port_byte_in(unsigned short port) {
    unsigned char result;
    __asm__ volatile("inb %%dx, %%al" : "=a"(result) : "d"(port));
    return result;
}
static void port_byte_out(unsigned short port, unsigned char data) {
    __asm__ volatile("outb %%al, %%dx" : : "a"(data), "d"(port));
}
static unsigned short port_word_in(unsigned short port) {
    unsigned short result;
    __asm__ volatile("inw %%dx, %%ax" : "=a"(result) : "d"(port));
    return result;
}
static void port_word_out(unsigned short port, unsigned short data) {
    __asm__ volatile("outw %%ax, %%dx" : : "a"(data), "d"(port));
}
static unsigned int port_long_in(unsigned short port) {
    unsigned int result;
    __asm__ volatile("inl %%dx, %%eax" : "=a"(result) : "d"(port));
    return result;
}
static void port_long_out(unsigned short port, unsigned int data) {
    __asm__ volatile("outl %%eax, %%dx" : : "a"(data), "d"(port));
}

#define REGB(off) port_byte_in((unsigned short)(io_base + (off)))
#define REGB_OUT(off, v) port_byte_out((unsigned short)(io_base + (off)), (v))
#define REGW(off) port_word_in((unsigned short)(io_base + (off)))
#define REGW_OUT(off, v) port_word_out((unsigned short)(io_base + (off)), (v))
#define REGL(off) port_long_in((unsigned short)(io_base + (off)))
#define REGL_OUT(off, v) port_long_out((unsigned short)(io_base + (off)), (v))

typedef struct {
    unsigned long long addr;
    unsigned int        len;
    unsigned short      flags;
    unsigned short      next;
} __attribute__((packed)) vdesc_t;

typedef struct { unsigned int id, len; } vused_elem_t;

// Кэш физ.адресов очередей (RX=0, TX=1) - десктрипторная таблица всегда в
// начале выделенного региона, avail сразу после (256*16=4096, ровно
// страница), used на следующей странице после avail (avail не заполняет
// свою страницу целиком - выравнивание used обязано быть постраничным).
typedef struct {
    vdesc_t*  desc;
    unsigned char* avail;   // flags(2) idx(2) ring[QUEUE_SIZE](2 каждый)
    unsigned char* used;    // flags(2) idx(2) elem[QUEUE_SIZE](8 каждый)
    unsigned short last_used;
} vqueue_t;

static vqueue_t rxq, txq;
static unsigned char* rx_bufs[NUM_ACTIVE];
static unsigned char* tx_scratch;
static unsigned char mac[6];
static int ready = 0;

// PFN virtqueue нужна выровненная на 4КБ ФИЗИЧЕСКАЯ страница. Раньше (пока
// куча ядра была identity-mapped) для этого сгодился бы и malloc(), но
// куча теперь живёт на случайном высоком виртуальном адресе, развязанном
// от физического (см. "64-битный KASLR" в paging.c) - использовать
// malloc()-указатель как физический адрес больше нельзя. dma_pool.c даёт
// память, которая ВСЕГДА identity-mapped, специально для таких случаев.
static void* alloc_pages_zeroed(unsigned int num_pages) {
    return dma_alloc_pages(num_pages);
}

static void avail_put16(unsigned char* avail, unsigned int off, unsigned short v) {
    avail[off] = (unsigned char)(v & 0xFF);
    avail[off + 1] = (unsigned char)(v >> 8);
}
static unsigned short avail_get16(unsigned char* p, unsigned int off) {
    return (unsigned short)(p[off] | (p[off + 1] << 8));
}

static int setup_queue(unsigned int idx, vqueue_t* q) {
    REGW_OUT(R_QUEUE_SELECT, (unsigned short)idx);
    unsigned short qsize = REGW(R_QUEUE_SIZE);
    if (qsize != QUEUE_SIZE) return -1;   // см. комментарий вверху файла

    // 1 страница desc (256*16=4096) + 1 страница avail (516Б, не заполнена
    // целиком, но used обязан начинаться со следующей страницы) + 1
    // страница used (2052Б) = 3 страницы, выделяем 4 с запасом.
    unsigned char* base = (unsigned char*)alloc_pages_zeroed(4);
    if (!base) return -1;

    q->desc  = (vdesc_t*)base;
    q->avail = base + PAGE_SIZE;
    q->used  = base + 2 * PAGE_SIZE;
    q->last_used = 0;

    unsigned long long pfn = (unsigned long long)base / PAGE_SIZE;
    REGL_OUT(R_QUEUE_PFN, (unsigned int)pfn);
    return 0;
}

// Кладёт rx_bufs[i] обратно в avail-ring очереди RX как пустой
// device-writable слот.
static void rx_repost(unsigned int i) {
    rxq.desc[i].addr  = (unsigned long long)rx_bufs[i];
    rxq.desc[i].len   = BUF_SIZE;
    rxq.desc[i].flags = DESC_WRITE;
    rxq.desc[i].next  = 0;

    // Позиция в avail-ring крутится по модулю ПОЛНОГО QUEUE_SIZE (256) -
    // так, как её понимает устройство - а не NUM_ACTIVE (8, сколько разных
    // id дескрипторов мы реально используем). Это два независимых понятия:
    // id - КАКОЙ буфер, позиция в кольце - КУДА в 256-слотный ring его
    // положить на этот раз.
    unsigned short ai = avail_get16(rxq.avail, 2);   // idx at offset 2
    unsigned int ring_off = 4 + (unsigned int)(ai % QUEUE_SIZE) * 2;
    avail_put16(rxq.avail, ring_off, (unsigned short)i);
    __asm__ volatile("" ::: "memory");
    avail_put16(rxq.avail, 2, (unsigned short)(ai + 1));
}

int virtio_net_init(void) {
    static struct pci_device devs[32];
    unsigned int count = pci_scan(devs, 32);

    io_base = 0;
    unsigned char bus = 0, dev = 0, fn = 0;
    int found = 0;
    for (unsigned int i = 0; i < count && i < 32; i++) {
        if (devs[i].vendor_id == VIRTIO_VENDOR_ID && devs[i].device_id == VIRTIO_NET_DEV_ID) {
            bus = devs[i].bus; dev = devs[i].device; fn = devs[i].function;
            found = 1;
            break;
        }
    }
    if (!found) return -1;

    unsigned int bar0 = pci_config_read32(bus, dev, fn, 0x10);
    if (!(bar0 & 0x1)) return -1;   // BAR0 должен быть I/O space (бит0=1) для legacy virtio
    io_base = bar0 & 0xFFFFFFFCu;

    // Включаем I/O Space (бит0) и Bus Master (бит2) в Command-регистре
    // (offset 0x04). Верхние 16 бит этого dword - Status (write-1-to-clear)
    // - пишем туда 0, это ничего не сбрасывает.
    unsigned int cmd_stat = pci_config_read32(bus, dev, fn, 0x04);
    unsigned int new_cmd = (cmd_stat & 0xFFFF) | 0x1 | 0x4;
    pci_config_write32(bus, dev, fn, 0x04, new_cmd);

    REGB_OUT(R_STATUS, 0);
    REGB_OUT(R_STATUS, S_ACK);
    REGB_OUT(R_STATUS, S_ACK | S_DRIVER);

    REGL_OUT(R_GUEST_FEATURES, (1u << VIRTIO_NET_F_MAC));

    if (setup_queue(RXQ, &rxq) != 0) return -1;
    if (setup_queue(TXQ, &txq) != 0) return -1;

    REGB_OUT(R_STATUS, S_ACK | S_DRIVER | S_DRIVER_OK);

    for (int i = 0; i < 6; i++) mac[i] = REGB(R_CONFIG + i);

    for (unsigned int i = 0; i < NUM_ACTIVE; i++) {
        rx_bufs[i] = (unsigned char*)alloc_pages_zeroed(1);
        if (!rx_bufs[i]) return -1;
    }
    tx_scratch = (unsigned char*)alloc_pages_zeroed(1);
    if (!tx_scratch) return -1;

    for (unsigned int i = 0; i < NUM_ACTIVE; i++) rx_repost(i);
    REGW_OUT(R_QUEUE_NOTIFY, RXQ);

    ready = 1;
    return 0;
}

int virtio_net_ready(void) { return ready; }

void virtio_net_get_mac(unsigned char out[6]) {
    for (int i = 0; i < 6; i++) out[i] = mac[i];
}

int virtio_net_send(const void* frame, unsigned int len) {
    if (!ready) return -1;
    if (len > MAX_FRAME) return -1;

    for (int i = 0; i < NET_HDR_SIZE; i++) tx_scratch[i] = 0;
    const unsigned char* src = (const unsigned char*)frame;
    for (unsigned int i = 0; i < len; i++) tx_scratch[NET_HDR_SIZE + i] = src[i];

    txq.desc[0].addr  = (unsigned long long)tx_scratch;
    txq.desc[0].len   = NET_HDR_SIZE + len;
    txq.desc[0].flags = 0;
    txq.desc[0].next  = 0;

    unsigned short ai = avail_get16(txq.avail, 2);
    unsigned int ring_off = 4 + (unsigned int)(ai % QUEUE_SIZE) * 2;
    avail_put16(txq.avail, ring_off, 0);
    __asm__ volatile("" ::: "memory");
    avail_put16(txq.avail, 2, (unsigned short)(ai + 1));

    REGW_OUT(R_QUEUE_NOTIFY, TXQ);

    // ВАЖНО: ждём завершения через sti+hlt (как ide_wait_irq() в ide.c),
    // а НЕ тугим busy-spin'ом. Реально пойманный баг: с чистым busy-spin
    // кадр УХОДИЛ на провод (подтверждено pcap-захватом на уровне QEMU
    // netdev - ARP-запрос реально долетал, SLIRP реально отвечал), но
    // used->idx в нашей копии памяти никогда не менялся за отведённые
    // 50 млн итераций - похоже, гостевой vCPU, ни разу не выходя из
    // режима исполнения (ни одного VM-exit), не давал циклу событий самого
    // QEMU (который и обслуживает virtio-backend/SLIRP) ни единого шанса
    // прогнать итерацию и дописать used ring. hlt - гарантированный
    // VM-exit на каждой итерации ожидания, чего busy-spin никогда не даёт.
    // int 0x80 - interrupt gate (IF гасится процессором на входе), поэтому
    // sti() обязателен перед hlt - иначе зависнет намертво (см. тот же
    // комментарий у ide_wait_irq()).
    unsigned long deadline = timer_ticks + 500;   // 5 секунд запаса (100 Гц)
    __asm__ volatile("sti");
    while (avail_get16(txq.used, 2) == txq.last_used) {
        if (timer_ticks >= deadline) return -1;
        __asm__ volatile("hlt");
    }
    txq.last_used++;
    return 0;
}

unsigned int virtio_net_recv(void* buf, unsigned int max_len) {
    if (!ready) return 0;
    unsigned short used_idx = avail_get16(rxq.used, 2);
    if (used_idx == rxq.last_used) return 0;

    unsigned int elem_off = 4 + (unsigned int)(rxq.last_used % QUEUE_SIZE) * 8;
    unsigned int slot  = *(unsigned int*)(rxq.used + elem_off);
    unsigned int total = *(unsigned int*)(rxq.used + elem_off + 4);
    rxq.last_used++;

    unsigned int frame_len = (total > NET_HDR_SIZE) ? (total - NET_HDR_SIZE) : 0;
    unsigned int copied = 0;
    if (frame_len > 0 && frame_len <= max_len && slot < NUM_ACTIVE) {
        unsigned char* dst = (unsigned char*)buf;
        unsigned char* s = rx_bufs[slot] + NET_HDR_SIZE;
        for (unsigned int i = 0; i < frame_len; i++) dst[i] = s[i];
        copied = frame_len;
    }

    if (slot < NUM_ACTIVE) {
        rx_repost(slot);
        REGW_OUT(R_QUEUE_NOTIFY, RXQ);
    }
    return copied;
}
