#include "virtio_sound.h"
#include "pmem.h"
#include "drivers/uart.h"

// VirtIO-sound — same MMIO virtqueue scaffold as virtio_net.c (see that
// file's own comment), generalized to FOUR queues instead of two via
// the same setup_queue_v1/v2(idx, vqueue_t*) pattern, just called in a
// loop. Control-queue command submission mirrors virtio_gpu.c's
// send_cmd()/hdr-in-buffer-at-offset-0 idiom, but the tx queue's PCM
// payload (up to ~4KB per chunk) is too big to share a page with even
// a small response at a fixed offset, so tx uses two SEPARATE
// dedicated pages (data, status) instead of the single cmd@0/resp@512
// page GPU commands use - see submit_and_wait() below, which is
// generic over queue index and buffers so both paths share it.
//
// Protocol facts (VIRTIO 1.2 §5.14 - command codes, struct layouts,
// format/rate bit numbers) were independently verified against spec
// knowledge by a design review before this was written, since this is
// the first audio driver in the codebase with no prior art to lean on.

#define VIRTIO_MMIO_BASE  0x10001000UL
#define VIRTIO_MMIO_STEP  0x1000UL
#define VIRTIO_MMIO_SLOTS 8

#define SOUND_DEVICE_ID 25

#define QUEUE_SIZE  8
#define PAGE_SHIFT  12

#define CTRLQ      0
#define EVENTQ     1
#define TXQ        2
#define RXQ        3
#define NUM_QUEUES 4

static unsigned long snd_base = 0;

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
#define R_CONFIG          0x100   // jacks(u32)@+0, streams(u32)@+4, chmaps(u32)@+8

#define REG(off)    (*(volatile unsigned int *)(snd_base + (off)))
#define CFGU32(off) (*(volatile unsigned int *)(snd_base + R_CONFIG + (off)))

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
    vdesc_t  *desc;
    vavail_t *avail;
    vused_t  *used;
    unsigned short last_used;
} vqueue_t;

static vqueue_t queues[NUM_QUEUES];
static int ready = 0;

/* ---- virtio-sound protocol (verified against spec, see file comment) ---- */
#define VIRTIO_SND_R_PCM_INFO       0x0100
#define VIRTIO_SND_R_PCM_SET_PARAMS 0x0101
#define VIRTIO_SND_R_PCM_PREPARE    0x0102
#define VIRTIO_SND_R_PCM_RELEASE    0x0103
#define VIRTIO_SND_R_PCM_START      0x0104
#define VIRTIO_SND_R_PCM_STOP       0x0105
#define VIRTIO_SND_S_OK             0x8000

#define VIRTIO_SND_PCM_FMT_S16    5
#define VIRTIO_SND_PCM_RATE_44100 6
#define VIRTIO_SND_PCM_RATE_48000 7

typedef struct { unsigned int code; } __attribute__((packed)) snd_hdr_t;
typedef struct { snd_hdr_t hdr; unsigned int stream_id; } __attribute__((packed)) snd_pcm_hdr_t;
typedef struct { snd_hdr_t hdr; unsigned int start_id, count, size; } __attribute__((packed)) snd_query_info_t;
typedef struct { unsigned int hda_fn_nid; } __attribute__((packed)) snd_info_t;
typedef struct {
    snd_info_t    hdr;
    unsigned int  features;
    unsigned long formats;         /* bitmask, bit N = VIRTIO_SND_PCM_FMT_N supported */
    unsigned long rates;           /* bitmask, bit N = VIRTIO_SND_PCM_RATE_N supported */
    unsigned char direction, channels_min, channels_max, padding[5];
} __attribute__((packed)) snd_pcm_info_t;
typedef struct {
    snd_pcm_hdr_t hdr;
    unsigned int  buffer_bytes, period_bytes;
    unsigned int  features;   /* MUST be 0 - shared-memory/polling extensions, unused here */
    unsigned char channels, format, rate, padding;
} __attribute__((packed)) snd_pcm_set_params_t;
typedef struct { unsigned int status, latency_bytes; } __attribute__((packed)) snd_pcm_status_t;

static void *ctrl_cmd_buf;    /* cmd @ 0, resp @ 512 - same idiom as virtio_gpu.c */
static void *tx_data_buf;     /* [4-byte LE stream_id][PCM data], one page */
static void *tx_status_buf;   /* snd_pcm_status_t response, one page */

