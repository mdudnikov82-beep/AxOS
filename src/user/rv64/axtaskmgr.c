#include "syscall.h"
#include "window.h"

/* AxTaskMgr — graphical process manager, RISC-V only (see the
 * project_window_resize-adjacent research this session: x86's GUI kernel
 * gfx_shell.c has NO process concept at all — it's a separate kernel
 * binary that never links tasking.c, so its "windows" are just draw-
 * functions in one loop, not real OS processes. RISC-V is the opposite:
 * every app here (including this one) is already a real ELF process with
 * a real pid under proc_t procs[MAX_PROCS]). Lists every live process via
 * the new ps_info() syscall (existing ps()/SYS_PS only dumps text to the
 * UART, invisible to a framebuffer app), with per-row Kill and Nice
 * (-/+ priority) buttons.
 *
 * MAX_PROCS is a kernel-only constant (proc.h) with no user-visible
 * mirror - hardcoded here as TM_MAX_PROCS, matching the same tradeoff
 * axtodo.c already makes with TODO_MAX. Keep in sync if proc.h's
 * MAX_PROCS ever changes again. */

#define ROW_H 16
#define TM_MAX_PROCS 8

static ps_entry_t tm_rows[TM_MAX_PROCS];
static int        tm_count;
static int        tm_my_pid;
static int        tm_pending_kill_pid = -1;   /* -1 = none armed */

/* proc_t.state values (proc.h) have no user-visible enum - mirrored here
 * positionally, same tradeoff as TM_MAX_PROCS above. Order: UNUSED,
 * RUNNABLE, RUNNING, WAITING, ZOMBIE, SLEEPING, WAITING_PIPE. UNUSED never
 * appears (ps_info() returns 0, not an entry, for unused slots). */
static const char *tm_state_name(int state) {
    static const char *names[] = {"???", "RUN", "RUN", "WAI", "ZMB", "SLP", "PIP"};
    if (state < 0 || state > 6) return "???";
    return names[state];
}

static int tm_name_eq(const char *a, const char *b) {
    int i = 0;
    for (; a[i] && b[i]; i++) if (a[i] != b[i]) return 0;
    return a[i] == b[i];
}

static void tm_refresh(void) {
    tm_count = 0;
    for (unsigned int i = 0; i < TM_MAX_PROCS; i++) {
        if (ps_info(i, &tm_rows[tm_count])) tm_count++;
    }
}

static int tm_udigits(unsigned int v) {
    int n = 1;
    while (v >= 10) { v /= 10; n++; }
    return n;
}
static void tm_draw_uint(unsigned int x, unsigned int y, unsigned int v, unsigned int color) {
    char buf[11];
    int n = tm_udigits(v);
    buf[n] = '\0';
    for (int i = n - 1; i >= 0; i--) { buf[i] = (char)('0' + v % 10); v /= 10; }
    gfx_draw_text(x, y, buf, color);
}

#define TM_PAD        10
#define TM_GAP        ROW_H
#define TM_PID_W      (3*ROW_H)
#define TM_NAME_W     (13*ROW_H)
#define TM_STATE_W    (4*ROW_H)
#define TM_PRIO_MINUS_W ROW_H
#define TM_PRIO_NUM_W   (2*ROW_H)
#define TM_PRIO_PLUS_W  ROW_H
#define TM_KILL_W     (6*ROW_H)

/* Shared by render + click hit-testing so they can't drift, same
 * reasoning as AxFiles' files_layout()/AxTodo's todo_layout(). */
static void tm_layout(const window_t *win, unsigned int *list_y0,
                      unsigned int *pid_x, unsigned int *name_x, unsigned int *state_x,
                      unsigned int *prio_minus_x, unsigned int *prio_num_x, unsigned int *prio_plus_x,
                      unsigned int *kill_x) {
    *pid_x        = win->x + TM_PAD;
    *name_x       = *pid_x + TM_PID_W + TM_GAP;
    *state_x      = *name_x + TM_NAME_W + TM_GAP;
    *prio_minus_x = *state_x + TM_STATE_W + TM_GAP;
    *prio_num_x   = *prio_minus_x + TM_PRIO_MINUS_W + 8;
    *prio_plus_x  = *prio_num_x + TM_PRIO_NUM_W + 8;
    *kill_x       = win->x + win->w - TM_PAD - TM_KILL_W;
    *list_y0      = win->content_y + TM_PAD + ROW_H + 6;
}

