#include "syscall.h"
#include "window.h"

/* AxTodo — checklist with disk persistence. Reuses three patterns
 * already established elsewhere in this codebase rather than inventing
 * anything new: a clickable row list (AxFiles), a single-line text-
 * input modal for "Add" (AxFiles' New/Rename prompt, collapsed to one
 * mode), and file persistence via the existing writefile()/open()/
 * read()/close() syscalls (AxNotepad/AxPaint/AxFiles all already use
 * these). Auto-saves on every mutation (add/toggle/delete) instead of
 * a manual Save/Load pair - a checklist's edits are small and frequent,
 * unlike a text document or a painting, so there's no "forgot to save"
 * failure mode worth designing around. */

#define ROW_H 16   /* gfx_draw_text's fixed 16px/char advance, see syscall.h */

#define TODO_MAX  10
#define TODO_TEXT_MAX 27   /* +1 NUL */
typedef struct {
    char text[TODO_TEXT_MAX + 1];
    int  done;
} todo_item_t;

static todo_item_t todos[TODO_MAX];
static int todo_count = 0;

/* Add-task modal text-input state - same shape as AxFiles'
 * files_input_mode/buf/len, collapsed to a single mode (no rename
 * variant needed here). */
static int  todo_input_mode;   /* 0=off, 1=adding */
static char todo_input_buf[TODO_TEXT_MAX + 1];
static int  todo_input_len;

#define TODO_FILE "TODO.TXT"
#define TODO_BUF_MAX 512   /* 10 tasks * (1 flag + 1 space + 27 text + 1 nl) = 300, generous */

static void todo_save(void) {
    static unsigned char buf[TODO_BUF_MAX];
    unsigned int p = 0;
    for (int i = 0; i < todo_count && p + TODO_TEXT_MAX + 3 < TODO_BUF_MAX; i++) {
        buf[p++] = todos[i].done ? '1' : '0';
        buf[p++] = ' ';
        for (int j = 0; todos[i].text[j] && j < TODO_TEXT_MAX; j++) buf[p++] = (unsigned char)todos[i].text[j];
        buf[p++] = '\n';
    }
    writefile(TODO_FILE, buf, p);
}

static void todo_load(void) {
    todo_count = 0;
    static unsigned char buf[TODO_BUF_MAX];
    int fd = open(TODO_FILE, 0);
    if (fd < 0) return;
    long n = read(fd, buf, TODO_BUF_MAX);
    close(fd);
    if (n <= 0) return;

    unsigned int i = 0;
    while (i < (unsigned int)n && todo_count < TODO_MAX) {
        if (i + 2 > (unsigned int)n) break;
        int done = (buf[i] == '1');
        i += 2;   /* flag + space */
        int j = 0;
        while (i < (unsigned int)n && buf[i] != '\n' && j < TODO_TEXT_MAX) {
            todos[todo_count].text[j++] = (char)buf[i++];
        }
        todos[todo_count].text[j] = '\0';
        todos[todo_count].done = done;
        todo_count++;
        while (i < (unsigned int)n && buf[i] != '\n') i++;   /* skip any overflow to the real newline */
        if (i < (unsigned int)n) i++;   /* skip the newline itself */
    }
}

static void todo_input_press(int c) {
    if (c < 0) return;
    if (c == '\n') {
        if (todo_input_len > 0 && todo_count < TODO_MAX) {
            int i = 0;
            for (; i < todo_input_len; i++) todos[todo_count].text[i] = todo_input_buf[i];
            todos[todo_count].text[i] = '\0';
            todos[todo_count].done = 0;
            todo_count++;
            todo_save();
        }
        todo_input_mode = 0;
        return;
    }
    if (c == '\b') {
        if (todo_input_len > 0) {
            todo_input_len--;
            todo_input_buf[todo_input_len] = '\0';
        }
        return;
    }
    if (todo_input_len < TODO_TEXT_MAX) {
        todo_input_buf[todo_input_len++] = (char)c;
        todo_input_buf[todo_input_len] = '\0';
    }
}

#define TODO_PAD 10

/* Shared by render + click hit-testing so they can't drift, same
 * reasoning as AxFiles' files_layout(). */
static void todo_layout(const window_t *win, unsigned int *list_y0,
                        unsigned int *del_x, unsigned int *add_y) {
    *list_y0 = win->content_y + TODO_PAD;
    *del_x   = win->x + win->w - TODO_PAD - 3*ROW_H;
    *add_y   = *list_y0 + TODO_MAX*ROW_H + 10;
}

static void render_todo_list(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int list_y0, del_x, add_y;
    todo_layout(win, &list_y0, &del_x, &add_y);

    if (todo_count == 0)
        gfx_draw_text(win->x + TODO_PAD, list_y0, "(no tasks yet)", gfx_rgb(160, 160, 160));

    for (int i = 0; i < todo_count; i++) {
        unsigned int ry = list_y0 + (unsigned int)i * ROW_H;
        const char *box = todos[i].done ? "[x] " : "[ ] ";
        unsigned int color = todos[i].done ? gfx_rgb(120, 120, 120) : gfx_rgb(255, 255, 255);
        gfx_draw_text(win->x + TODO_PAD, ry, box, color);
        window_draw_text_clipped(win, win->x + TODO_PAD + 4*ROW_H, ry, todos[i].text, color);
        gfx_draw_text(del_x, ry, "[x]", gfx_rgb(255, 80, 80));
    }

    gfx_fill_rect(win->x + TODO_PAD, add_y - 6, win->w - 2*TODO_PAD, 1, gfx_rgb(120, 120, 120));
    gfx_draw_text(win->x + TODO_PAD, add_y, "[ Add ]", gfx_rgb(0, 255, 0));
}

