#include "syscall.h"
#include "window.h"
#include "tcp.h"

/* AxChat — a real network chat window between two AxOS/RV64 instances,
 * RISC-V only (x86's GUI kernel gfx_shell.c has no network stack linked
 * in at all — the same platform gap as AxTaskMgr's process concept, see
 * that memory/comment). Reuses tcp.h's existing single-connection API
 * (tcp_connect/tcp_accept/tcp_send/tcp_recv/tcp_close, already proven
 * live in tcptest.c/tcpserve.c) and mirrors axterm.c's window shape
 * almost exactly: window_println() scrollback + a persistent input line
 * at the bottom + kbd_getc() drain loop. The only genuinely new pieces
 * are the connection setup and the non-blocking recv-into-scrollback
 * poll each tick.
 *
 * No peer-discovery/DNS exists anywhere in this codebase - every
 * existing network example hardcodes an IP. AxChat takes its role from
 * argv instead of a hardcoded address:
 *   run AXCHAT.ELF host <my_ip>             - passive open (listen)
 *   run AXCHAT.ELF join <my_ip> <peer_ip>    - active open (connect)
 * <my_ip> overrides g_my_ip (arp.h) - a plain mutable static, per-
 * process, safe to overwrite before connecting (dhcp.h already does
 * exactly this after a DORA exchange). This is also what makes a REAL
 * two-QEMU-instance test possible: default SLIRP gives every guest the
 * same NAT'd 10.0.2.15, unreachable from a second instance - two
 * `-netdev socket,listen=/connect=` QEMU processes with distinct argv
 * IPs form a real Ethernet segment between two independent boots
 * instead. */

#define ROW_H 16
#define CHAT_PORT 7777
#define LINE_MAX 64   /* both directions - matches the input line's own cap */

static char input[LINE_MAX];
static unsigned int input_len = 0;

static char recv_buf[LINE_MAX * 2];   /* accumulates partial/coalesced TCP data */
static unsigned int recv_len = 0;

static int conn_alive = 1;

static unsigned int parse_ip(const char *s) {
    unsigned int octs[4] = {0, 0, 0, 0};
    int oi = 0;
    for (int i = 0; s[i] && oi < 4; i++) {
        if (s[i] == '.') { oi++; continue; }
        if (s[i] >= '0' && s[i] <= '9') octs[oi] = octs[oi] * 10 + (unsigned int)(s[i] - '0');
    }
    return IP4(octs[0], octs[1], octs[2], octs[3]);
}

static void draw_input_line(window_t *win, int cursor_on) {
    unsigned int y = win->content_y + win->content_h;
    gfx_fill_rect(win->x + 4, y, win->w - 8, ROW_H, win->bg);
    gfx_draw_text(win->x + 6, y, "> ", gfx_rgb(255, 255, 0));
    if (input_len) window_draw_text_clipped(win, win->x + 6 + 2 * ROW_H, y, input, gfx_rgb(255, 255, 255));
    if (cursor_on)
        gfx_fill_rect(win->x + 6 + 2 * ROW_H + input_len * ROW_H, y, 10, ROW_H, gfx_rgb(255, 255, 255));
}

/* Drains complete '\n'-terminated lines out of recv_buf into scrollback,
 * leaving any trailing partial line buffered for the next poll - the
 * peer's line can arrive split across two tcp_recv() calls, or two fast
 * lines can arrive coalesced in one, and this handles both. */
static void drain_recv_lines(window_t *win) {
    unsigned int start = 0;
    for (unsigned int i = 0; i < recv_len; i++) {
        if (recv_buf[i] != '\n') continue;
        char line[LINE_MAX + 8];
        unsigned int n = i - start;
        if (n > LINE_MAX) n = LINE_MAX;
        for (unsigned int k = 0; k < n; k++) line[k] = recv_buf[start + k];
        line[n] = '\0';
        window_println(win, line, gfx_rgb(80, 220, 255));
        start = i + 1;
    }
    /* Shift any leftover partial line down to the front of the buffer. */
    unsigned int rest = recv_len - start;
    for (unsigned int k = 0; k < rest; k++) recv_buf[k] = recv_buf[start + k];
    recv_len = rest;
}

