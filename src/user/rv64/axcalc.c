#include "syscall.h"
#include "window.h"
#include "malloc.h"

/* AxCalc — calculator with arbitrary-precision decimal arithmetic
 * (not IEEE 754 - this freestanding build never initializes the FPU,
 * and this isn't fixed-width binary float either: every value is a
 * heap-allocated decimal digit string of whatever length it needs).
 * Sequential-evaluation four-function calculator (2+3*4=20, not 14 -
 * same rule a real basic calculator uses, no operator precedence).
 *
 * Reuses this platform's EXISTING malloc()/free() (malloc.h, already
 * proven by mtetest.c/malloctest.c) as-is - no new allocator needed
 * here, unlike x86's port of this same feature (gfx_shell.c has no
 * heap linked in at all, so it grows its own small arena allocator).
 * RISC-V's real limit: the whole per-process address slot is only
 * 64KB (code+data+stack+heap share it, see kernel.c's
 * USER_PROGRAM_SLOT_SIZE) - malloc() returning NULL on exhaustion is
 * handled by falling into the same "Error" state division-by-zero
 * already uses, not a crash. */

#define ROW_H 16   /* gfx_draw_text's fixed 16px/char advance, see syscall.h */
#define FRAC_DIGITS 20   /* every result's fractional part is capped/rounded to this many digits */

typedef struct {
    char *digits;   /* heap-allocated, MOST-significant digit first (natural
                     * reading/typing order - no reversal needed anywhere) */
    int   len;
    int   scale;    /* trailing `len` digits after the decimal point; 0 = integer.
                     * Invariant maintained everywhere: len >= scale >= 0. */
    int   sign;     /* 0 or 1; canonical zero is always sign=0 */
} bignum_t;

static bignum_t bignum_from_digit(int d) {
    bignum_t n;
    n.digits = (char *)malloc(1);
    n.len = 1;
    n.scale = 0;
    n.sign = 0;
    if (n.digits) n.digits[0] = (char)d;
    return n;
}

static void bignum_free(bignum_t *n) {
    if (n->digits) free(n->digits);
    n->digits = 0;
}

/* Returns 1 on OOM (digits left null). */
static int bignum_alloc(bignum_t *n, int len) {
    n->digits = (char *)malloc((unsigned int)len);
    n->len = len;
    return n->digits == 0;
}

static int bignum_copy(const bignum_t *src, bignum_t *out) {
    if (bignum_alloc(out, src->len)) return 1;
    for (int i = 0; i < src->len; i++) out->digits[i] = src->digits[i];
    out->scale = src->scale;
    out->sign = src->sign;
    return 0;
}

static int bignum_is_zero(const bignum_t *n) {
    for (int i = 0; i < n->len; i++) if (n->digits[i] != 0) return 0;
    return 1;
}

/* Trims leading zero digits (down to one integer digit minimum), and
 * re-canonicalizes sign=0 for zero. In-place, never reallocates
 * (shrinks len only - the extra allocated bytes just go unused). */
static void bignum_trim(bignum_t *n) {
    int min_len = n->scale + 1;
    int i = 0;
    while (n->len - i > min_len && n->digits[i] == 0) i++;
    if (i > 0) {
        for (int j = i; j < n->len; j++) n->digits[j - i] = n->digits[j];
        n->len -= i;
    }
    if (bignum_is_zero(n)) n->sign = 0;
}

/* Produces two new heap copies of a/b, both at scale=max(a.scale,b.scale)
 * and equal integer-part length (leading-zero-padded) - the one place
 * scale-alignment logic lives; add/sub/div's magnitude-compare all
 * build on this. Returns 1 on OOM (nothing left allocated in that case). */
static int bignum_align(const bignum_t *a, const bignum_t *b, bignum_t *pa, bignum_t *pb) {
    int scale = a->scale > b->scale ? a->scale : b->scale;
    int a_int = a->len - a->scale;
    int b_int = b->len - b->scale;
    int int_len = a_int > b_int ? a_int : b_int;
    int total = int_len + scale;

    if (bignum_alloc(pa, total)) return 1;
    if (bignum_alloc(pb, total)) { bignum_free(pa); return 1; }

    int p = 0;
    for (int i = 0; i < int_len - a_int; i++) pa->digits[p++] = 0;
    for (int i = 0; i < a->len; i++) pa->digits[p++] = a->digits[i];
    for (int i = 0; i < scale - a->scale; i++) pa->digits[p++] = 0;
    pa->scale = scale;
    pa->sign = a->sign;

    p = 0;
    for (int i = 0; i < int_len - b_int; i++) pb->digits[p++] = 0;
    for (int i = 0; i < b->len; i++) pb->digits[p++] = b->digits[i];
    for (int i = 0; i < scale - b->scale; i++) pb->digits[p++] = 0;
    pb->scale = scale;
    pb->sign = b->sign;

    return 0;
}

