#pragma once
#include "syscall.h"
#include "gfx_ui.h"

/* Minimal bordered-window helper on top of the gfx_* syscalls. No window
 * manager, no z-ordering — every process draws directly into the one
 * shared framebuffer via kernel-mediated syscalls (each gfx_* call runs
 * to completion without preemption, so concurrent windows from different
 * processes never tear/interleave mid-draw). Two windows coexist simply
 * by owning non-overlapping screen rectangles. */

#define WIN_TITLE_H 14
#define WIN_RADIUS  16   /* matches x86 gfx_shell.c's CARD_R - see gfx_ui.h UI_MAX_R */

typedef struct {
    unsigned int x, y, w, h;
    unsigned int content_y;
    unsigned int content_h;
    unsigned int border;
    unsigned int bg;
    unsigned int cur_row;
} window_t;

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
}

/* Prints one line into the content area; when it fills up, clears just
 * the content area (not the whole window/screen) and restarts at the top. */
static void window_println(window_t *win, const char *s, unsigned int color) {
    if (!win->content_h) return;
    unsigned int rows = win->content_h / 8;
    if (win->cur_row >= rows) {
        gfx_fill_rect(win->x + 4, win->content_y, win->w - 8, win->content_h, win->bg);
        win->cur_row = 0;
    }
    gfx_draw_text(win->x + 6, win->content_y + win->cur_row * 8, s, color);
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
