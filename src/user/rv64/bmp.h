#pragma once
#include "syscall.h"

/* Минимальный BMP-декодер для маленьких иконок (AxDesktop и т.п.) - как
 * и весь остальной стек AxOS, только "счастливый путь": поддерживается
 * ровно то подмножество формата, которое реально экспортируют графические
 * редакторы для простых непрозрачных значков без сжатия.
 *
 * Поддержано: BITMAPFILEHEADER(14Б) + BITMAPINFOHEADER(40Б,
 * biSize>=40), biBitCount 24 (BGR) или 32 (BGRX/BGRA - альфа
 * игнорируется), biCompression=0 (BI_RGB), biHeight>0 (стандартный
 * bottom-up порядок строк - top-down с отрицательной высотой не
 * поддержан). Максимум BMP_MAX_W x BMP_MAX_H - иконки, не обои: на
 * RISC-V каждый пиксель отрисовки идёт отдельным gfx_putpixel() syscall
 * (ecall) - для полноэкранной картинки это были бы сотни тысяч ecall'ов,
 * для 32x32 иконки, отрисованной один раз при старте - незаметно.
 *
 * Нет lseek() (такого syscall'а в этом дереве нет) - если bfOffBits
 * больше 54 (лишние байты между заголовком и пиксельными данными,
 * редко), они вычитываются и отбрасываются последовательным read(),
 * не пропускаются. */

#define BMP_MAX_W 64
#define BMP_MAX_H 64

typedef struct {
    unsigned int width, height;
    unsigned int pixels[BMP_MAX_W * BMP_MAX_H];   /* gfx_rgb()-упакованные, pixels[0] = левый верхний угол */
} bmp_image_t;

static unsigned int bmp_rd32(const unsigned char *p) {
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8) |
           ((unsigned int)p[2] << 16) | ((unsigned int)p[3] << 24);
}
static unsigned short bmp_rd16(const unsigned char *p) {
    return (unsigned short)((unsigned int)p[0] | ((unsigned int)p[1] << 8));
}

/* Грузит filename (FAT12) в *img. Возвращает 1 при успехе, 0 при любой
 * ошибке (файл не найден/не BMP/неподдерживаемый вариант формата/
 * слишком большой) - вызывающий код должен трактовать 0 как "картинки
 * нет", не падать. */
static int bmp_load(const char *filename, bmp_image_t *img) {
    int fd = open(filename, 0);
    if (fd < 0) return 0;

    static unsigned char hdr[54];
    if (read(fd, hdr, 54) != 54 || hdr[0] != 'B' || hdr[1] != 'M') {
        close(fd);
        return 0;
    }

    unsigned int   data_off     = bmp_rd32(hdr + 10);
    unsigned int   dib_size     = bmp_rd32(hdr + 14);
    int            width        = (int)bmp_rd32(hdr + 18);
    int            height       = (int)bmp_rd32(hdr + 22);
    unsigned short bpp          = bmp_rd16(hdr + 28);
    unsigned int   compression  = bmp_rd32(hdr + 30);

    if (dib_size < 40 || compression != 0 || (bpp != 24 && bpp != 32) ||
        width <= 0 || height <= 0 ||
        (unsigned int)width > BMP_MAX_W || (unsigned int)height > BMP_MAX_H) {
        close(fd);
        return 0;
    }

    /* Обычно data_off == 54 (без цветовой таблицы - её нет для 24/32bpp);
     * если больше - вычитываем и отбрасываем разницу последовательным
     * чтением, раз lseek() недоступен. */
    if (data_off > 54) {
        unsigned int skip = data_off - 54;
        static unsigned char discard[256];
        while (skip > 0) {
            unsigned int chunk = skip > sizeof(discard) ? sizeof(discard) : skip;
            if (read(fd, discard, chunk) != (int)chunk) { close(fd); return 0; }
            skip -= chunk;
        }
    } else if (data_off < 54) {
        close(fd);
        return 0;   /* поломанный файл - заголовок сам себя перекрывает */
    }

    unsigned int bytes_per_px = bpp / 8u;
    unsigned int row_bytes    = ((unsigned int)width * bytes_per_px + 3u) & ~3u;   /* выровнено на 4Б */

    static unsigned char row_buf[BMP_MAX_W * 4];
    for (int y = 0; y < height; y++) {
        if (read(fd, row_buf, row_bytes) != (int)row_bytes) { close(fd); return 0; }
        int dst_row = height - 1 - y;   /* bottom-up: первая прочитанная строка - НИЗ картинки */
        for (int x = 0; x < width; x++) {
            unsigned char b = row_buf[(unsigned int)x * bytes_per_px + 0];
            unsigned char g = row_buf[(unsigned int)x * bytes_per_px + 1];
            unsigned char r = row_buf[(unsigned int)x * bytes_per_px + 2];
            img->pixels[(unsigned int)dst_row * (unsigned int)width + (unsigned int)x] = gfx_rgb(r, g, b);
        }
    }
    close(fd);

    img->width  = (unsigned int)width;
    img->height = (unsigned int)height;
    return 1;
}

