#include "syscall.h"
#include "window.h"

/* AxAbout — right-hand window with static info plus a pulsing "alive"
 * indicator dot. Meant to run as a background process alongside
 * AxTerminal (`run AXABOUT.ELF &`) to prove two windows can update
 * concurrently on the same shared framebuffer. */
int main(void) {
    window_t win;
    window_init(&win, 332, 40, 292, 424, gfx_rgb(255, 140, 0), gfx_rgb(30, 10, 10),
               "AxAbout");

    window_println(&win, "AxOS/RV64", gfx_rgb(255, 255, 255));
    window_println(&win, "RISC-V 64-bit hobby kernel", gfx_rgb(200, 200, 200));
    window_println(&win, "", 0);
    window_println(&win, "sv39 paging, kernel W^X", gfx_rgb(0, 255, 255));
    window_println(&win, "scoped SMAP-lite (SUM)", gfx_rgb(0, 255, 255));
    window_println(&win, "software MTE heap", gfx_rgb(0, 255, 255));
    window_println(&win, "virtio-blk + virtio-gpu", gfx_rgb(0, 255, 255));
    window_println(&win, "cooperative multitasking", gfx_rgb(0, 255, 255));
    window_println(&win, "", 0);
    window_println_udec(&win, "pid: ", (unsigned long)getpid(), gfx_rgb(255, 255, 0));
    gfx_flush();

    /* Pulsing dot in the bottom-right corner — proves this process keeps
     * running (and gets scheduled) rather than just drawing once and
     * blocking forever. */
    int on = 0;
    for (int i = 0; i < 200; i++) {
        unsigned int color = on ? gfx_rgb(0, 255, 0) : gfx_rgb(0, 80, 0);
        gfx_fill_rect(win.x + win.w - 20, win.y + win.h - 20, 10, 10, color);
        gfx_flush();
        on = !on;
        sleep_ms(500);
    }

    exit(0);
    return 0;
}
