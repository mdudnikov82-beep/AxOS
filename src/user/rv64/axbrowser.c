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
 * stack exists anywhere in this codebase - clicking an https:// link
 * shows a clear error instead of navigating), no CSS/layout, no
 * images, no JavaScript, no history/back button. Links ARE clickable:
 * document-relative/host-absolute/protocol-relative hrefs resolve
 * against the current page, but there's no "../" collapsing (naive
 * concatenation - honest partial support, matches the entity-decoding
 * below), and `#fragment`/`mailto:`/`javascript:` hrefs render as
 * plain non-clickable text rather than mis-navigating. */

#define ROW_H 16
#define PAD 10
#define BTN_W (3 * ROW_H)

#define ADDR_MAX 160   /* matches link_ent.url's size - a clicked real-world
                         * URL shouldn't silently truncate in the address bar */
static char addr_buf[ADDR_MAX];
static unsigned int addr_len = 0;

#define RAW_BUF_SIZE 65536
static unsigned char raw_buf[RAW_BUF_SIZE];

#define CONTENT_BUF_SIZE 32768
static char content_buf[CONTENT_BUF_SIZE];
static unsigned int content_len = 0;
static int scroll_offset = 0;

/* Clickable-link table: html_strip() records byte ranges [start,len)
 * into content_buf (post-stripping, already-plain-text coordinates) -
 * see html_strip()'s own comment for why a real DOM/per-character color
 * array isn't needed here. */
#define MAX_LINKS 64
struct link_ent { unsigned int start; unsigned int len; char url[160]; };
static struct link_ent links[MAX_LINKS];
static int link_count = 0;

static int pending_link_active = 0;
static unsigned int pending_link_start = 0;
static char pending_url[160];

/* Current page's host/port/path, promoted from do_fetch()'s locals so
 * html_strip() (called later in the same do_fetch()) can resolve
 * relative hrefs against them. */
static char g_host[64];
static int  g_port = 80;
static char g_path[160];

/* Screen-space row -> content_buf start-index map, populated by the
 * last render_browser() call so handle_content_click() can map a click
 * to a link without re-walking the whole buffer. Real ceiling is ~32
 * visible rows given the 800x600 screen's resize clamp; 40 leaves
 * headroom. */
#define MAX_VISIBLE_ROWS 40
static int row_start_idx[MAX_VISIBLE_ROWS];
static int row_count = 0;

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

static int is_ws(unsigned char c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }

static void bcopy_bounded(char *dst, int dst_max, const char *src) {
    int i = 0;
    while (src[i] && i < dst_max - 1) { dst[i] = src[i]; i++; }
    dst[i] = '\0';
}

static void bcat_bounded(char *dst, int dst_max, const char *src) {
    int i = 0;
    while (dst[i] && i < dst_max - 1) i++;
    int j = 0;
    while (src[j] && i < dst_max - 1) { dst[i++] = src[j++]; }
    dst[i] = '\0';
}

static void bcat_uint(char *dst, int dst_max, unsigned int v) {
    char tmp[12]; int n = 0;
    if (v == 0) tmp[n++] = '0';
    while (v > 0 && n < (int)sizeof(tmp)) { tmp[n++] = (char)('0' + v % 10); v /= 10; }
    char rev[12];
    for (int i = 0; i < n; i++) rev[i] = tmp[n - 1 - i];
    rev[n] = '\0';
    bcat_bounded(dst, dst_max, rev);
}

/* Scans a raw tag's bytes [tag, tag+tag_len) (e.g. `<a href="x">`) for
 * an href="..."/'...'/unquoted attribute value, decoding entities
 * inline via the existing decode_entity() (so href="a.html?x=1&amp;y=2"
 * decodes the &amp; correctly - same function already used for body
 * text, pure reuse). Returns 1 if a non-empty value was captured. */
static int extract_href(const unsigned char *tag, unsigned int tag_len, char *out, int out_max) {
    unsigned int i = 0;
    while (i < tag_len) {
        if (ci_starts_with(tag + i, tag_len - i, "href") &&
            (i == 0 || is_ws(tag[i - 1]))) {
            unsigned int j = i + 4;
            while (j < tag_len && is_ws(tag[j])) j++;
            if (j < tag_len && tag[j] == '=') {
                j++;
                while (j < tag_len && is_ws(tag[j])) j++;
                char quote = 0;
                if (j < tag_len && (tag[j] == '"' || tag[j] == '\'')) { quote = (char)tag[j]; j++; }
                int n = 0;
                while (j < tag_len) {
                    unsigned char c = tag[j];
                    if (quote) { if (c == (unsigned char)quote) break; }
                    else       { if (is_ws(c) || c == '>' || c == '/') break; }
                    if (c == '&') { j += (unsigned int)decode_entity((const char *)tag + j, out, &n, out_max); continue; }
                    if (n < out_max - 1) out[n++] = (char)c;
                    j++;
                }
                out[n] = '\0';
                return n > 0;
            }
        }
        i++;
    }
    return 0;
}

