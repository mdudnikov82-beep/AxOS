#include "syscall.h"
#include "window.h"

/* AxFiles — file manager, ported from x86 gfx_shell.c's AxFiles window
 * (see that file's own "Files (AxFiles) state" comment block for the
 * original design this mirrors almost line-for-line). Lists files,
 * previews raw content as text, can delete a file (with a confirm
 * step), and can create a new (empty) file or rename an existing one
 * via a small modal text-input prompt (kbd_getc() drain loop below -
 * this file's first use of keyboard input, mirrors axnotepad.c's
 * np_press() shape collapsed to a single line). Rename is synthesized
 * as load-old+write-new+delete-old since there's no rename syscall.
 * Unlike the x86 port, no new disk driver work was needed here - RISC-V
 * userspace already has real readdir()/open()/read()/close()/unlink()
 * syscalls (same ones axsh.c's `ls`/`cat`/`rm` already use, and unlike
 * x86 there's no read-only lock to unset either). The only genuinely
 * new code is the UI: window.h's window_println() doesn't scroll or
 * wrap text and gives no per-row Y control for click hit-testing, so
 * the list/preview renderers here are hand-rolled via gfx_fill_rect()/
 * gfx_draw_text() directly, same as x86's own render_files_list()/
 * render_files_preview(). */

#define ROW_H 16   /* gfx_draw_text's fixed 16px/char advance, see syscall.h */

#define FILES_MAX 64   /* matches tools/make_fat12_rv64.py ROOT_ENTRIES=64 */
static char files_names[FILES_MAX][13];
static unsigned int files_sizes[FILES_MAX];
static int files_count;
static int files_scroll;
static int files_preview_mode;   /* 0=list, 1=preview */
static int files_confirm_delete; /* showing "Delete FOO.BIN? [Yes] [No]" for files_preview_name */

/* New/Rename modal text-input state - files_input_mode: 0=off, 1=new,
 * 2=rename (files_rename_from holds the file being replaced). */
static int  files_input_mode;
static char files_input_buf[13];
static int  files_input_len;
static char files_rename_from[13];

#define FILES_PREVIEW_MAX 4096   /* well under sys_open's own 32KB (8-page) cap */
static char files_preview_name[13];
static unsigned char files_preview_buf[FILES_PREVIEW_MAX];
static unsigned int files_preview_len;
static int files_preview_truncated;
static int files_preview_scroll;

/* Dedicated scratch space for the rename load-old/write-new round trip
 * - sys_open() itself hard-caps whole-file reads at 32KB, a platform
 * ceiling nothing can raise, so that's exactly the right size here
 * (unlike x86, a bigger buffer wouldn't help). Reusing the smaller
 * preview buffer would silently truncate any renamed file over 4KB. */
#define FILES_RENAME_MAX 32768
static unsigned char files_rename_buf[FILES_RENAME_MAX];

static void files_scan(void) {
    files_count = 0;
    while (files_count < FILES_MAX &&
           readdir((unsigned int)files_count, files_names[files_count], &files_sizes[files_count]))
        files_count++;
}

/* Loads files_names[idx] into the preview buffer and flips into
 * preview mode. sys_open() itself already caps whole-file loads at
 * 32KB; comparing bytes actually read against the cached files_sizes[]
 * catches truncation from either that cap or FILES_PREVIEW_MAX,
 * whichever is smaller - same "(truncated)" marker either way. */
static void files_open_preview(int idx) {
    int i = 0;
    for (; files_names[idx][i] && i < 12; i++) files_preview_name[i] = files_names[idx][i];
    files_preview_name[i] = '\0';

    files_preview_len = 0;
    int fd = open(files_names[idx], 0);
    if (fd >= 0) {
        long n = read(fd, files_preview_buf, FILES_PREVIEW_MAX);
        if (n > 0) files_preview_len = (unsigned int)n;
        close(fd);
    }
    files_preview_truncated = (files_preview_len < files_sizes[idx]);
    files_preview_scroll = 0;
    files_preview_mode = 1;
}

/* Confirms the pending New/Rename action (files_input_mode already
 * validated non-empty by the caller), then always rescans so the
 * change shows up immediately and drops the modal. */