static void poll_recv(window_t *win, tcp_conn_t *conn) {
    if (!conn_alive) return;
    unsigned char buf[128];
    int n = tcp_recv(conn, buf, sizeof(buf), 0);
    if (n > 0) {
        unsigned int room = (unsigned int)sizeof(recv_buf) - recv_len;
        unsigned int take = (unsigned int)n;
        if (take > room) take = room;   /* defensive - LINE_MAX*2 comfortably fits one poll's worth */
        for (unsigned int i = 0; i < take; i++) recv_buf[recv_len++] = (char)buf[i];
        drain_recv_lines(win);
    } else if (n < 0) {
        window_println(win, "* peer disconnected", gfx_rgb(255, 120, 60));
        conn_alive = 0;
    }
}

static void send_line(window_t *win, tcp_conn_t *conn) {
    if (input_len == 0) return;
    window_println(win, input, gfx_rgb(120, 255, 120));
    if (conn_alive) {
        char out[LINE_MAX + 1];
        unsigned int k = 0;
        for (; k < input_len; k++) out[k] = input[k];
        out[k++] = '\n';
        tcp_send(conn, out, k);
    }
    input_len = 0;
    input[0] = '\0';
}

int main(int argc, char **argv) {
    if (argc < 3) {
        puts_rv("Usage: AXCHAT.ELF host <my_ip>\r\n");
        puts_rv("       AXCHAT.ELF join <my_ip> <peer_ip>\r\n");
        exit(1);
    }

    unsigned char mac[6];
    if (!net_mac(mac)) {
        puts_rv("axchat: no NIC found\r\n");
        exit(1);
    }

    g_my_ip = parse_ip(argv[2]);

    static tcp_conn_t conn;
    int is_host = (argv[1][0] == 'h');
    if (is_host) {
        puts_rv("axchat: listening...\r\n");
        if (!tcp_accept(&conn, CHAT_PORT, 30000)) {
            puts_rv("axchat: no connection within timeout\r\n");
            exit(1);
        }
    } else {
        if (argc < 4) {
            puts_rv("Usage: AXCHAT.ELF join <my_ip> <peer_ip>\r\n");
            exit(1);
        }
        unsigned int peer_ip = parse_ip(argv[3]);
        puts_rv("axchat: connecting...\r\n");
        if (!tcp_connect(&conn, peer_ip, CHAT_PORT, 10000)) {
            puts_rv("axchat: could not connect\r\n");
            exit(1);
        }
    }
    puts_rv("axchat: connected!\r\n");

    unsigned int screen_w = 800, screen_h = 600;
    if (!gfx_info(&screen_w, &screen_h)) {
        puts_rv("axchat: no GPU available\r\n");
        exit(1);
    }

    window_t win;
    window_init(&win, 200, 120, 360, 380, 260, 200, gfx_rgb(0, 200, 160), gfx_rgb(10, 15, 20),
               "AxChat");
    win.content_h -= ROW_H;   /* reserve the bottom strip for the input line, same trick as axterm.c */

    window_println(&win, "AxChat - connected. Type a message.", gfx_rgb(255, 255, 0));
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
                if (conn_alive) tcp_close(&conn);
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
                win.content_h -= ROW_H;   /* re-reserve the input-line strip window_resize() just recomputed away */
                changed = 1;
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxChat");
                win.cur_row = 0;   /* content lost on move - no retained scrollback buffer */
                changed = 1;
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxChat");
                win.cur_row = 0;
                changed = 1;
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (c == '\n') {
                send_line(&win, &conn);
                draw_input_line(&win, 1);
                changed = 1;
            } else if (c == '\b') {
                if (input_len) { input[--input_len] = '\0'; changed = 1; }
            } else if (input_len < LINE_MAX - 1) {
                input[input_len++] = (char)c;
                input[input_len] = '\0';
                changed = 1;
            }
        }

        poll_recv(&win, &conn);

        tick++;
        int cursor_on = (int)((tick / 15) & 1);
        if (changed || (tick % 15 == 0)) {
            draw_input_line(&win, cursor_on);
        }

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