/* Assumes a->len == b->len (already aligned). Ignores sign. */
static int bignum_cmp_abs(const bignum_t *a, const bignum_t *b) {
    for (int i = 0; i < a->len; i++)
        if (a->digits[i] != b->digits[i]) return a->digits[i] > b->digits[i] ? 1 : -1;
    return 0;
}

/* a+b magnitude, assumes a->len == b->len. out gets len+1 digits. */
static int bignum_add_abs(const bignum_t *a, const bignum_t *b, bignum_t *out) {
    int n = a->len;
    if (bignum_alloc(out, n + 1)) return 1;
    int carry = 0;
    for (int i = 0; i < n; i++) {
        int sum = a->digits[n - 1 - i] + b->digits[n - 1 - i] + carry;
        carry = sum / 10;
        out->digits[n - i] = (char)(sum % 10);
    }
    out->digits[0] = (char)carry;
    out->scale = a->scale;
    return 0;
}

/* a-b magnitude, assumes a->len == b->len and |a|>=|b|. */
static int bignum_sub_abs(const bignum_t *a, const bignum_t *b, bignum_t *out) {
    int n = a->len;
    if (bignum_alloc(out, n)) return 1;
    int borrow = 0;
    for (int i = 0; i < n; i++) {
        int idx = n - 1 - i;
        int d = a->digits[idx] - b->digits[idx] - borrow;
        if (d < 0) { d += 10; borrow = 1; } else borrow = 0;
        out->digits[idx] = (char)d;
    }
    out->scale = a->scale;
    return 0;
}

/* Returns 1 on OOM. */
static int bignum_add(const bignum_t *a, const bignum_t *b, bignum_t *out) {
    bignum_t pa, pb;
    if (bignum_align(a, b, &pa, &pb)) return 1;
    int fail;
    if (a->sign == b->sign) {
        fail = bignum_add_abs(&pa, &pb, out);
        out->sign = a->sign;
    } else {
        int cmp = bignum_cmp_abs(&pa, &pb);
        if (cmp >= 0) { fail = bignum_sub_abs(&pa, &pb, out); out->sign = a->sign; }
        else          { fail = bignum_sub_abs(&pb, &pa, out); out->sign = b->sign; }
    }
    bignum_free(&pa);
    bignum_free(&pb);
    if (fail) return 1;
    bignum_trim(out);
    return 0;
}

static int bignum_sub(const bignum_t *a, const bignum_t *b, bignum_t *out) {
    bignum_t neg_b = *b;
    neg_b.sign = b->sign ? 0 : 1;
    if (bignum_is_zero(b)) neg_b.sign = 0;
    return bignum_add(a, &neg_b, out);
}

static int bignum_mul(const bignum_t *a, const bignum_t *b, bignum_t *out) {
    int n = a->len, m = b->len;
    int total_len = n + m;
    char *tmp = (char *)malloc((unsigned int)total_len);
    if (!tmp) return 1;
    for (int i = 0; i < total_len; i++) tmp[i] = 0;

    for (int i = n - 1; i >= 0; i--) {
        int carry = 0;
        for (int j = m - 1; j >= 0; j--) {
            int pos = i + j + 1;
            int prod = a->digits[i] * b->digits[j] + tmp[pos] + carry;
            tmp[pos] = (char)(prod % 10);
            carry = prod / 10;
        }
        int pos = i;
        while (carry && pos >= 0) {
            int sum = tmp[pos] + carry;
            tmp[pos] = (char)(sum % 10);
            carry = sum / 10;
            pos--;
        }
    }

    out->digits = tmp;
    out->len = total_len;
    out->scale = a->scale + b->scale;
    out->sign = (a->sign != b->sign) ? 1 : 0;

    if (out->scale > FRAC_DIGITS) {
        out->len -= (out->scale - FRAC_DIGITS);
        out->scale = FRAC_DIGITS;
    }
    bignum_trim(out);
    return 0;
}

