#include "syscall.h"
#include "window.h"
#include "dns.h"
#include "tcp.h"

/* AxBrowser — a genuine from-scratch "reader mode" text browser,
 * RISC-V only (x86's GUI kernel has no network stack linked in at all,
 * same gap as AxChat/AxTaskMgr). Real WebKit is not possible on AxOS at
 * all (millions of lines of C++ needing POSIX/threads/virtual memory/a
 * JS JIT/dozens of external libraries - this OS is plain C with no
 * standard library) - this is the honest alternative: fetches a page
 * over plain HTTP (reusing the exact dns_resolve_a/tcp_connect/
 * tcp_send/tcp_recv flow already proven in httpget.c), strips HTML
 * tags down to plain readable text, and shows it in a scrollable
 * window. Deliberately NOT pretending to be more: no HTTPS (no TLS
 * stack exists anywhere in this codebase), no CSS/layout, no images,
 * no JavaScript, no clickable links (type a new URL to navigate), no
 * history/back button. */

#define ROW_H 16
#define PAD 10
#define BTN_W (3 * ROW_H)

#define ADDR_MAX 96
static char addr_buf[ADDR_MAX];
static unsigned int addr_len = 0;

#define RAW_BUF_SIZE 65536
static unsigned char raw_buf[RAW_BUF_SIZE];

#define CONTENT_BUF_SIZE 32768
static char content_buf[CONTENT_BUF_SIZE];
static unsigned int content_len = 0;
static int scroll_offset = 0;

static char status_msg[64] = "Type a URL and press Enter (http:// only)";

static void render_browser(const window_t *win);

static int slen_i(const char *s) { int n = 0; while (s[n]) n++; return n; }

static int is_ip_literal(const char *host, int len) {
    for (int i = 0; i < len; i++) {
        char c = host[i];
        if (!((c >= '0' && c <= '9') || c == '.')) return 0;
    }
    return len > 0;
}

static unsigned int parse_ip_literal(const char *host, int len) {
    unsigned int octs[4] = {0, 0, 0, 0};
    int oi = 0;
    for (int i = 0; i < len && oi < 4; i++) {
        if (host[i] == '.') { oi++; continue; }
        octs[oi] = octs[oi] * 10 + (unsigned int)(host[i] - '0');
    }
    return IP4(octs[0], octs[1], octs[2], octs[3]);
}

/* Parses addr_buf into host/port/path. Accepts an optional "http://"
 * prefix (case-insensitive), an optional ":port", and an optional
 * "/path..." - matches a plain browser address bar's usual shorthand. */
static void parse_url(char *host, int host_max, int *port, char *path, int path_max) {
    const char *p = addr_buf;
    if ((p[0] == 'h' || p[0] == 'H') && (p[1] == 't' || p[1] == 'T') &&
        (p[2] == 't' || p[2] == 'T') && (p[3] == 'p' || p[3] == 'P') &&
        p[4] == ':' && p[5] == '/' && p[6] == '/') {
        p += 7;
    }

    int hi = 0;
    while (*p && *p != ':' && *p != '/' && hi < host_max - 1) host[hi++] = *p++;
    host[hi] = '\0';

    *port = 80;
    if (*p == ':') {
        p++;
        int pv = 0;
        while (*p >= '0' && *p <= '9') pv = pv * 10 + (*p++ - '0');
        if (pv > 0) *port = pv;
    }

    if (*p == '/') {
        int pi = 0;
        while (*p && pi < path_max - 1) path[pi++] = *p++;
        path[pi] = '\0';
    } else {
        path[0] = '/'; path[1] = '\0';
    }
}

/* Decodes the handful of entities real pages actually use; anything
 * else passes through with the '&' intact rather than silently
 * guessing - honest partial support, matches this codebase's existing
 * "don't pretend to handle what you don't" style. Returns bytes
 * consumed from `s` (at least 1). */
