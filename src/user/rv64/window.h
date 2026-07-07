#pragma once
#include "syscall.h"

/* Minimal bordered-window helper on top of the gfx_* syscalls. No window
 * manager, no z-ordering — every process draws directly into the one
 * shared framebuffer via kernel-mediated syscalls (each gfx_* call runs
 * to completion without preemption, so concurrent windows from different
 * processes never tear/interleave mid-draw). Two windows coexist simply
 * by owning non-overlapping screen rectangles. */

#define WIN_TITLE_H 14

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

    gfx_fill_rect(x, y, w, h, bg);
    gfx_fill_rect(x, y, w, 2, border);                 /* top    */
    gfx_fill_rect(x, y + h - 2, w, 2, border);          /* bottom */
    gfx_fill_rect(x, y, 2, h, border);                  /* left   */
    gfx_fill_rect(x + w - 2, y, 2, h, border);          /* right  */
    gfx_fill_rect(x + 2, y + 2, w - 4, WIN_TITLE_H, border); /* title bar */
    gfx_draw_text(x + 6, y + 4, title, gfx_rgb(255, 255, 255));
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