static void strip_leading_zeros_arr(char *d, int *len) {
    int i = 0;
    while (*len - i > 1 && d[i] == 0) i++;
    if (i > 0) {
        for (int k = i; k < *len; k++) d[k - i] = d[k];
        *len -= i;
    }
}

/* Returns 0 ok, 1 OOM, 2 division by zero. Produces exactly FRAC_DIGITS
 * fractional digits via schoolbook long division: after aligning a/b to
 * the same scale (which makes their digit arrays plain equal-scaled
 * integers - a/b's true ratio is unaffected since both were scaled by
 * the same factor), run long division for (integer digit count) +
 * FRAC_DIGITS steps - the first phase consumes the dividend's real
 * digits, the second phase "brings down" implicit zeros, which is
 * exactly what extends the quotient into FRAC_DIGITS fractional places.
 * Each digit found via repeated trial subtraction (max 9 tries/step) -
 * simple, safe, plenty fast for a calculator's realistic inputs. */
static int bignum_div(const bignum_t *a, const bignum_t *b, bignum_t *out) {
    if (bignum_is_zero(b)) return 2;

    bignum_t pa, pb;
    if (bignum_align(a, b, &pa, &pb)) return 1;
    /* pb may carry leading-zero padding from alignment - strip it so
     * magnitude comparisons against the running remainder are valid
     * (comparing by length is only correct once both sides are
     * canonical, no leading zeros). */
    strip_leading_zeros_arr(pb.digits, &pb.len);

    int qlen = pa.len + FRAC_DIGITS;
    char *q = (char *)malloc((unsigned int)qlen);
    if (!q) { bignum_free(&pa); bignum_free(&pb); return 1; }

    int rem_cap = pb.len + 1;
    char *rem = (char *)malloc((unsigned int)rem_cap);
    if (!rem) { free(q); bignum_free(&pa); bignum_free(&pb); return 1; }
    int rem_len = 0;

    int total_steps = pa.len + FRAC_DIGITS;
    for (int step = 0; step < total_steps; step++) {
        int next_digit = (step < pa.len) ? pa.digits[step] : 0;

        if (rem_len < rem_cap) {
            rem[rem_len++] = (char)next_digit;
        } else {
            for (int k = 1; k < rem_len; k++) rem[k - 1] = rem[k];
            rem[rem_len - 1] = (char)next_digit;
        }
        strip_leading_zeros_arr(rem, &rem_len);

        int qd = 0;
        for (;;) {
            int cmp;
            if (rem_len != pb.len) cmp = (rem_len > pb.len) ? 1 : -1;
            else {
                cmp = 0;
                for (int k = 0; k < rem_len; k++)
                    if (rem[k] != pb.digits[k]) { cmp = (rem[k] > pb.digits[k]) ? 1 : -1; break; }
            }
            if (cmp < 0) break;

            int borrow = 0;
            int shift = rem_len - pb.len;
            for (int k = rem_len - 1; k >= 0; k--) {
                int bdig = (k < shift) ? 0 : pb.digits[k - shift];
                int d = rem[k] - bdig - borrow;
                if (d < 0) { d += 10; borrow = 1; } else borrow = 0;
                rem[k] = (char)d;
            }
            strip_leading_zeros_arr(rem, &rem_len);
            qd++;
        }
        q[step] = (char)qd;
    }

    free(rem);
    bignum_free(&pa);
    bignum_free(&pb);

    out->digits = q;
    out->len = qlen;
    out->scale = FRAC_DIGITS;
    out->sign = (a->sign != b->sign) ? 1 : 0;
    bignum_trim(out);
    return 0;
}

/* Returns 0 ok, 1 OOM, 2 division by zero. */
static int calc_do_op(const bignum_t *a, char op, const bignum_t *b, bignum_t *out) {
    switch (op) {
        case '+': return bignum_add(a, b, out);
        case '-': return bignum_sub(a, b, out);
        case '*': return bignum_mul(a, b, out);
        case '/': return bignum_div(a, b, out);
    }
    return 1;
}

/* Percent's "/100" is an exact decimal-point shift, not a division -
 * prepend two zero digits and bump scale by 2, then let the existing
 * bignum_trim() clean up any now-redundant leading zeros. O(n), exact
 * (no rounding, unlike routing this through bignum_div which would
 * force the result to exactly FRAC_DIGITS scale). Returns 1 on OOM. */
