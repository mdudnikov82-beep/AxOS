#include "syscall.h"
#include "gfx_ui.h"

/* AxTaskbar — the compositor's always-on-top layer (see
 * SYS_WIN_SET_TOPMOST/composite_screen()'s final pass in
 * src/arch/riscv64/syscall.c): a bottom strip with a Start button (opens
 * a small launcher popup), one button per currently open window (click
 * brings it to front via win_focus()), and a live uptime clock. Auto-
 * launched by axdesk.c right after it registers itself as the desktop
 * backdrop - never needs to be started manually.
 *
 * No real wall clock exists on this RISC-V port (see axclock.c's own
 * comment) - the clock here is uptime (gettime()/10000000, 10 MHz CLINT
 * timebase), same idiom already used by axclock.c and AxSH's prompt. */

#define BAR_H     32
#define BTN_H     24
#define START_X   4
#define START_W   60
#define WIN_BTN_W 110
#define WIN_BTN_GAP 6
#define CLOCK_W   (8 * 16)   /* "HH:MM:SS", 8 chars at 16px/char */
#define MENU_ROW_H 20

/* MAX_PROCS is a kernel-only constant (proc.h) with no user-visible
 * mirror - hardcoded here as TB_MAX_PROCS, same tradeoff axtaskmgr.c
 * already documents and accepts for its own copy of this constant. */
#define TB_MAX_PROCS 8

typedef struct {
    const char *label;
    const char *file;
} launch_item_t;

/* Mirrors axdesk.c's icon list (minus the Power/shutdown pseudo-icon,
 * which has no .ELF, and minus AxChat - its main(argc,argv) requires a
 * real IP argument that exec() from a menu click can't supply, same
 * reasoning axdesk.c's own comment documents for skipping its icon). */
static const launch_item_t LAUNCH_ITEMS[] = {
    { "Term",   "AXTERM.ELF"   },
    { "About",  "AXABOUT.ELF"  },
    { "Paint",  "AXPAINT.ELF"  },
    { "Files",  "AXFILES.ELF"  },
    { "Calc",   "AXCALC.ELF"   },
    { "Note",   "AXNOTE.ELF"   },
    { "Snake",  "AXSNAKE.ELF"  },
    { "Clock",  "AXCLOCK.ELF"  },
    { "Todo",   "AXTODO.ELF"   },
    { "Tasks",  "AXTASKM.ELF"  },
    { "Tetris", "AXTETRIS.ELF" },
    { "Web",    "AXBROWSR.ELF" },
};
#define N_LAUNCH_ITEMS ((int)(sizeof(LAUNCH_ITEMS) / sizeof(LAUNCH_ITEMS[0])))

static void draw_uptime(unsigned int x, unsigned int y) {
    long secs = gettime() / 10000000;
    unsigned int hh = (unsigned int)((secs / 3600) % 100);
    unsigned int mm = (unsigned int)((secs / 60) % 60);
    unsigned int ss = (unsigned int)(secs % 60);
    char buf[9];
    buf[0] = (char)('0' + (hh / 10) % 10); buf[1] = (char)('0' + hh % 10); buf[2] = ':';
    buf[3] = (char)('0' + (mm / 10) % 10); buf[4] = (char)('0' + mm % 10); buf[5] = ':';
    buf[6] = (char)('0' + (ss / 10) % 10); buf[7] = (char)('0' + ss % 10); buf[8] = '\0';
    gfx_draw_text(x, y, buf, gfx_rgb(255, 255, 255));
}

/* Truncates to fit WIN_BTN_W (110px / 16px-per-char ~= 6 chars) - a
 * manual char-by-char loop, not a struct/array copy, so it can't hit the
 * freestanding memcpy-lowering landmine documented elsewhere in this
 * codebase (project_riscv_os_aggregate_init_landmine). */
static void draw_button_label(unsigned int x, unsigned int y, const char *name) {
    char buf[7];
    int i = 0;
    while (name[i] && i < 6) { buf[i] = name[i]; i++; }
    buf[i] = '\0';
    gfx_draw_text(x, y, buf, gfx_rgb(220, 220, 220));
}

