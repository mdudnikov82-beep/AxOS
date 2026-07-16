#pragma once
#include "syscall.h"
#include "gfx_ui.h"

/* Minimal bordered-window helper on top of the gfx_* syscalls. No window
 * manager, no z-ordering — every process draws directly into the one
 * shared framebuffer via kernel-mediated syscalls (each gfx_* call runs
 * to completion without preemption, so concurrent windows from different
 * processes never tear/interleave mid-draw). Two windows coexist simply
 * by owning non-overlapping screen rectangles. */

#define WIN_TITLE_H 28   /* 2x the old 14, matches the font's own 2x scale */
#define WIN_RADIUS  16   /* matches x86 gfx_shell.c's CARD_R - see gfx_ui.h UI_MAX_R */
#define WIN_CLOSE_SIZE 16   /* close-button square, inset in the title bar's top-right */

typedef struct {
    unsigned int x, y, w, h;
    unsigned int content_y;
    unsigned int content_h;
    unsigned int border;
    unsigned int bg;
    unsigned int cur_row;
} window_t;

/* ---- drag/close primitives (first real step toward a window manager -
 * see the top-of-file note: still no z-ordering, so these only make
 * sense while a window stays clear of any other window's rectangle). */

/* Erases (x,y,w,h) back to AxDesk's own background gradient (see
 * axdesk.c's ui_vgrad(0,0,screen_w,screen_h, gfx_rgb(30,30,60),
 * gfx_rgb(8,8,20)) call) - the only way to restore what a dragged
 * window vacates, since there's no compositor to ask "what's really
 * there". Correct against the real desktop; visually wrong if dragged
 * over ANOTHER window's rectangle - an accepted, already-documented
 * limitation, not a new one this adds. */
static void window_erase_desktop_bg(int x, int y, int w, int h, unsigned int screen_h) {
    for (int dy = 0; dy < h; dy++) {
        int ay = y + dy;
        if (ay < 0 || (unsigned int)ay >= screen_h) continue;
        unsigned char a = (unsigned char)(((unsigned int)ay * 255) / (screen_h - 1));
        gfx_fill_rect((unsigned int)x, (unsigned int)ay, (unsigned int)w, 1,
                     ui_blend(gfx_rgb(30, 30, 60), gfx_rgb(8, 8, 20), a));
    }
}

/* 1 if (mx,my) is within the title bar's DRAG region (excludes the
 * close button's own corner so a click there doesn't also start a drag). */
static int window_hit_titlebar(const window_t *win, unsigned int mx, unsigned int my) {
    if (my < win->y || my >= win->y + WIN_TITLE_H) return 0;
    if (mx < win->x || mx >= win->x + win->w) return 0;
    if (mx >= win->x + win->w - WIN_CLOSE_SIZE - 6) return 0;
    return 1;
}

/* 1 if (mx,my) is within the close button (top-right of the title bar). */
static int window_hit_close(const window_t *win, unsigned int mx, unsigned int my) {
    unsigned int bx = win->x + win->w - WIN_CLOSE_SIZE - 6;
    unsigned int by = win->y + (WIN_TITLE_H - WIN_CLOSE_SIZE) / 2;
    return mx >= bx && mx < bx + WIN_CLOSE_SIZE && my >= by && my < by + WIN_CLOSE_SIZE;
}

/* Draws the close button (small red square with a white X) at the
 * window's CURRENT x/y - call after window_init() and after every
 * window_draw_ghost()/window_redraw_chrome(). */
static void window_draw_close(const window_t *win) {
    unsigned int bx = win->x + win->w - WIN_CLOSE_SIZE - 6;
    unsigned int by = win->y + (WIN_TITLE_H - WIN_CLOSE_SIZE) / 2;
    gfx_fill_rect(bx, by, WIN_CLOSE_SIZE, WIN_CLOSE_SIZE, gfx_rgb(200, 40, 40));
    for (unsigned int i = 2; i < WIN_CLOSE_SIZE - 2; i++) {
        gfx_putpixel(bx + i, by + i, gfx_rgb(255, 255, 255));
        gfx_putpixel(bx + i, by + WIN_CLOSE_SIZE - 1 - i, gfx_rgb(255, 255, 255));
    }
}

/* Cheap "ghost" redraw used WHILE actively dragging (every tick the
 * mouse moves) - border + body fill only, no rounded corners/shadow/
 * title-bar gradient. Full-quality chrome is far too expensive to
 * redraw every tick (ui_round_window's corner treatment alone is
 * O(radius^2) getpixel+putpixel calls per corner - fine ONCE at
 * window_init(), not dozens of times per drag gesture) - see gfx_ui.h's
 * own "runs exactly once, never per-frame" comment. */