static int bignum_div100(const bignum_t *a, bignum_t *out) {
    if (bignum_alloc(out, a->len + 2)) return 1;
    out->digits[0] = 0;
    out->digits[1] = 0;
    for (int i = 0; i < a->len; i++) out->digits[2 + i] = a->digits[i];
    out->scale = a->scale + 2;
    out->sign = a->sign;
    bignum_trim(out);
    return 0;
}

/* Newton-Raphson square root using only the existing add/div - no new
 * low-level primitive needed. Returns 0 ok, 1 OOM, 2 negative input
 * (no real square root). x0 = a+1 is always >= the true root, so the
 * iteration converges monotonically from above regardless of a's
 * magnitude. 60 fixed iterations is a generous constant - quadratic
 * convergence means this is far more than enough for any realistically
 * hand-typed input, matching bignum_div's own "simple, safe, plenty
 * fast" trial-subtraction approach. */
static int calc_sqrt(const bignum_t *a, bignum_t *out) {
    if (a->sign) return 2;
    if (bignum_is_zero(a)) { *out = bignum_from_digit(0); return out->digits ? 0 : 1; }

    bignum_t one = bignum_from_digit(1);
    bignum_t x;
    int fail = bignum_add(a, &one, &x);
    bignum_free(&one);
    if (fail) return 1;

    bignum_t two = bignum_from_digit(2);
    for (int i = 0; i < 60; i++) {
        bignum_t q;
        if (bignum_div(a, &x, &q)) { bignum_free(&x); bignum_free(&two); return 1; }
        bignum_t s;
        fail = bignum_add(&x, &q, &s);
        bignum_free(&q);
        if (fail) { bignum_free(&x); bignum_free(&two); return 1; }
        bignum_t nx;
        fail = bignum_div(&s, &two, &nx);
        bignum_free(&s);
        if (fail) { bignum_free(&x); bignum_free(&two); return 1; }
        bignum_free(&x);
        x = nx;
    }
    bignum_free(&two);
    *out = x;
    return 0;
}

static bignum_t calc_acc;
static bignum_t calc_cur;
static bignum_t calc_memory;
static int  calc_has_digits = 0;
static char calc_pending_op = 0;
static int  calc_error = 0;

/* 4 cols x 6 rows: row0 = scientific (%, sqrt, MR, MC), rows 1-4 are
 * the original 4x4 digit/operator grid unchanged, row5 = M+/M- centered
 * with the outer two cells blank. '\0' is the blank-cell sentinel. */
static const char calc_btn_keys[24] = {
    '%', 's', 'r', 'k',
    '7', '8', '9', '/',
    '4', '5', '6', '*',
    '1', '2', '3', '-',
    'C', '0', '=', '+',
     0 , 'p', 'n',  0 ,
};

