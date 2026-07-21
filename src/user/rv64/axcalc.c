#include "syscall.h"
#include "window.h"

/* AxCalc — calculator, ported from x86 gfx_shell.c's own AxCalc window
 * (see that file's "AxCalc (WIN_CALC) state" comment for the original
 * design this mirrors line-for-line). Sequential-evaluation four-
 * function calculator (2+3*4=20, not 14 - same rule a real basic
 * calculator uses, no operator precedence). Plain int - no float/
 * double anywhere, the FPU is never initialized in this freestanding
 * build either. */

#define ROW_H 16   /* gfx_draw_text's fixed 16px/char advance, see syscall.h */

static int  calc_acc = 0;
static int  calc_cur = 0;
static int  calc_has_digits = 0;
static char calc_pending_op = 0;
static int  calc_error = 0;

static const char calc_btn_keys[16] = {
    '7','8','9','/',
    '4','5','6','*',
    '1','2','3','-',
    'C','0','=','+',
};

/* Returns 1 on division by zero (result left untouched), else 0. */
static int calc_apply(int a, char op, int b, int *out) {
    switch (op) {
        case '+': *out = a + b; return 0;
        case '-': *out = a - b; return 0;
        case '*': *out = a * b; return 0;
        case '/': if (b == 0) return 1; *out = a / b; return 0;
    }
    return 0;
}

static void calc_press(char key) {
    if (key >= '0' && key <= '9') {
        if (calc_error) { calc_error = 0; calc_cur = 0; calc_has_digits = 0; }
        if (calc_cur < 99999999) calc_cur = calc_cur * 10 + (key - '0');
        calc_has_digits = 1;
        return;
    }
    if (key == 'C') {
        calc_acc = 0; calc_cur = 0; calc_has_digits = 0;
        calc_pending_op = 0; calc_error = 0;
        return;
    }
    if (calc_error) return;   /* ignore ops/= until C clears the error */
    if (key == '=') {
        if (calc_pending_op) {
            int b = calc_has_digits ? calc_cur : calc_acc;
            int result;
            if (calc_apply(calc_acc, calc_pending_op, b, &result)) { calc_error = 1; return; }
            calc_acc = result;
            calc_pending_op = 0;
            calc_has_digits = 0;
        }
        return;
    }
    /* Operator key (+ - * /) */
    if (calc_pending_op && calc_has_digits) {
        int result;
        if (calc_apply(calc_acc, calc_pending_op, calc_cur, &result)) { calc_error = 1; return; }
        calc_acc = result;
    } else if (!calc_pending_op) {
        calc_acc = calc_has_digits ? calc_cur : calc_acc;
    }
    calc_pending_op = key;
    calc_cur = 0;
    calc_has_digits = 0;
}

static int calc_display(void) { return calc_has_digits ? calc_cur : calc_acc; }

static int udigits(unsigned int v) {
    int n = 1;
    while (v >= 10) { v /= 10; n++; }
    return n;
}
static void draw_uint(unsigned int x, unsigned int y, unsigned int v, unsigned int color) {
    char buf[11];
    int n = udigits(v);
    buf[n] = '\0';
    for (int i = n - 1; i >= 0; i--) { buf[i] = (char)('0' + v % 10); v /= 10; }
    gfx_draw_text(x, y, buf, color);
}
static void draw_uint_right(unsigned int x_right, unsigned int y, unsigned int v, unsigned int color) {
    unsigned int w = (unsigned int)udigits(v) * ROW_H;
    draw_uint(x_right - w, y, v, color);
}
static void draw_int_right(unsigned int x_right, unsigned int y, int v, unsigned int color) {
    if (v < 0) {
        unsigned int uv = (unsigned int)(-v);
        char buf[12];
        buf[0] = '-';
        int n = udigits(uv);
        for (int i = n - 1; i >= 0; i--) { buf[1+i] = (char)('0' + uv % 10); uv /= 10; }
        buf[1+n] = '\0';
        gfx_draw_text(x_right - (unsigned int)(n+1) * ROW_H, y, buf, color);
    } else {
        draw_uint_right(x_right, y, (unsigned int)v, color);
    }
}

