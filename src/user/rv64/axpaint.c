#include "syscall.h"
#include "cursor.h"
#include "gfx_ui.h"

/* AxPaint — simple finger-paint over the shared framebuffer, driven by the
 * virtio-input tablet (SYS_MOUSE_STATE). See cursor.h for why the cursor
 * is software-drawn rather than using the virtio-gpu hardware cursor plane.
 *
 * Top strip = palette (click a swatch to select color).
 * Rest of the screen = canvas. Hold left button to paint, right to clear.
 * Meant to run in the background (`run AXPAINT.ELF &`); stop it with
 * `kill <pid>` from AxSH. */

#define TOOLBAR_H    36  /* was a bare 20px strip of flat swatches */
#define SWATCH_GAP   4
#define SWATCH_R     8   /* swatches are only ~32px tall - a bigger radius (like window.h's 16) would look like a blob */
#define BRUSH        6

static const unsigned int NUM_COLORS = 6;
static unsigned int palette[6];

/* Redraws one swatch button - shadowed rounded card, white border if it's
 * the selected color, black otherwise. Canvas itself stays flat black on
 * purpose (unlike the desktop's gradient wallpaper): a paint surface
 * should read as neutral, not tint whatever the user draws on it. */
static void draw_swatch(unsigned int w, unsigned int idx, int selected) {
    unsigned int swatch_w = w / NUM_COLORS;
    int x = (int)(idx * swatch_w) + SWATCH_GAP / 2;
    int sw = (int)swatch_w - SWATCH_GAP;
    int y = SWATCH_GAP / 2, sh = TOOLBAR_H - SWATCH_GAP;
    unsigned int border = selected ? gfx_rgb(255, 255, 255) : gfx_rgb(0, 0, 0);
    ui_shadow(x, y, sw, sh, 3, 90);
    ui_round_rect(x, y, sw, sh, SWATCH_R, border, palette[idx]);
}

int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) {
        puts_rv("axpaint: no GPU available\r\n");
        exit(1);
    }

    palette[0] = gfx_rgb(255, 0, 0);
    palette[1] = gfx_rgb(0, 255, 0);
    palette[2] = gfx_rgb(0, 0, 255);
    palette[3] = gfx_rgb(255, 255, 0);
    palette[4] = gfx_rgb(255, 0, 255);
    palette[5] = gfx_rgb(0, 255, 255);

    unsigned int swatch_w = w / NUM_COLORS;

    ui_vgrad(0, 0, w, TOOLBAR_H, gfx_rgb(50, 50, 70), gfx_rgb(20, 20, 35));
    unsigned int cur_idx = 0;
    for (unsigned int i = 0; i < NUM_COLORS; i++)
        draw_swatch(w, i, i == cur_idx);
    gfx_fill_rect(0, TOOLBAR_H, w, h - TOOLBAR_H, gfx_rgb(0, 0, 0));
    gfx_draw_text(4, TOOLBAR_H + 4, "AxPaint: hold left button to draw, right to clear",
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
            if (my < TOOLBAR_H) {
                unsigned int idx = mx / swatch_w;
                if (idx >= NUM_COLORS) idx = NUM_COLORS - 1;
                if (idx != cur_idx) {
                    unsigned int prev = cur_idx;
                    cur_idx = idx;
                    cur_color = palette[idx];
                    draw_swatch(w, prev, 0);   /* drop the old highlight */
                    draw_swatch(w, idx, 1);    /* show the new one */
                }
            } else {
                unsigned int bx = (mx > BRUSH / 2) ? mx - BRUSH / 2 : 0;
                unsigned int by = (my > BRUSH / 2) ? my - BRUSH / 2 : 0;
                gfx_fill_rect(bx, by, BRUSH, BRUSH, cur_color);
            }
        } else if (buttons & 2) {                /* right button: clear */
            gfx_fill_rect(0, TOOLBAR_H, w, h - TOOLBAR_H, gfx_rgb(0, 0, 0));
        }

        cursor_draw_at(mx, my);

        gfx_flush();
        sleep_ms(20);   /* ~50 Hz poll */
    }

    return 0;
}
