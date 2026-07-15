#include "console.h"
#include "virtio_gpu.h"

// Real on-screen glyph size is 8*GFX_FONT_SCALE square (virtio_gpu_draw_char
// scales up from the 8x8 source bitmap) - was hardcoded to plain 8 here,
// which never matched once GFX_FONT_SCALE became 2: every cell overlapped
// the previous one by half, garbling all console text on screen (caught
// live via a screendump, not from reading the code).
#define CELL_PX      (8 * GFX_FONT_SCALE)
#define CONSOLE_COLS (GPU_FB_WIDTH  / CELL_PX)
#define CONSOLE_ROWS (GPU_FB_HEIGHT / CELL_PX)

#define BGRA(r, g, b) ((0xFFu << 24) | ((unsigned int)(r) << 16) | \
                       ((unsigned int)(g) << 8) | (unsigned int)(b))
#define BG_COLOR BGRA(0, 0, 0)

static unsigned int cur_col = 0, cur_row = 0;
static unsigned int cur_fg  = 0xFFFFFFFFu;   /* white */

/* ESC-parser state: 0=normal, 1=saw ESC, 2=collecting a CSI ("\033[...") */
static int esc_state   = 0;
static int esc_params[4];
static int esc_nparams = 0;

/* Standard ANSI 30-37 foreground palette (bright/bold "1;" prefix is
 * accepted but doesn't change the color — AxSH only ever combines it with
 * an already-saturated color like 36=cyan). */
static const unsigned int ansi_fg[8] = {
    BGRA(0, 0, 0),     /* 30 black   */
    BGRA(255, 0, 0),   /* 31 red     */
    BGRA(0, 255, 0),   /* 32 green   */
    BGRA(255, 255, 0), /* 33 yellow  */
    BGRA(0, 0, 255),   /* 34 blue    */
    BGRA(255, 0, 255), /* 35 magenta */
    BGRA(0, 255, 255), /* 36 cyan    */
    BGRA(255, 255, 255), /* 37 white */
};

static void scroll_up(void) {
    unsigned int *px = (unsigned int *)virtio_gpu_fb();
    unsigned long total_px = (unsigned long)GPU_FB_WIDTH * GPU_FB_HEIGHT;
    unsigned long shift_px = (unsigned long)GPU_FB_WIDTH * CELL_PX;
    for (unsigned long i = 0; i < total_px - shift_px; i++) px[i] = px[i + shift_px];
    virtio_gpu_fill_rect(0, GPU_FB_HEIGHT - CELL_PX, GPU_FB_WIDTH, CELL_PX, BG_COLOR);
    /* The memmove above writes directly into the fb pointer, bypassing
     * putpixel/fill_rect's dirty tracking entirely - without this, only
     * the bottom strip (cleared via the real fill_rect call just above)
     * would be marked dirty, and flush() would leave the rest of the
     * screen showing stale pre-scroll content (old/new text visibly
     * double-exposed - a real artifact caught live, not just theoretical). */
    virtio_gpu_mark_dirty(0, 0, GPU_FB_WIDTH, GPU_FB_HEIGHT);
}

static void draw_cell(unsigned int col, unsigned int row, char ch) {
    unsigned int x = col * CELL_PX, y = row * CELL_PX;
    virtio_gpu_fill_rect(x, y, CELL_PX, CELL_PX, BG_COLOR);
    virtio_gpu_draw_char(x, y, ch, cur_fg);
}

static void newline(void) {
    cur_col = 0;
    cur_row++;
    if (cur_row >= CONSOLE_ROWS) { scroll_up(); cur_row = CONSOLE_ROWS - 1; }
}

/* Executes one fully-parsed CSI sequence ("\033[<params><final>"). */
static void handle_csi(char final) {
    if (final == 'm') {
        int n = esc_nparams ? esc_nparams : 1;
        for (int i = 0; i < n; i++) {
            int p = esc_nparams ? esc_params[i] : 0;
            if (p == 0) cur_fg = 0xFFFFFFFFu;
            else if (p >= 30 && p <= 37) cur_fg = ansi_fg[p - 30];
            /* p==1 (bold) and anything else: no-op */
        }
    } else if (final == 'J') {
        virtio_gpu_fill_rect(0, 0, GPU_FB_WIDTH, GPU_FB_HEIGHT, BG_COLOR);
        cur_col = 0; cur_row = 0;
    } else if (final == 'H') {
        cur_col = 0; cur_row = 0;
    } else if (final == 'K') {
        virtio_gpu_fill_rect(cur_col * CELL_PX, cur_row * CELL_PX,
                             GPU_FB_WIDTH - cur_col * CELL_PX, CELL_PX, BG_COLOR);
    }
    /* Unrecognized final bytes: silently ignored. */
}

static void console_putc(char c) {
    if (esc_state == 1) {
        if (c == '[') { esc_state = 2; esc_nparams = 0; esc_params[0] = 0; }
        else esc_state = 0;
        return;
    }
    if (esc_state == 2) {
        if (c >= '0' && c <= '9') {
            esc_params[esc_nparams] = esc_params[esc_nparams] * 10 + (c - '0');
            return;
        }
        if (c == ';') {
            if (esc_nparams < 3) { esc_nparams++; esc_params[esc_nparams] = 0; }
            return;
        }
        /* Any other byte terminates the CSI sequence. */
        esc_nparams++;
        handle_csi(c);
        esc_state = 0;
        return;
    }

    if (c == 0x1B)              { esc_state = 1; return; }
    if (c == '\r')               { cur_col = 0; return; }
    if (c == '\n')               { newline(); return; }
    if (c == 0x08 || c == 0x7F)  { if (cur_col > 0) cur_col--; return; }

    draw_cell(cur_col, cur_row, c);
    cur_col++;
    if (cur_col >= CONSOLE_COLS) newline();
}

void console_init(void) {
    if (!virtio_gpu_ready()) return;
    cur_col = 0; cur_row = 0; cur_fg = 0xFFFFFFFFu;
    esc_state = 0; esc_nparams = 0;
    virtio_gpu_fill_rect(0, 0, GPU_FB_WIDTH, GPU_FB_HEIGHT, BG_COLOR);
    virtio_gpu_flush();
}

void console_write(const char *buf, unsigned long len) {
    if (!virtio_gpu_ready()) return;
    for (unsigned long i = 0; i < len; i++) console_putc(buf[i]);
    virtio_gpu_flush();
}
