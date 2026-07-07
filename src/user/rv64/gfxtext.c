#include "syscall.h"

int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) {
        puts_rv("gfxtext: no GPU available\r\n");
        exit(1);
    }
    puts_rv("gfxtext: drawing text via gfx_draw_text syscall...\r\n");

    gfx_fill_rect(0, 0, w, h, gfx_rgb(0, 0, 64));  /* dark blue background */

    gfx_draw_text(16, 16,  "AxOS/RV64", gfx_rgb(255, 255, 255));
    gfx_draw_text(16, 32,  "Hello, RISC-V!", gfx_rgb(0, 255, 0));
    gfx_draw_text(16, 48,  "0123456789 !@#$%^&*()", gfx_rgb(255, 255, 0));
    gfx_draw_text(16, 64,  "abcdefghijklmnopqrstuvwxyz", gfx_rgb(0, 255, 255));
    gfx_draw_text(16, 80,  "ABCDEFGHIJKLMNOPQRSTUVWXYZ", gfx_rgb(255, 128, 255));

    if (gfx_flush() != 0) {
        puts_rv("gfxtext: gfx_flush failed\r\n");
        exit(1);
    }

    puts_rv("gfxtext: done\r\n");
    exit(0);
    return 0;
}
