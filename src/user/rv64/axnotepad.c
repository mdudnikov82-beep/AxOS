#include "syscall.h"
#include "window.h"

/* AxNotepad — a simple text editor, ported from x86 gfx_shell.c's own
 * AxNotepad window (see that file's "AxNotepad (WIN_NOTEPAD) state"
 * comment for the original design this mirrors line-for-line).
 * Typewriter-style append editor: cursor is always at (np_row,np_col),
 * typing appends there, Enter starts a new row, Backspace deletes the
 * last char (stepping onto the end of the previous row once the
 * current one is empty - not real line-merging). No arrow keys, no
 * mid-line insert, no word wrap. Fixed filename "NOTES.TXT" (v1 scope,
 * same as AxPaint's original single CANVAS.BMP before slots).
 *
 * Keyboard input reuses axterm.c's exact kbd_getc() drain-loop pattern
 * (virtio-keyboard, already-translated ASCII - no scancode table
 * needed here unlike x86). Unlike axterm.c, this app keeps a real
 * retained/editable multi-line buffer (axterm.c only has scrollback
 * that's printed once and forgotten via window_println()), so its own
 * render_notepad() draws directly via gfx_draw_text()/gfx_fill_rect()
 * instead of window_println(). */

#define ROW_H 16   /* gfx_draw_text's fixed 16px/char advance, see syscall.h */

#define NP_MAX_ROWS 24
#define NP_MAX_COLS 48
static char np_lines[NP_MAX_ROWS][NP_MAX_COLS+1];
static int  np_len[NP_MAX_ROWS];
static int  np_row = 0, np_col = 0;
static char np_status[40];
static int  np_status_timer = 0;
static char np_scratch[NP_MAX_ROWS * (NP_MAX_COLS + 1) + 1];

static void np_status_set(const char *s) {
    int i = 0;
    while (s[i] && i < (int)sizeof(np_status) - 1) { np_status[i] = s[i]; i++; }
    np_status[i] = '\0';
    np_status_timer = 90;
}

#define NP_PAD 8

/* Shared by render_notepad()/handle_content_click()/np_press() so
 * hit-testing and the input cap can't drift from what's drawn - same
 * reasoning as axfiles.c's files_layout()/axcalc.c's calc_layout(). */
static void np_layout(const window_t *win, unsigned int *text_x0, unsigned int *text_y0,
                       int *visible_rows, int *visible_cols,
                       unsigned int *save_x, unsigned int *load_x, unsigned int *btn_y) {
    *btn_y   = win->content_y + NP_PAD;
    *save_x  = win->x + 2 + NP_PAD;
    *load_x  = *save_x + 7*ROW_H;   /* "[Save] " = 7 chars */
    *text_x0 = win->x + 2 + NP_PAD;
    *text_y0 = win->content_y + NP_PAD + ROW_H + 6;

    int rows = (int)(win->content_y + win->content_h) - (int)NP_PAD - (int)*text_y0;
    rows /= ROW_H;
    if (rows > NP_MAX_ROWS) rows = NP_MAX_ROWS;
    if (rows < 1) rows = 1;
    *visible_rows = rows;

    int cols = ((int)win->w - 4 - 2*NP_PAD) / ROW_H;
    if (cols > NP_MAX_COLS) cols = NP_MAX_COLS;
    if (cols < 1) cols = 1;
    *visible_cols = cols;
}

static void np_press(const window_t *win, int c) {
    if (c < 0) return;

    unsigned int tx0, ty0, sx, lx, by;
    int vrows, vcols;
    np_layout(win, &tx0, &ty0, &vrows, &vcols, &sx, &lx, &by);

    if (c == '\n') {
        if (np_row < vrows - 1) {
            np_row++; np_col = 0;
            np_lines[np_row][0] = '\0';
            np_len[np_row] = 0;
        }
        return;
    }
    if (c == '\b') {
        if (np_col > 0) {
            np_col--;
            np_lines[np_row][np_col] = '\0';
            np_len[np_row] = np_col;
        } else if (np_row > 0) {
            np_row--;
            np_col = np_len[np_row];
        }
        return;
    }
    if (np_col < vcols - 1) {
        np_lines[np_row][np_col] = (char)c;
        np_col++;
        np_lines[np_row][np_col] = '\0';
        np_len[np_row] = np_col;
    }
}

static void np_save(void) {
    int p = 0;
    for (int r = 0; r <= np_row; r++) {
        for (int i = 0; i < np_len[r]; i++) np_scratch[p++] = np_lines[r][i];
        if (r < np_row) np_scratch[p++] = '\n';
    }
    int ok = writefile("NOTES.TXT", np_scratch, p);
    np_status_set(ok ? "Saved: NOTES.TXT" : "Save failed");
}

