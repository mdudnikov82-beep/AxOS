#include "syscall.h"
#include "window.h"

/* AxTetris — classic falling-block puzzle, mirrors axsnake.c's own
 * architecture almost line-for-line (real-time tick-based loop,
 * window.h GUI boilerplate for drag/resize/close, WASD-style keyboard
 * input via kbd_getc(), flat-file high-score persistence). New game
 * logic only. Deliberately simple, same accepted-simplification ethos
 * axsnake.c's own collision check already uses: rotation is a plain
 * 90-degree turn around a 4x4 box with no wall kicks/SRS, and there's
 * no lock delay - a piece locks the instant it can't move down. */

#define BOARD_W 10
#define BOARD_H 20
#define CELL    16
#define TETRIS_TICK_N 40   /* 40 * sleep_ms(20) = 800ms/drop, matches
                            * real NES Tetris level-0 pace */
#define HISCORE_FILE "TETRIS.HI"

typedef struct { int cells[4][4]; } shape4_t;

/* Reference (spawn) orientations - verified against the real, standard
 * Tetris tetrominoes (the classic J/L and S/Z mix-ups both checked).
 * All active cells sit within rows 0-2, so spawning at board row 0
 * never needs a negative row index. The O-piece is deliberately placed
 * at rows 1-2 (not 0-1) - found live: rotate_cw()'s box-rotation is
 * only visually a no-op for a shape centered in the 4x4 box (rows 1-2,
 * cols 1-2); at rows 0-1 the square visibly hopped one cell diagonally
 * on every rotate keypress even though it stayed collision-correct. */
static const shape4_t SHAPES[7] = {
    { { {0,0,0,0}, {1,1,1,1}, {0,0,0,0}, {0,0,0,0} } },  /* I */
    { { {0,0,0,0}, {0,1,1,0}, {0,1,1,0}, {0,0,0,0} } },  /* O */
    { { {0,1,0,0}, {1,1,1,0}, {0,0,0,0}, {0,0,0,0} } },  /* T */
    { { {0,1,1,0}, {1,1,0,0}, {0,0,0,0}, {0,0,0,0} } },  /* S */
    { { {1,1,0,0}, {0,1,1,0}, {0,0,0,0}, {0,0,0,0} } },  /* Z */
    { { {1,0,0,0}, {1,1,1,0}, {0,0,0,0}, {0,0,0,0} } },  /* J */
    { { {0,0,1,0}, {1,1,1,0}, {0,0,0,0}, {0,0,0,0} } },  /* L */
};

static unsigned int piece_color(int id) {
    switch (id) {
        case 0: return gfx_rgb(0, 220, 220);    /* I cyan   */
        case 1: return gfx_rgb(220, 220, 0);    /* O yellow */
        case 2: return gfx_rgb(170, 0, 220);    /* T purple */
        case 3: return gfx_rgb(0, 220, 0);      /* S green  */
        case 4: return gfx_rgb(220, 0, 0);      /* Z red    */
        case 5: return gfx_rgb(0, 90, 220);     /* J blue   */
        case 6: return gfx_rgb(230, 140, 0);    /* L orange */
        default: return gfx_rgb(180, 180, 180);
    }
}

/* Explicit field-by-field copy, NOT a struct assignment - this
 * freestanding build has no libc, and GCC silently lowers a plain
 * `dst = src;` struct copy of this size into a memcpy() call that
 * doesn't exist, only caught at link time (the same recurring
 * landmine documented for aggregate initializers elsewhere in this
 * codebase - this is the runtime-copy variant of it). */
static void shape_copy(shape4_t *dst, const shape4_t *src) {
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
            dst->cells[y][x] = src->cells[y][x];
}

/* Generic 90-degree clockwise rotation of a 4x4 shape - verified by
 * hand-tracing against the L and T pieces (produces the real,
 * known-correct rotated forms), not just trusting the algebra. Used
 * instead of hardcoding 4 rotation states per piece - fewer chances
 * for a hand-typed table to be subtly wrong. */
static void rotate_cw(shape4_t *p) {
    shape4_t r;
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
            r.cells[y][x] = p->cells[3 - x][y];
    shape_copy(p, &r);
}

static int board[BOARD_H][BOARD_W];   /* 0 = empty, else piece-color-id 1..7 */

static shape4_t cur_shape;
static int cur_x, cur_y;
static int cur_piece_id;
static int next_piece_id;
static int score;
static int high_score;
static int game_over;
static unsigned long tetris_seed = 54321;