struct entity_ent { const char *name; char ch; };
static const struct entity_ent entity_table[6] = {
    {"amp;", '&'}, {"lt;", '<'}, {"gt;", '>'},
    {"quot;", '"'}, {"nbsp;", ' '}, {"#39;", '\''},
};

static int decode_entity(const char *s, char *out, int *out_len, int out_max) {
    const struct entity_ent *table = entity_table;
    for (int t = 0; t < 6; t++) {
        int n = slen_i(table[t].name);
        int match = 1;
        for (int i = 0; i < n; i++) if (s[1 + i] != table[t].name[i]) { match = 0; break; }
        if (match) {
            if (*out_len < out_max - 1) out[(*out_len)++] = table[t].ch;
            return 1 + n;
        }
    }
    if (*out_len < out_max - 1) out[(*out_len)++] = '&';
    return 1;
}

static int ci_starts_with(const unsigned char *s, unsigned int rem, const char *lit) {
    int n = slen_i(lit);
    if ((unsigned int)n > rem) return 0;
    for (int i = 0; i < n; i++) {
        char a = (char)s[i];
        if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
        char b = lit[i];
        if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
        if (a != b) return 0;
    }
    return 1;
}

/* Strips HTML tags down to plain text: TEXT / IN_TAG / SKIP_SCRIPT /
 * SKIP_STYLE. <script>/<style> CONTENTS are skipped entirely (not real
 * page text), every other tag is dropped but its surrounding text kept.
 * A handful of common entities are decoded (see decode_entity). */
static void html_strip(const unsigned char *body, unsigned int body_len) {
    content_len = 0;
    unsigned int i = 0;
    while (i < body_len && content_len < CONTENT_BUF_SIZE - 1) {
        unsigned char c = body[i];
        if (c == '<') {
            if (ci_starts_with(body + i, body_len - i, "<script")) {
                unsigned int j = i;
                while (j < body_len && !ci_starts_with(body + j, body_len - j, "</script>")) j++;
                i = (j < body_len) ? j + 9 : body_len;
                continue;
            }
            if (ci_starts_with(body + i, body_len - i, "<style")) {
                unsigned int j = i;
                while (j < body_len && !ci_starts_with(body + j, body_len - j, "</style>")) j++;
                i = (j < body_len) ? j + 8 : body_len;
                continue;
            }
            while (i < body_len && body[i] != '>') i++;
            if (i < body_len) i++;
            /* A closed tag boundary is a reasonable place to force a
             * line break in the output - keeps block-level elements
             * (paragraphs, headings, list items) from all running
             * together on one line. Cheap approximation, not real
             * block/inline awareness. */
            if (content_len < CONTENT_BUF_SIZE - 1 &&
                (content_len == 0 || content_buf[content_len - 1] != '\n'))
                content_buf[content_len++] = '\n';
            continue;
        }
        if (c == '&') {
            i += (unsigned int)decode_entity((const char *)body + i, content_buf, (int *)&content_len, CONTENT_BUF_SIZE);
            continue;
        }
        content_buf[content_len++] = (char)c;
        i++;
    }
    content_buf[content_len] = '\0';
}

static void set_status(const char *s) {
    int i = 0;
    while (s[i] && i < (int)sizeof(status_msg) - 1) { status_msg[i] = s[i]; i++; }
    status_msg[i] = '\0';
    content_len = 0;
}