static void calc_press(char key) {
    if (key >= '0' && key <= '9') {
        if (calc_error) {
            calc_error = 0;
            bignum_free(&calc_cur);
            calc_cur = bignum_from_digit(0);
            calc_has_digits = 0;
        }
        int d = key - '0';
        char *nd = (char *)malloc((unsigned int)(calc_cur.len + 1));
        if (!nd) { calc_error = 1; return; }
        for (int i = 0; i < calc_cur.len; i++) nd[i] = calc_cur.digits[i];
        nd[calc_cur.len] = (char)d;
        free(calc_cur.digits);
        calc_cur.digits = nd;
        calc_cur.len++;
        if (calc_cur.len == 2 && calc_cur.digits[0] == 0) {
            calc_cur.digits[0] = calc_cur.digits[1];
            calc_cur.len = 1;
        }
        calc_has_digits = 1;
        return;
    }
    if (key == 'C') {
        bignum_free(&calc_acc); calc_acc = bignum_from_digit(0);
        bignum_free(&calc_cur); calc_cur = bignum_from_digit(0);
        calc_has_digits = 0;
        calc_pending_op = 0;
        calc_error = 0;
        return;
    }
    if (calc_error) return;
    if (key == 'p' || key == 'n') {   /* M+ / M- */
        const bignum_t *cur_val = calc_has_digits ? &calc_cur : &calc_acc;
        bignum_t result;
        int fail = (key == 'p') ? bignum_add(&calc_memory, cur_val, &result)
                                 : bignum_sub(&calc_memory, cur_val, &result);
        if (fail) { calc_error = 1; return; }
        bignum_free(&calc_memory);
        calc_memory = result;
        return;
    }
    if (key == 'r') {   /* MR */
        bignum_t copy;
        if (bignum_copy(&calc_memory, &copy)) { calc_error = 1; return; }
        bignum_free(&calc_cur);
        calc_cur = copy;
        calc_has_digits = 1;
        return;
    }
    if (key == 'k') {   /* MC */
        bignum_free(&calc_memory);
        calc_memory = bignum_from_digit(0);
        return;
    }
    if (key == '%') {
        const bignum_t *cur_val = calc_has_digits ? &calc_cur : &calc_acc;
        bignum_t result;
        int fail;
        if (calc_pending_op && calc_has_digits) {
            bignum_t prod;
            fail = bignum_mul(&calc_acc, &calc_cur, &prod);
            if (!fail) { fail = bignum_div100(&prod, &result); bignum_free(&prod); }
        } else {
            fail = bignum_div100(cur_val, &result);
        }
        if (fail) { calc_error = 1; return; }
        if (calc_has_digits) { bignum_free(&calc_cur); calc_cur = result; }
        else                 { bignum_free(&calc_acc); calc_acc = result; }
        return;
    }
    if (key == 's') {   /* sqrt */
        const bignum_t *cur_val = calc_has_digits ? &calc_cur : &calc_acc;
        bignum_t result;
        int fail = calc_sqrt(cur_val, &result);
        if (fail) { calc_error = 1; return; }
        if (calc_has_digits) { bignum_free(&calc_cur); calc_cur = result; }
        else                 { bignum_free(&calc_acc); calc_acc = result; }
        return;
    }
    if (key == '=') {
        if (calc_pending_op) {
            const bignum_t *b = calc_has_digits ? &calc_cur : &calc_acc;
            bignum_t result;
            int fail = calc_do_op(&calc_acc, calc_pending_op, b, &result);
            if (fail) { calc_error = 1; return; }
            bignum_free(&calc_acc);
            calc_acc = result;
            calc_pending_op = 0;
            calc_has_digits = 0;
        }
        return;
    }
    /* Operator key (+ - * /) */
    if (calc_pending_op && calc_has_digits) {
        bignum_t result;
        int fail = calc_do_op(&calc_acc, calc_pending_op, &calc_cur, &result);
        if (fail) { calc_error = 1; return; }
        bignum_free(&calc_acc);
        calc_acc = result;
    } else if (!calc_pending_op && calc_has_digits) {
        bignum_t copy;
        if (bignum_copy(&calc_cur, &copy)) { calc_error = 1; return; }
        bignum_free(&calc_acc);
        calc_acc = copy;
    }
    calc_pending_op = key;
    bignum_free(&calc_cur);
    calc_cur = bignum_from_digit(0);
    calc_has_digits = 0;
}

static const bignum_t *calc_display(void) { return calc_has_digits ? &calc_cur : &calc_acc; }

/* Writes up to bufcap-1 chars of n's decimal representation (sign +
 * integer part, or a synthetic leading '0' if the integer part is
 * empty, + '.' + fractional digits) into buf, null-terminated.
 * Returns the chars actually written (<=bufcap-1) - callers compare
 * against bignum_display_len() to know if this was truncated. */
static int bignum_to_str(const bignum_t *n, char *buf, int bufcap) {
    int p = 0;
    if (n->sign && p < bufcap - 1) buf[p++] = '-';
    int int_len = n->len - n->scale;
    if (int_len == 0) {
        if (p < bufcap - 1) buf[p++] = '0';
    } else {
        for (int i = 0; i < int_len && p < bufcap - 1; i++)
            buf[p++] = (char)('0' + n->digits[i]);
    }
    if (n->scale > 0 && p < bufcap - 1) {
        buf[p++] = '.';
        for (int i = int_len; i < n->len && p < bufcap - 1; i++)
            buf[p++] = (char)('0' + n->digits[i]);
    }
    buf[p] = '\0';
    return p;
}

/* Full logical display length (sign + int part-or-"0" + '.' + frac),
 * without materializing the (potentially huge) string. */
static int bignum_display_len(const bignum_t *n) {
    int int_len = n->len - n->scale;
    int total = (n->sign ? 1 : 0) + (int_len == 0 ? 1 : int_len);
    if (n->scale > 0) total += 1 + n->scale;
    return total;
}

