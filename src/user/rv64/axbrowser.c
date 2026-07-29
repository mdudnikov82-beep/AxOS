#include "syscall.h"
#include "window.h"
#include "dns.h"
#include "tcp.h"
#include "bmp.h"

/* AxBrowser — a genuine from-scratch "reader mode" text browser,
 * RISC-V only (x86's GUI kernel has no network stack linked in at all,
 * same gap as AxChat/AxTaskMgr). Real Blink/WebKit is not possible on
 * AxOS at all (~30M lines of C++ needing POSIX/threads/dynamic
 * linking/a JS JIT/GPU/dozens of external libraries - this OS is
 * plain C with no standard library, single-core, freestanding) - this
 * is the honest alternative, grown incrementally instead of imported:
 * fetches a page over plain HTTP (reusing the exact dns_resolve_a/
 * tcp_connect/tcp_send/tcp_recv flow already proven in httpget.c) and
 * renders SOME real block structure - headings, paragraph spacing,
 * list items, bold/italic emphasis, horizontal rules, and inline
 * links/emphasis that flow within a paragraph's wrapped text (see
 * html_strip()'s tag-category dispatch and draw_styled_row() below) -
 * not just flat plain text. Still deliberately NOT pretending to be
 * more: no HTTPS (no TLS stack exists anywhere in this codebase -
 * clicking an https:// link shows a clear error instead of
 * navigating), no CSS, no tables, no JavaScript, no history/back
 * button, no real DOM (tag styling is a single active span at a time,
 * not a real nesting stack - see style_active's own comment).
 * `<img>` support is BMP-only (see bmp.h's bmp_decode_mem()) - real
 * web images are almost always JPEG/PNG, which this codebase has no
 * decoder for at all (no DEFLATE/DCT - out of scope entirely, not a
 * bug), so this only ever shows a real picture on pages that happen
 * to link a `.bmp` file. Links ARE clickable: document-relative/
 * host-absolute/protocol-relative hrefs resolve against the current
 * page, but
 * there's no "../" collapsing (naive concatenation - honest partial
 * support, matches the entity-decoding below), and `#fragment`/
 * `mailto:`/`javascript:` hrefs render as plain non-clickable text
 * rather than mis-navigating. */

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

/* Same byte-range-annotation technique as links[] above, for
 * <b>/<strong>/<em>/<i>/<h1>-<h6> emphasis - see draw_styled_row().
 * Only ONE span can be active at a time (style_active/style_kind/
 * style_start below), not a real nesting stack: opening a style tag
 * while one is already active, or closing one while a DIFFERENT kind
 * is active, is a no-op. This mirrors pending_link_active's own
 * existing simplicity and this file's established "honest partial
 * support" philosophy (see the entity table / no "../" collapsing) -
 * nested emphasis in real pages is rare enough that getting it
 * partially wrong (inner span just doesn't get its own styling) beats
 * the complexity of a real stack for what's still just a reader mode. */
#define STYLE_BOLD    1
#define STYLE_EM      2
#define STYLE_HEADING 3
#define MAX_STYLES 64
struct style_ent { unsigned int start; unsigned int len; unsigned char kind; };
static struct style_ent styles[MAX_STYLES];
static int style_count = 0;

static int style_active = 0;
static unsigned char style_kind = 0;
static unsigned int style_start = 0;

/* <img src="..."> support - BMP only (see bmp.h's bmp_decode_mem()
 * and this file's own top-of-file comment on why). html_strip() only
 * COLLECTS resolved image URLs into pending_img_urls[] and writes a
 * 2-byte marker ('\x02' + the slot index, both safe control bytes -
 * never produced by entity-decoding or raw body text, and distinct
 * from the '\x01' hr marker) into content_buf; it does NOT fetch
 * anything itself (parsing stays pure string processing). do_fetch()
 * fetches+decodes each one into page_images[]/image_ok[] in a separate
 * pass AFTER html_strip() returns. MAX_IMAGES=4 also caps how long a
 * page load can take, since each image needs its own full DNS+TCP+
 * HTTP round trip. */
#define MAX_IMAGES 4
static char pending_img_urls[MAX_IMAGES][176];
static bmp_image_t page_images[MAX_IMAGES];
static int image_ok[MAX_IMAGES];
static int image_count = 0;

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