int main(void) {
    unsigned int w, h;
    if (!gfx_info(&w, &h)) exit(1);

    unsigned int bar_y = h - BAR_H;

    /* Registration must come before any drawing below - same ordering
     * reasoning as axdesk.c/window_init(): gfx_* draws only redirect
     * into this process's own slot buffer once win_registered is set. */
    win_set_rect(0, (int)bar_y, (int)w, BAR_H);
    win_set_topmost();

    int my_pid = getpid();
    int menu_open = 0;
    int prev_left = 0;
    unsigned int mx = 0, my = 0, buttons = 0, focused = 1;
    static ps_entry_t rows[TB_MAX_PROCS];

    unsigned int start_y = bar_y + (BAR_H - BTN_H) / 2;
    unsigned int menu_h  = (unsigned int)(N_LAUNCH_ITEMS * MENU_ROW_H);
    unsigned int menu_y0 = bar_y - menu_h;

    for (;;) {
        /* Poll the process list once per frame - reused for BOTH drawing
         * the open-window buttons and hit-testing clicks on them below,
         * so the two can never disagree about layout within one frame.
         * ps_info() writes straight into rows[n] (kernel-side pointer
         * write) rather than a local temp + struct assignment, matching
         * axtaskmgr.c's exact pattern - avoids the same memcpy-lowering
         * landmine draw_button_label()'s own comment mentions. */
        int n = 0;
        for (unsigned int i = 0; i < TB_MAX_PROCS && n < TB_MAX_PROCS; i++) {
            if (!ps_info(i, &rows[n])) continue;
            if (!rows[n].win_registered || rows[n].win_is_base) continue;
            if (rows[n].pid == my_pid) continue;
            n++;
        }

        /* The registered rect is a single bounding box, and the popup
         * sits ABOVE the bar's own (0,bar_y,w,BAR_H) footprint - the
         * compositor's blit_into_fb() only copies pixels within the
         * CURRENTLY registered rect, regardless of what's drawn into the
         * slot buffer outside it (confirmed live: without this, the menu
         * drew into the buffer and gfx_flush() succeeded, but nothing
         * ever appeared on screen). So the rect must grow to cover both
         * the popup and the bar while open, and shrink back to just the
         * bar when closed - the same dynamic win_set_rect() pattern
         * window.h's window_resize() already uses, just driven by
         * menu_open instead of a drag. Called every frame unconditionally
         * (cheap - a few field writes) rather than only on the open/close
         * transition, so there's no separate state to get out of sync. */
        if (menu_open) {
            win_set_rect(0, (int)menu_y0, (int)w, (int)(h - menu_y0));
            /* Fills the WHOLE enlarged area first - otherwise the space
             * beside the popup (not touched by any other draw call this
             * frame) would expose whatever was last in this slot buffer
             * at those pixels, which is undefined/stale, not "whatever's
             * really behind it" (this compositor has no cheap way to
             * make a window read what's underneath it). */
            gfx_fill_rect(0, menu_y0, w, h - menu_y0, gfx_rgb(15, 15, 25));
        } else {
            win_set_rect(0, (int)bar_y, (int)w, BAR_H);
        }

        gfx_fill_rect(0, bar_y, w, BAR_H, gfx_rgb(20, 20, 35));
        gfx_fill_rect(0, bar_y, w, 2, gfx_rgb(60, 60, 90));

        ui_round_rect((int)START_X, (int)start_y, START_W, BTN_H, 6, gfx_rgb(255, 255, 255), gfx_rgb(60, 120, 220));
        gfx_draw_text(START_X + 6, start_y + 4, "Start", gfx_rgb(255, 255, 255));

        unsigned int clock_x = w - CLOCK_W - 8;
        unsigned int bx = START_X + START_W + 8;
        for (int i = 0; i < n; i++) {
            if (bx + WIN_BTN_W + WIN_BTN_GAP > clock_x) break;   /* don't run into the clock */
            ui_round_rect((int)bx, (int)start_y, WIN_BTN_W, BTN_H, 6, gfx_rgb(255, 255, 255), gfx_rgb(50, 50, 70));
            draw_button_label(bx + 6, start_y + 4, rows[i].name);
            bx += WIN_BTN_W + WIN_BTN_GAP;
        }

        draw_uptime(clock_x, start_y + 4);

        if (menu_open) {
            ui_round_rect((int)START_X, (int)menu_y0, WIN_BTN_W, (int)menu_h, 6, gfx_rgb(255, 255, 255), gfx_rgb(30, 30, 50));
            for (int i = 0; i < N_LAUNCH_ITEMS; i++)
                gfx_draw_text(START_X + 6, menu_y0 + (unsigned int)(i * MENU_ROW_H) + 2, LAUNCH_ITEMS[i].label, gfx_rgb(230, 230, 230));
        }

        gfx_flush();

        if (!mouse_state(&mx, &my, &buttons, &focused, 0)) {
            puts_rv("axtaskb: no mouse device found\r\n");
            exit(1);
        }

        int left = buttons & 1;
        if (left && !prev_left && focused) {
            int in_start = (mx >= START_X && mx < START_X + START_W && my >= start_y && my < start_y + BTN_H);
            if (menu_open) {
                if (mx >= START_X && mx < START_X + WIN_BTN_W && my >= menu_y0 && my < menu_y0 + menu_h) {
                    int idx = (int)((my - menu_y0) / MENU_ROW_H);
                    if (idx >= 0 && idx < N_LAUNCH_ITEMS) {
                        int pid = exec(LAUNCH_ITEMS[idx].file);
                        if (pid < 0) puts_rv("axtaskb: launch failed\r\n");
                    }
                }
                menu_open = 0;   /* any click while open closes it - on Start, a menu item, or elsewhere */
            } else if (in_start) {
                menu_open = 1;
            } else {
                unsigned int bx2 = START_X + START_W + 8;
                for (int i = 0; i < n; i++) {
                    if (bx2 + WIN_BTN_W + WIN_BTN_GAP > clock_x) break;
                    if (mx >= bx2 && mx < bx2 + WIN_BTN_W && my >= start_y && my < start_y + BTN_H) {
                        win_focus(rows[i].pid);
                        break;
                    }
                    bx2 += WIN_BTN_W + WIN_BTN_GAP;
                }
            }
        }
        prev_left = left;

        sleep_ms(30);
    }

    return 0;
}
