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

/* Shrunk from 70/9 when AxTaskMgr became the 11th icon - the old pitch
 * (11*70 + 10*9 = 860px) no longer fit an 800px-wide screen. BMP icon
 * art (<=64x64, see bmp.h) still centers fine at this width.
 * ICON_GAP shrunk again (8->2) when AxTetris became the 12th icon -
 * same overflow, same fix (icon art is fixed-size, so the gap is the
 * only thing cheap to shrink): 12*64 + 11*2 = 790px, fits with margin.
 * AxChat/AxBrowser becoming icons 13-14 finally outgrew a single row
 * even at this minimal gap (14*64+13*2=922px) - the gap can't shrink
 * further and icon art is fixed-size, so icons now wrap onto additional
 * rows instead (see row_max/ROW_GAP below) rather than squeezing
 * forever. */
#define ICON_W   64
#define ICON_H   96
#define ICON_GAP 2
#define ICON_TOP 70
#define ROW_GAP  12   /* vertical gap between icon rows */

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

    /* Registers AxDesk as the compositor's backdrop layer - always
     * painted first, exempt from click/keyboard focus arbitration (see
     * src/arch/riscv64/syscall.c's SYS_MOUSE_STATE/SYS_KBD_GETC). Must
     * come BEFORE any drawing below, same reasoning as window_init()'s
     * own registration-first ordering: gfx_* draws only redirect into
     * this process's own slot buffer once win_registered is set, so
     * drawing the gradient+icons first would leave them in the real
     * framebuffer instead, invisible on the first composite. */
    win_set_rect(0, 0, (int)w, (int)h);
    win_set_base();

    /* Auto-launches the taskbar (Start menu + open-window buttons +
     * clock) alongside the desktop - never needs a separate manual
     * launch step. Non-blocking, same fire-and-forget exec() pattern as
     * an icon click; checked here (unlike a plain icon click, which
     * only fails visibly via the on-screen "launch failed" message)
     * because a silent failure here would leave the desktop looking
     * "done" with no taskbar at all and no obvious reason why. */
    if (exec("AXTASKB.ELF") < 0) {
        puts_rv("axdesk: failed to launch AXTASKB.ELF\r\n");
    }

    icon_t icons[14];
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
    icons[7].label = "Snake"; icons[7].file = "AXSNAKE.ELF"; icons[7].icon_bmp = 0;          icons[7].color = gfx_rgb(60, 220, 60);
    icons[8].label = "Clock"; icons[8].file = "AXCLOCK.ELF"; icons[8].icon_bmp = 0;          icons[8].color = gfx_rgb(255, 165, 0);
    icons[9].label = "Todo";  icons[9].file = "AXTODO.ELF";  icons[9].icon_bmp = 0;          icons[9].color = gfx_rgb(220, 180, 0);
    icons[10].label = "Tasks"; icons[10].file = "AXTASKM.ELF"; icons[10].icon_bmp = 0;        icons[10].color = gfx_rgb(150, 90, 220);
    icons[11].label = "Tetris"; icons[11].file = "AXTETRIS.ELF"; icons[11].icon_bmp = 0;       icons[11].color = gfx_rgb(30, 100, 220);
    /* AxBrowser was deliberately left off this row before (launched via
     * "run AXBROWSR.ELF &" from AxSH) - its main(void) takes no argv at
     * all (navigation happens via the in-app address bar), so a plain
     * icon click works fine, unlike AxChat below. */
    icons[12].label = "Web";  icons[12].file = "AXBROWSR.ELF";  icons[12].icon_bmp = 0;         icons[12].color = gfx_rgb(90, 150, 220);
    /* AxChat does NOT get an icon: its main(argc,argv) requires a real
     * "host <my_ip>"/"join <my_ip> <peer_ip>" argument - exec() from an
     * icon click passes no argv at all, so a bare click would just print
     * a usage message to AxChat's own stdout (not visible in the GUI)
     * and exit immediately - confirmed live: clicking a would-be Chat
     * icon here silently did nothing. There's no single sensible default
     * IP to hardcode (it has to match whatever this machine's real
     * network config is, and differs per chat session/peer) - stays
     * shell-launch-only until/unless icons gain real argv support. */
    unsigned int n_icons = 13;

    /* Icons wrap onto additional rows once they no longer fit one 800px-
     * wide line (see ICON_W's own comment above for the history of why
     * the gap/width can't just shrink further). row_max = how many fit
     * per row; a full row is centered, later rows left-align under it
     * rather than each independently re-centering (fewer icons on the
     * last row looks intentional, not scattered). */
    unsigned int row_max = (w + ICON_GAP) / (ICON_W + ICON_GAP);
    if (row_max < 1) row_max = 1;
    unsigned int full_row_w = row_max * ICON_W + (row_max - 1) * ICON_GAP;
    unsigned int start_x = (w > full_row_w) ? (w - full_row_w) / 2 : 0;
    unsigned int total_rows = (n_icons + row_max - 1) / row_max;

    /* Desktop background (gradient - was flat) + title bar. */
    ui_vgrad(0, 0, w, h, gfx_rgb(30, 30, 60), gfx_rgb(8, 8, 20));
    ui_vgrad(0, 0, w, 28, gfx_rgb(20, 20, 45), gfx_rgb(10, 10, 25));
    gfx_draw_text(8, 10, "AxOS Desktop  --  click an icon to launch", gfx_rgb(200, 200, 255));

    /* Один переиспользуемый буфер декодирования - иконки рисуются по
     * очереди, ни одна не должна пережить следующий bmp_load(). */
    static bmp_image_t icon_img;

    for (unsigned int i = 0; i < n_icons; i++) {
        unsigned int col = i % row_max;
        unsigned int row = i / row_max;
        int x = (int)(start_x + col * (ICON_W + ICON_GAP));
        int y = (int)(ICON_TOP + row * (ICON_H + ROW_GAP));
        ui_shadow(x, y, ICON_W, ICON_H, 5, 90);
        /* matches x86 gfx_shell.c's ICON_R - see gfx_ui.h's UI_MAX_R comment */
        ui_round_rect(x, y, ICON_W, ICON_H, 14, gfx_rgb(255, 255, 255), icons[i].color);

        /* Настоящая иконка (BMP) поверх карточки, если файл нашёлся и
         * декодировался - иначе просто остаётся цветная карточка с
         * подписью (fallback, не крашимся на отсутствующем/битом файле). */
        if (icons[i].icon_bmp && bmp_load(icons[i].icon_bmp, &icon_img)) {
            unsigned int icon_x = (unsigned int)x + (ICON_W - icon_img.width) / 2;
            bmp_draw(&icon_img, icon_x, (unsigned int)y + 6);
        }

        /* Clamp to 0 rather than let (ICON_W - lw) underflow (unsigned) -
         * some 5-char labels ("About","Files","Snake","Clock","Tasks")
         * are now wider than ICON_W=64 since it shrank for the 11-icon
         * row (see this file's own comment above ICON_W); a negative
         * result wrapped to a huge x and drew the label off-screen,
         * invisible - found live via screendump. Left-aligned + a small
         * bleed into the gap reads fine, unlike "not there at all". */
        unsigned int lw = text_px_w(icons[i].label);
        unsigned int lx = (lw < ICON_W) ? (unsigned int)x + (ICON_W - lw) / 2 : (unsigned int)x;
        gfx_draw_text(lx, (unsigned int)y + ICON_H - 20, icons[i].label, gfx_rgb(0, 0, 0));
    }
    gfx_flush();

    int prev_left = 0;
    unsigned int mx = 0, my = 0, buttons = 0, focused = 1;

    for (;;) {
        /* AxDesk never registers a window of its own, but it's NOT
         * exempt from ownership either - a window drawn on top of the
         * icon row must still block the icon underneath it (see the
         * kernel's SYS_MOUSE_STATE handler: for a non-windowed process,
         * "focused" means "no registered window claimed this click",
         * not "always true" - closes a real gap found live in the
         * window-manager work, where clicking a window sitting over
         * the icon row also re-launched whatever icon was underneath). */
        if (!mouse_state(&mx, &my, &buttons, &focused, 0)) {
            puts_rv("axdesk: no mouse device found\r\n");
            exit(1);
        }

        int left = buttons & 1;
        if (left && !prev_left && focused) {   /* click edge, not held-down repeat */
            for (unsigned int i = 0; i < n_icons; i++) {
                unsigned int col = i % row_max;
                unsigned int row = i / row_max;
                unsigned int x = start_x + col * (ICON_W + ICON_GAP);
                unsigned int y = ICON_TOP + row * (ICON_H + ROW_GAP);
                if (mx >= x && mx < x + ICON_W && my >= y && my < y + ICON_H) {
                    if (icons[i].file) {
                        int pid = exec(icons[i].file);
                        if (pid < 0) {
                            /* Always below the LAST icon row (not just row 0)
                             * so it can never collide with a second row of
                             * icons, regardless of how many rows exist. */
                            gfx_draw_text(start_x, ICON_TOP + total_rows * (ICON_H + ROW_GAP),
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
