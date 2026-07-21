#include "syscall.h"
#include "window.h"

/* AxSnake — classic grid-based Snake, ported from x86 gfx_shell.c's
 * own AxSnake window (see that file's "AxSnake (WIN_SNAKE) state"
 * comment for the original design this mirrors line-for-line).
 * WASD-only movement - RISC-V's virtio_keyboard.c (`handle_event()`)
 * discards any keycode >= 89 before translation, which covers every
 * arrow key (Linux KEY_UP=103 etc.) - unsupported at the driver
 * level, not something this app can work around. `kbd_getc()` already
 * returns plain ASCII for WASD with zero extra translation, same path
 * axterm.c/axnotepad.c use.
 *
 * Advances on a tick counter (not every poll), same idiom axterm.c's
 * cursor blink already established: `sleep_ms(20)` per iteration,
 * advance every 10 ticks -> ~200ms/move. */

#define GRID_W 20
#define GRID_H 14
#define CELL   16
#define SNAKE_MAX (GRID_W * GRID_H)
#define SNAKE_TICK_N 10

static int snake_x[SNAKE_MAX], snake_y[SNAKE_MAX];
static int snake_len;
static int snake_dx, snake_dy;
static int food_x, food_y;
static int score;
static int game_over;
static unsigned long snake_seed = 12345;

static unsigned long snake_rand(void) {
    snake_seed = snake_seed * 1103515245UL + 12345UL;
    return (snake_seed >> 16) & 0x7fffUL;
}

static int snake_occupied(int x, int y) {
    for (int i = 0; i < snake_len; i++)
        if (snake_x[i] == x && snake_y[i] == y) return 1;
    return 0;
}

static void snake_spawn_food(void) {
    for (int attempt = 0; attempt < 100; attempt++) {
        int x = (int)(snake_rand() % GRID_W);
        int y = (int)(snake_rand() % GRID_H);
        if (!snake_occupied(x, y)) { food_x = x; food_y = y; return; }
    }
    for (int y = 0; y < GRID_H; y++)
        for (int x = 0; x < GRID_W; x++)
            if (!snake_occupied(x, y)) { food_x = x; food_y = y; return; }
}

static void snake_reset(void) {
    snake_len = 3;
    snake_x[0] = GRID_W/2;     snake_y[0] = GRID_H/2;
    snake_x[1] = GRID_W/2 - 1; snake_y[1] = GRID_H/2;
    snake_x[2] = GRID_W/2 - 2; snake_y[2] = GRID_H/2;
    snake_dx = 1; snake_dy = 0;
    score = 0;
    game_over = 0;
    snake_spawn_food();
}

static void snake_set_dir(int dx, int dy) {
    if (game_over) { snake_reset(); return; }
    if (dx == -snake_dx && dy == -snake_dy) return;   /* no instant reversal */
    snake_dx = dx; snake_dy = dy;
}

/* Self-collision checked against the PRE-move body (including the
 * current tail cell, about to vacate unless growing) - deliberately
 * simple, same accepted simplification as the x86 port. */
static void snake_advance(void) {
    if (game_over) return;

    int newx = snake_x[0] + snake_dx;
    int newy = snake_y[0] + snake_dy;

    if (newx < 0 || newx >= GRID_W || newy < 0 || newy >= GRID_H) { game_over = 1; return; }
    if (snake_occupied(newx, newy)) { game_over = 1; return; }

    int grow = (newx == food_x && newy == food_y);
    if (grow && snake_len < SNAKE_MAX) snake_len++;
    for (int i = snake_len - 1; i >= 1; i--) {
        snake_x[i] = snake_x[i-1];
        snake_y[i] = snake_y[i-1];
    }
    snake_x[0] = newx; snake_y[0] = newy;
    if (grow) { score++; snake_spawn_food(); }
}

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

#define SNAKE_PAD 8
#define SNAKE_BAR_H (16 + 6)

static void render_snake(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int bx = win->x + 2 + SNAKE_PAD;
    unsigned int by = win->content_y + SNAKE_PAD;
    if (game_over) {
        /* window_draw_text_clipped(), not gfx_draw_text() - this string
         * (448px at 16px/char) overflows the window's own right edge
         * (content width ~332px); unclipped, the overflow draws straight
         * onto the framebuffer outside the content rect that
         * render_snake()'s own gfx_fill_rect() clears each frame, so a
         * restarted game left ghost pixels behind - caught live via a
         * screendump after a restart, same class of bug window.h's own
         * comment on this helper documents (axfiles.c hit it first). */
        window_draw_text_clipped(win, bx, by, "GAME OVER - WASD to restart", gfx_rgb(255, 80, 80));
    } else {
        gfx_draw_text(bx, by, "Score:", gfx_rgb(0, 220, 220));
        draw_uint(bx + 7*16, by, (unsigned int)score, gfx_rgb(255, 255, 0));
    }

    unsigned int grid_x0 = win->x + 2 + SNAKE_PAD;
    unsigned int grid_y0 = win->content_y + SNAKE_PAD + SNAKE_BAR_H;

    for (int i = 0; i < snake_len; i++)
        gfx_fill_rect(grid_x0 + (unsigned int)snake_x[i]*CELL + 1,
                     grid_y0 + (unsigned int)snake_y[i]*CELL + 1,
                     CELL-2, CELL-2, gfx_rgb(60, 220, 60));
    gfx_fill_rect(grid_x0 + (unsigned int)food_x*CELL + 1,
                 grid_y0 + (unsigned int)food_y*CELL + 1,
                 CELL-2, CELL-2, gfx_rgb(220, 60, 60));
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    window_t win;
    window_init(&win, 220, 190, 340, 298, gfx_rgb(60, 220, 60), gfx_rgb(10, 15, 10),
               "AxSnake");

    snake_reset();
    render_snake(&win);
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
            } else if (dragging && left) {
                unsigned int nx = (mx > drag_off_x) ? mx - drag_off_x : 0;
                unsigned int ny = (my > drag_off_y) ? my - drag_off_y : 0;
                if (nx + win.w > screen_w) nx = screen_w - win.w;
                if (ny + win.h > screen_h) ny = screen_h - win.h;
                window_move(&win, nx, ny, screen_h);
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxSnake");
                changed = 1;
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (c == 'w')      snake_set_dir(0, -1);
            else if (c == 's') snake_set_dir(0, 1);
            else if (c == 'a') snake_set_dir(-1, 0);
            else if (c == 'd') snake_set_dir(1, 0);
        }

        tick++;
        if (tick % SNAKE_TICK_N == 0) { snake_advance(); changed = 1; }

        if (changed) render_snake(&win);
        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
