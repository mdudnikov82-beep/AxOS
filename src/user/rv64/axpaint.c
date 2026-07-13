#include "syscall.h"
#include "cursor.h"
#include "gfx_ui.h"
#include "bmp.h"

/* AxPaint — simple finger-paint over the shared framebuffer, driven by the
 * virtio-input tablet (SYS_MOUSE_STATE). See cursor.h for why the cursor
 * is software-drawn rather than using the virtio-gpu hardware cursor plane.
 *
 * Top strip = palette (click a swatch to select color).
 * Rest of the screen = canvas. Hold left button to paint, right to clear.
 * Meant to run in the background (`run AXPAINT.ELF &`); stop it with
 * `kill <pid>` from AxSH.
 *
 * 's'/'l' (virtio-keyboard) save/load a small THUMBNAIL snapshot of the
 * canvas as CANVAS.BMP - not the full-resolution drawing. sys_open()
 * deliberately caps any file read at 32KB (see bmp.h's bmp_load_indexed
 * comment); a full-resolution 800x564 canvas is ~441KB, nowhere close,
 * so this saves/loads at THUMB_SCALE:1 instead. */

#define TOOLBAR_H    36  /* was a bare 20px strip of flat swatches */
#define SWATCH_GAP   4
#define SWATCH_R     8   /* swatches are only ~32px tall - a bigger radius (like window.h's 16) would look like a blob */
#define BRUSH        6
#define THUMB_SCALE  5   /* 800/5=160, (600-36)/5=112.8->112 (4px remainder ignored) */

static const unsigned int NUM_COLORS = 6;
static unsigned int palette[6];
static unsigned int save_palette[7];        /* [0]=background/black, [1..6]=palette[0..5] */
static unsigned char thumb_idx[256 * 256];  /* generous fixed cap; actual w/h computed at runtime */

static unsigned char color_to_index(unsigned int c) {
    for (unsigned char i = 0; i < 7; i++) if (save_palette[i] == c) return i;
    /* Defensive nearest-color fallback - shouldn't normally trigger,
     * the canvas only ever contains flat palette fills or background,
     * no blending happens below the toolbar. */
    unsigned char best = 0;
    unsigned int best_d = 0xFFFFFFFFu;
    for (unsigned char i = 0; i < 7; i++) {
        int dr = (int)((c >> 16) & 0xFF) - (int)((save_palette[i] >> 16) & 0xFF);
        int dg = (int)((c >> 8) & 0xFF)  - (int)((save_palette[i] >> 8) & 0xFF);
        int db = (int)(c & 0xFF)         - (int)(save_palette[i] & 0xFF);
        unsigned int d = (unsigned int)(dr * dr + dg * dg + db * db);
        if (d < best_d) { best_d = d; best = i; }
    }
    return best;
}

static void do_save(unsigned int w, unsigned int h) {
    unsigned int tw = w / THUMB_SCALE, th = (h - TOOLBAR_H) / THUMB_SCALE;
    for (unsigned int ty = 0; ty < th; ty++)
        for (unsigned int tx = 0; tx < tw; tx++)
            thumb_idx[ty * tw + tx] =
                color_to_index(gfx_getpixel(tx * THUMB_SCALE, TOOLBAR_H + ty * THUMB_SCALE));
    int ok = bmp_save_indexed("CANVAS.BMP", thumb_idx, tw, th, save_palette, 7);
    /* gfx_draw_text() only sets "on" glyph pixels, it never clears
     * behind itself - must blank the strip first or this overlaps
     * whatever text (the original hint, or an earlier status message)
     * was already there instead of replacing it. */
    gfx_fill_rect(0, TOOLBAR_H, w, 16, gfx_rgb(0, 0, 0));
    gfx_draw_text(4, TOOLBAR_H + 4, ok ? "Saved: CANVAS.BMP (thumbnail)" : "Save failed",
                 gfx_rgb(255, 255, 0));
}

static void do_load(unsigned int w, unsigned int h) {
    unsigned int tw = w / THUMB_SCALE, th = (h - TOOLBAR_H) / THUMB_SCALE;
    unsigned int pal[8];
    unsigned char n;
    if (!bmp_load_indexed("CANVAS.BMP", thumb_idx, tw, th, pal, &n)) {
        gfx_fill_rect(0, TOOLBAR_H, w, 16, gfx_rgb(0, 0, 0));
        gfx_draw_text(4, TOOLBAR_H + 4, "No saved file", gfx_rgb(255, 80, 80));
        return;
    }
    for (unsigned int ty = 0; ty < th; ty++)
        for (unsigned int tx = 0; tx < tw; tx++)
            gfx_fill_rect(tx * THUMB_SCALE, TOOLBAR_H + ty * THUMB_SCALE, THUMB_SCALE, THUMB_SCALE,
                         pal[thumb_idx[ty * tw + tx]]);
    /* Status line sits just below TOOLBAR_H, inside the canvas area
     * that the load loop above already repainted - draw straight over
     * the freshly-loaded pixels there, no separate clear needed. */
    gfx_draw_text(4, TOOLBAR_H + 4, "Loaded: CANVAS.BMP (thumbnail)", gfx_rgb(0, 255, 120));
}

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

    save_palette[0] = gfx_rgb(0, 0, 0);   /* background/unpainted */
    save_palette[1] = palette[0];
    save_palette[2] = palette[1];
    save_palette[3] = palette[2];
    save_palette[4] = palette[3];
    save_palette[5] = palette[4];
    save_palette[6] = palette[5];

    unsigned int swatch_w = w / NUM_COLORS;

    ui_vgrad(0, 0, w, TOOLBAR_H, gfx_rgb(50, 50, 70), gfx_rgb(20, 20, 35));
    unsigned int cur_idx = 0;
    for (unsigned int i = 0; i < NUM_COLORS; i++)
        draw_swatch(w, i, i == cur_idx);
    gfx_fill_rect(0, TOOLBAR_H, w, h - TOOLBAR_H, gfx_rgb(0, 0, 0));
    gfx_draw_text(4, TOOLBAR_H + 4, "Left=draw  Right=clear",
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

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (c == 's') do_save(w, h);
            else if (c == 'l') do_load(w, h);
        }

        cursor_draw_at(mx, my);

        gfx_flush();
        sleep_ms(20);   /* ~50 Hz poll */
    }

    return 0;
}
