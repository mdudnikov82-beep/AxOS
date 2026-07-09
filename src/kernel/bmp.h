#pragma once

/* Минимальный BMP-декодер для gfx_shell.c - тот же формат/ограничения,
 * что и у RISC-V-стороны (src/user/rv64/bmp.h): BITMAPFILEHEADER(14Б)
 * + BITMAPINFOHEADER(40Б, biSize>=40), 24 или 32 бита на пиксель
 * (BGR/BGRX/BGRA - альфа игнорируется), biCompression=0 (BI_RGB),
 * biHeight>0 (стандартный bottom-up порядок строк) - только "счастливый
 * путь", то подмножество, которое реально экспортируют графические
 * редакторы для простых непрозрачных значков.
 *
 * Отличие от RISC-V-версии: здесь source - уже встроенный в бинарник
 * массив байт (см. tools/bmp_to_c.py, build\icons_data.h), а не файл -
 * у gfx_shell.c (отдельный мини-кернел) нет доступа к диску/FAT12
 * вообще. Декодирует напрямую в color_t (0xRRGGBB, без альфа-байта -
 * формат этого backbuffer'а), рисуется через уже существующий px()
 * (прямая запись в BACKBUF, никаких syscall'ов - в отличие от RISC-V,
 * где каждый пиксель идёт отдельным ecall'ом). */

#define BMP_MAX_W 64
#define BMP_MAX_H 64

typedef struct {
    int      width, height;
    color_t  pixels[BMP_MAX_W * BMP_MAX_H];   /* pixels[0] = левый верхний угол */
} bmp_image_t;

static unsigned int bmp_rd32(const unsigned char *p) {
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8) |
           ((unsigned int)p[2] << 16) | ((unsigned int)p[3] << 24);
}
static unsigned short bmp_rd16(const unsigned char *p) {
    return (unsigned short)((unsigned int)p[0] | ((unsigned int)p[1] << 8));
}

/* Декодирует уже встроенный в память BMP (data, len байт) в *img.
 * Возвращает 1 при успехе, 0 при любой ошибке (не BMP/неподдерживаемый
 * вариант формата/слишком большой) - вызывающий код должен трактовать
 * 0 как "иконки нет", не падать. */
static int bmp_decode(const unsigned char *data, unsigned int len, bmp_image_t *img) {
    if (len < 54 || data[0] != 'B' || data[1] != 'M') return 0;

    unsigned int   data_off    = bmp_rd32(data + 10);
    unsigned int   dib_size    = bmp_rd32(data + 14);
    int            width       = (int)bmp_rd32(data + 18);
    int            height      = (int)bmp_rd32(data + 22);
    unsigned short bpp         = bmp_rd16(data + 28);
    unsigned int   compression = bmp_rd32(data + 30);

    if (dib_size < 40 || compression != 0 || (bpp != 24 && bpp != 32) ||
        width <= 0 || height <= 0 ||
        (unsigned int)width > BMP_MAX_W || (unsigned int)height > BMP_MAX_H ||
        data_off < 54 || data_off > len) {
        return 0;
    }

    unsigned int bytes_per_px = bpp / 8u;
    unsigned int row_bytes    = ((unsigned int)width * bytes_per_px + 3u) & ~3u;   /* выровнено на 4Б */

    unsigned int pos = data_off;
    for (int y = 0; y < height; y++) {
        if (pos + row_bytes > len) return 0;
        int dst_row = height - 1 - y;   /* bottom-up: первая строка в файле - НИЗ картинки */
        for (int x = 0; x < width; x++) {
            unsigned char b = data[pos + (unsigned int)x * bytes_per_px + 0];
            unsigned char g = data[pos + (unsigned int)x * bytes_per_px + 1];
            unsigned char r = data[pos + (unsigned int)x * bytes_per_px + 2];
            img->pixels[(unsigned int)dst_row * (unsigned int)width + (unsigned int)x] =
                ((color_t)r << 16) | ((color_t)g << 8) | (color_t)b;
        }
        pos += row_bytes;
    }

    img->width  = width;
    img->height = height;
    return 1;
}

/* Рисует img левым верхним углом в (x, y) прямо в BACKBUF через px(). */
static void bmp_draw(const bmp_image_t *img, int x, int y) {
    for (int dy = 0; dy < img->height; dy++)
        for (int dx = 0; dx < img->width; dx++)
            px(x + dx, y + dy, img->pixels[dy * img->width + dx]);
}
