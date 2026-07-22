#include "syscall.h"
#include "gfx_ui.h"
#include "bmp.h"

/* AxPaint — simple finger-paint over the shared framebuffer, driven by the
 * virtio-input tablet (SYS_MOUSE_STATE). The kernel draws the software
 * mouse cursor itself now, as part of every gfx_flush() (see
 * kernel_cursor_render() in src/arch/riscv64/syscall.c) - this app no
 * longer needs to manage it.
 *
 * Top strip = palette (click a swatch to select color) + [S:n]/[Save]/
 * [Load] buttons on the right. Rest of the screen = canvas. Hold left
 * button to paint, right to clear. Meant to run in the background
 * (`run AXPAINT.ELF &`); stop it with `kill <pid>` from AxSH.
 *
 * [S:n] cycles the save slot 1-8 (PAINT1.BMP..PAINT8.BMP - 8 slots so
 * several drawings can coexist instead of one shared CANVAS.BMP).
 * [Save]/[Load] (click, or 's'/'l' on a virtio-keyboard - both call the
 * same do_save()/do_load()) save/load a small THUMBNAIL snapshot of the
 * CURRENT slot's canvas - not the full-resolution drawing. sys_open()
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

/* Multiple save slots (PAINT1.BMP..PAINT8.BMP) - 8 to match AI.WTS's
 * own BANK_SIZE convention, single digit keeps the 8.3 filename trivial. */
#define PAINT_SLOTS 8
static int paint_slot = 1;

static void paint_slot_filename(char *out) {
    out[0]='P'; out[1]='A'; out[2]='I'; out[3]='N'; out[4]='T';
    out[5] = (char)('0' + paint_slot);
    out[6]='.'; out[7]='B'; out[8]='M'; out[9]='P'; out[10]='\0';
}

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
    char fname[11];
    paint_slot_filename(fname);
    int ok = bmp_save_indexed(fname, thumb_idx, tw, th, save_palette, 7);
    /* gfx_draw_text() only sets "on" glyph pixels, it never clears
     * behind itself - must blank the strip first or this overlaps
     * whatever text (the original hint, or an earlier status message)
     * was already there instead of replacing it. */
    gfx_fill_rect(0, TOOLBAR_H, w, 16, gfx_rgb(0, 0, 0));
    if (ok) {
        char msg[40];
        const char *prefix = "Saved: ";
        int p = 0;
        for (int i = 0; prefix[i]; i++) msg[p++] = prefix[i];
        for (int i = 0; fname[i]; i++) msg[p++] = fname[i];
        const char *suffix = " (thumbnail)";
        for (int i = 0; suffix[i]; i++) msg[p++] = suffix[i];
        msg[p] = '\0';
        gfx_draw_text(4, TOOLBAR_H + 4, msg, gfx_rgb(255, 255, 0));
    } else {
        gfx_draw_text(4, TOOLBAR_H + 4, "Save failed", gfx_rgb(255, 255, 0));
    }
}