#define TX_CHUNK_MAX 4092   /* one page minus the 4-byte stream_id header */

static int info_cached = 0;
static unsigned long cached_formats, cached_rates;
static unsigned char cached_ch_min, cached_ch_max;
static unsigned char chosen_channels, chosen_format, chosen_rate;
static unsigned int  chosen_rate_hz;

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
        uart_puts("[sound] v1: pages not adjacent!\r\n");
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

/* Generic 2-descriptor submit+poll, used for BOTH controlq commands and
 * txq PCM chunks: desc0=device-readable(cmd/data), desc1=device-
 * writable(resp/status), notify `qidx`, spin on used->idx advancing
 * (same ~20M-iteration timeout idiom as virtio_gpu.c/virtio_net.c). */
static int submit_and_wait(unsigned int qidx, void *cmd, unsigned int cmd_len,
                           void *resp, unsigned int resp_len) {
    vqueue_t *q = &queues[qidx];
    q->desc[0].addr = (unsigned long)cmd;
    q->desc[0].len  = cmd_len;
    q->desc[0].flags = DESC_NEXT; q->desc[0].next = 1;

    q->desc[1].addr = (unsigned long)resp;
    q->desc[1].len  = resp_len;
    q->desc[1].flags = DESC_WRITE; q->desc[1].next = 0;

    unsigned short ai = q->avail->idx;
    q->avail->ring[ai % QUEUE_SIZE] = 0;
    __asm__ volatile("fence ow, ow" ::: "memory");
    q->avail->idx = (unsigned short)(ai + 1);
    __asm__ volatile("fence ow, ow" ::: "memory");

    REG(R_QUEUE_NOTIFY) = qidx;

    for (unsigned int spin = 0; ; spin++) {
        __asm__ volatile("fence ir, ir" ::: "memory");
        if (q->used->idx != q->last_used) break;
        if (spin > 20000000U) { uart_puts("[sound] command timeout\r\n"); return -1; }
    }
    q->last_used++;
    return 0;
}

static int ctrl_cmd(unsigned int cmd_len, unsigned int resp_len) {
    return submit_and_wait(CTRLQ, ctrl_cmd_buf, cmd_len,
                           (unsigned char *)ctrl_cmd_buf + 512, resp_len);
}

/* The response's status lands in the same 4-byte position as a
 * request's own `code` field - virtio_snd_hdr is reused as the bare
 * "just a status" response for every PCM control command. */
static unsigned int ctrl_resp_status(void) {
    return ((snd_hdr_t *)((unsigned char *)ctrl_cmd_buf + 512))->code;
}

static int pcm_simple(unsigned int code) {
    snd_pcm_hdr_t *req = (snd_pcm_hdr_t *)ctrl_cmd_buf;
    req->hdr.code = code;
    req->stream_id = 0;
    if (ctrl_cmd(sizeof(*req), sizeof(snd_hdr_t)) != 0) return -1;
    if (ctrl_resp_status() != VIRTIO_SND_S_OK) { uart_puts("[sound] pcm command rejected\r\n"); return -1; }
    return 0;
}

static int pcm_set_params(unsigned int buffer_bytes, unsigned int period_bytes) {
    snd_pcm_set_params_t *req = (snd_pcm_set_params_t *)ctrl_cmd_buf;
    req->hdr.hdr.code = VIRTIO_SND_R_PCM_SET_PARAMS;
    req->hdr.stream_id = 0;
    req->buffer_bytes = buffer_bytes;
    req->period_bytes = period_bytes;
    req->features = 0;
    req->channels = chosen_channels;
    req->format = chosen_format;
    req->rate = chosen_rate;
    req->padding = 0;
    if (ctrl_cmd(sizeof(*req), sizeof(snd_hdr_t)) != 0) return -1;
    if (ctrl_resp_status() != VIRTIO_SND_S_OK) { uart_puts("[sound] SET_PARAMS rejected\r\n"); return -1; }
    return 0;
}

/* Queries PCM_INFO for stream 0 once (cached - device capabilities
 * don't change at runtime), picks S16 (required, fails if unsupported)
 * and 44100-then-48000 Hz, and mono if the device's [channels_min,
 * channels_max] range allows it. No jack/chmap introspection at all -
 * a stream is legitimately usable without it. */
