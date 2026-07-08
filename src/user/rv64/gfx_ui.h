#pragma once
#include "syscall.h"

/* GUI polish shared by the RV64 desktop programs (window.h, axdesk.c) -
 * the same gradient/rounded-corner/drop-shadow upgrade done for the x86
 * gfx_shell, adapted to a real constraint that doesn't exist there:
 * drawing here goes through gfx_* SYSCALLS (one ecall per pixel/rect),
 * not a direct framebuffer write in the same address space, so a naive
 * per-pixel blend over a whole window would be thousands of syscalls.
 *
 * Kept cheap by construction: gradients cost one syscall per ROW (not
 * per pixel, since each row is a flat color); shadows only touch the
 * thin "L" sliver actually visible beyond a rect's own footprint, not
 * the rect's whole area; and all of this runs exactly ONCE, when a
 * window/icon is first drawn (window_init(), axdesk's icon draw) - never
 * per-frame - so even the getpixel+putpixel-heavy corner pass is a
 * one-time startup cost, not a per-tick one. */

static unsigned int ui_blend(unsigned int bg, unsigned int fg, unsigned char alpha) {
    int br=(bg>>16)&0xFF, bgc=(bg>>8)&0xFF, bb=bg&0xFF;
    int fr=(fg>>16)&0xFF, fgc=(fg>>8)&0xFF, fb=fg&0xFF;
    int r = br + ((fr-br)*alpha)/255;
    int g = bgc + ((fgc-bgc)*alpha)/255;
    int b = bb + ((fb-bb)*alpha)/255;
    return 0xFF000000u | ((unsigned int)r<<16) | ((unsigned int)g<<8) | (unsigned int)b;
}

/* Vertical gradient: one gfx_fill_rect() per row - h syscalls, not w*h. */
static void ui_vgrad(unsigned int x, unsigned int y, unsigned int w, unsigned int h,
                     unsigned int c1, unsigned int c2) {
    for (unsigned int dy = 0; dy < h; dy++) {
        unsigned char a = (h<=1) ? 255 : (unsigned char)((dy*255)/(h-1));
        gfx_fill_rect(x, y+dy, w, 1, ui_blend(c1, c2, a));
    }
}

/* dx,dy relative to a w x h box's own top-left; true if inside the
 * rounded-rect shape (radius r in every corner). */
static int ui_in_rounded(int dx, int dy, int w, int h, int r) {
    if (dx >= r && dx < w-r) return 1;
    if (dy >= r && dy < h-r) return 1;
    int cx = (dx < r) ? r : w-r-1;
    int cy = (dy < r) ? r : h-r-1;
    int ddx = dx-cx, ddy = dy-cy;
    return (ddx*ddx + ddy*ddy) <= r*r;
}

static void ui_blend_rect(int x, int y, int w, int h, unsigned int fg, unsigned char alpha) {
    for (int dy=0; dy<h; dy++) for (int dx=0; dx<w; dx++) {
        unsigned int px=(unsigned int)(x+dx), py=(unsigned int)(y+dy);
        gfx_putpixel(px, py, ui_blend(gfx_getpixel(px, py), fg, alpha));
    }
}

/* Soft drop shadow: only the L-shaped sliver visible beyond the rect's
 * own right/bottom edge once offset by `off`, blended into whatever's
 * already on screen there (desktop background) - not the rect's own
 * footprint, which the rect itself will cover right after this. */
static void ui_shadow(int x, int y, int w, int h, int off, unsigned char alpha) {
    ui_blend_rect(x+w,   y+off, off, h,   0x00000000u, alpha); /* right strip  */
    ui_blend_rect(x+off, y+h,   w,   off, 0x00000000u, alpha); /* bottom strip */
}