static int udigits(unsigned int v) {
    int n = 1;
    while (v >= 10) { v /= 10; n++; }
    return n;
}

/* Fills buf with key's button label and returns its length - most keys
 * are still a single char, but the new scientific/memory keys need
 * multi-char labels ("sqrt", "MR", "MC", "M+", "M-"). */
static int calc_key_label(char key, char *buf) {
    switch (key) {
        case 's': buf[0]='s'; buf[1]='q'; buf[2]='r'; buf[3]='t'; buf[4]=0; return 4;
        case 'r': buf[0]='M'; buf[1]='R'; buf[2]=0; return 2;
        case 'k': buf[0]='M'; buf[1]='C'; buf[2]=0; return 2;
        case 'p': buf[0]='M'; buf[1]='+'; buf[2]=0; return 2;
        case 'n': buf[0]='M'; buf[1]='-'; buf[2]=0; return 2;
        default:  buf[0]=key; buf[1]=0; return 1;
    }
}

#define CALC_PAD       8
#define CALC_DISP_LINES 6
#define CALC_GRID_ROWS 6
#define CALC_GRID_COLS 4

static void calc_layout(const window_t *win, unsigned int *grid_x0, unsigned int *grid_y0,
                         unsigned int *btn_sz, unsigned int *text_x0, unsigned int *text_y0,
                         int *cols_per_line) {
    int avail_w = (int)win->w - 4 - 2*CALC_PAD;
    *text_x0 = win->x + 2 + CALC_PAD;
    *text_y0 = win->content_y + CALC_PAD;
    *cols_per_line = avail_w / ROW_H;
    if (*cols_per_line < 1) *cols_per_line = 1;

    *grid_y0 = *text_y0 + CALC_DISP_LINES*ROW_H + 6;
    int avail_h = (int)(win->content_y + win->content_h) - (int)*grid_y0 - CALC_PAD;
    int sz = avail_w / CALC_GRID_COLS;
    int sz_h = avail_h / CALC_GRID_ROWS;
    if (sz_h < sz) sz = sz_h;
    if (sz < 8) sz = 8;
    *btn_sz = (unsigned int)sz;
    *grid_x0 = win->x + 2 + CALC_PAD;
}

static void render_calc(const window_t *win) {
    gfx_fill_rect(win->x + 2, win->content_y, win->w - 4, win->content_h, win->bg);

    unsigned int grid_x0, grid_y0, btn_sz, text_x0, text_y0;
    int cols_per_line;
    calc_layout(win, &grid_x0, &grid_y0, &btn_sz, &text_x0, &text_y0, &cols_per_line);

    if (calc_error) {
        window_draw_text_clipped(win, text_x0, text_y0, "Error", gfx_rgb(255, 80, 80));
    } else {
        const bignum_t *v = calc_display();
        int total = bignum_display_len(v);
        int cap = cols_per_line * CALC_DISP_LINES;
        int shown_cap = (total < cap ? total : cap) + 1;
        char buf[6*16 + 8];   /* generous: matches CALC_DISP_LINES * a reasonable max cols_per_line */
        if (shown_cap > (int)sizeof(buf)) shown_cap = sizeof(buf);
        int shown = bignum_to_str(v, buf, shown_cap);

        int pos = 0, line = 0;
        while (pos < shown && line < CALC_DISP_LINES) {
            char linebuf[32];
            int n = shown - pos;
            if (n > cols_per_line) n = cols_per_line;
            if (n > (int)sizeof(linebuf) - 1) n = sizeof(linebuf) - 1;
            for (int i = 0; i < n; i++) linebuf[i] = buf[pos + i];
            linebuf[n] = '\0';
            gfx_draw_text(text_x0, text_y0 + (unsigned int)line*ROW_H, linebuf, gfx_rgb(80, 255, 80));
            pos += n;
            line++;
        }
        if (total > shown && line <= CALC_DISP_LINES) {
            char more[24];
            int more_n = total - shown;
            int p = 0;
            more[p++] = '(';
            int md = udigits((unsigned int)more_n);
            for (int i = md - 1; i >= 0; i--) { more[1+i] = (char)('0' + more_n % 10); more_n /= 10; }
            p += md;
            const char *suf = " more)";
            for (int i = 0; suf[i]; i++) more[p++] = suf[i];
            more[p] = '\0';
            gfx_draw_text(text_x0, text_y0 + (unsigned int)(line < CALC_DISP_LINES ? line : CALC_DISP_LINES-1)*ROW_H,
                         more, gfx_rgb(200, 200, 0));
        }
    }

    for (unsigned int row = 0; row < CALC_GRID_ROWS; row++) {
        for (unsigned int col = 0; col < CALC_GRID_COLS; col++) {
            char key = calc_btn_keys[row*CALC_GRID_COLS+col];
            if (key == 0) continue;
            unsigned int bx = grid_x0 + col*btn_sz;
            unsigned int by = grid_y0 + row*btn_sz;
            unsigned int bg = (key == '=') ? gfx_rgb(0, 170, 0) :
                              (key == 'C') ? gfx_rgb(170, 0, 0) :
                              (key=='+'||key=='-'||key=='*'||key=='/') ? gfx_rgb(0, 0, 170) :
                              (key=='%'||key=='s'||key=='r'||key=='k'||key=='p'||key=='n') ? gfx_rgb(110, 60, 150) :
                              gfx_rgb(20, 30, 45);
            gfx_fill_rect(bx+2, by+2, btn_sz-4, btn_sz-4, bg);
            char lbl[6];
            int llen = calc_key_label(key, lbl);
            gfx_draw_text(bx + btn_sz/2 - (unsigned int)(llen*ROW_H)/2, by + btn_sz/2 - ROW_H/2, lbl, gfx_rgb(255, 255, 255));
        }
    }
}