static void render_taskmgr(const window_t *win) {
    tm_refresh();
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int list_y0, pid_x, name_x, state_x, prio_minus_x, prio_num_x, prio_plus_x, kill_x;
    tm_layout(win, &list_y0, &pid_x, &name_x, &state_x,
              &prio_minus_x, &prio_num_x, &prio_plus_x, &kill_x);

    unsigned int hdr_y = win->content_y + TM_PAD;
    gfx_draw_text(pid_x, hdr_y, "PID", gfx_rgb(0, 220, 220));
    window_draw_text_clipped(win, name_x, hdr_y, "NAME", gfx_rgb(0, 220, 220));
    gfx_draw_text(state_x, hdr_y, "ST", gfx_rgb(0, 220, 220));
    gfx_draw_text(prio_minus_x, hdr_y, "PRIO", gfx_rgb(0, 220, 220));
    gfx_draw_text(kill_x, hdr_y, "KILL", gfx_rgb(0, 220, 220));

    for (int i = 0; i < tm_count && i < TM_MAX_PROCS; i++) {
        unsigned int ry = list_y0 + (unsigned int)i * ROW_H;
        ps_entry_t *e = &tm_rows[i];
        unsigned int name_color = (e->pid == tm_my_pid) ? gfx_rgb(255, 255, 120) : gfx_rgb(255, 255, 255);

        tm_draw_uint(pid_x, ry, (unsigned int)e->pid, name_color);
        window_draw_text_clipped(win, name_x, ry, e->name, name_color);
        gfx_draw_text(state_x, ry, tm_state_name(e->state), gfx_rgb(180, 180, 180));

        gfx_draw_text(prio_minus_x, ry, "-", gfx_rgb(255, 255, 80));
        tm_draw_uint(prio_num_x, ry, (unsigned int)e->priority, gfx_rgb(255, 255, 80));
        gfx_draw_text(prio_plus_x, ry, "+", gfx_rgb(255, 255, 80));

        int protected_pid = (e->pid == 0 || e->pid == tm_my_pid);
        int confirming = (protected_pid && tm_pending_kill_pid == e->pid);
        gfx_draw_text(kill_x, ry, confirming ? "Sure?" : "Kill", confirming ? gfx_rgb(255, 60, 60) : gfx_rgb(255, 120, 120));
    }
}

/* Returns 1 if the click changed something worth re-rendering (rendering
 * happens unconditionally every frame regardless, same as AxClock - this
 * return value only matters for tm_pending_kill_pid bookkeeping below). */