static void do_load(unsigned int w, unsigned int h) {
    unsigned int tw = w / THUMB_SCALE, th = (h - TOOLBAR_H) / THUMB_SCALE;
    unsigned int pal[8];
    unsigned char n;
    char fname[11];
    paint_slot_filename(fname);
    if (!bmp_load_indexed(fname, thumb_idx, tw, th, pal, &n)) {
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
    char msg[40];
    const char *prefix = "Loaded: ";
    int p = 0;
    for (int i = 0; prefix[i]; i++) msg[p++] = prefix[i];
    for (int i = 0; fname[i]; i++) msg[p++] = fname[i];
    const char *suffix = " (thumbnail)";
    for (int i = 0; suffix[i]; i++) msg[p++] = suffix[i];
    msg[p] = '\0';
    gfx_draw_text(4, TOOLBAR_H + 4, msg, gfx_rgb(0, 255, 120));
}

/* [Save]/[Load] hit-boxes - plain bracketed text buttons, same style as
 * AxFiles' [Delete]/[< Back] (axfiles.c) rather than the swatches' own
 * rounded-card look, since this is a one-off action button pair, not a
 * palette. BTN_CHAR_W=16 matches virtio_gpu.h's GFX_FONT_SCALE=2 (8*2)
 * - that constant itself is kernel-side, not visible to userspace, so
 * it's hardcoded here rather than included across the syscall boundary. */
#define BTN_CHAR_W  16
#define BTN_W       (6 * BTN_CHAR_W)   /* "[Save]"/"[Load]" = 6 chars */
#define SLOT_W      (5 * BTN_CHAR_W)   /* "[S:n]" = 5 chars, n is a single digit */
#define BTN_GAP     8
#define BTN_MARGIN  12
#define BUTTONS_W   (SLOT_W + BTN_GAP + BTN_W*2 + BTN_GAP + BTN_MARGIN)
#define BTN_Y       ((TOOLBAR_H - BTN_CHAR_W) / 2)

/* Redraws one swatch button - shadowed rounded card, white border if it's
 * the selected color, black otherwise. Canvas itself stays flat black on
 * purpose (unlike the desktop's gradient wallpaper): a paint surface
 * should read as neutral, not tint whatever the user draws on it.
 * Swatches only span (w - BUTTONS_W) now, leaving room on the right for
 * the [Save]/[Load] buttons below - matches x86 AxPaint's own layout
 * (swatches left, action buttons right-aligned). */
static void draw_swatch(unsigned int w, unsigned int idx, int selected) {
    unsigned int swatch_w = (w - BUTTONS_W) / NUM_COLORS;
    int x = (int)(idx * swatch_w) + SWATCH_GAP / 2;
    int sw = (int)swatch_w - SWATCH_GAP;
    int y = SWATCH_GAP / 2, sh = TOOLBAR_H - SWATCH_GAP;
    unsigned int border = selected ? gfx_rgb(255, 255, 255) : gfx_rgb(0, 0, 0);
    ui_shadow(x, y, sw, sh, 3, 90);
    ui_round_rect(x, y, sw, sh, SWATCH_R, border, palette[idx]);
}

static unsigned int btn_load_x(unsigned int w) { return w - BTN_MARGIN - BTN_W; }
static unsigned int btn_save_x(unsigned int w) { return btn_load_x(w) - BTN_GAP - BTN_W; }
static unsigned int btn_slot_x(unsigned int w) { return btn_save_x(w) - BTN_GAP - SLOT_W; }

static void draw_buttons(unsigned int w) {
    char slot_label[6] = "[S:n]";
    slot_label[3] = (char)('0' + paint_slot);
    gfx_draw_text(btn_slot_x(w), BTN_Y, slot_label, gfx_rgb(255, 255, 255));
    gfx_draw_text(btn_save_x(w), BTN_Y, "[Save]", gfx_rgb(255, 255, 255));
    gfx_draw_text(btn_load_x(w), BTN_Y, "[Load]", gfx_rgb(255, 255, 255));
}

int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) {
        puts_rv("axpaint: no GPU available\r\n");
        exit(1);
    }
    /* AxPaint has no window_t/window.h (it spans the whole framebuffer
     * like a second full-screen layer, closer to AxDesk than to the
     * windowed apps), so it registers its click-ownership rect directly
     * instead of getting it for free from window_init(). */
    win_set_rect(0, 0, (int)w, (int)h);

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

    unsigned int swatch_w = (w - BUTTONS_W) / NUM_COLORS;

    ui_vgrad(0, 0, w, TOOLBAR_H, gfx_rgb(50, 50, 70), gfx_rgb(20, 20, 35));
    unsigned int cur_idx = 0;
    for (unsigned int i = 0; i < NUM_COLORS; i++)
        draw_swatch(w, i, i == cur_idx);
    draw_buttons(w);
    gfx_fill_rect(0, TOOLBAR_H, w, h - TOOLBAR_H, gfx_rgb(0, 0, 0));
    gfx_draw_text(4, TOOLBAR_H + 4, "Left=draw  Right=clear",
                 gfx_rgb(180, 180, 180));
    gfx_flush();

    unsigned int cur_color = palette[0];
    unsigned int mx = 0, my = 0, buttons = 0, prev_buttons = 0, focused = 1;

    for (;;) {
        if (!mouse_state(&mx, &my, &buttons, &focused)) {
            puts_rv("axpaint: no mouse device found\r\n");
            exit(1);
        }

        if ((buttons & 1) && focused) {           /* left button: draw */
            if (my < TOOLBAR_H) {
                unsigned int sx = btn_save_x(w), lx = btn_load_x(w), slx = btn_slot_x(w);
                int on_save = mx >= sx && mx < sx+BTN_W && my >= BTN_Y && my < BTN_Y+BTN_CHAR_W;
                int on_load = mx >= lx && mx < lx+BTN_W && my >= BTN_Y && my < BTN_Y+BTN_CHAR_W;
                int on_slot = mx >= slx && mx < slx+SLOT_W && my >= BTN_Y && my < BTN_Y+BTN_CHAR_W;
                int edge = !(prev_buttons & 1);   /* fire once per press, not every ~20ms while held - avoids spamming disk writes */
                if (on_slot) {
                    if (edge) {
                        paint_slot = paint_slot % PAINT_SLOTS + 1;
                        char slot_label[6] = "[S:n]";
                        slot_label[3] = (char)('0' + paint_slot);
                        gfx_fill_rect(slx, BTN_Y, SLOT_W, BTN_CHAR_W, gfx_rgb(20, 20, 35));
                        gfx_draw_text(slx, BTN_Y, slot_label, gfx_rgb(255, 255, 255));
                        gfx_fill_rect(0, TOOLBAR_H, w, 16, gfx_rgb(0, 0, 0));
                        char msg[8];
                        const char *smsg = "Slot: ";
                        int sp = 0;
                        for (int i = 0; smsg[i]; i++) msg[sp++] = smsg[i];
                        msg[sp++] = (char)('0' + paint_slot);
                        msg[sp] = '\0';
                        gfx_draw_text(4, TOOLBAR_H + 4, msg, gfx_rgb(255, 255, 0));
                    }
                } else if (on_save) {
                    if (edge) do_save(w, h);
                } else if (on_load) {
                    if (edge) do_load(w, h);
                } else {
                    unsigned int idx = mx / swatch_w;
                    if (idx >= NUM_COLORS) idx = NUM_COLORS - 1;
                    if (idx != cur_idx) {
                        unsigned int prev = cur_idx;
                        cur_idx = idx;
                        cur_color = palette[idx];
                        draw_swatch(w, prev, 0);   /* drop the old highlight */
                        draw_swatch(w, idx, 1);    /* show the new one */
                    }
                }
            } else {
                unsigned int bx = (mx > BRUSH / 2) ? mx - BRUSH / 2 : 0;
                unsigned int by = (my > BRUSH / 2) ? my - BRUSH / 2 : 0;
                gfx_fill_rect(bx, by, BRUSH, BRUSH, cur_color);
            }
        } else if ((buttons & 2) && focused) {    /* right button: clear */
            gfx_fill_rect(0, TOOLBAR_H, w, h - TOOLBAR_H, gfx_rgb(0, 0, 0));
        }
        prev_buttons = buttons;

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (c == 's') do_save(w, h);
            else if (c == 'l') do_load(w, h);
        }

        gfx_flush();
        sleep_ms(20);   /* ~50 Hz poll */
    }

    return 0;
}
