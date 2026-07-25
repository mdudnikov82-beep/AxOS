#include "syscall.h"
#include "window.h"

/* AxClock — clock + alarm. RISC-V has NO real-time-clock hardware at
 * all (confirmed: no CMOS, no goldfish-rtc, no virtio-rtc anywhere in
 * src/arch/riscv64 — only the monotonic `time` CSR used for
 * scheduling), so unlike x86's mirror of this file (which shows a real
 * wall clock via CMOS RTC), this shows uptime — seconds since boot,
 * from the existing gettime() syscall (10 MHz CLINT timebase, see
 * counter.c/axterm.c's own use of the same /10000000 conversion). Same
 * "clock" widget shape, different underlying meaning - matches how
 * this whole session has already handled other platform asymmetries
 * (e.g. AxCalc's allocator gap).
 *
 * No audio hardware exists on RISC-V either (confirmed via grep - no
 * virtio-sound, no PWM buzzer), so the alarm here is visual-only
 * (flashing state button), unlike x86's PC-speaker tone.
 *
 * Deliberate simplification: the alarm compares only hour:minute, no
 * day-wraparound - arming it for a time earlier than the current
 * displayed time fires immediately rather than waiting for "tomorrow".
 * Fine for a hobby-OS alarm tested a minute or two ahead; full
 * calendar arithmetic is out of scope. */

#define ROW_H 16

static int clock_alarm_h = 0;
static int clock_alarm_m = 0;
static int clock_armed = 0;
static int clock_fired = 0;
static int clock_flash_tick = 0;

static void clock_get_uptime(int *h, int *m, int *s) {
    long secs = gettime() / 10000000;
    *h = (int)(secs / 3600);
    *m = (int)((secs / 60) % 60);
    *s = (int)(secs % 60);
}

static void clock_check_alarm(void) {
    if (!clock_armed || clock_fired) return;
    int h, m, s;
    clock_get_uptime(&h, &m, &s);
    if (h > clock_alarm_h || (h == clock_alarm_h && m >= clock_alarm_m)) {
        clock_fired = 1;
    }
}

#define CLOCK_PAD          8
#define CLOCK_SPIN_SZ      32
#define CLOCK_BTN_H        36
#define CLOCK_UPTIME_LBL_Y_OFF (CLOCK_PAD + ROW_H + 6)
#define CLOCK_ALARM_LBL_Y_OFF  (CLOCK_UPTIME_LBL_Y_OFF + ROW_H + 14)
#define CLOCK_SPIN_Y_OFF   (CLOCK_ALARM_LBL_Y_OFF + ROW_H + 8)
#define CLOCK_BTN_Y_OFF    (CLOCK_SPIN_Y_OFF + CLOCK_SPIN_SZ + 14)
#define CLOCK_HMINUS_X_OFF CLOCK_PAD
#define CLOCK_NUMH_X_OFF   (CLOCK_HMINUS_X_OFF + CLOCK_SPIN_SZ + 6)
#define CLOCK_HPLUS_X_OFF  (CLOCK_NUMH_X_OFF + 2*ROW_H + 6)
#define CLOCK_MMINUS_X_OFF (CLOCK_HPLUS_X_OFF + CLOCK_SPIN_SZ + 20)
#define CLOCK_NUMM_X_OFF   (CLOCK_MMINUS_X_OFF + CLOCK_SPIN_SZ + 6)
#define CLOCK_MPLUS_X_OFF  (CLOCK_NUMM_X_OFF + 2*ROW_H + 6)

