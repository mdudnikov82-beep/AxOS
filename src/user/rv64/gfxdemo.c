#include "syscall.h"

/* Draws entirely through the gfx_* syscalls (putpixel/fill_rect/flush) —
 * proves the userspace API works, not just the kernel-side driver calls
 * used for the boot test pattern. */
int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) {
        puts_rv("gfxdemo: no GPU available\r\n");
        exit(1);
    }
    puts_rv("gfxdemo: drawing via gfx_putpixel/gfx_fill_rect syscalls...\r\n");

    /* Dark gray background. */
    gfx_fill_rect(0, 0, w, h, gfx_rgb(32, 32, 32));

    /* Four colored quadrants. */
    unsigned int hw = w / 2, hh = h / 2;
    gfx_fill_rect(0,  0,  hw, hh, gfx_rgb(255,   0,   0));  /* red    top-left     */
    gfx_fill_rect(hw, 0,  w - hw, hh, gfx_rgb(0, 255,   0));  /* green  top-right    */
    gfx_fill_rect(0,  hh, hw, h - hh, gfx_rgb(0,   0, 255));  /* blue   bottom-left  */
    gfx_fill_rect(hw, hh, w - hw, h - hh, gfx_rgb(255, 255, 0));  /* yellow bottom-right */

    /* White diagonal, pixel by pixel — exercises gfx_putpixel specifically. */
    unsigned int n = (w < h) ? w : h;
    for (unsigned int i = 0; i < n; i++) {
        unsigned int x = i * w / n;
        unsigned int y = i * h / n;
        gfx_putpixel(x, y, gfx_rgb(255, 255, 255));
        gfx_putpixel(x, y + 1 < h ? y + 1 : y, gfx_rgb(255, 255, 255));
    }

    if (gfx_flush() != 0) {
        puts_rv("gfxdemo: gfx_flush failed\r\n");
        exit(1);
    }

    puts_rv("gfxdemo: done\r\n");
    exit(0);
    return 0;
}
