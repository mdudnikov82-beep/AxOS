#include "bootsplash.h"
#include "virtio_gpu.h"
#include "drivers/uart.h"

/* Own CSR `time` read (10 MHz CLINT timebase, same as kernel_main.c's
 * read_time()/gettime() elsewhere) - kept local rather than shared,
 * matching this codebase's existing per-file-driver convention (each
 * virtio driver reimplements its own tiny MMIO/CSR helpers too). This
 * runs entirely before timer_init()/proc_init() exist, so a plain
 * busy-wait is the only pacing option - no scheduler to sleep() on yet. */
static inline unsigned long splash_read_time(void) {
    unsigned long t;
    __asm__ volatile("csrr %0, time" : "=r"(t));
    return t;
}

static void delay_ms(unsigned int ms) {
    unsigned long target = splash_read_time() + (unsigned long)ms * 10000UL;
    while (splash_read_time() < target) { }
}

/* Same 5-wide x 6-tall block letterforms already verified live in
 * src/user/rv64/axsh.c's ASCII startup banner - reused here as filled
 * squares instead of monospace text glyphs, at a much bigger scale. */
static const char *const LETTER_A[6] = { " ### ", "#   #", "#   #", "#####", "#   #", "#   #" };
static const char *const LETTER_X[6] = { "#   #", "#   #", " # # ", "  #  ", " # # ", "#   #" };
static const char *const LETTER_O[6] = { " ### ", "#   #", "#   #", "#   #", "#   #", " ### " };
static const char *const LETTER_S[6] = { " ####", "#    ", " ### ", "    #", "    #", "#### " };

typedef struct {
    const char *const *rows;
    unsigned int r, g, b;
} letter_spec_t;

#define BGRA(r, g, b) ((0xFFu << 24) | ((unsigned int)(r) << 16) | ((unsigned int)(g) << 8) | (unsigned int)(b))

#define CELL  20u
#define GAP   6u
#define PITCH (CELL + GAP)          /* 26 */
#define LETTER_W (5u * PITCH)       /* 130 */
#define LETTER_GAP 40u
#define LETTER_PITCH (LETTER_W + LETTER_GAP)  /* 170 */
#define LOGO_Y 160u

static void draw_letter(const letter_spec_t *L, unsigned int lx, unsigned int pct) {
    unsigned int r = L->r * pct / 100u;
    unsigned int g = L->g * pct / 100u;
    unsigned int b = L->b * pct / 100u;
    unsigned int bgra = BGRA(r, g, b);
    for (unsigned int row = 0; row < 6; row++) {
        const char *s = L->rows[row];
        for (unsigned int col = 0; col < 5; col++) {
            if (s[col] != '#') continue;
            virtio_gpu_fill_rect(lx + col * PITCH, LOGO_Y + row * PITCH, CELL, CELL, bgra);
        }
    }
}

void boot_splash_show(void) {
    if (!virtio_gpu_ready()) return;

    static const letter_spec_t LETTERS[4] = {
        { LETTER_A, 0,   190, 255 },  /* cyan-blue  */
        { LETTER_X, 255, 70,  130 },  /* pink       */
        { LETTER_O, 255, 205, 0   },  /* gold       */
        { LETTER_S, 60,  220, 120 },  /* green      */
    };

    unsigned int logo_x0 = (GPU_FB_WIDTH - (4u * LETTER_W + 3u * LETTER_GAP)) / 2u;

    uart_puts("[splash] starting\r\n");

    virtio_gpu_fill_rect(0, 0, GPU_FB_WIDTH, GPU_FB_HEIGHT, BGRA(0, 0, 0));
    virtio_gpu_flush();

    /* Letters assemble one at a time, Pixel-dots style. */
    for (unsigned int i = 0; i < 4; i++) {
        draw_letter(&LETTERS[i], logo_x0 + i * LETTER_PITCH, 100);
        virtio_gpu_flush();
        delay_ms(180);
    }

    delay_ms(300);

    /* Whole logo pulses (brightness ramps down/up) a couple of times. */
    static const unsigned int PULSE[] = { 100, 70, 40, 70, 100, 70, 40, 100 };
    for (unsigned int s = 0; s < sizeof(PULSE) / sizeof(PULSE[0]); s++) {
        for (unsigned int i = 0; i < 4; i++)
            draw_letter(&LETTERS[i], logo_x0 + i * LETTER_PITCH, PULSE[s]);
        virtio_gpu_flush();
        delay_ms(100);
    }

    /* "Powered by AxOS" fades in underneath, white on black. */
    const char *text = "Powered by AxOS";
    unsigned int text_w = 16u * (8u * GFX_FONT_SCALE); /* 16 chars, no kerning */
    unsigned int text_x = (GPU_FB_WIDTH - text_w) / 2u;
    unsigned int text_y = LOGO_Y + 6u * PITCH + 40u;

    static const unsigned int FADE[] = { 20, 40, 60, 80, 100 };
    for (unsigned int s = 0; s < sizeof(FADE) / sizeof(FADE[0]); s++) {
        unsigned int c = 255u * FADE[s] / 100u;
        virtio_gpu_draw_text(text_x, text_y, text, BGRA(c, c, c));
        virtio_gpu_flush();
        delay_ms(90);
    }

    delay_ms(500);
    uart_puts("[splash] done\r\n");
    /* console_init() (called right after this from kernel_main.c) blanks
     * the screen again before AxSH's own output starts, so no cleanup
     * clear is needed here. */
}
