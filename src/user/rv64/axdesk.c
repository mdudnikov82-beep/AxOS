#include "syscall.h"
#include "gfx_ui.h"
#include "bmp.h"

/* AxDesktop — a minimal point-and-click desktop: draws icons, and a left
 * click on one launches the corresponding program via exec() directly
 * (no need to type `run <FILE> &` in AxSH). Meant to run in the
 * background (`run AXDESK.ELF &`) alongside AxSH, which stays available
 * over serial for text commands (`kill <pid>` to stop the desktop).
 *
 * Not a real window manager — launched apps just draw into the same
 * shared framebuffer as everything else (see window.h for how they avoid
 * overlapping AxSH's own console text). This only draws icons + dispatches
 * clicks; it doesn't try to track/composite the windows it launches. */

/* Shrunk from 112/20 when AxNotepad became the 7th icon - the old
 * pitch (7*112 + 6*20 = 904px) no longer fit an 800px-wide screen.
 * BMP icon art (<=64x64, see bmp.h) still centers fine at this width. */
#define ICON_W   100
#define ICON_H   96
#define ICON_GAP 12
#define ICON_TOP 70

typedef struct {
    const char   *label;
    const char   *file;    /* NULL for the built-in shutdown action */
    const char   *icon_bmp; /* NULL if no icon art - card+text fallback used */
    unsigned int  color;
} icon_t;

/* Pixel width of a gfx_draw_text() string at the current 2x font scale
 * (16px/char) - used to center variable-length labels in a fixed-width
 * icon card. */
static unsigned int text_px_w(const char *s) {
    unsigned int n = 0;
    while (*s++) n++;
    return n * 16;
}

int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) {
        puts_rv("axdesk: no GPU available\r\n");
        exit(1);
    }

    icon_t icons[7];
    icons[0].label = "Term";  icons[0].file = "AXTERM.ELF";  icons[0].icon_bmp = "TERM.BMP";  icons[0].color = gfx_rgb(0, 150, 255);
    icons[1].label = "About"; icons[1].file = "AXABOUT.ELF"; icons[1].icon_bmp = "ABOUT.BMP"; icons[1].color = gfx_rgb(255, 140, 0);
    icons[2].label = "Paint"; icons[2].file = "AXPAINT.ELF"; icons[2].icon_bmp = "PAINT.BMP"; icons[2].color = gfx_rgb(0, 200, 120);
    icons[3].label = "Power"; icons[3].file = 0;             icons[3].icon_bmp = "POWER.BMP"; icons[3].color = gfx_rgb(220, 30, 30);
    /* No BMP asset (icon_bmp=0) - matches x86 AxFiles' own no-pixel-art
     * choice; bmp_load() is never even attempted, same NULL-guard the
     * Power icon's file=0 already exercises below. */
    icons[4].label = "Files"; icons[4].file = "AXFILES.ELF"; icons[4].icon_bmp = 0;          icons[4].color = gfx_rgb(80, 200, 120);
    icons[5].label = "Calc";  icons[5].file = "AXCALC.ELF";  icons[5].icon_bmp = 0;          icons[5].color = gfx_rgb(255, 210, 0);
    icons[6].label = "Note";  icons[6].file = "AXNOTE.ELF";  icons[6].icon_bmp = 0;          icons[6].color = gfx_rgb(0, 200, 200);
    unsigned int n_icons = 7;

    unsigned int total_w = n_icons * ICON_W + (n_icons - 1) * ICON_GAP;
    unsigned int start_x = (w > total_w) ? (w - total_w) / 2 : 0;

    /* Desktop background (gradient - was flat) + title bar. */
    ui_vgrad(0, 0, w, h, gfx_rgb(30, 30, 60), gfx_rgb(8, 8, 20));
    ui_vgrad(0, 0, w, 28, gfx_rgb(20, 20, 45), gfx_rgb(10, 10, 25));
    gfx_draw_text(8, 10, "AxOS Desktop  --  click an icon to launch", gfx_rgb(200, 200, 255));

    /* Один переиспользуемый буфер декодирования - иконки рисуются по
     * очереди, ни одна не должна пережить следующий bmp_load(). */
    static bmp_image_t icon_img;

    for (unsigned int i = 0; i < n_icons; i++) {
        int x = (int)(start_x + i * (ICON_W + ICON_GAP));
        ui_shadow(x, ICON_TOP, ICON_W, ICON_H, 5, 90);
        /* matches x86 gfx_shell.c's ICON_R - see gfx_ui.h's UI_MAX_R comment */
        ui_round_rect(x, ICON_TOP, ICON_W, ICON_H, 14, gfx_rgb(255, 255, 255), icons[i].color);

        /* Настоящая иконка (BMP) поверх карточки, если файл нашёлся и
         * декодировался - иначе просто остаётся цветная карточка с
         * подписью (fallback, не крашимся на отсутствующем/битом файле). */
        if (icons[i].icon_bmp && bmp_load(icons[i].icon_bmp, &icon_img)) {
            unsigned int icon_x = (unsigned int)x + (ICON_W - icon_img.width) / 2;
            bmp_draw(&icon_img, icon_x, (unsigned int)ICON_TOP + 6);
        }

        unsigned int lw = text_px_w(icons[i].label);
        gfx_draw_text((unsigned int)x + (ICON_W - lw) / 2, ICON_TOP + ICON_H - 20,
                     icons[i].label, gfx_rgb(0, 0, 0));
    }
    gfx_flush();

    int prev_left = 0;
    unsigned int mx = 0, my = 0, buttons = 0;

    for (;;) {
        if (!mouse_state(&mx, &my, &buttons)) {
            puts_rv("axdesk: no mouse device found\r\n");
            exit(1);
        }

        int left = buttons & 1;
        if (left && !prev_left) {   /* click edge, not held-down repeat */
            for (unsigned int i = 0; i < n_icons; i++) {
                unsigned int x = start_x + i * (ICON_W + ICON_GAP);
                if (mx >= x && mx < x + ICON_W && my >= ICON_TOP && my < ICON_TOP + ICON_H) {
                    if (icons[i].file) {
                        int pid = exec(icons[i].file);
                        if (pid < 0) {
                            gfx_draw_text(start_x, ICON_TOP + ICON_H + 10,
                                         "launch failed                    ",
                                         gfx_rgb(255, 80, 80));
                        }
                    } else {
                        shutdown();  /* Shutdown icon; does not return */
                    }
                }
            }
        }
        prev_left = left;

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