static void window_draw_ghost(const window_t *win) {
    gfx_fill_rect(win->x, win->y, win->w, win->h, win->border);
    gfx_fill_rect(win->x + 2, win->y + 2, win->w - 4, win->h - 4, win->bg);
    window_draw_close(win);
}

/* Full-quality redraw (rounded corners, shadow, gradient title bar) -
 * call ONCE when a drag ends, not per tick. */
static void window_redraw_chrome(const window_t *win, const char *title) {
    ui_shadow((int)win->x, (int)win->y, (int)win->w, (int)win->h, 6, 90);
    ui_round_window((int)win->x, (int)win->y, (int)win->w, (int)win->h, WIN_RADIUS, WIN_TITLE_H,
                    win->border, win->bg, title);
    window_draw_close(win);
}

/* Moves the window to (new_x,new_y): erases the OLD footprint back to
 * the desktop background, updates geometry, and draws the cheap ghost
 * chrome at the new position. Does NOT touch content_h or cur_row -
 * callers own their own content-loss/redraw policy (see axterm.c/
 * axabout.c: neither retains a content buffer, so a move implies the
 * caller decides how/whether to reprint afterward). */
static void window_move(window_t *win, unsigned int new_x, unsigned int new_y, unsigned int screen_h) {
    if (new_x == win->x && new_y == win->y) return;
    window_erase_desktop_bg((int)win->x, (int)win->y, (int)win->w, (int)win->h, screen_h);
    win->x = new_x; win->y = new_y;
    win->content_y = new_y + WIN_TITLE_H + 4;
    window_draw_ghost(win);
}

static void window_init(window_t *win, unsigned int x, unsigned int y,
                        unsigned int w, unsigned int h,
                        unsigned int border, unsigned int bg, const char *title) {
    win->x = x; win->y = y; win->w = w; win->h = h;
    win->border = border; win->bg = bg;
    win->content_y = y + WIN_TITLE_H + 4;
    win->content_h = (h > WIN_TITLE_H + 8) ? h - WIN_TITLE_H - 8 : 0;
    win->cur_row = 0;

    /* Drop shadow first (into the desktop behind), then the rounded,
     * gradient-titled card on top - was a flat bg fill + four 2px-thick
     * border strips before (plain rectangle, no depth). */
    ui_shadow((int)x, (int)y, (int)w, (int)h, 6, 90);
    ui_round_window((int)x, (int)y, (int)w, (int)h, WIN_RADIUS, WIN_TITLE_H,
                    border, bg, title);
    window_draw_close(win);
}

/* Truncates s to fit within the window's own right edge before drawing
 * - gfx_draw_text() has no clipping of its own (bounded only by the
 * framebuffer edge), so an unclipped long line silently overruns into
 * whatever's drawn next to this window (another window, the desktop) -
 * confirmed live: a long echo in AxTerminal bled straight through into
 * AxAbout's window sitting next to it. Truncates (doesn't wrap) -
 * matches window_println()'s existing one-call-one-line contract. */
static void window_draw_text_clipped(const window_t *win, unsigned int x,
                                     unsigned int y, const char *s, unsigned int color) {
    unsigned int avail_px = (x < win->x + win->w) ? (win->x + win->w - x) : 0;
    unsigned int max_chars = avail_px / 16;
    char buf[80];
    if (max_chars > sizeof(buf) - 1) max_chars = sizeof(buf) - 1;
    unsigned int n = 0;
    while (s[n] && n < max_chars) { buf[n] = s[n]; n++; }
    buf[n] = '\0';
    gfx_draw_text(x, y, buf, color);
}

/* Prints one line into the content area; when it fills up, clears just
 * the content area (not the whole window/screen) and restarts at the top. */
static void window_println(window_t *win, const char *s, unsigned int color) {
    if (!win->content_h) return;
    unsigned int rows = win->content_h / 16;
    if (win->cur_row >= rows) {
        gfx_fill_rect(win->x + 4, win->content_y, win->w - 8, win->content_h, win->bg);
        win->cur_row = 0;
    }
    window_draw_text_clipped(win, win->x + 6, win->content_y + win->cur_row * 16, s, color);
    win->cur_row++;
}

/* Builds "<prefix><decimal v>" into buf (caller-sized, no bounds check —
 * keep prefixes short) and prints it as one content line. */
static void window_println_udec(window_t *win, const char *prefix, unsigned long v,
                                unsigned int color) {
    char buf[48];
    int i = 0;
    while (*prefix) buf[i++] = *prefix++;
    char tmp[20]; int n = 0;
    if (!v) tmp[n++] = '0';
    while (v) { tmp[n++] = '0' + (v % 10); v /= 10; }
    while (n > 0) buf[i++] = tmp[--n];
    buf[i] = '\0';
    window_println(win, buf, color);
}