static unsigned long tetris_rand(void) {
    tetris_seed = tetris_seed * 1103515245UL + 12345UL;
    return (tetris_seed >> 16) & 0x7fffUL;
}

static int collides(const shape4_t *s, int px, int py) {
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
            if (s->cells[y][x]) {
                int bx = px + x, by = py + y;
                if (bx < 0 || bx >= BOARD_W || by >= BOARD_H) return 1;
                if (by >= 0 && board[by][bx]) return 1;
            }
    return 0;
}

static void spawn_piece(void) {
    cur_piece_id = next_piece_id;
    next_piece_id = (int)(tetris_rand() % 7);
    shape_copy(&cur_shape, &SHAPES[cur_piece_id]);
    cur_x = (BOARD_W - 4) / 2;
    cur_y = 0;
    if (collides(&cur_shape, cur_x, cur_y)) game_over = 1;
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

/* Plain decimal ASCII, not a binary struct - same reasoning axsnake.c's
 * own high-score save uses (human-readable via AxFiles' own preview). */
static void tetris_save_highscore(void) {
    char buf[12];
    unsigned int v = (unsigned int)high_score;
    int n = udigits(v);
    for (int i = n - 1; i >= 0; i--) { buf[i] = (char)('0' + v % 10); v /= 10; }
    writefile(HISCORE_FILE, buf, n);
}

static void tetris_load_highscore(void) {
    char buf[12];
    unsigned int n = 0;
    int fd = open(HISCORE_FILE, 0);
    if (fd >= 0) {
        long r = read(fd, buf, sizeof(buf));
        if (r > 0) n = (unsigned int)r;
        close(fd);
    }
    int v = 0;
    for (unsigned int i = 0; i < n; i++) {
        if (buf[i] < '0' || buf[i] > '9') break;
        v = v * 10 + (buf[i] - '0');
    }
    high_score = v;
}

static void tetris_reset(void) {
    for (int y = 0; y < BOARD_H; y++)
        for (int x = 0; x < BOARD_W; x++)
            board[y][x] = 0;
    score = 0;
    game_over = 0;
    next_piece_id = (int)(tetris_rand() % 7);
    spawn_piece();
}

/* Stamps the current piece into the board, clears any completed rows,
 * scores, then spawns the next piece. Bottom-to-top scan with a same-
 * index recheck after a shift - verified by hand-trace to find every
 * cleared row exactly once, whether adjacent or not, with no skip and
 * no double count. */
static void lock_piece(void) {
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
            if (cur_shape.cells[y][x]) {
                int by = cur_y + y, bx = cur_x + x;
                if (by >= 0 && by < BOARD_H && bx >= 0 && bx < BOARD_W)
                    board[by][bx] = cur_piece_id + 1;
            }

    int cleared = 0;
    for (int y = BOARD_H - 1; y >= 0; y--) {
        int full = 1;
        for (int x = 0; x < BOARD_W; x++) if (!board[y][x]) { full = 0; break; }
        if (full) {
            for (int yy = y; yy > 0; yy--)
                for (int x = 0; x < BOARD_W; x++) board[yy][x] = board[yy - 1][x];
            for (int x = 0; x < BOARD_W; x++) board[0][x] = 0;
            cleared++;
            y++;   /* recheck the same index - everything above just shifted into it */
        }
    }
    if (cleared > 4) cleared = 4;   /* defensive - a single piece spans at most 4 rows */
    if (cleared) {
        static const int line_score[5] = {0, 40, 100, 300, 1200};
        score += line_score[cleared];
        if (score > high_score) { high_score = score; tetris_save_highscore(); }
    }
    spawn_piece();
}

/* if blocked and dy>0 specifically, the piece has landed - a blocked
 * pure horizontal move (dy==0) never locks. */
static void move_piece(int dx, int dy) {
    if (game_over) return;
    if (!collides(&cur_shape, cur_x + dx, cur_y + dy)) { cur_x += dx; cur_y += dy; }
    else if (dy > 0) lock_piece();
}

static void rotate_piece(void) {
    if (game_over) return;
    shape4_t r;
    shape_copy(&r, &cur_shape);
    rotate_cw(&r);
    if (!collides(&r, cur_x, cur_y)) shape_copy(&cur_shape, &r);
}

static void hard_drop(void) {
    if (game_over) return;
    while (!collides(&cur_shape, cur_x, cur_y + 1)) cur_y++;
    lock_piece();
}

/* Single key-dispatch funnel, mirrors axsnake.c's snake_set_dir() -
 * the game-over-restart check lives here ONCE; move_piece/rotate_piece/
 * hard_drop keep their own independent game_over guards too, since the
 * automatic gravity tick calls move_piece(0,1) directly, bypassing
 * this dispatcher entirely. */
static void tetris_handle_key(int c) {
    if (game_over) { tetris_reset(); return; }
    if (c == 'a')      move_piece(-1, 0);
    else if (c == 'd') move_piece(1, 0);
    else if (c == 's') move_piece(0, 1);
    else if (c == 'w') rotate_piece();
    else if (c == ' ') hard_drop();
}

#define TETRIS_PAD 8
#define TETRIS_BAR_H (2*16 + 6)
#define NEXT_GAP 16
#define NEXT_PANEL_W 88
#define PREVIEW_CELL 12

static void render_tetris(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int bx = win->x + 2 + TETRIS_PAD;
    unsigned int by = win->content_y + TETRIS_PAD;

    if (game_over) {
        /* window_draw_text_clipped(), not gfx_draw_text() - same
         * overflow-safety axsnake.c's own comment documents for its
         * "GAME OVER" string, doubly relevant here since this window
         * is narrower than AxSnake's. */
        window_draw_text_clipped(win, bx, by, "GAME OVER - key restarts", gfx_rgb(255, 80, 80));
    } else {
        gfx_draw_text(bx, by, "Score:", gfx_rgb(0, 220, 220));
        draw_uint(bx + 7*16, by, (unsigned int)score, gfx_rgb(255, 255, 0));
    }
    gfx_draw_text(bx, by + 16, "Best:", gfx_rgb(0, 220, 220));
    draw_uint(bx + 6*16, by + 16, (unsigned int)high_score, gfx_rgb(60, 220, 60));

    unsigned int grid_x0 = win->x + 2 + TETRIS_PAD;
    unsigned int grid_y0 = win->content_y + TETRIS_PAD + TETRIS_BAR_H;

    gfx_fill_rect(grid_x0, grid_y0, BOARD_W * CELL, BOARD_H * CELL, gfx_rgb(20, 20, 30));
    for (int y = 0; y < BOARD_H; y++)
        for (int x = 0; x < BOARD_W; x++)
            if (board[y][x])
                gfx_fill_rect(grid_x0 + (unsigned int)x*CELL + 1, grid_y0 + (unsigned int)y*CELL + 1,
                             CELL-2, CELL-2, piece_color(board[y][x] - 1));

    if (!game_over) {
        unsigned int color = piece_color(cur_piece_id);
        for (int y = 0; y < 4; y++)
            for (int x = 0; x < 4; x++)
                if (cur_shape.cells[y][x]) {
                    int bx2 = cur_x + x, by2 = cur_y + y;
                    if (by2 >= 0)
                        gfx_fill_rect(grid_x0 + (unsigned int)bx2*CELL + 1, grid_y0 + (unsigned int)by2*CELL + 1,
                                     CELL-2, CELL-2, color);
                }
    }

    unsigned int next_x = grid_x0 + BOARD_W*CELL + NEXT_GAP;
    gfx_draw_text(next_x, grid_y0, "Next:", gfx_rgb(0, 220, 220));
    unsigned int prev_y0 = grid_y0 + 20;
    unsigned int next_color = piece_color(next_piece_id);
    for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
            if (SHAPES[next_piece_id].cells[y][x])
                gfx_fill_rect(next_x + (unsigned int)x*PREVIEW_CELL + 1, prev_y0 + (unsigned int)y*PREVIEW_CELL + 1,
                             PREVIEW_CELL-2, PREVIEW_CELL-2, next_color);
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    window_t win;
    window_init(&win, 280, 60, 284, 410, 284, 410, gfx_rgb(30, 100, 220), gfx_rgb(10, 10, 15),
               "AxTetris");

    tetris_load_highscore();
    tetris_reset();
    render_tetris(&win);
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
                window_erase_desktop_bg((int)win.x, (int)win.y, (int)win.w, (int)win.h, screen_h);
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
            } else if (resizing && left) {
                unsigned int nw = (mx > win.x + WIN_RESIZE_SIZE) ? mx - win.x : win.min_w;
                unsigned int nh = (my > win.y + WIN_RESIZE_SIZE) ? my - win.y : win.min_h;
                window_resize(&win, nw, nh, screen_w, screen_h);
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxTetris");
                changed = 1;
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxTetris");
                changed = 1;
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            tetris_handle_key(c);
            changed = 1;
        }

        tick++;
        if (tick % TETRIS_TICK_N == 0) { move_piece(0, 1); changed = 1; }

        if (changed) render_tetris(&win);
        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