/* Рисует img левым верхним углом в (x, y) - по одному gfx_putpixel() на
 * пиксель, см. коммент вверху файла про цену ecall'ов. */
static void bmp_draw(const bmp_image_t *img, unsigned int x, unsigned int y) {
    for (unsigned int dy = 0; dy < img->height; dy++)
        for (unsigned int dx = 0; dx < img->width; dx++)
            gfx_putpixel(x + dx, y + dy, img->pixels[dy * img->width + dx]);
}

/* ---- 8bpp-indexed encoder/decoder (added for AxPaint's save/load) ----
 *
 * sys_open() (syscall.c) deliberately caps any file READ at 32KB
 * (8 pages, bump-allocated per fd - "avoids the kmalloc recursion issue
 * for large buffers"). writefile() has no such cap, but a symmetric
 * load does - so anything meant to be loadable back through open()/
 * read() must stay under that ceiling. A full-resolution 800x564
 * canvas at 1 byte/pixel alone is ~441KB - nowhere close. This format
 * (8bpp indexed, a handful of palette colors) is for AxPaint's small
 * thumbnail snapshot, not a full-screen picture. */

static void bmp_wr32(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)v; p[1] = (unsigned char)(v >> 8);
    p[2] = (unsigned char)(v >> 16); p[3] = (unsigned char)(v >> 24);
}
static void bmp_wr16(unsigned char *p, unsigned short v) {
    p[0] = (unsigned char)v; p[1] = (unsigned char)(v >> 8);
}

/* idx[] is row-major TOP-DOWN (idx[0] = top-left) - flips to BMP's
 * bottom-up storage order itself, same as bmp_load() does on the way
 * in. palette[] holds n_colors gfx_rgb()-packed colors (index 0..
 * n_colors-1). Returns 1 ok / 0 err (incl. "would exceed the 32KB read
 * cap" - checked explicitly so a future resolution bump fails loudly
 * instead of silently writing an unloadable file). */
static int bmp_save_indexed(const char *filename, const unsigned char *idx,
                            unsigned int w, unsigned int h,
                            const unsigned int *palette, unsigned char n_colors) {
    unsigned int row_bytes = (w + 3u) & ~3u;
    unsigned int pal_bytes = (unsigned int)n_colors * 4u;
    unsigned int off_bits  = 14u + 40u + pal_bytes;
    unsigned int img_bytes = row_bytes * h;
    unsigned int total     = off_bits + img_bytes;

    static unsigned char buf[32 * 1024];   /* must stay under sys_open()'s 32KB read cap */
    if (total > sizeof(buf)) return 0;

    unsigned char *p = buf;
    p[0] = 'B'; p[1] = 'M';
    bmp_wr32(p + 2, total);
    bmp_wr32(p + 6, 0);
    bmp_wr32(p + 10, off_bits);

    bmp_wr32(p + 14, 40);
    bmp_wr32(p + 18, w);
    bmp_wr32(p + 22, h);
    bmp_wr16(p + 26, 1);
    bmp_wr16(p + 28, 8);
    bmp_wr32(p + 30, 0);
    bmp_wr32(p + 34, img_bytes);
    bmp_wr32(p + 38, 0);
    bmp_wr32(p + 42, 0);
    bmp_wr32(p + 46, n_colors);
    bmp_wr32(p + 50, 0);

    for (unsigned char c = 0; c < n_colors; c++) {
        unsigned int col = palette[c];
        unsigned char *e = p + 54 + (unsigned int)c * 4;
        e[0] = (unsigned char)col;          /* B */
        e[1] = (unsigned char)(col >> 8);   /* G */
        e[2] = (unsigned char)(col >> 16);  /* R */
        e[3] = 0;
    }

    unsigned char *pix = p + off_bits;
    for (unsigned int y = 0; y < h; y++) {
        unsigned int src_row = h - 1 - y;   /* flip to bottom-up */
        for (unsigned int x = 0; x < w; x++)
            pix[y * row_bytes + x] = idx[src_row * w + x];
        for (unsigned int x = w; x < row_bytes; x++)
            pix[y * row_bytes + x] = 0;     /* 4-byte row padding */
    }

    return writefile(filename, buf, (long)total);
}

