#pragma once
#include "syscall.h"

/* Shared software cursor helper (see axpaint.c's original comment for why
 * this is software, not the virtio-gpu hardware cursor plane): draws a
 * small black/white checkerboard-outlined square at the given position,
 * saving whatever was underneath so it can be restored next frame without
 * permanently damaging whatever's on screen.
 *
 * Usage per frame:
 *   cursor_restore();              // undo last frame's overlay
 *   ... do real drawing/logic ...
 *   cursor_draw_at(mx, my);        // save + draw overlay at new position
 *   gfx_flush();
 */

#define CURSOR_SIZE 8

static unsigned int __cursor_saved[CURSOR_SIZE * CURSOR_SIZE];
static unsigned int __cursor_x = 0, __cursor_y = 0;
static int __cursor_shown = 0;

static int __cursor_is_border(int dx, int dy) {
    return dx == 0 || dy == 0 || dx == CURSOR_SIZE - 1 || dy == CURSOR_SIZE - 1;
}

static void cursor_restore(void) {
    if (!__cursor_shown) return;
    for (int dy = 0; dy < CURSOR_SIZE; dy++)
        for (int dx = 0; dx < CURSOR_SIZE; dx++)
            if (__cursor_is_border(dx, dy))
                gfx_putpixel(__cursor_x + dx, __cursor_y + dy, __cursor_saved[dy * CURSOR_SIZE + dx]);
    __cursor_shown = 0;
}

static void cursor_draw_at(unsigned int mx, unsigned int my) {
    unsigned int x = (mx > CURSOR_SIZE / 2) ? mx - CURSOR_SIZE / 2 : 0;
    unsigned int y = (my > CURSOR_SIZE / 2) ? my - CURSOR_SIZE / 2 : 0;
    for (int dy = 0; dy < CURSOR_SIZE; dy++)
        for (int dx = 0; dx < CURSOR_SIZE; dx++)
            if (__cursor_is_border(dx, dy)) {
                __cursor_saved[dy * CURSOR_SIZE + dx] = gfx_getpixel(x + dx, y + dy);
                unsigned int c = ((dx + dy) & 1) ? gfx_rgb(0, 0, 0) : gfx_rgb(255, 255, 255);
                gfx_putpixel(x + dx, y + dy, c);
            }
    __cursor_x = x; __cursor_y = y;
    __cursor_shown = 1;
}