static void render_clock(const window_t *win) {
    clock_check_alarm();
    clock_flash_tick++;

    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int cx0 = win->x + 2;
    unsigned int cy0 = win->content_y;

    int h, m, s;
    clock_get_uptime(&h, &m, &s);
    char tbuf[9];
    tbuf[0]=(char)('0'+h/10); tbuf[1]=(char)('0'+h%10); tbuf[2]=':';
    tbuf[3]=(char)('0'+m/10); tbuf[4]=(char)('0'+m%10); tbuf[5]=':';
    tbuf[6]=(char)('0'+s/10); tbuf[7]=(char)('0'+s%10); tbuf[8]=0;
    gfx_draw_text(cx0 + CLOCK_PAD, cy0 + CLOCK_PAD, tbuf, gfx_rgb(80, 255, 80));
    window_draw_text_clipped(win, cx0 + CLOCK_PAD, cy0 + CLOCK_UPTIME_LBL_Y_OFF,
                             "Uptime", gfx_rgb(170, 170, 170));

    window_draw_text_clipped(win, cx0 + CLOCK_PAD, cy0 + CLOCK_ALARM_LBL_Y_OFF,
                             "Alarm:", gfx_rgb(255, 255, 255));

    unsigned int spin_y = cy0 + CLOCK_SPIN_Y_OFF;
    gfx_fill_rect(cx0+CLOCK_HMINUS_X_OFF, spin_y, CLOCK_SPIN_SZ, CLOCK_SPIN_SZ, gfx_rgb(0,0,170));
    gfx_draw_text(cx0+CLOCK_HMINUS_X_OFF+CLOCK_SPIN_SZ/2-ROW_H/2, spin_y+CLOCK_SPIN_SZ/2-ROW_H/2, "-", gfx_rgb(255,255,255));
    char hb[3]; hb[0]=(char)('0'+clock_alarm_h/10); hb[1]=(char)('0'+clock_alarm_h%10); hb[2]=0;
    gfx_draw_text(cx0+CLOCK_NUMH_X_OFF, spin_y+CLOCK_SPIN_SZ/2-ROW_H/2, hb, gfx_rgb(255,255,80));
    gfx_fill_rect(cx0+CLOCK_HPLUS_X_OFF, spin_y, CLOCK_SPIN_SZ, CLOCK_SPIN_SZ, gfx_rgb(0,0,170));
    gfx_draw_text(cx0+CLOCK_HPLUS_X_OFF+CLOCK_SPIN_SZ/2-ROW_H/2, spin_y+CLOCK_SPIN_SZ/2-ROW_H/2, "+", gfx_rgb(255,255,255));

    gfx_fill_rect(cx0+CLOCK_MMINUS_X_OFF, spin_y, CLOCK_SPIN_SZ, CLOCK_SPIN_SZ, gfx_rgb(0,0,170));
    gfx_draw_text(cx0+CLOCK_MMINUS_X_OFF+CLOCK_SPIN_SZ/2-ROW_H/2, spin_y+CLOCK_SPIN_SZ/2-ROW_H/2, "-", gfx_rgb(255,255,255));
    char mb[3]; mb[0]=(char)('0'+clock_alarm_m/10); mb[1]=(char)('0'+clock_alarm_m%10); mb[2]=0;
    gfx_draw_text(cx0+CLOCK_NUMM_X_OFF, spin_y+CLOCK_SPIN_SZ/2-ROW_H/2, mb, gfx_rgb(255,255,80));
    gfx_fill_rect(cx0+CLOCK_MPLUS_X_OFF, spin_y, CLOCK_SPIN_SZ, CLOCK_SPIN_SZ, gfx_rgb(0,0,170));
    gfx_draw_text(cx0+CLOCK_MPLUS_X_OFF+CLOCK_SPIN_SZ/2-ROW_H/2, spin_y+CLOCK_SPIN_SZ/2-ROW_H/2, "+", gfx_rgb(255,255,255));

    unsigned int btn_y = cy0 + CLOCK_BTN_Y_OFF;
    unsigned int btn_w = win->w - 4 - 2*CLOCK_PAD;
    unsigned int btn_bg; const char *btn_lbl;
    if (clock_fired) {
        btn_bg = (clock_flash_tick/10)%2 ? gfx_rgb(170,0,0) : gfx_rgb(80,0,0);
        btn_lbl = "ALARM! tap to stop";
    } else if (clock_armed) {
        btn_bg = gfx_rgb(0,170,0);
        btn_lbl = "Armed (tap to cancel)";
    } else {
        btn_bg = gfx_rgb(0,0,170);
        btn_lbl = "Arm";
    }
    gfx_fill_rect(cx0+CLOCK_PAD, btn_y, btn_w, CLOCK_BTN_H, btn_bg);
    unsigned int lbl_len = 0; while (btn_lbl[lbl_len]) lbl_len++;
    window_draw_text_clipped(win, cx0+CLOCK_PAD + btn_w/2 - (lbl_len*ROW_H)/2,
                             btn_y + CLOCK_BTN_H/2 - ROW_H/2, btn_lbl, gfx_rgb(255,255,255));
}

