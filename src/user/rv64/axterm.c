#include "syscall.h"
#include "window.h"

/* AxTerminal — left-hand window with a live-updating tick log. Meant to
 * run as a background process (`run AXTERM.ELF &`) alongside AxAbout to
 * demonstrate real concurrent scheduling: both windows update
 * independently, interleaved by the round-robin scheduler. */
int main(void) {
    window_t win;
    window_init(&win, 16, 40, 300, 424, gfx_rgb(0, 150, 255), gfx_rgb(10, 10, 30),
               "AxTerminal");

    int pid = getpid();
    window_println_udec(&win, "AxTerminal, pid=", (unsigned long)pid,
                        gfx_rgb(255, 255, 255));
    window_println(&win, "", 0);
    gfx_flush();

    for (unsigned long tick = 1; tick <= 200; tick++) {
        window_println_udec(&win, "tick ", tick, gfx_rgb(0, 255, 120));
        gfx_flush();
        sleep_ms(500);
    }

    window_println(&win, "-- done --", gfx_rgb(255, 255, 0));
    gfx_flush();
    exit(0);
    return 0;
}