/* Modal Add-task text-entry prompt - preempts the list entirely while
 * active, same shape as AxFiles' render_files_input(). */
static void render_todo_input(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int x = win->x + TODO_PAD;
    unsigned int y = win->content_y + TODO_PAD;
    window_draw_text_clipped(win, x, y, "New task:", gfx_rgb(0, 220, 220));

    unsigned int input_y = y + 2*ROW_H;
    gfx_draw_text(x, input_y, todo_input_buf, gfx_rgb(255, 255, 255));
    gfx_fill_rect(x + (unsigned int)todo_input_len*ROW_H, input_y, ROW_H/2, ROW_H, gfx_rgb(255, 255, 255));

    unsigned int btn_y = input_y + 2*ROW_H;
    gfx_draw_text(x, btn_y, "[OK]", gfx_rgb(0, 255, 0));
    gfx_draw_text(x + 5*ROW_H, btn_y, "[Cancel]", gfx_rgb(255, 80, 80));
}

static void render_todo(const window_t *win) {
    if (todo_input_mode) render_todo_input(win);
    else                 render_todo_list(win);
}

static int in_content(const window_t *win, unsigned int mx, unsigned int my) {
    return mx >= win->x && mx < win->x + win->w &&
           my >= win->content_y && my < win->content_y + win->content_h;
}

/* Returns 1 if the click changed something worth re-rendering. */
static int handle_content_click(const window_t *win, unsigned int mx, unsigned int my) {
    if (todo_input_mode) {
        unsigned int x = win->x + TODO_PAD;
        unsigned int input_y = win->content_y + TODO_PAD + 2*ROW_H;
        unsigned int btn_y = input_y + 2*ROW_H;
        if (my >= btn_y && my < btn_y + ROW_H) {
            if (mx >= x && mx < x + 4*ROW_H) {
                todo_input_press('\n');
                return 1;
            }
            if (mx >= x + 5*ROW_H && mx < x + 5*ROW_H + 8*ROW_H) {
                todo_input_mode = 0;
                return 1;
            }
        }
        return 0;
    }

    unsigned int list_y0, del_x, add_y;
    todo_layout(win, &list_y0, &del_x, &add_y);

    if (my >= add_y && my < add_y + ROW_H && mx >= win->x + TODO_PAD && mx < win->x + TODO_PAD + 7*ROW_H) {
        todo_input_mode = 1;
        todo_input_len = 0;
        todo_input_buf[0] = '\0';
        return 1;
    }

    if (my >= list_y0 && my < list_y0 + (unsigned int)todo_count*ROW_H) {
        int row = (int)(my - list_y0) / ROW_H;
        if (row < 0 || row >= todo_count) return 0;
        if (mx >= del_x && mx < del_x + 3*ROW_H) {
            /* Manual field copy, not a struct assignment - GCC lowers
             * whole-struct assignment to a memcpy() call that doesn't
             * exist in this freestanding -nostdlib build (hit this
             * exact class of landmine before, see the memory note on
             * aggregate-init patterns silently pulling in libc calls). */
            for (int i = row; i < todo_count - 1; i++) {
                int k = 0;
                for (; todos[i+1].text[k] && k < TODO_TEXT_MAX; k++) todos[i].text[k] = todos[i+1].text[k];
                todos[i].text[k] = '\0';
                todos[i].done = todos[i+1].done;
            }
            todo_count--;
            todo_save();
            return 1;
        }
        if (mx >= win->x + TODO_PAD && mx < del_x) {
            todos[row].done = !todos[row].done;
            todo_save();
            return 1;
        }
    }
    return 0;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    todo_load();

    window_t win;
    window_init(&win, 260, 130, 480, 260, 300, 235, gfx_rgb(220, 180, 0), gfx_rgb(15, 15, 20),
               "AxTodo");

    render_todo(&win);
    gfx_flush();

    int dragging = 0, resizing = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;

    for (;;) {
        unsigned int mx = 0, my = 0, buttons = 0, focused = 1;
        if (mouse_state(&mx, &my, &buttons, &focused, 0)) {
            int left = buttons & 1;
            if (!dragging && !resizing && left && !prev_left && focused && window_hit_close(&win, mx, my)) {
                window_erase_desktop_bg((int)win.x, (int)win.y, (int)win.w, (int)win.h, screen_h);
                gfx_flush();
                exit(0);
            } else if (!dragging && !resizing && left && !prev_left && focused && window_hit_resize(&win, mx, my)) {
                /* Must be checked before in_content()/handle_content_click()
                 * below - the delete glyph on the bottom row can
                 * geometrically overlap the resize grip's corner. */
                resizing = 1;
            } else if (!dragging && !resizing && left && !prev_left && focused && window_hit_titlebar(&win, mx, my)) {
                dragging = 1;
                drag_off_x = mx - win.x;
                drag_off_y = my - win.y;
            } else if (!dragging && !resizing && left && !prev_left && focused && in_content(&win, mx, my)) {
                if (handle_content_click(&win, mx, my)) render_todo(&win);
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
                window_redraw_chrome(&win, "AxTodo");
                render_todo(&win);
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxTodo");
                render_todo(&win);
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (todo_input_mode) {
                todo_input_press(c);
                render_todo(&win);
            }
        }

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