/* Returns 1 if the click changed something worth re-rendering. */
static int handle_content_click(const window_t *win, unsigned int mx, unsigned int my) {
    unsigned int cx0 = win->x + 2;
    unsigned int cy0 = win->content_y;

    unsigned int spin_y = cy0 + CLOCK_SPIN_Y_OFF;
    if (my >= spin_y && my < spin_y + CLOCK_SPIN_SZ) {
        if (mx >= cx0+CLOCK_HMINUS_X_OFF && mx < cx0+CLOCK_HMINUS_X_OFF+CLOCK_SPIN_SZ) {
            clock_alarm_h = (clock_alarm_h + 23) % 24; return 1;
        }
        if (mx >= cx0+CLOCK_HPLUS_X_OFF && mx < cx0+CLOCK_HPLUS_X_OFF+CLOCK_SPIN_SZ) {
            clock_alarm_h = (clock_alarm_h + 1) % 24; return 1;
        }
        if (mx >= cx0+CLOCK_MMINUS_X_OFF && mx < cx0+CLOCK_MMINUS_X_OFF+CLOCK_SPIN_SZ) {
            clock_alarm_m = (clock_alarm_m + 59) % 60; return 1;
        }
        if (mx >= cx0+CLOCK_MPLUS_X_OFF && mx < cx0+CLOCK_MPLUS_X_OFF+CLOCK_SPIN_SZ) {
            clock_alarm_m = (clock_alarm_m + 1) % 60; return 1;
        }
    }

    unsigned int btn_y = cy0 + CLOCK_BTN_Y_OFF;
    unsigned int btn_w = win->w - 4 - 2*CLOCK_PAD;
    if (my >= btn_y && my < btn_y + CLOCK_BTN_H && mx >= cx0+CLOCK_PAD && mx < cx0+CLOCK_PAD+btn_w) {
        if (clock_fired)      { clock_fired = 0; clock_armed = 0; }
        else if (clock_armed) { clock_armed = 0; }
        else                  { clock_armed = 1; clock_fired = 0; }
        return 1;
    }
    return 0;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    window_t win;
    window_init(&win, 460, 200, 320, 300, 260, 215, gfx_rgb(255, 165, 0), gfx_rgb(10, 15, 25),
               "AxClock");

    render_clock(&win);
    gfx_flush();

    int dragging = 0, resizing = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;

    for (;;) {
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
            } else if (!dragging && !resizing && left && !prev_left && focused && mx >= win.x && mx < win.x + win.w &&
                      my >= win.content_y && my < win.content_y + win.content_h) {
                handle_content_click(&win, mx, my);   /* re-rendered unconditionally below regardless */
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
                window_redraw_chrome(&win, "AxClock");
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxClock");
            }
            prev_left = left;
        }

        /* Time (and the flash animation while firing) keeps moving even
         * with no mouse/keyboard input, so re-render unconditionally
         * each loop iteration - unlike AxCalc, which only re-renders on
         * an actual keypress/click. */
        render_clock(&win);
        gfx_flush();
        sleep_ms(200);
    }

    return 0;
}