/* Parses an arbitrary URL string (the caller decides the source -
 * addr_buf for the page itself, a resolved <img src> for an inline
 * image). Accepts an optional "http://" prefix (case-insensitive), an
 * optional ":port", and an optional "/path..." - matches a plain
 * browser address bar's usual shorthand. */
static void parse_url_str(const char *p, char *host, int host_max, int *port, char *path, int path_max) {
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

/* Scans a raw tag's bytes [tag, tag+tag_len) (e.g. `<a href="x">` or
 * `<img src="y">`) for an attr_name="..."/'...'/unquoted attribute
 * value, decoding entities inline via the existing decode_entity() (so
 * href="a.html?x=1&amp;y=2" decodes the &amp; correctly - same function
 * already used for body text, pure reuse). Returns 1 if a non-empty
 * value was captured. */
static int extract_attr(const unsigned char *tag, unsigned int tag_len, const char *attr_name, char *out, int out_max) {
    int an = slen_i(attr_name);
    unsigned int i = 0;
    while (i < tag_len) {
        if (ci_starts_with(tag + i, tag_len - i, attr_name) &&
            (i == 0 || is_ws(tag[i - 1]))) {
            unsigned int j = i + (unsigned int)an;
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

static int extract_href(const unsigned char *tag, unsigned int tag_len, char *out, int out_max) {
    return extract_attr(tag, tag_len, "href", out, out_max);
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

/* True if body[i] (which points at '<') is exactly the tag `name`
 * (case-insensitive), open or close per `close`, followed by a real
 * word boundary ('>', '/', or whitespace) - not just a prefix match,
 * so e.g. "b" doesn't also match "<blockquote>". Mirrors the boundary
 * check already used for "<a" above, generalized to any tag name. */
static int tag_name_is(const unsigned char *body, unsigned int i, unsigned int body_len,
                       const char *name, int close) {
    unsigned int j = i + 1;
    if (close) {
        if (j >= body_len || body[j] != '/') return 0;
        j++;
    }
    int n = slen_i(name);
    if (!ci_starts_with(body + j, body_len - j, name)) return 0;
    unsigned int after = j + (unsigned int)n;
    if (after >= body_len) return 0;
    unsigned char c = body[after];
    return c == '>' || c == '/' || is_ws(c);
}

#define T_NONE    0   /* not specially recognized - default single newline */
#define T_HEADING 1   /* h1-h6 */
#define T_BOLD    2   /* b, strong */
#define T_EM      3   /* em, i */
#define T_LI      4   /* li */
#define T_BLOCK   5   /* p, div, blockquote */
#define T_BR      6
#define T_HR      7
#define T_SPAN    8   /* inline, no break at all */

/* Classifies a non-<a> tag at body[i] (which must point at '<').
 * Sets *out_close. Word-boundary-checked via tag_name_is() above, so
 * checking order doesn't matter - "b" can never accidentally match
 * "blockquote" etc. */
static int classify_tag(const unsigned char *body, unsigned int i, unsigned int body_len, int *out_close) {
    int close = (i + 1 < body_len && body[i + 1] == '/');
    *out_close = close;
    static const char *const headings[6] = { "h1", "h2", "h3", "h4", "h5", "h6" };
    for (int k = 0; k < 6; k++)
        if (tag_name_is(body, i, body_len, headings[k], close)) return T_HEADING;
    if (tag_name_is(body, i, body_len, "b", close) || tag_name_is(body, i, body_len, "strong", close)) return T_BOLD;
    if (tag_name_is(body, i, body_len, "em", close) || tag_name_is(body, i, body_len, "i", close)) return T_EM;
    if (tag_name_is(body, i, body_len, "li", close)) return T_LI;
    if (tag_name_is(body, i, body_len, "p", close) || tag_name_is(body, i, body_len, "div", close) ||
        tag_name_is(body, i, body_len, "blockquote", close)) return T_BLOCK;
    if (tag_name_is(body, i, body_len, "br", close)) return T_BR;
    if (tag_name_is(body, i, body_len, "hr", close)) return T_HR;
    if (tag_name_is(body, i, body_len, "span", close)) return T_SPAN;
    return T_NONE;
}

/* Ensures content_buf ends with a newline (adds one if the last byte
 * isn't already '\n', or the buffer is still empty - matches the
 * unconditional check this file used everywhere before this feature). */
static void ensure_newline(void) {
    if (content_len < CONTENT_BUF_SIZE - 1 &&
        (content_len == 0 || content_buf[content_len - 1] != '\n'))
        content_buf[content_len++] = '\n';
}

/* Ensures a full BLANK line (two consecutive newlines) - real
 * paragraph separation for block-level tags, instead of every block
 * just running into the next on its own line. Idempotent: calling it
 * repeatedly (e.g. </p><div>) never accumulates more than one blank
 * line. */
static void ensure_blank_line(void) {
    ensure_newline();
    if (content_len < CONTENT_BUF_SIZE - 1 &&
        (content_len < 2 || content_buf[content_len - 2] != '\n'))
        content_buf[content_len++] = '\n';
}

static void style_open(unsigned char kind) {
    if (style_active) return;   /* nested style tag - no-op, see styles[]'s own comment */
    style_active = 1;
    style_kind = kind;
    style_start = content_len;
}

static void style_close(unsigned char kind) {
    if (!style_active || style_kind != kind) return;   /* mismatched/no-op close */
    style_active = 0;
    if (style_count < MAX_STYLES && content_len > style_start) {
        styles[style_count].start = style_start;
        styles[style_count].len   = content_len - style_start;
        styles[style_count].kind  = kind;
        style_count++;
    }
}

/* Strips HTML tags down to plain text: TEXT / IN_TAG / SKIP_SCRIPT /
 * SKIP_STYLE. <script>/<style> CONTENTS are skipped entirely (not real
 * page text). A handful of common entities are decoded (see
 * decode_entity). <a href=...>/</a> pairs are tracked into the
 * links[] table (see that table's own comment); <b>/<strong>/<em>/
 * <i>/<h1>-<h6> into styles[] (see that table's own comment). Other
 * tags are dispatched by category (classify_tag() above): blank-line
 * block (p/div/li/blockquote/headings), single-line block (br),
 * inline/no-break (a/b/strong/em/i/span - lets these flow within a
 * paragraph's wrapped text instead of always being isolated on their
 * own line), or the default single newline for anything else
 * (unrecognized tags - preserves this file's original behavior for
 * everything not explicitly special-cased above). */
static void html_strip(const unsigned char *body, unsigned int body_len) {
    content_len = 0;
    link_count = 0;
    pending_link_active = 0;
    style_count = 0;
    style_active = 0;
    image_count = 0;
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
            /* "<img" - same word-boundary check as "<a" above (so it
             * doesn't also match a hypothetical "<imgur>" or similar). */
            int is_img = ci_starts_with(body + i, body_len - i, "<img") &&
                         (body_len - i <= 4 || is_ws(body[i + 4]) || body[i + 4] == '>' || body[i + 4] == '/');

            if (is_close_a && pending_link_active) {
                /* Closes the pending link's range at exactly content_len
                 * as of right now - <a> is inline (no break forced
                 * anywhere near this), so this is the link's true end,
                 * not an approximation. */
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

            /* <img src="..."> - queues the resolved URL for do_fetch()
             * to fetch AFTER this whole parse finishes (see
             * pending_img_urls[]'s own comment); writes a 2-byte
             * marker into content_buf so render_browser() knows where
             * to draw it once fetched. Isolated onto its own blank-
             * line-separated "paragraph", same block treatment as
             * <hr>/<p>. */
            if (is_img && image_count < MAX_IMAGES) {
                unsigned int tag_end = tag_start;
                while (tag_end < body_len && body[tag_end] != '>') tag_end++;
                char src_buf[160];
                if (extract_attr(body + tag_start, tag_end - tag_start, "src", src_buf, (int)sizeof(src_buf))) {
                    char resolved[176];
                    resolve_href(src_buf, resolved, (int)sizeof(resolved));
                    if (resolved[0]) {
                        bcopy_bounded(pending_img_urls[image_count], (int)sizeof(pending_img_urls[image_count]), resolved);
                        ensure_blank_line();
                        if (content_len + 2 < CONTENT_BUF_SIZE) {
                            content_buf[content_len++] = '\x02';
                            content_buf[content_len++] = (char)image_count;
                        }
                        ensure_blank_line();
                        image_count++;
                    }
                }
            }

            int tag_close = 0;
            int kind = T_NONE;
            if (!is_open_a && !is_close_a && !is_img) kind = classify_tag(body, tag_start, body_len, &tag_close);

            while (i < body_len && body[i] != '>') i++;
            if (i < body_len) i++;

            /* <a>/</a> are inline (no break at all - handled by the
             * separate open/close-a logic above/below); <img> is
             * handled entirely by its own block above. Everything else
             * dispatches by category; T_NONE (unrecognized tags) falls
             * back to the single-newline behavior this file always
             * had. */
            if (!is_open_a && !is_close_a && !is_img) {
                switch (kind) {
                    case T_HEADING:
                        if (!tag_close) { ensure_blank_line(); style_open(STYLE_HEADING); }
                        else            { style_close(STYLE_HEADING); ensure_blank_line(); }
                        break;
                    case T_BOLD:
                        if (!tag_close) style_open(STYLE_BOLD); else style_close(STYLE_BOLD);
                        break;
                    case T_EM:
                        if (!tag_close) style_open(STYLE_EM); else style_close(STYLE_EM);
                        break;
                    case T_LI:
                        ensure_blank_line();
                        if (!tag_close && content_len + 2 < CONTENT_BUF_SIZE) {
                            /* No bullet glyph in the 8x8 font's ASCII
                             * 0x20-0x7F range - a plain "* " is the
                             * honest substitute. */
                            content_buf[content_len++] = '*';
                            content_buf[content_len++] = ' ';
                        }
                        break;
                    case T_BLOCK:
                        ensure_blank_line();
                        break;
                    case T_BR:
                        ensure_newline();
                        break;
                    case T_HR:
                        if (content_len + 1 < CONTENT_BUF_SIZE) content_buf[content_len++] = '\x01';
                        ensure_newline();
                        break;
                    case T_SPAN:
                        break;   /* inline, no break */
                    default:
                        ensure_newline();
                        break;
                }
            }

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

#define HTTP_OK            0
#define HTTP_ERR_NO_NET    1
#define HTTP_ERR_DNS       2
#define HTTP_ERR_CONNECT   3
#define HTTP_ERR_SEND      4
#define HTTP_ERR_EMPTY     5
#define HTTP_ERR_NO_BODY   6

/* One blocking HTTP/1.0 GET for `path` on `host`:`port`, collecting the
 * full response into raw_buf. On HTTP_OK, *out_body_start/*out_total
 * mark where the body starts (right after the blank line ending the
 * headers) and the total bytes fetched. Shared by do_fetch() (the page
 * itself) and the inline-image fetch loop below - both need the exact
 * same DNS/connect/send/recv/header-skip dance, just for a different
 * host/port/path each time. Returns a specific HTTP_ERR_* so callers
 * that show it to the user (do_fetch()) can keep the same precise
 * status messages this file always had; the image loop just checks
 * for HTTP_OK/not. */
static int http_get(const char *host, int port, const char *path,
                    unsigned int *out_body_start, unsigned int *out_total) {
    unsigned char mac[6];
    if (!net_mac(mac)) return HTTP_ERR_NO_NET;

    unsigned int ip;
    int hlen = slen_i(host);
    if (is_ip_literal(host, hlen)) {
        ip = parse_ip_literal(host, hlen);
    } else if (!dns_resolve_a(host, IP4(10, 0, 2, 3), 3000, &ip)) {
        return HTTP_ERR_DNS;
    }

    static tcp_conn_t conn;
    if (!tcp_connect(&conn, ip, (unsigned short)port, 3000)) return HTTP_ERR_CONNECT;

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
        return HTTP_ERR_SEND;
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
    if (total == 0) return HTTP_ERR_EMPTY;

    /* Body starts right after the blank line ending the headers. */
    unsigned int body_start = total;
    for (unsigned int i = 0; i + 3 < total; i++) {
        if (raw_buf[i] == '\r' && raw_buf[i+1] == '\n' && raw_buf[i+2] == '\r' && raw_buf[i+3] == '\n') {
            body_start = i + 4;
            break;
        }
    }
    if (body_start >= total) return HTTP_ERR_NO_BODY;

    *out_body_start = body_start;
    *out_total = total;
    return HTTP_OK;
}

static void do_fetch(window_t *win) {
    if (addr_len == 0) return;

    /* No TLS stack anywhere in this codebase - catch this BEFORE
     * parse_url_str() mangles the "https://" prefix into garbage
     * hostname text (it only strips a literal 7-char "http://", so an
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
    parse_url_str(addr_buf, host, sizeof(host), &port, path, sizeof(path));
    bcopy_bounded(g_host, (int)sizeof(g_host), host);
    g_port = port;
    bcopy_bounded(g_path, (int)sizeof(g_path), path);

    unsigned int body_start, total;
    int err = http_get(host, port, path, &body_start, &total);
    if (err != HTTP_OK) {
        switch (err) {
            case HTTP_ERR_NO_NET:  set_status("No network device found"); break;
            case HTTP_ERR_DNS:     set_status("DNS resolve failed"); break;
            case HTTP_ERR_CONNECT: set_status("Connection failed"); break;
            case HTTP_ERR_SEND:    set_status("Request send failed"); break;
            case HTTP_ERR_EMPTY:   set_status("Empty response"); break;
            default:               set_status("No response body"); break;
        }
        return;
    }

    html_strip(raw_buf + body_start, total - body_start);

    /* One more blocking fetch per <img> found (see html_strip()'s
     * pending_img_urls[]) - deliberately sequential and AFTER the page
     * itself is fully parsed, reusing the same raw_buf/http_get() as
     * the page fetch (its content is no longer needed once html_strip()
     * has consumed it into content_buf/links[]/styles[]). A failed
     * fetch or a non-BMP/oversized image just leaves image_ok[k]==0 -
     * render_browser() skips drawing that slot, doesn't error the
     * whole page. */
    for (int k = 0; k < image_count; k++) {
        char ihost[64]; int iport; char ipath[160];
        parse_url_str(pending_img_urls[k], ihost, sizeof(ihost), &iport, ipath, sizeof(ipath));
        unsigned int ibody, itotal;
        image_ok[k] = (http_get(ihost, iport, ipath, &ibody, &itotal) == HTTP_OK) &&
                      bmp_decode_mem(raw_buf + ibody, itotal - ibody, &page_images[k]);
    }

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

/* Same lookup as find_link_at(), for styles[] - *out_kind is only
 * meaningful when the return value is >= 0. */
static int find_style_at(unsigned int idx, unsigned char *out_kind) {
    for (int k = 0; k < style_count; k++)
        if (idx >= styles[k].start && idx < styles[k].start + styles[k].len) {
            *out_kind = styles[k].kind;
            return k;
        }
    return -1;
}

/* Per-character color/weight: link color always wins over inherited
 * emphasis (matches how a real browser's link color usually overrides
 * surrounding bold/italic text). "bold" here means "draw twice, 1px
 * offset" - the fixed 8x8@2x bitmap font has no real bold glyph or
 * size variation, so this is an honest, cheap approximation, not
 * actual bold. Italic gets a distinct tint instead, for the same
 * reason (no way to slant a bitmap glyph). */
static void char_style(unsigned int idx, unsigned int *color, int *bold) {
    if (find_link_at(idx) >= 0) { *color = gfx_rgb(120, 170, 255); *bold = 0; return; }
    unsigned char kind;
    int k = find_style_at(idx, &kind);
    if (k >= 0 && kind == STYLE_HEADING) { *color = gfx_rgb(255, 255, 255); *bold = 1; return; }
    if (k >= 0 && kind == STYLE_BOLD)    { *color = gfx_rgb(200, 200, 200); *bold = 1; return; }
    if (k >= 0 && kind == STYLE_EM)      { *color = gfx_rgb(255, 220, 120); *bold = 0; return; }
    *color = gfx_rgb(200, 200, 200); *bold = 0;
}

/* Draws one already-wrapped row in per-character-styled runs instead
 * of a single gfx_draw_text() call - needed because inline tags
 * (<a>/<b>/<em>/...) no longer force their own line (see html_strip()),
 * so a single row can now mix plain text with a link or emphasis run.
 * Groups consecutive same-(color,bold) characters into one draw call
 * each, same "one syscall per contiguous run, not per pixel/char"
 * cost discipline as gfx_ui.h's ui_vgrad(). */
static void draw_styled_row(unsigned int x, unsigned int y, const char *text, int len, unsigned int row_start) {
    int start = 0;
    while (start < len) {
        unsigned int color; int bold;
        char_style(row_start + (unsigned int)start, &color, &bold);

        int end = start + 1;
        while (end < len) {
            unsigned int c2; int b2;
            char_style(row_start + (unsigned int)end, &c2, &b2);
            if (c2 != color || b2 != bold) break;
            end++;
        }

        char seg[128];
        int seg_len = end - start;
        if (seg_len > 127) seg_len = 127;
        for (int k = 0; k < seg_len; k++) seg[k] = text[start + k];
        seg[seg_len] = '\0';

        unsigned int seg_x = x + (unsigned int)start * ROW_H;
        gfx_draw_text(seg_x, y, seg, color);
        if (bold) gfx_draw_text(seg_x + 1, y, seg, color);

        start = end;
    }
}

/* How many ROW_H-tall line-units this already-wrapped row occupies:
 * always 1, except a valid decoded <img> marker (see html_strip()'s
 * '\x02' case), which needs ceil(image height / ROW_H). A failed/
 * undecoded image (image_ok[slot]==0 - fetch failed, wrong format,
 * bigger than BMP_MAX_W/H) collapses to a single blank row rather than
 * some indeterminate size - render_browser() just won't draw anything
 * there. Called BEFORE knowing whether this row actually fits in the
 * remaining visible viewport, so it must not touch drawing state. */
static int content_row_height(const char *linebuf, int col) {
    if (col == 2 && linebuf[0] == '\x02') {
        int slot = (int)(unsigned char)linebuf[1];
        if (slot >= 0 && slot < MAX_IMAGES && image_ok[slot]) {
            int h = (int)((page_images[slot].height + ROW_H - 1) / ROW_H);
            return h > 0 ? h : 1;
        }
    }
    return 1;
}

/* Draws one already-wrapped row: a horizontal rule for the <hr>
 * sentinel byte (html_strip()'s T_HR case), a decoded image for the
 * <img> marker pair (html_strip()'s is_img case - per-pixel
 * gfx_putpixel() loop, same cost/reasoning as bmp.h's own bmp_draw()),
 * or a normal styled text row otherwise. Shared by both draw sites in
 * the wrap loop below so these special cases only need to live once. */
static void draw_content_row(const window_t *win, const char *linebuf, int col,
                             unsigned int y, unsigned int row_start) {
    if (col == 1 && linebuf[0] == '\x01') {
        gfx_fill_rect(win->x + PAD, y + ROW_H / 2, win->w - 2 * PAD, 1, gfx_rgb(120, 120, 120));
        return;
    }
    if (col == 2 && linebuf[0] == '\x02') {
        int slot = (int)(unsigned char)linebuf[1];
        if (slot >= 0 && slot < MAX_IMAGES && image_ok[slot]) {
            const bmp_image_t *img = &page_images[slot];
            for (unsigned int dy = 0; dy < img->height; dy++)
                for (unsigned int dx = 0; dx < img->width; dx++)
                    gfx_putpixel(win->x + PAD + dx, y + dy, img->pixels[dy * img->width + dx]);
        }
        return;
    }
    draw_styled_row(win->x + PAD, y, linebuf, col, row_start);
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
            if (line >= scroll_offset) {
                unsigned int row_start = i - (unsigned int)col;
                int row_h = content_row_height(linebuf, col);
                /* Only actually draws if the WHOLE row (1 line-unit for
                 * text/hr, several for a tall image) fits in what's left
                 * of the viewport - avoids partial-image-clipping math;
                 * see this file's own comment on content_row_height(). */
                if (drawn + row_h <= visible_rows)
                    draw_content_row(win, linebuf, col, text_y0 + (unsigned int)drawn * ROW_H, row_start);
                for (int rr = 0; rr < row_h && drawn + rr < visible_rows && drawn + rr < MAX_VISIBLE_ROWS; rr++)
                    row_start_idx[drawn + rr] = (int)row_start;
                int filled = row_h;
                if (drawn + filled > visible_rows) filled = visible_rows - drawn;
                if (filled > 0 && drawn + filled > row_count) row_count = drawn + filled;
                drawn += row_h;
            }
            line++; col = 0;
            continue;
        }
        if (is_newline || is_end) {
            linebuf[col] = '\0';
            if (col > 0 && line >= scroll_offset) {
                unsigned int row_start = i - (unsigned int)col;
                int row_h = content_row_height(linebuf, col);
                if (drawn + row_h <= visible_rows)
                    draw_content_row(win, linebuf, col, text_y0 + (unsigned int)drawn * ROW_H, row_start);
                for (int rr = 0; rr < row_h && drawn + rr < visible_rows && drawn + rr < MAX_VISIBLE_ROWS; rr++)
                    row_start_idx[drawn + rr] = (int)row_start;
                int filled = row_h;
                if (drawn + filled > visible_rows) filled = visible_rows - drawn;
                if (filled > 0 && drawn + filled > row_count) row_count = drawn + filled;
                drawn += row_h;
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