static void do_fetch(window_t *win) {
    if (addr_len == 0) return;
    set_status("Loading...");
    /* Render immediately so the user sees feedback before the
     * (blocking, like AxFiles' own cat/delete) fetch below - a real
     * page load is a few seconds at most per this session's own
     * HTTPGET tests, an accepted simplification, not an oversight. */
    render_browser(win);
    gfx_flush();

    char host[64]; int port; char path[160];
    parse_url(host, sizeof(host), &port, path, sizeof(path));

    unsigned char mac[6];
    if (!net_mac(mac)) { set_status("No network device found"); return; }

    unsigned int ip;
    int hlen = slen_i(host);
    if (is_ip_literal(host, hlen)) {
        ip = parse_ip_literal(host, hlen);
    } else {
        if (!dns_resolve_a(host, IP4(10, 0, 2, 3), 3000, &ip)) {
            set_status("DNS resolve failed");
            return;
        }
    }

    static tcp_conn_t conn;
    if (!tcp_connect(&conn, ip, (unsigned short)port, 3000)) {
        set_status("Connection failed");
        return;
    }

    char req[256]; int rn = 0;
    const char *p1 = "GET "; while (*p1 && rn < 255) req[rn++] = *p1++;
    for (int i = 0; path[i] && rn < 255; i++) req[rn++] = path[i];
    const char *p2 = " HTTP/1.0\r\nHost: ";
    while (*p2 && rn < 255) req[rn++] = *p2++;
    for (int i = 0; host[i] && rn < 255; i++) req[rn++] = host[i];
    const char *p3 = "\r\nConnection: close\r\n\r\n";
    while (*p3 && rn < 255) req[rn++] = *p3++;

    if (tcp_send(&conn, req, (unsigned int)rn) != 0) {
        tcp_close(&conn);
        set_status("Request send failed");
        return;
    }

    unsigned int total = 0;
    for (;;) {
        int n = tcp_recv(&conn, raw_buf + total, RAW_BUF_SIZE - total - 1, 5000);
        if (n > 0) {
            total += (unsigned int)n;
            if (total >= RAW_BUF_SIZE - 1) break;
        } else {
            break;   /* n==0 idle timeout, n<0 peer closed - either way, done */
        }
    }
    tcp_close(&conn);
    raw_buf[total] = '\0';

    if (total == 0) { set_status("Empty response"); return; }

    /* Body starts right after the blank line ending the headers. */
    unsigned int body_start = total;
    for (unsigned int i = 0; i + 3 < total; i++) {
        if (raw_buf[i] == '\r' && raw_buf[i+1] == '\n' && raw_buf[i+2] == '\r' && raw_buf[i+3] == '\n') {
            body_start = i + 4;
            break;
        }
    }
    if (body_start >= total) { set_status("No response body"); return; }

    html_strip(raw_buf + body_start, total - body_start);
    scroll_offset = 0;
    status_msg[0] = '\0';
}

/* Shared by render + click hit-testing, same reasoning as
 * axfiles.c's files_layout(). */
static void browser_layout(const window_t *win, unsigned int *addr_y,
                           unsigned int *up_x, unsigned int *down_x,
                           unsigned int *text_y0, int *visible_rows, int *max_cols) {
    *addr_y = win->content_y + PAD;
    *down_x = win->x + win->w - PAD - BTN_W;
    *up_x   = *down_x - BTN_W - 8;
    *text_y0 = *addr_y + ROW_H + 6;
    int avail = (int)(win->content_y + win->content_h) - (int)PAD - (int)*text_y0;
    *visible_rows = (avail > 0) ? avail / ROW_H : 0;
    *max_cols = (int)(win->w - 2 * PAD) / ROW_H;
    if (*max_cols < 1) *max_cols = 1;
    if (*max_cols > 127) *max_cols = 127;
}