/* Resolves a raw href value against the current page (g_host/g_port/
 * g_path) into an absolute http(s):// URL in `out`. Empty `out` means
 * "not a real navigable link" - covers #fragment-only hrefs (no in-page
 * scroll-to-anchor support) and non-http(s) schemes (mailto:,
 * javascript:, tel:, ...) which would otherwise be mangled by
 * parse_url() if clicked. https:// links ARE resolved through
 * (verbatim), not rejected here - do_fetch()'s own HTTPS check gives a
 * clear error at click time instead, so the address bar still shows
 * the real target rather than something mangled. No "../" collapsing -
 * honest, documented scope limit; naive concatenation still often
 * works since many real servers normalize "."/".." segments themselves. */
static void resolve_href(const char *href, char *out, int out_max) {
    char stripped[160];
    int n = 0;
    for (int i = 0; href[i] && href[i] != '#' && n < (int)sizeof(stripped) - 1; i++)
        stripped[n++] = href[i];
    stripped[n] = '\0';
    out[0] = '\0';
    if (n == 0) return;

    for (int i = 0; stripped[i] && stripped[i] != '/'; i++) {
        if (stripped[i] == ':') {
            if (!(ci_starts_with((const unsigned char *)stripped, (unsigned int)n, "http:") ||
                  ci_starts_with((const unsigned char *)stripped, (unsigned int)n, "https:")))
                return;
            break;
        }
    }

    if (ci_starts_with((const unsigned char *)stripped, (unsigned int)n, "http://") ||
        ci_starts_with((const unsigned char *)stripped, (unsigned int)n, "https://")) {
        bcopy_bounded(out, out_max, stripped);
        return;
    }
    if (stripped[0] == '/' && stripped[1] == '/') {
        bcopy_bounded(out, out_max, "http:");
        bcat_bounded(out, out_max, stripped);
        return;
    }
    if (stripped[0] == '/') {
        bcopy_bounded(out, out_max, "http://");
        bcat_bounded(out, out_max, g_host);
        if (g_port != 80) { bcat_bounded(out, out_max, ":"); bcat_uint(out, out_max, (unsigned int)g_port); }
        bcat_bounded(out, out_max, stripped);
        return;
    }

    char dir[160];
    int dn = 0, last_slash = 0;
    for (int i = 0; g_path[i] && dn < (int)sizeof(dir) - 1; i++) {
        dir[dn++] = g_path[i];
        if (g_path[i] == '/') last_slash = dn;
    }
    dir[last_slash] = '\0';
    bcopy_bounded(out, out_max, "http://");
    bcat_bounded(out, out_max, g_host);
    if (g_port != 80) { bcat_bounded(out, out_max, ":"); bcat_uint(out, out_max, (unsigned int)g_port); }
    bcat_bounded(out, out_max, dir);
    bcat_bounded(out, out_max, stripped);
}

/* Strips HTML tags down to plain text: TEXT / IN_TAG / SKIP_SCRIPT /
 * SKIP_STYLE. <script>/<style> CONTENTS are skipped entirely (not real
 * page text), every other tag is dropped but its surrounding text kept.
 * A handful of common entities are decoded (see decode_entity).
 * <a href=...>/</a> pairs are ALSO tracked into the links[] table (see
 * that table's own comment) - since every tag close already forces a
 * newline (below), an anchor's visible text is already isolated onto
 * its own contiguous content_buf run before this feature ever needed
 * to add anything to that mechanic. */
