#include "syscall.h"
#include "window.h"

/* AxAbout — right-hand window with static info plus a pulsing "alive"
 * indicator dot. Meant to run as a background process alongside
 * AxTerminal (`run AXABOUT.ELF &`) to prove two windows can update
 * concurrently on the same shared framebuffer. Also drag/close-able
 * (see window.h) - since its content is a small fixed block, it's
 * cheap to just reprint the whole thing after a drag ends, unlike
 * AxTerminal's dynamic scrollback (no retained buffer either way). */

static void print_info(window_t *win) {
    window_println(win, "AxOS/RV64", gfx_rgb(255, 255, 255));
    window_println(win, "RISC-V 64-bit hobby kernel", gfx_rgb(200, 200, 200));
    window_println(win, "", 0);
    window_println(win, "sv39 paging, kernel W^X", gfx_rgb(0, 255, 255));
    window_println(win, "scoped SMAP-lite (SUM)", gfx_rgb(0, 255, 255));
    window_println(win, "software MTE heap", gfx_rgb(0, 255, 255));
    window_println(win, "virtio-blk + virtio-gpu", gfx_rgb(0, 255, 255));
    window_println(win, "preemptive sched, priorities", gfx_rgb(0, 255, 255));
    window_println(win, "", 0);
    window_println_udec(win, "pid: ", (unsigned long)getpid(), gfx_rgb(255, 255, 0));
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    window_t win;
    window_init(&win, 332, 40, 292, 424, 260, 180, gfx_rgb(255, 140, 0), gfx_rgb(30, 10, 10),
               "AxAbout");
    print_info(&win);
    gfx_flush();

    int dragging = 0, resizing = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;

    /* Pulsing dot in the bottom-right corner — proves this process keeps
     * running (and gets scheduled) rather than just drawing once and
     * blocking forever. */
    int on = 0;
    unsigned long tick = 0;
    for (;;) {
        unsigned int mx = 0, my = 0, buttons = 0, focused = 1;
        if (mouse_state(&mx, &my, &buttons, &focused, 0)) {
            int left = buttons & 1;
            if (!dragging && !resizing && left && !prev_left && focused && window_hit_close(&win, mx, my)) {
                /* Nothing else ever erases a closed window's footprint
                 * (no compositor) - see axterm.c's identical fix. */
                window_erase_desktop_bg((int)win.x, (int)win.y, (int)win.w, (int)win.h, screen_h);
                gfx_flush();
                exit(0);
            } else if (!dragging && !resizing && left && !prev_left && focused && window_hit_resize(&win, mx, my)) {
                resizing = 1;
            } else if (!dragging && !resizing && left && !prev_left && focused && window_hit_titlebar(&win, mx, my)) {
                dragging = 1;
                drag_off_x = mx - win.x;
                drag_off_y = my - win.y;
            } else if (dragging && left) {
                unsigned int nx = (mx > drag_off_x) ? mx - drag_off_x : 0;
                unsigned int ny = (my > drag_off_y) ? my - drag_off_y : 0;
                if (nx + win.w > screen_w) nx = screen_w - win.w;
                if (ny + win.h > screen_h) ny = screen_h - win.h;
                window_move(&win, nx, ny, screen_h);
            } else if (resizing && left) {
                unsigned int nw = (mx > win.x + WIN_RESIZE_SIZE) ? mx - win.x : win.min_w;
                unsigned int nh = (my > win.y + WIN_RESIZE_SIZE) ? my - win.y : win.min_h;
                window_resize(&win, nw, nh, screen_w, screen_h);
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxAbout");
                win.cur_row = 0;
                print_info(&win);   /* static content - cheap to just reprint */
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxAbout");
                win.cur_row = 0;
                print_info(&win);
            }
            prev_left = left;
        }

        if (tick % 25 == 0) {   /* ~500ms at a 20ms poll, matches the old sleep_ms(500) cadence */
            unsigned int color = on ? gfx_rgb(0, 255, 0) : gfx_rgb(0, 80, 0);
            /* Shifted left from win.w-20 - the new resize grip now claims
             * the rightmost 16px of this same corner. */
            gfx_fill_rect(win.x + win.w - 36, win.y + win.h - 20, 10, 10, color);
            on = !on;
        }

        gfx_flush();
        tick++;
        sleep_ms(20);
    }

    return 0;
}