static int handle_content_click(const window_t *win, unsigned int mx, unsigned int my) {
    unsigned int list_y0, pid_x, name_x, state_x, prio_minus_x, prio_num_x, prio_plus_x, kill_x;
    tm_layout(win, &list_y0, &pid_x, &name_x, &state_x,
              &prio_minus_x, &prio_num_x, &prio_plus_x, &kill_x);

    if (my < list_y0 || my >= list_y0 + (unsigned int)tm_count * ROW_H) {
        tm_pending_kill_pid = -1;
        return 0;
    }
    int row = (int)(my - list_y0) / ROW_H;
    if (row < 0 || row >= tm_count) { tm_pending_kill_pid = -1; return 0; }
    ps_entry_t *e = &tm_rows[row];

    /* tm_rows is a snapshot from the last render, up to one refresh
     * interval (200ms) stale. In that window the pid at this row could
     * have naturally exited and been reused by a completely unrelated
     * new process (pids ARE slot indices, freed slots get reclaimed
     * immediately - see proc_create()). Re-check by NAME, not just "is
     * the slot still in use", before acting on a click - otherwise a
     * mistimed click could kill/renice a process the user never
     * actually clicked on. An already-gone/mismatched target is treated
     * the same as "nothing to do", not an error. */
    ps_entry_t fresh;
    if (!ps_info((unsigned int)e->pid, &fresh) || !tm_name_eq(fresh.name, e->name)) {
        tm_pending_kill_pid = -1;
        return 1;
    }

    if (mx >= prio_minus_x && mx < prio_minus_x + TM_PRIO_MINUS_W) {
        tm_pending_kill_pid = -1;
        int p = e->priority - 1; if (p < 1) p = 1;
        set_priority(e->pid, p);
        return 1;
    }
    if (mx >= prio_plus_x && mx < prio_plus_x + TM_PRIO_PLUS_W) {
        tm_pending_kill_pid = -1;
        int p = e->priority + 1; if (p > 10) p = 10;
        set_priority(e->pid, p);
        return 1;
    }
    if (mx >= kill_x && mx < kill_x + TM_KILL_W) {
        int protected_pid = (e->pid == 0 || e->pid == tm_my_pid);
        if (protected_pid && tm_pending_kill_pid != e->pid) {
            /* First click on pid 0 (AxSH) or our own pid just arms the
             * confirm state - the kernel's SYS_KILL has no such guard
             * (it will happily zombie the shell or the caller), so the
             * UI supplies it instead. A second click on the SAME row
             * confirms. */
            tm_pending_kill_pid = e->pid;
            return 1;
        }
        tm_pending_kill_pid = -1;
        if (e->pid == tm_my_pid) {
            /* Self-kill via kill()+wait() is unsafe: neither syscall
             * calls schedule(), so procs[tm_my_pid] would sit marked
             * PROC_UNUSED while THIS code keeps right on executing.
             * Any timer-tick reschedule before our next syscall would
             * see the slot not RUNNING, switch to some other process,
             * and never save our register state anywhere - silently
             * losing this process's execution mid-flight (confirmed by
             * reading schedule()'s "only save state if state==RUNNING"
             * guard in proc.c). exit() is the only safe self-termination
             * path - it marks ZOMBIE AND calls schedule() before
             * returning, exactly like every other process's normal exit. */
            exit(0);
        }
        kill(e->pid);
        /* Reap synchronously - SYS_KILL already marks the target ZOMBIE,
         * so wait() on it returns immediately without blocking (see
         * SYS_WAIT's already-zombie fast path in syscall.c). Without
         * this, the slot stays a permanent zombie until something else
         * happens to wait() on it, eating one of only TM_MAX_PROCS
         * slots for good. */
        wait(e->pid);
        return 1;
    }

    tm_pending_kill_pid = -1;
    return 0;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);
    tm_my_pid = getpid();

    window_t win;
    /* min_w=590: KILL is right-anchored (win.w-dependent) while PID/NAME/
     * STATE/PRIO are left-anchored fixed offsets - same two-independently-
     * anchored-columns risk as AxFiles' SIZE-column bug found during the
     * resize feature; min_w is set so they can never collide (worked out
     * from tm_layout()'s column widths, plus margin). min_h=210 is the
     * true floor to show the header + all 8 possible rows without
     * clipping any of them - shrinking below either isn't allowed. */
    window_init(&win, 60, 60, 640, 280, 590, 210, gfx_rgb(150, 90, 220), gfx_rgb(15, 12, 20),
               "AxTaskMgr");

    render_taskmgr(&win);
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
                resizing = 1;
            } else if (!dragging && !resizing && left && !prev_left && focused && window_hit_titlebar(&win, mx, my)) {
                dragging = 1;
                drag_off_x = mx - win.x;
                drag_off_y = my - win.y;
            } else if (!dragging && !resizing && left && !prev_left && focused && mx >= win.x && mx < win.x + win.w &&
                      my >= win.content_y && my < win.content_y + win.content_h) {
                handle_content_click(&win, mx, my);
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
                window_redraw_chrome(&win, "AxTaskMgr");
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxTaskMgr");
            }
            prev_left = left;
        }

        /* Process list keeps changing on its own (other apps launched/
         * exited) even with no mouse input, so re-render unconditionally
         * every tick - same reasoning as AxClock's live uptime display. */
        render_taskmgr(&win);
        gfx_flush();
        sleep_ms(200);
    }

    return 0;
}