static void files_input_confirm(void) {
    if (files_input_mode == 1) {
        writefile(files_input_buf, files_rename_buf, 0);
    } else if (files_input_mode == 2) {
        long n = 0;
        int fd = open(files_rename_from, 0);
        if (fd >= 0) {
            n = read(fd, files_rename_buf, FILES_RENAME_MAX);
            if (n < 0) n = 0;
            close(fd);
        }
        writefile(files_input_buf, files_rename_buf, n);
        unlink(files_rename_from);
        files_preview_mode = 0;
    }
    files_scan();
    files_input_mode = 0;
}

static void files_input_press(int c) {
    if (c < 0) return;
    if (c == '\n') {
        if (files_input_len > 0) files_input_confirm();
        return;
    }
    if (c == '\b') {
        if (files_input_len > 0) {
            files_input_len--;
            files_input_buf[files_input_len] = '\0';
        }
        return;
    }
    if (files_input_len < 12) {
        files_input_buf[files_input_len++] = (char)c;
        files_input_buf[files_input_len] = '\0';
    }
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
static void draw_uint_right(unsigned int x_right, unsigned int y, unsigned int v, unsigned int color) {
    unsigned int w = (unsigned int)udigits(v) * ROW_H;
    draw_uint(x_right - w, y, v, color);
}

#define FILES_PAD   10
#define FILES_BTN_W (3*ROW_H)   /* "[^]"/"[v]" */

/* List-mode row/button geometry - shared by render_files_list() and
 * handle_content_click() so hit-testing can't drift from what's
 * actually drawn (same reasoning as x86's files_layout()). */
static void files_layout(const window_t *win,
                          unsigned int *list_y0, int *visible_rows,
                          unsigned int *up_x, unsigned int *down_x,
                          unsigned int *btn_y, unsigned int *size_right,
                          unsigned int *new_x) {
    unsigned int header_y = win->content_y + FILES_PAD;
    *down_x = win->x + win->w - FILES_PAD - FILES_BTN_W;
    *up_x   = *down_x - FILES_BTN_W - 8;
    *btn_y  = header_y;
    *size_right = *up_x - 16;
    *list_y0 = header_y + ROW_H + 6;
    int avail = (int)(win->content_y + win->content_h) - (int)FILES_PAD - (int)*list_y0;
    *visible_rows = (avail > 0) ? avail / ROW_H : 0;
    *new_x = win->x + FILES_PAD + 6*ROW_H;   /* right after the "NAME" header label */
}

static void render_files_list(const window_t *win) {
    unsigned int x = win->x + FILES_PAD;
    unsigned int y = win->content_y + FILES_PAD;

    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int list_y0, up_x, down_x, btn_y, size_right, new_x;
    int visible_rows;
    files_layout(win, &list_y0, &visible_rows, &up_x, &down_x, &btn_y, &size_right, &new_x);

    gfx_draw_text(x, y, "NAME", gfx_rgb(0, 220, 220));
    gfx_draw_text(new_x, y, "[New]", gfx_rgb(0, 255, 0));
    gfx_draw_text(size_right - 4*ROW_H, y, "SIZE", gfx_rgb(0, 220, 220));
    gfx_draw_text(up_x,   btn_y, "[^]", gfx_rgb(255, 255, 255));
    gfx_draw_text(down_x, btn_y, "[v]", gfx_rgb(255, 255, 255));
    gfx_fill_rect(x, list_y0 - 4, win->w - 2*FILES_PAD, 1, gfx_rgb(120, 120, 120));

    if (files_count == 0) { gfx_draw_text(x, list_y0, "(no files)", gfx_rgb(160, 160, 160)); return; }

    int max_scroll = files_count - visible_rows;
    if (max_scroll < 0) max_scroll = 0;
    if (files_scroll > max_scroll) files_scroll = max_scroll;
    if (files_scroll < 0) files_scroll = 0;

    for (int i = 0; i < visible_rows && files_scroll + i < files_count; i++) {
        int idx = files_scroll + i;
        unsigned int ry = list_y0 + (unsigned int)i * ROW_H;
        gfx_draw_text(x, ry, files_names[idx], gfx_rgb(0, 255, 120));
        draw_uint_right(size_right, ry, files_sizes[idx], gfx_rgb(180, 180, 180));
    }
}

/* Preview-mode header/text-area geometry - shared with the click
 * handler's "[< Back]" hit-test, same reasoning as files_layout(). */
static void files_preview_layout(const window_t *win,
                                  unsigned int *back_x, unsigned int *back_y,
                                  unsigned int *text_y0, int *visible_rows, int *max_cols,
                                  unsigned int *rename_x) {
    *back_x = win->x + FILES_PAD;
    *back_y = win->content_y + FILES_PAD;
    *text_y0 = *back_y + ROW_H + 6;
    int avail = (int)(win->content_y + win->content_h) - (int)FILES_PAD - (int)*text_y0;
    *visible_rows = (avail > 0) ? avail / ROW_H : 0;
    *max_cols = (int)(win->w - 2*FILES_PAD) / ROW_H;
    if (*max_cols < 1) *max_cols = 1;
    /* "[Rename]" (8 chars) sits just left of "[Delete]" (8 chars),
     * both right-aligned - well clear of the filename label drawn at
     * back_x+9*ROW_H for any realistic 8.3 filename length. */
    *rename_x = (win->x + win->w - FILES_PAD - 8*ROW_H) - 9*ROW_H;
}

static void render_files_preview(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int back_x, back_y, text_y0, rename_x;
    int visible_rows, max_cols;
    files_preview_layout(win, &back_x, &back_y, &text_y0, &visible_rows, &max_cols, &rename_x);

    gfx_draw_text(back_x, back_y, "[< Back]", gfx_rgb(255, 255, 0));
    gfx_draw_text(back_x + 9*ROW_H, back_y, files_preview_name, gfx_rgb(255, 255, 255));
    gfx_draw_text(rename_x, back_y, "[Rename]", gfx_rgb(0, 220, 220));
    /* "[Delete]" is the same 8-char width as "[< Back]" - right-align
     * it in the same header row, same reasoning files_layout() already
     * uses for the list view's [^]/[v] buttons. */
    gfx_draw_text(win->x + win->w - FILES_PAD - 8*ROW_H, back_y, "[Delete]", gfx_rgb(255, 80, 80));
    gfx_fill_rect(win->x + FILES_PAD, text_y0 - 4, win->w - 2*FILES_PAD, 1, gfx_rgb(120, 120, 120));

    /* Walk the raw buffer once per render (only called on real state
     * changes - see the main loop below), breaking on '\n' and
     * hard-wrapping long runs at max_cols, skipping files_preview_scroll
     * lines. Same algorithm as x86's render_files_preview(). */
    int line = 0, drawn = 0, col = 0;
    char linebuf[128];
    if (max_cols > 127) max_cols = 127;
    unsigned int i = 0;
    while (i <= files_preview_len) {
        int is_end = (i == files_preview_len);
        unsigned char c = is_end ? 0 : files_preview_buf[i];
        int is_newline = (!is_end) && (c == '\n');
        int is_wrap    = (!is_end) && (!is_newline) && (col >= max_cols);

        if (is_wrap) {
            linebuf[col] = '\0';
            if (line >= files_preview_scroll && drawn < visible_rows) {
                gfx_draw_text(win->x + FILES_PAD, text_y0 + (unsigned int)drawn*ROW_H, linebuf, gfx_rgb(0, 255, 120));
                drawn++;
            }
            line++; col = 0;
            continue;   /* i unchanged - byte i starts the fresh line */
        }

        if (is_newline || is_end) {
            linebuf[col] = '\0';
            if (line >= files_preview_scroll && drawn < visible_rows) {
                gfx_draw_text(win->x + FILES_PAD, text_y0 + (unsigned int)drawn*ROW_H, linebuf, gfx_rgb(0, 255, 120));
                drawn++;
            }
            line++; col = 0; i++;
            if (is_end) break;
            continue;
        }

        linebuf[col++] = (char)c;
        i++;
    }
    if (files_preview_truncated && drawn < visible_rows)
        gfx_draw_text(win->x + FILES_PAD, text_y0 + (unsigned int)drawn*ROW_H, "(truncated)", gfx_rgb(255, 255, 0));
}

/* Delete-confirm geometry - shared with handle_content_click()'s
 * [Yes]/[No] hit-test, same reasoning as files_layout()/
 * files_preview_layout(). */
static void files_confirm_layout(const window_t *win, unsigned int *yes_x,
                                 unsigned int *no_x, unsigned int *btn_y) {
    *yes_x = win->x + FILES_PAD;
    *no_x  = *yes_x + 6*ROW_H + 16;
    *btn_y = win->content_y + FILES_PAD + ROW_H + 10;
}

static void render_files_confirm_delete(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int yes_x, no_x, btn_y;
    files_confirm_layout(win, &yes_x, &no_x, &btn_y);

    char msg[13 + 10];
    int p = 0;
    const char *pre = "Delete ";
    while (pre[p]) { msg[p] = pre[p]; p++; }
    for (int i = 0; files_preview_name[i] && p < (int)sizeof(msg) - 2; i++) msg[p++] = files_preview_name[i];
    msg[p++] = '?';
    msg[p] = '\0';
    gfx_draw_text(win->x + FILES_PAD, win->content_y + FILES_PAD, msg, gfx_rgb(255, 255, 0));

    gfx_draw_text(yes_x, btn_y, "[Yes]", gfx_rgb(255, 80, 80));
    gfx_draw_text(no_x,  btn_y, "[No]",  gfx_rgb(255, 255, 255));
}

/* Modal New/Rename text-entry prompt - preempts list/preview/confirm-
 * delete entirely while active. window_draw_text_clipped() (not
 * gfx_draw_text()) for the prompt line - it's the longest string here
 * and this exact overflow-past-the-window-edge bug already bit
 * axsnake.c's "GAME OVER" message once this session. */
static void render_files_input(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int x = win->x + FILES_PAD;
    unsigned int y = win->content_y + FILES_PAD;

    if (files_input_mode == 1) {
        window_draw_text_clipped(win, x, y, "New file name:", gfx_rgb(0, 220, 220));
    } else {
        char msg[13 + 16];
        int p = 0;
        const char *pre = "Rename ";
        while (pre[p]) { msg[p] = pre[p]; p++; }
        for (int i = 0; files_rename_from[i] && p < (int)sizeof(msg) - 8; i++) msg[p++] = files_rename_from[i];
        const char *suf = " to:";
        for (int i = 0; suf[i]; i++) msg[p++] = suf[i];
        msg[p] = '\0';
        window_draw_text_clipped(win, x, y, msg, gfx_rgb(0, 220, 220));
    }

    unsigned int input_y = y + 2*ROW_H;
    gfx_draw_text(x, input_y, files_input_buf, gfx_rgb(255, 255, 255));
    gfx_fill_rect(x + (unsigned int)files_input_len*ROW_H, input_y, ROW_H/2, ROW_H, gfx_rgb(255, 255, 255));

    unsigned int btn_y = input_y + 2*ROW_H;
    gfx_draw_text(x, btn_y, "[OK]", gfx_rgb(0, 255, 0));
    gfx_draw_text(x + 5*ROW_H, btn_y, "[Cancel]", gfx_rgb(255, 80, 80));
}

static void render_files(const window_t *win) {
    if (files_input_mode)         render_files_input(win);
    else if (files_confirm_delete) render_files_confirm_delete(win);
    else if (files_preview_mode)  render_files_preview(win);
    else                          render_files_list(win);
}

/* 1 if (mx,my) falls inside this window's own content area - each
 * RISC-V GUI process only ever reacts to clicks within its OWN rect
 * (no shared window manager to arbitrate who a click belongs to, same
 * model axterm.c/axabout.c already use for titlebar/close). */
static int in_content(const window_t *win, unsigned int mx, unsigned int my) {
    return mx >= win->x && mx < win->x + win->w &&
           my >= win->content_y && my < win->content_y + win->content_h;
}

/* Returns 1 if the click changed something worth re-rendering. */
static int handle_content_click(const window_t *win, unsigned int mx, unsigned int my) {
    if (files_input_mode) {
        unsigned int x = win->x + FILES_PAD;
        unsigned int input_y = win->content_y + FILES_PAD + 2*ROW_H;
        unsigned int btn_y = input_y + 2*ROW_H;
        if (my >= btn_y && my < btn_y + ROW_H) {
            if (mx >= x && mx < x + 4*ROW_H) {
                if (files_input_len > 0) files_input_confirm();
                return 1;
            }
            if (mx >= x + 5*ROW_H && mx < x + 5*ROW_H + 8*ROW_H) {
                files_input_mode = 0;
                return 1;
            }
        }
        return 0;
    }

    if (files_confirm_delete) {
        unsigned int yes_x, no_x, btn_y;
        files_confirm_layout(win, &yes_x, &no_x, &btn_y);
        if (my >= btn_y && my < btn_y + ROW_H) {
            if (mx >= yes_x && mx < yes_x + 5*ROW_H) {
                unlink(files_preview_name);
                files_scan();   /* refresh from disk - the deleted file must actually disappear */
                files_confirm_delete = 0;
                files_preview_mode = 0;
                return 1;
            }
            if (mx >= no_x && mx < no_x + 4*ROW_H) {
                files_confirm_delete = 0;
                return 1;
            }
        }
        return 0;
    }

    if (files_preview_mode) {
        unsigned int back_x, back_y, text_y0, rename_x;
        int visible_rows, max_cols;
        files_preview_layout(win, &back_x, &back_y, &text_y0, &visible_rows, &max_cols, &rename_x);
        if (mx >= back_x && mx < back_x + 8*ROW_H &&
            my >= back_y && my < back_y + ROW_H) {
            files_preview_mode = 0;
            return 1;
        }
        unsigned int del_x = win->x + win->w - FILES_PAD - 8*ROW_H;
        if (mx >= del_x && mx < del_x + 8*ROW_H &&
            my >= back_y && my < back_y + ROW_H) {
            files_confirm_delete = 1;
            return 1;
        }
        if (mx >= rename_x && mx < rename_x + 8*ROW_H &&
            my >= back_y && my < back_y + ROW_H) {
            int i = 0;
            for (; files_preview_name[i] && i < 12; i++) files_rename_from[i] = files_preview_name[i];
            files_rename_from[i] = '\0';
            files_input_mode = 2;
            files_input_len = 0;
            files_input_buf[0] = '\0';
            return 1;
        }
        return 0;
    }

    unsigned int list_y0, up_x, down_x, btn_y, size_right, new_x;
    int visible_rows;
    files_layout(win, &list_y0, &visible_rows, &up_x, &down_x, &btn_y, &size_right, &new_x);

    if (my >= btn_y && my < btn_y + ROW_H) {
        if (mx >= new_x && mx < new_x + 5*ROW_H) {
            files_input_mode = 1;
            files_input_len = 0;
            files_input_buf[0] = '\0';
            return 1;
        }
        if (files_count > 0) {
            if (mx >= up_x && mx < up_x + FILES_BTN_W) {
                files_scroll -= visible_rows;
                if (files_scroll < 0) files_scroll = 0;
                return 1;
            }
            if (mx >= down_x && mx < down_x + FILES_BTN_W) {
                files_scroll += visible_rows;   /* clamped in render_files_list() */
                return 1;
            }
        }
    }

    if (files_count == 0) return 0;

    if (my >= list_y0) {
        int row = (int)(my - list_y0) / ROW_H;
        int idx = files_scroll + row;
        if (row < visible_rows && idx < files_count) { files_open_preview(idx); return 1; }
    }
    return 0;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    files_scan();

    window_t win;
    window_init(&win, 100, 90, 600, 430, gfx_rgb(80, 200, 120), gfx_rgb(10, 25, 15),
               "AxFiles");

    render_files(&win);
    gfx_flush();

    int dragging = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;

    for (;;) {
        unsigned int mx = 0, my = 0, buttons = 0, focused = 1;
        if (mouse_state(&mx, &my, &buttons, &focused)) {
            int left = buttons & 1;
            if (!dragging && left && !prev_left && focused && window_hit_close(&win, mx, my)) {
                /* Nothing else ever erases a closed window's footprint
                 * (no compositor) - see axterm.c's identical fix. */
                window_erase_desktop_bg((int)win.x, (int)win.y, (int)win.w, (int)win.h, screen_h);
                gfx_flush();
                exit(0);
            } else if (!dragging && left && !prev_left && focused && window_hit_titlebar(&win, mx, my)) {
                dragging = 1;
                drag_off_x = mx - win.x;
                drag_off_y = my - win.y;
            } else if (!dragging && left && !prev_left && focused && in_content(&win, mx, my)) {
                if (handle_content_click(&win, mx, my)) render_files(&win);
            } else if (dragging && left) {
                unsigned int nx = (mx > drag_off_x) ? mx - drag_off_x : 0;
                unsigned int ny = (my > drag_off_y) ? my - drag_off_y : 0;
                if (nx + win.w > screen_w) nx = screen_w - win.w;
                if (ny + win.h > screen_h) ny = screen_h - win.h;
                window_move(&win, nx, ny, screen_h);
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxFiles");
                /* Unlike axterm/axabout, AxFiles keeps its real state
                 * (file list / preview buffer) in static arrays the
                 * whole time - actually restoring content here is just
                 * correct, not extra work. */
                render_files(&win);
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (files_input_mode) {
                files_input_press(c);
                render_files(&win);
            }
        }

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