/* Inverse of bmp_save_indexed() - rejects anything that doesn't match
 * the expected w/h/bpp exactly (happy-path only, same discipline as
 * bmp_load()). Caller sizes idx[] for w*h bytes, palette[] for >=8
 * entries. Returns 1 ok / 0 err (not found / not BMP / unsupported
 * variant / size mismatch). */
static int bmp_load_indexed(const char *filename, unsigned char *idx,
                            unsigned int w, unsigned int h,
                            unsigned int *palette, unsigned char *n_colors_out) {
    int fd = open(filename, 0);
    if (fd < 0) return 0;

    static unsigned char hdr[54];
    if (read(fd, hdr, 54) != 54 || hdr[0] != 'B' || hdr[1] != 'M') {
        close(fd);
        return 0;
    }

    unsigned int   data_off = bmp_rd32(hdr + 10);
    unsigned int   dib_size = bmp_rd32(hdr + 14);
    unsigned int   fw       = bmp_rd32(hdr + 18);
    unsigned int   fh       = bmp_rd32(hdr + 22);
    unsigned short bpp      = bmp_rd16(hdr + 28);
    unsigned int   clr_used = bmp_rd32(hdr + 46);

    if (dib_size < 40 || bpp != 8 || fw != w || fh != h ||
        clr_used == 0 || clr_used > 8) {
        close(fd);
        return 0;
    }

    static unsigned char pal_buf[8 * 4];
    unsigned int pal_bytes = clr_used * 4u;
    if (read(fd, pal_buf, pal_bytes) != (int)pal_bytes) { close(fd); return 0; }
    for (unsigned int c = 0; c < clr_used; c++)
        palette[c] = gfx_rgb(pal_buf[c * 4 + 2], pal_buf[c * 4 + 1], pal_buf[c * 4 + 0]);
    *n_colors_out = (unsigned char)clr_used;

    /* Gap between palette end and bfOffBits (rare, defensive) - no
     * lseek() on this platform, discard via sequential read like
     * bmp_load() already does. */
    unsigned int consumed = 54u + pal_bytes;
    if (data_off > consumed) {
        unsigned int skip = data_off - consumed;
        static unsigned char discard[64];
        while (skip > 0) {
            unsigned int chunk = skip > sizeof(discard) ? sizeof(discard) : skip;
            if (read(fd, discard, chunk) != (int)chunk) { close(fd); return 0; }
            skip -= chunk;
        }
    } else if (data_off < consumed) {
        close(fd);
        return 0;
    }

    unsigned int row_bytes = (w + 3u) & ~3u;
    static unsigned char row_buf[256];
    if (row_bytes > sizeof(row_buf)) { close(fd); return 0; }
    for (unsigned int y = 0; y < h; y++) {
        if (read(fd, row_buf, row_bytes) != (int)row_bytes) { close(fd); return 0; }
        unsigned int dst_row = h - 1 - y;   /* bottom-up in file -> top-down in idx[] */
        for (unsigned int x = 0; x < w; x++) idx[dst_row * w + x] = row_buf[x];
    }
    close(fd);
    return 1;
}
