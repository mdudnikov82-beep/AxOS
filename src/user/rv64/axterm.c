#include "syscall.h"
#include "window.h"

/* AxTerminal — a real interactive terminal window, driven by
 * kbd_getc() (virtio-keyboard, see virtio_keyboard.c). Mirrors x86
 * gfx_shell.c's built-in terminal (help/ver/cls/exit) in spirit, but
 * built on RV64's syscall-per-draw-call gfx API: the input line is
 * redrawn on every keystroke (cheap, a few ecalls), scrollback only
 * grows via window_println() on Enter, not every poll tick.
 *
 * Reuses window_init()/window_println() from window.h COMPLETELY
 * UNMODIFIED (window.h is shared with axabout.c) via one trick: shrink
 * win.content_h by exactly one row (16px) right after window_init() to
 * reclaim a strip at the bottom of the content area for the input line
 * - window_println()'s own row math (content_h/16) then transparently
 * leaves that strip alone. */

#define INPUT_MAX 40

static char input[INPUT_MAX];
static unsigned int input_len = 0;

static int streq(const char *s) {
    unsigned int i = 0;
    while (s[i] && input[i] == s[i]) i++;
    return s[i] == 0 && input[i] == 0;
}

static int starts_with(const char *s) {
    unsigned int i = 0;
    while (s[i]) {
        if (input[i] != s[i]) return 0;
        i++;
    }
    return 1;
}

static void draw_input_line(window_t *win, int cursor_on) {
    unsigned int y = win->content_y + win->content_h;
    gfx_fill_rect(win->x + 4, y, win->w - 8, 16, win->bg);
    gfx_draw_text(win->x + 6, y, "> ", gfx_rgb(255, 255, 0));
    if (input_len) window_draw_text_clipped(win, win->x + 6 + 32, y, input, gfx_rgb(255, 255, 255));
    if (cursor_on)
        gfx_fill_rect(win->x + 6 + 32 + input_len * 16, y, 10, 16, gfx_rgb(255, 255, 255));
}

static void run_command(window_t *win) {
    /* echo "> <cmd>" into scrollback before dispatching */
    char echo[INPUT_MAX + 4];
    int i = 0;
    echo[i++] = '>'; echo[i++] = ' ';
    for (unsigned int k = 0; k < input_len; k++) echo[i++] = input[k];
    echo[i] = '\0';
    window_println(win, echo, gfx_rgb(0, 255, 120));

    if (input_len == 0) {
        /* nothing to do */
    } else if (streq("help")) {
        window_println(win, "help ver cls echo uptime exit", gfx_rgb(180, 180, 255));
    } else if (streq("ver")) {
        window_println(win, "AxOS/RV64 AxTerminal v1.0", gfx_rgb(180, 180, 255));
    } else if (streq("cls")) {
        gfx_fill_rect(win->x + 4, win->content_y, win->w - 8, win->content_h, win->bg);
        win->cur_row = 0;
    } else if (starts_with("echo ")) {
        window_println(win, input + 5, gfx_rgb(180, 180, 255));
    } else if (streq("uptime")) {
        window_println_udec(win, "uptime (s): ", gettime() / 10000000UL, gfx_rgb(180, 180, 255));
    } else if (streq("exit")) {
        gfx_flush();
        exit(0);
    } else {
        window_println(win, "Unknown. Try: help", gfx_rgb(255, 80, 80));
    }

    input_len = 0;
    input[0] = '\0';
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);   /* runtime query, matches axdesk.c/axpaint.c's convention */

    window_t win;
    window_init(&win, 16, 40, 300, 424, 260, 200, gfx_rgb(0, 150, 255), gfx_rgb(10, 10, 30),
               "AxTerminal");
    win.content_h -= 16;   /* reserve the reclaimed bottom strip for the input line */

    window_println(&win, "AxOS/RV64 AxTerminal - type 'help'", gfx_rgb(255, 255, 0));
    draw_input_line(&win, 0);
    gfx_flush();

    int dragging = 0, resizing = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;

    unsigned long tick = 0;
    for (;;) {
        int changed = 0;

        unsigned int mx = 0, my = 0, buttons = 0, focused = 1;
        if (mouse_state(&mx, &my, &buttons, &focused, 0)) {
            int left = buttons & 1;
            if (!dragging && !resizing && left && !prev_left && focused && window_hit_close(&win, mx, my)) {
                gfx_flush();
                exit(0);
            } else if (!dragging && !resizing && left && !prev_left && focused && window_hit_resize(&win, mx, my)) {
                resizing = 1;
            } else if (!dragging && !resizing && left && !prev_left && focused && window_hit_titlebar(&win, mx, my)) {
                dragging = 1;
                drag_off_x = mx - win.x;
                drag_off_y = my - win.y;
            } else if (dragging && left) {
                unsigned int nx = (mx > drag_off_x) ? mx - drag_off_x : 0;
                unsigned int ny = (my > drag_off_y) ? my - drag_off_y : 0;
                if (nx + win.w > screen_w) nx = screen_w - win.w;
                if (ny + win.h > screen_h) ny = screen_h - win.h;
                window_move(&win, nx, ny, screen_h);
                changed = 1;
            } else if (resizing && left) {
                unsigned int nw = (mx > win.x + WIN_RESIZE_SIZE) ? mx - win.x : win.min_w;
                unsigned int nh = (my > win.y + WIN_RESIZE_SIZE) ? my - win.y : win.min_h;
                window_resize(&win, nw, nh, screen_w, screen_h);
                win.content_h -= 16;   /* re-reserve the input-line strip window_resize() just recomputed away */
                changed = 1;
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxTerminal");
                win.cur_row = 0;   /* content lost on move - no retained scrollback buffer */
                changed = 1;
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxTerminal");
                win.cur_row = 0;   /* content lost on resize too, same as move */
                changed = 1;
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (c == '\n') {
                run_command(&win);
                draw_input_line(&win, 1);
                changed = 1;
            } else if (c == '\b') {
                if (input_len) { input[--input_len] = '\0'; changed = 1; }
            } else if (input_len < INPUT_MAX - 1) {
                input[input_len++] = (char)c;
                input[input_len] = '\0';
                changed = 1;
            }
        }

        tick++;
        int cursor_on = (int)((tick / 15) & 1);   /* ~blink every ~300ms at a 20ms poll */
        if (changed || (tick % 15 == 0)) {
            draw_input_line(&win, cursor_on);
        }

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