static int query_pcm_info(void) {
    snd_query_info_t *req = (snd_query_info_t *)ctrl_cmd_buf;
    req->hdr.code = VIRTIO_SND_R_PCM_INFO;
    req->start_id = 0;
    req->count = 1;
    req->size = sizeof(snd_pcm_info_t);

    if (ctrl_cmd(sizeof(*req), sizeof(snd_hdr_t) + sizeof(snd_pcm_info_t)) != 0) return -1;
    if (ctrl_resp_status() != VIRTIO_SND_S_OK) { uart_puts("[sound] PCM_INFO failed\r\n"); return -1; }

    snd_pcm_info_t *info = (snd_pcm_info_t *)((unsigned char *)ctrl_cmd_buf + 512 + sizeof(snd_hdr_t));
    cached_formats = info->formats;
    cached_rates   = info->rates;
    cached_ch_min  = info->channels_min;
    cached_ch_max  = info->channels_max;

    if (!(cached_formats & (1UL << VIRTIO_SND_PCM_FMT_S16))) {
        uart_puts("[sound] device doesn't support S16 samples\r\n");
        return -1;
    }
    if (cached_rates & (1UL << VIRTIO_SND_PCM_RATE_44100)) {
        chosen_rate = VIRTIO_SND_PCM_RATE_44100; chosen_rate_hz = 44100;
    } else if (cached_rates & (1UL << VIRTIO_SND_PCM_RATE_48000)) {
        chosen_rate = VIRTIO_SND_PCM_RATE_48000; chosen_rate_hz = 48000;
    } else {
        uart_puts("[sound] device doesn't support 44100 or 48000 Hz\r\n");
        return -1;
    }
    chosen_format = VIRTIO_SND_PCM_FMT_S16;
    chosen_channels = (cached_ch_min <= 1 && 1 <= cached_ch_max) ? 1 : cached_ch_min;
    if (chosen_channels == 0) chosen_channels = 1;

    info_cached = 1;
    return 0;
}

static int send_tx_chunk(unsigned int bytes) {
    if (submit_and_wait(TXQ, tx_data_buf, 4 + bytes, tx_status_buf, sizeof(snd_pcm_status_t)) != 0)
        return -1;
    snd_pcm_status_t *st = (snd_pcm_status_t *)tx_status_buf;
    if (st->status != VIRTIO_SND_S_OK) { uart_puts("[sound] tx chunk rejected\r\n"); return -1; }
    return 0;
}

int virtio_sound_init(void) {
    snd_base = 0;
    for (int i = 0; i < VIRTIO_MMIO_SLOTS; i++) {
        unsigned long base = VIRTIO_MMIO_BASE + (unsigned long)i * VIRTIO_MMIO_STEP;
        volatile unsigned int *magic_reg = (volatile unsigned int *)(base + R_MAGIC);
        volatile unsigned int *id_reg    = (volatile unsigned int *)(base + R_DEVICE_ID);
        if (*magic_reg == 0x74726976 && *id_reg == SOUND_DEVICE_ID) { snd_base = base; break; }
    }
    if (!snd_base) {
        uart_puts("[sound] virtio-sound device not found (scanned 8 MMIO slots)\r\n");
        return -1;
    }
    uart_puts("[sound] found @ 0x1000");
    uart_putc('0' + (char)((snd_base - VIRTIO_MMIO_BASE) / VIRTIO_MMIO_STEP + 1));
    uart_puts("000\r\n");

    ctrl_cmd_buf  = alloc_page();
    tx_data_buf   = alloc_page();
    tx_status_buf = alloc_page();
    if (!ctrl_cmd_buf || !tx_data_buf || !tx_status_buf) {
        uart_puts("[sound] OOM allocating buffers\r\n");
        return -1;
    }

    unsigned int ver = REG(R_VERSION);

    REG(R_STATUS) = 0;
    __asm__ volatile("fence" ::: "memory");
    REG(R_STATUS) = S_ACK | S_DRIVER;

    if (ver == 1) {
        uart_puts("[sound] using legacy v1 MMIO\r\n");
        REG(R_DRV_FEAT) = 0;   /* no sound-specific feature bits needed */
        REG(R_GUEST_PAGE_SIZE) = PAGE_SIZE;
    } else {
        uart_puts("[sound] using modern v2 MMIO\r\n");
        REG(R_DRV_FEAT_SEL) = 0; REG(R_DRV_FEAT) = 0;
        REG(R_DRV_FEAT_SEL) = 1; REG(R_DRV_FEAT) = 1;   /* VIRTIO_F_VERSION_1 (bit 32) */
        REG(R_STATUS) |= S_FEAT_OK;
        __asm__ volatile("fence" ::: "memory");
        if (!(REG(R_STATUS) & S_FEAT_OK)) { uart_puts("[sound] FEATURES_OK rejected\r\n"); return -1; }
    }

    int (*setup)(unsigned int, vqueue_t *) = (ver == 1) ? setup_queue_v1 : setup_queue_v2;
    static const char *qnames[NUM_QUEUES] = { "ctrlq", "eventq", "txq", "rxq" };
    for (unsigned int i = 0; i < NUM_QUEUES; i++) {
        if (setup(i, &queues[i]) != 0) {
            uart_puts("[sound] "); uart_puts(qnames[i]); uart_puts(" init failed\r\n");
            return -1;
        }
        queues[i].last_used = 0;
    }

    REG(R_STATUS) |= S_DRIVER_OK;
    __asm__ volatile("fence" ::: "memory");

    if (CFGU32(4) < 1) {
        uart_puts("[sound] device reports 0 PCM streams\r\n");
        return -1;
    }

    ready = 1;
    uart_puts("[sound] ready\r\n");
    return 0;
}

