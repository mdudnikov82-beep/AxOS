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