/* ── Rounded corners for a w x h rect at (x,y) ───────────────────────
 * Corners are "punched" by restoring whatever was already on screen
 * before the rect overwrote it - correct regardless of what the
 * background looks like (gradient, wallpaper, ...), unlike guessing an
 * erase color. Split into save/punch so callers can draw arbitrary
 * flat/gradient content (border, body, title bar, ...) for the rect IN
 * BETWEEN the two - the corner punch must always run LAST, after
 * everything else, or a later flat draw over the title bar area would
 * re-square a corner the punch already rounded.
 *
 * UI_MAX_R MUST stay tiny: a RISC-V user process here gets exactly ONE
 * 4KB page of stack (elf_loader.h's USER_STACK_VA), for its ENTIRE call
 * chain - not just this header. A first attempt at UI_MAX_R=16 (4 corners
 * x 16x16 int = 4096 bytes, the save buffer ALONE) blew straight through
 * that page and store-page-faulted axdesk.elf on startup. UI_MAX_R=4 (4 x
 * 4x4 int = 256 bytes) is what's actually safe; the corner radius is
 * correspondingly small (a subtle rounding, not x86 gfx_shell's much
 * bigger 12-16px one - that side has a real multi-KB kernel stack per
 * task and draws straight into its own backbuf, no per-pixel syscalls or
 * save buffers needed at all). */
#define UI_MAX_R 4
static const int ui_corner_dx[4] = {0,1,0,1};   /* 1 = mirror this corner's dx */
static const int ui_corner_dy[4] = {0,0,1,1};   /* 1 = mirror this corner's dy */

static void ui_round_save(int x, int y, int w, int h, int r,
                          unsigned int save[4][UI_MAX_R*UI_MAX_R], int cx[4], int cy[4]) {
    if (r > UI_MAX_R) r = UI_MAX_R;
    cx[0]=0; cx[1]=w-r; cx[2]=0;   cx[3]=w-r;
    cy[0]=0; cy[1]=0;   cy[2]=h-r; cy[3]=h-r;
    for (int k=0; k<4; k++)
        for (int dy=0; dy<r; dy++) for (int dx=0; dx<r; dx++)
            save[k][dy*r+dx] = gfx_getpixel((unsigned int)(x+cx[k]+dx), (unsigned int)(y+cy[k]+dy));
}
static void ui_round_punch(int x, int y, int r,
                           unsigned int save[4][UI_MAX_R*UI_MAX_R], const int cx[4], const int cy[4]) {
    if (r > UI_MAX_R) r = UI_MAX_R;
    for (int k=0; k<4; k++)
        for (int dy=0; dy<r; dy++) for (int dx=0; dx<r; dx++) {
            int ldx = ui_corner_dx[k] ? (r-1-dx) : dx;
            int ldy = ui_corner_dy[k] ? (r-1-dy) : dy;
            if (!ui_in_rounded(ldx, ldy, r, r, r))
                gfx_putpixel((unsigned int)(x+cx[k]+dx), (unsigned int)(y+cy[k]+dy), save[k][dy*r+dx]);
        }
}

/* Plain rounded card (icons): 2px border + inset body, corners rounded. */
static void ui_round_rect(int x, int y, int w, int h, int r,
                          unsigned int border, unsigned int body) {
    unsigned int save[4][UI_MAX_R*UI_MAX_R]; int cx[4], cy[4];
    ui_round_save(x, y, w, h, r, save, cx, cy);

    gfx_fill_rect((unsigned int)x, (unsigned int)y, (unsigned int)w, (unsigned int)h, border);
    gfx_fill_rect((unsigned int)(x+2), (unsigned int)(y+2), (unsigned int)(w-4), (unsigned int)(h-4), body);

    ui_round_punch(x, y, r, save, cx, cy);
}

/* Rounded window with a gradient title bar + label (window.h's chrome). */
static void ui_round_window(int x, int y, int w, int h, int r, int title_h,
                            unsigned int border, unsigned int body, const char *title) {
    unsigned int save[4][UI_MAX_R*UI_MAX_R]; int cx[4], cy[4];
    ui_round_save(x, y, w, h, r, save, cx, cy);

    gfx_fill_rect((unsigned int)x, (unsigned int)y, (unsigned int)w, (unsigned int)h, border);
    gfx_fill_rect((unsigned int)(x+2), (unsigned int)(y+2), (unsigned int)(w-4), (unsigned int)(h-4), body);
    ui_vgrad((unsigned int)(x+2), (unsigned int)(y+2), (unsigned int)(w-4), (unsigned int)title_h,
            ui_blend(border, 0xFFFFFFFFu, 50), border);

    ui_round_punch(x, y, r, save, cx, cy);

    /* Text drawn LAST, after the corner punch, and nudged in from the
     * very corner so the rounding curve never clips a letter. */
    gfx_draw_text((unsigned int)(x+8), (unsigned int)(y+5), title, gfx_rgb(255,255,255));
}
