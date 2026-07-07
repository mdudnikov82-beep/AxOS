#include "syscall.h"
#include "cursor.h"

/* AxPaint — simple finger-paint over the shared framebuffer, driven by the
 * virtio-input tablet (SYS_MOUSE_STATE). See cursor.h for why the cursor
 * is software-drawn rather than using the virtio-gpu hardware cursor plane.
 *
 * Top strip = palette (click a swatch to select color).
 * Rest of the screen = canvas. Hold left button to paint, right to clear.
 * Meant to run in the background (`run AXPAINT.ELF &`); stop it with
 * `kill <pid>` from AxSH. */

#define PALETTE_H    20
#define BRUSH        6

static const unsigned int NUM_COLORS = 6;

int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) {
        puts_rv("axpaint: no GPU available\r\n");
        exit(1);
    }

    unsigned int palette[6];
    palette[0] = gfx_rgb(255, 0, 0);
    palette[1] = gfx_rgb(0, 255, 0);
    palette[2] = gfx_rgb(0, 0, 255);
    palette[3] = gfx_rgb(255, 255, 0);
    palette[4] = gfx_rgb(255, 0, 255);
    palette[5] = gfx_rgb(0, 255, 255);

    unsigned int swatch_w = w / NUM_COLORS;
    for (unsigned int i = 0; i < NUM_COLORS; i++)
        gfx_fill_rect(i * swatch_w, 0, swatch_w, PALETTE_H, palette[i]);
    gfx_fill_rect(0, PALETTE_H, w, h - PALETTE_H, gfx_rgb(0, 0, 0));
    gfx_draw_text(4, PALETTE_H + 4, "AxPaint: hold left button to draw, right to clear",
                 gfx_rgb(180, 180, 180));
    gfx_flush();

    unsigned int cur_color = palette[0];
    unsigned int mx = 0, my = 0, buttons = 0;

    for (;;) {
        cursor_restore();   /* undo last frame's overlay before touching anything */

        if (!mouse_state(&mx, &my, &buttons)) {
            puts_rv("axpaint: no mouse device found\r\n");
            exit(1);
        }

        if (buttons & 1) {                       /* left button: draw */
            if (my < PALETTE_H) {
                unsigned int idx = mx / swatch_w;
                if (idx >= NUM_COLORS) idx = NUM_COLORS - 1;
                cur_color = palette[idx];
            } else {
                unsigned int bx = (mx > BRUSH / 2) ? mx - BRUSH / 2 : 0;
                unsigned int by = (my > BRUSH / 2) ? my - BRUSH / 2 : 0;
                gfx_fill_rect(bx, by, BRUSH, BRUSH, cur_color);
            }
        } else if (buttons & 2) {                /* right button: clear */
            gfx_fill_rect(0, PALETTE_H, w, h - PALETTE_H, gfx_rgb(0, 0, 0));
        }

        cursor_draw_at(mx, my);

        gfx_flush();
        sleep_ms(20);   /* ~50 Hz poll */
    }

    return 0;
}
