#include "syscall.h"
#include "cursor.h"
#include "gfx_ui.h"

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

#define ICON_W   90
#define ICON_H   70
#define ICON_GAP 20
#define ICON_TOP 70

typedef struct {
    const char   *label;
    const char   *file;    /* NULL for the built-in shutdown action */
    unsigned int  color;
} icon_t;

int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) {
        puts_rv("axdesk: no GPU available\r\n");
        exit(1);
    }

    icon_t icons[4];
    icons[0].label = "AxTerminal"; icons[0].file = "AXTERM.ELF";  icons[0].color = gfx_rgb(0, 150, 255);
    icons[1].label = "AxAbout";    icons[1].file = "AXABOUT.ELF"; icons[1].color = gfx_rgb(255, 140, 0);
    icons[2].label = "AxPaint";    icons[2].file = "AXPAINT.ELF"; icons[2].color = gfx_rgb(0, 200, 120);
    icons[3].label = "Shutdown";   icons[3].file = 0;             icons[3].color = gfx_rgb(220, 30, 30);
    unsigned int n_icons = 4;

    unsigned int total_w = n_icons * ICON_W + (n_icons - 1) * ICON_GAP;
    unsigned int start_x = (w > total_w) ? (w - total_w) / 2 : 0;

    /* Desktop background (gradient - was flat) + title bar. */
    ui_vgrad(0, 0, w, h, gfx_rgb(30, 30, 60), gfx_rgb(8, 8, 20));
    ui_vgrad(0, 0, w, 28, gfx_rgb(20, 20, 45), gfx_rgb(10, 10, 25));
    gfx_draw_text(8, 10, "AxOS Desktop  --  click an icon to launch", gfx_rgb(200, 200, 255));

    for (unsigned int i = 0; i < n_icons; i++) {
        int x = (int)(start_x + i * (ICON_W + ICON_GAP));
        ui_shadow(x, ICON_TOP, ICON_W, ICON_H, 5, 90);
        /* matches x86 gfx_shell.c's ICON_R - see gfx_ui.h's UI_MAX_R comment */
        ui_round_rect(x, ICON_TOP, ICON_W, ICON_H, 14, gfx_rgb(255, 255, 255), icons[i].color);
        gfx_draw_text((unsigned int)x + 6, ICON_TOP + ICON_H / 2 - 4, icons[i].label, gfx_rgb(0, 0, 0));
    }
    gfx_flush();

    int prev_left = 0;
    unsigned int mx = 0, my = 0, buttons = 0;

    for (;;) {
        cursor_restore();

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

        cursor_draw_at(mx, my);
        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