int virtio_sound_ready(void) { return ready; }

int virtio_sound_beep(unsigned int freq_hz, unsigned int duration_ms) {
    if (!ready) return -1;
    if (duration_ms == 0) return 0;
    if (freq_hz < 20 || freq_hz > 20000) return -1;   /* sane audible range */

    if (!info_cached && query_pcm_info() != 0) return -1;

    unsigned int rate = chosen_rate_hz;
    if (freq_hz >= rate / 2) return -1;   /* Nyquist guard - also keeps half_period below nonzero */

    unsigned int bytes_per_sample = 2u * chosen_channels;   /* S16 = 2 bytes/channel */
    unsigned int period_bytes = (TX_CHUNK_MAX / bytes_per_sample) * bytes_per_sample;
    if (period_bytes == 0) return -1;

    if (pcm_set_params(period_bytes, period_bytes) != 0) return -1;
    if (pcm_simple(VIRTIO_SND_R_PCM_PREPARE) != 0) return -1;
    if (pcm_simple(VIRTIO_SND_R_PCM_START) != 0) {
        pcm_simple(VIRTIO_SND_R_PCM_RELEASE);
        return -1;
    }

    unsigned int half_period = rate / (2u * freq_hz);
    if (half_period == 0) half_period = 1;
    unsigned long total_samples = ((unsigned long)rate * duration_ms) / 1000;
    unsigned int samples_per_chunk = period_bytes / bytes_per_sample;

    /* stream_id=0, little-endian, set once - the tx buffer's header
     * never changes between chunks, only the PCM payload after it. */
    unsigned char *hdr_bytes = (unsigned char *)tx_data_buf;
    hdr_bytes[0] = 0; hdr_bytes[1] = 0; hdr_bytes[2] = 0; hdr_bytes[3] = 0;
    short *pcm = (short *)((unsigned char *)tx_data_buf + 4);

    unsigned long sample_n = 0;
    int ok = 1;
    while (sample_n < total_samples && ok) {
        unsigned int n = 0;
        while (n < samples_per_chunk && sample_n < total_samples) {
            /* Square wave, phase-continuous across chunks since the sign
             * is a pure function of the ABSOLUTE sample index (never
             * reset per chunk) - no click at chunk boundaries. Amplitude
             * kept well under full INT16 scale to avoid harsh clipping
             * in QEMU's audio backend. */
            short v = (((sample_n / half_period) & 1UL) == 0) ? 10000 : -10000;
            for (unsigned int c = 0; c < chosen_channels; c++) pcm[n * chosen_channels + c] = v;
            n++; sample_n++;
        }
        if (send_tx_chunk(n * bytes_per_sample) != 0) ok = 0;
    }

    pcm_simple(VIRTIO_SND_R_PCM_STOP);
    pcm_simple(VIRTIO_SND_R_PCM_RELEASE);
    return ok ? 0 : -1;
}