static void render_browser(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int addr_y, up_x, down_x, text_y0;
    int visible_rows, max_cols;
    browser_layout(win, &addr_y, &up_x, &down_x, &text_y0, &visible_rows, &max_cols);

    window_draw_text_clipped(win, win->x + PAD, addr_y, addr_buf, gfx_rgb(255, 255, 255));
    gfx_fill_rect(win->x + PAD + addr_len * ROW_H, addr_y, ROW_H / 2, ROW_H, gfx_rgb(255, 255, 0));
    gfx_draw_text(up_x, addr_y, "[^]", gfx_rgb(0, 220, 220));
    gfx_draw_text(down_x, addr_y, "[v]", gfx_rgb(0, 220, 220));
    gfx_fill_rect(win->x + PAD, text_y0 - 4, win->w - 2 * PAD, 1, gfx_rgb(120, 120, 120));

    if (content_len == 0) {
        gfx_draw_text(win->x + PAD, text_y0, status_msg, gfx_rgb(255, 255, 0));
        return;
    }

    int line = 0, drawn = 0, col = 0;
    char linebuf[128];
    unsigned int i = 0;
    while (i <= content_len) {
        int is_end = (i == content_len);
        char c = is_end ? 0 : content_buf[i];
        int is_newline = (!is_end) && (c == '\n');
        int is_wrap    = (!is_end) && (!is_newline) && (col >= max_cols);

        if (is_wrap) {
            linebuf[col] = '\0';
            if (line >= scroll_offset && drawn < visible_rows) {
                gfx_draw_text(win->x + PAD, text_y0 + (unsigned int)drawn * ROW_H, linebuf, gfx_rgb(200, 200, 200));
                drawn++;
            }
            line++; col = 0;
            continue;
        }
        if (is_newline || is_end) {
            linebuf[col] = '\0';
            if (col > 0 && line >= scroll_offset && drawn < visible_rows) {
                gfx_draw_text(win->x + PAD, text_y0 + (unsigned int)drawn * ROW_H, linebuf, gfx_rgb(200, 200, 200));
                drawn++;
            }
            line++; col = 0; i++;
            if (is_end) break;
            continue;
        }
        if (col < 127) linebuf[col++] = c;
        i++;
    }
}

/* Returns 1 if the click changed something worth re-rendering. */
static int handle_content_click(window_t *win, unsigned int mx, unsigned int my) {
    unsigned int addr_y, up_x, down_x, text_y0;
    int visible_rows, max_cols;
    browser_layout(win, &addr_y, &up_x, &down_x, &text_y0, &visible_rows, &max_cols);

    if (my >= addr_y && my < addr_y + ROW_H) {
        if (mx >= up_x && mx < up_x + BTN_W) {
            if (scroll_offset > 0) scroll_offset--;
            return 1;
        }
        if (mx >= down_x && mx < down_x + BTN_W) {
            scroll_offset++;
            return 1;
        }
    }
    return 0;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    if (!gfx_info(&screen_w, &screen_h)) {
        puts_rv("axbrowser: no GPU available\r\n");
        exit(1);
    }

    window_t win;
    window_init(&win, 60, 60, 680, 440, 300, 200, gfx_rgb(90, 150, 220), gfx_rgb(12, 14, 20),
               "AxBrowser");

    render_browser(&win);
    gfx_flush();

    int dragging = 0, resizing = 0, prev_left = 0;
    unsigned int drag_off_x = 0, drag_off_y = 0;

    for (;;) {
        int changed = 0;

        unsigned int mx = 0, my = 0, buttons = 0, focused = 1;
        int wheel = 0;
        if (mouse_state(&mx, &my, &buttons, &focused, &wheel)) {
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
                if (handle_content_click(&win, mx, my)) changed = 1;
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
                changed = 1;
            } else if (dragging && !left) {
                dragging = 0;
                window_redraw_chrome(&win, "AxBrowser");
                changed = 1;
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxBrowser");
                changed = 1;
            }
            prev_left = left;

            if (!dragging && !resizing && focused && wheel != 0 &&
                mx >= win.x && mx < win.x + win.w &&
                my >= win.content_y && my < win.content_y + win.content_h) {
                if (wheel > 0) scroll_offset = (scroll_offset > wheel) ? scroll_offset - wheel : 0;
                else scroll_offset += -wheel;
                changed = 1;
            }
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            if (c == '\n') {
                do_fetch(&win);
                changed = 1;
            } else if (c == '\b') {
                if (addr_len) { addr_len--; addr_buf[addr_len] = '\0'; changed = 1; }
            } else if ((unsigned char)c >= 32 && addr_len < ADDR_MAX - 1) {
                addr_buf[addr_len++] = (char)c;
                addr_buf[addr_len] = '\0';
                changed = 1;
            }
        }

        if (changed) {
            render_browser(&win);
        }
        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