static void html_strip(const unsigned char *body, unsigned int body_len) {
    content_len = 0;
    link_count = 0;
    pending_link_active = 0;
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

            unsigned int tag_start = i;
            /* "<a" open tag: the char right after must be whitespace or
             * '>' - otherwise it's <abbr>, <article>, etc, not a real
             * anchor. */
            int is_open_a = ci_starts_with(body + i, body_len - i, "<a") &&
                            (body_len - i <= 2 || is_ws(body[i + 2]) || body[i + 2] == '>');
            int is_close_a = ci_starts_with(body + i, body_len - i, "</a>");

            if (is_close_a && pending_link_active) {
                /* Close off the pending link BEFORE this tag's own
                 * forced newline below, so trailing whitespace isn't
                 * counted as part of the clickable range. */
                pending_link_active = 0;
                if (link_count < MAX_LINKS && content_len > pending_link_start) {
                    links[link_count].start = pending_link_start;
                    links[link_count].len   = content_len - pending_link_start;
                    bcopy_bounded(links[link_count].url, (int)sizeof(links[link_count].url), pending_url);
                    link_count++;
                }
            }

            int have_href = 0;
            char href_buf[160];
            if (is_open_a) {
                unsigned int tag_end = tag_start;
                while (tag_end < body_len && body[tag_end] != '>') tag_end++;
                int self_closing = (tag_end > tag_start && tag_end < body_len && body[tag_end - 1] == '/');
                if (!self_closing) {
                    have_href = extract_href(body + tag_start, tag_end - tag_start, href_buf, (int)sizeof(href_buf));
                }
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

            if (is_open_a && have_href) {
                char resolved[176];
                resolve_href(href_buf, resolved, (int)sizeof(resolved));
                if (resolved[0]) {
                    bcopy_bounded(pending_url, (int)sizeof(pending_url), resolved);
                    pending_link_start = content_len;
                    pending_link_active = 1;
                }
            }
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

    /* No TLS stack anywhere in this codebase - catch this BEFORE
     * parse_url() mangles the "https://" prefix into garbage hostname
     * text (parse_url() only strips a literal 7-char "http://", so an
     * 8-char "https://" URL would otherwise fall through as if the
     * whole scheme were part of the host). Clickable links make this
     * far more likely to actually happen than it was when the address
     * bar could only be hand-typed. */
    if (ci_starts_with((const unsigned char *)addr_buf, addr_len, "https://")) {
        set_status("HTTPS not supported (no TLS)");
        return;
    }

    set_status("Loading...");
    /* Render immediately so the user sees feedback before the
     * (blocking, like AxFiles' own cat/delete) fetch below - a real
     * page load is a few seconds at most per this session's own
     * HTTPGET tests, an accepted simplification, not an oversight. */
    render_browser(win);
    gfx_flush();

    char host[64]; int port; char path[160];
    parse_url(host, sizeof(host), &port, path, sizeof(path));
    bcopy_bounded(g_host, (int)sizeof(g_host), host);
    g_port = port;
    bcopy_bounded(g_path, (int)sizeof(g_path), path);

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

/* 1 if content_buf index `idx` falls inside some tracked link's range -
 * used both to pick this row's draw color and (from
 * handle_content_click()) to resolve an actual click. */
static int find_link_at(unsigned int idx) {
    for (int k = 0; k < link_count; k++)
        if (idx >= links[k].start && idx < links[k].start + links[k].len) return k;
    return -1;
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

    row_count = 0;

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
                unsigned int row_start = i - (unsigned int)col;
                unsigned int color = (find_link_at(row_start) >= 0)
                                    ? gfx_rgb(120, 170, 255) : gfx_rgb(200, 200, 200);
                gfx_draw_text(win->x + PAD, text_y0 + (unsigned int)drawn * ROW_H, linebuf, color);
                if (drawn < MAX_VISIBLE_ROWS) { row_start_idx[drawn] = (int)row_start; row_count = drawn + 1; }
                drawn++;
            }
            line++; col = 0;
            continue;
        }
        if (is_newline || is_end) {
            linebuf[col] = '\0';
            if (col > 0 && line >= scroll_offset && drawn < visible_rows) {
                unsigned int row_start = i - (unsigned int)col;
                unsigned int color = (find_link_at(row_start) >= 0)
                                    ? gfx_rgb(120, 170, 255) : gfx_rgb(200, 200, 200);
                gfx_draw_text(win->x + PAD, text_y0 + (unsigned int)drawn * ROW_H, linebuf, color);
                if (drawn < MAX_VISIBLE_ROWS) { row_start_idx[drawn] = (int)row_start; row_count = drawn + 1; }
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

/* Copies url into the address bar (like the user typed it) and fetches
 * it - so clicking a link visibly updates the address bar too, same as
 * a real browser. */
static void navigate_to(window_t *win, const char *url) {
    unsigned int i = 0;
    while (url[i] && i < ADDR_MAX - 1) { addr_buf[i] = url[i]; i++; }
    addr_buf[i] = '\0';
    addr_len = i;
    do_fetch(win);
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
    } else if (my >= text_y0 && mx >= win->x + PAD) {
        int row = (int)(my - text_y0) / ROW_H;
        if (row < row_count) {
            int col_click = (int)(mx - (win->x + PAD)) / ROW_H;
            int idx = row_start_idx[row] + col_click;
            int k = find_link_at((unsigned int)idx);
            if (k >= 0) {
                navigate_to(win, links[k].url);
                return 1;
            }
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