#define CALC_PAD    8
#define CALC_DISP_H ROW_H

static void calc_layout(const window_t *win, unsigned int *grid_x0, unsigned int *grid_y0,
                         unsigned int *btn_sz) {
    int avail_w = (int)win->w - 4 - 2*CALC_PAD;
    int avail_h = (int)win->content_h - 2*CALC_PAD - CALC_DISP_H - 6;
    int sz = avail_w / 4;
    int sz_h = avail_h / 4;
    if (sz_h < sz) sz = sz_h;
    if (sz < 8) sz = 8;
    *btn_sz = (unsigned int)sz;
    *grid_x0 = win->x + 2 + CALC_PAD;
    *grid_y0 = win->content_y + CALC_PAD + CALC_DISP_H + 6;
}

static void render_calc(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int grid_x0, grid_y0, btn_sz;
    calc_layout(win, &grid_x0, &grid_y0, &btn_sz);

    if (calc_error) {
        gfx_draw_text(win->x + 2 + CALC_PAD, win->content_y + CALC_PAD, "Error", gfx_rgb(255, 80, 80));
    } else {
        draw_int_right(win->x + win->w - 2 - CALC_PAD, win->content_y + CALC_PAD,
                       calc_display(), gfx_rgb(80, 255, 80));
    }

    for (unsigned int row = 0; row < 4; row++) {
        for (unsigned int col = 0; col < 4; col++) {
            unsigned int bx = grid_x0 + col*btn_sz;
            unsigned int by = grid_y0 + row*btn_sz;
            char key = calc_btn_keys[row*4+col];
            unsigned int bg = (key == '=') ? gfx_rgb(0, 170, 0) :
                              (key == 'C') ? gfx_rgb(170, 0, 0) :
                              (key=='+'||key=='-'||key=='*'||key=='/') ? gfx_rgb(0, 0, 170) :
                              gfx_rgb(20, 30, 45);
            gfx_fill_rect(bx+2, by+2, btn_sz-4, btn_sz-4, bg);
            char lbl[2];
            lbl[0] = key; lbl[1] = '\0';
            gfx_draw_text(bx + btn_sz/2 - ROW_H/2, by + btn_sz/2 - ROW_H/2, lbl, gfx_rgb(255, 255, 255));
        }
    }
}

/* Returns 1 if the click changed something worth re-rendering. */
static int handle_content_click(const window_t *win, unsigned int mx, unsigned int my) {
    unsigned int grid_x0, grid_y0, btn_sz;
    calc_layout(win, &grid_x0, &grid_y0, &btn_sz);

    if (mx < grid_x0 || my < grid_y0) return 0;
    unsigned int col = (mx - grid_x0) / btn_sz;
    unsigned int row = (my - grid_y0) / btn_sz;
    if (col >= 4 || row >= 4) return 0;
    calc_press(calc_btn_keys[row*4+col]);
    return 1;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    window_t win;
    window_init(&win, 420, 190, 240, 320, gfx_rgb(255, 210, 0), gfx_rgb(10, 15, 25),
               "AxCalc");

    render_calc(&win);
    gfx_flush();

    int dragging = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;

    for (;;) {
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
                if (handle_content_click(&win, mx, my)) render_calc(&win);
            } else if (dragging && left) {
                unsigned int nx = (mx > drag_off_x) ? mx - drag_off_x : 0;
                unsigned int ny = (my > drag_off_y) ? my - drag_off_y : 0;
                if (nx + win.w > screen_w) nx = screen_w - win.w;
                if (ny + win.h > screen_h) ny = screen_h - win.h;
                window_move(&win, nx, ny, screen_h);
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxCalc");
                render_calc(&win);
            }
            prev_left = left;
        }

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