/* Returns 1 if the click changed something worth re-rendering. */
static int handle_content_click(const window_t *win, unsigned int mx, unsigned int my) {
    unsigned int grid_x0, grid_y0, btn_sz, text_x0, text_y0;
    int cols_per_line;
    calc_layout(win, &grid_x0, &grid_y0, &btn_sz, &text_x0, &text_y0, &cols_per_line);

    if (mx < grid_x0 || my < grid_y0) return 0;
    unsigned int col = (mx - grid_x0) / btn_sz;
    unsigned int row = (my - grid_y0) / btn_sz;
    if (col >= CALC_GRID_COLS || row >= CALC_GRID_ROWS) return 0;
    char key = calc_btn_keys[row*CALC_GRID_COLS+col];
    if (key == 0) return 0;
    calc_press(key);
    return 1;
}

int main(void) {
    unsigned int screen_w = 800, screen_h = 600;
    gfx_info(&screen_w, &screen_h);

    calc_acc = bignum_from_digit(0);
    calc_cur = bignum_from_digit(0);
    calc_memory = bignum_from_digit(0);

    window_t win;
    /* min_w/min_h pinned to the CURRENT default size - AxCalc's grid
     * already sits close to the edge of fitting its widest labels
     * ("sqrt"/"MR"/"MC", 4 chars * ROW_H=16px = 64px) at this size;
     * shrinking either dimension further makes btn_sz drop below that
     * and the labels visibly bleed into the next button - found live
     * via screendump. So AxCalc's resize is effectively grow-only in
     * practice (still genuinely useful - bigger buttons on request),
     * not a hidden bug, a deliberate floor. */
    window_init(&win, 380, 60, 260, 520, 260, 520, gfx_rgb(255, 210, 0), gfx_rgb(10, 15, 25),
               "AxCalc");

    render_calc(&win);
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
                if (handle_content_click(&win, mx, my)) render_calc(&win);
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
                window_redraw_chrome(&win, "AxCalc");
                render_calc(&win);
            } else if (resizing && !left) {
                resizing = 0;
                window_redraw_chrome(&win, "AxCalc");
                render_calc(&win);
            }
            prev_left = left;
        }

        int c;
        while ((c = kbd_getc()) >= 0) {
            /* Unlike x86's PS/2 demo, this driver DOES track shift (see
             * virtio_keyboard.c's shift_ch()), so both numpad-plus and
             * shift-equals already arrive here as '+' - no special-casing
             * needed beyond the same digit/op/Enter/'c' translation the
             * x86 port uses. */
            char key = (char)c;
            if (key == '\n') key = '=';
            else if (key == 'c') key = 'C';
            if ((key >= '0' && key <= '9') || key=='+' || key=='-' || key=='*' || key=='/' || key=='=' || key=='C') {
                calc_press(key);
                render_calc(&win);
            }
        }

        gfx_flush();
        sleep_ms(20);
    }

    return 0;
}