static void np_load(const window_t *win) {
    unsigned int n = 0;
    int fd = open("NOTES.TXT", 0);
    if (fd >= 0) {
        long r = read(fd, np_scratch, sizeof(np_scratch));
        if (r > 0) n = (unsigned int)r;
        close(fd);
    }
    if (n == 0) { np_status_set("No saved file"); return; }

    unsigned int tx0, ty0, sx, lx, by;
    int vrows, vcols;
    np_layout(win, &tx0, &ty0, &vrows, &vcols, &sx, &lx, &by);

    for (int i = 0; i < NP_MAX_ROWS; i++) { np_lines[i][0] = '\0'; np_len[i] = 0; }
    int rr = 0, cc = 0;
    for (unsigned int i = 0; i < n && rr < vrows; i++) {
        char ch2 = np_scratch[i];
        if (ch2 == '\n') { np_lines[rr][cc] = '\0'; np_len[rr] = cc; rr++; cc = 0; continue; }
        if (cc < vcols - 1) np_lines[rr][cc++] = ch2;
    }
    if (rr < vrows) { np_lines[rr][cc] = '\0'; np_len[rr] = cc; } else { rr = vrows - 1; cc = np_len[rr]; }
    np_row = rr; np_col = cc;
    np_status_set("Loaded: NOTES.TXT");
}

static void render_notepad(const window_t *win, int cursor_on) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int tx0, ty0, sx, lx, by;
    int vrows, vcols;
    np_layout(win, &tx0, &ty0, &vrows, &vcols, &sx, &lx, &by);
    (void)vcols;

    gfx_draw_text(sx, by, "[Save]", gfx_rgb(0, 255, 120));
    gfx_draw_text(lx, by, "[Load]", gfx_rgb(255, 255, 0));
    if (np_status_timer > 0) {
        gfx_draw_text(lx + 7*ROW_H, by, np_status, gfx_rgb(0, 220, 220));
        np_status_timer--;
    }

    for (int r = 0; r < vrows; r++)
        gfx_draw_text(tx0, ty0 + (unsigned int)r*ROW_H, np_lines[r], gfx_rgb(255, 255, 255));

    if (cursor_on)
        gfx_fill_rect(tx0 + (unsigned int)np_col*ROW_H, ty0 + (unsigned int)np_row*ROW_H,
                     8, ROW_H, gfx_rgb(255, 255, 255));
}

/* Returns 1 if the click changed something worth re-rendering. */
static int handle_content_click(const window_t *win, unsigned int mx, unsigned int my) {
    unsigned int tx0, ty0, sx, lx, by;
    int vrows, vcols;
    np_layout(win, &tx0, &ty0, &vrows, &vcols, &sx, &lx, &by);
    (void)tx0; (void)ty0; (void)vrows; (void)vcols;

    if (my < by || my >= by + ROW_H) return 0;
    if (mx >= sx && mx < sx + 6*ROW_H) { np_save(); return 1; }
    if (mx >= lx && mx < lx + 6*ROW_H) { np_load(win); return 1; }
    return 0;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    window_t win;
    window_init(&win, 80, 150, 640, 420, gfx_rgb(0, 200, 200), gfx_rgb(10, 15, 25),
               "AxNotepad");

    render_notepad(&win, 0);
    gfx_flush();

    int dragging = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;
    unsigned long tick = 0;

    for (;;) {
        int changed = 0;

        unsigned int mx = 0, my = 0, buttons = 0;
        if (mouse_state(&mx, &my, &buttons)) {
            int left = buttons & 1;
            if (!dragging && left && !prev_left && window_hit_close(&win, mx, my)) {
                window_erase_desktop_bg((int)win.x, (int)win.y, (int)win.w, (int)win.h, screen_h);
                gfx_flush();
                exit(0);
            } else if (!dragging && left && !prev_left && window_hit_titlebar(&win, mx, my)) {
                dragging = 1;
                drag_off_x = mx - win.x;
                drag_off_y = my - win.y;
            } else if (!dragging && left && !prev_left && mx >= win.x && mx < win.x + win.w &&
                      my >= win.content_y && my < win.content_y + win.content_h) {
                if (handle_content_click(&win, mx, my)) changed = 1;
            } else if (dragging && left) {
                unsigned int nx = (mx > drag_off_x) ? mx - drag_off_x : 0;
                unsigned int ny = (my > drag_off_y) ? my - drag_off_y : 0;
                if (nx + win.w > screen_w) nx = screen_w - win.w;
                if (ny + win.h > screen_h) ny = screen_h - win.h;
                window_move(&win, nx, ny, screen_h);
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxNotepad");
                changed = 1;
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            np_press(&win, c);
            changed = 1;
        }

        tick++;
        int cursor_on = (int)((tick / 15) & 1);   /* ~blink every ~300ms at a 20ms poll */
        if (changed || (tick % 15 == 0)) render_notepad(&win, cursor_on);

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
