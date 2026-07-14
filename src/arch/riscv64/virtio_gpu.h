#pragma once

// Разрешение фреймбуфера. 800x600x32bpp = 1875 КБ — укладывается в наш
// bump-аллокатор без проблем (RAM 128 МБ). Было 640x480 - поднято, чтобы
// сравняться с x86-стороной (gfx_shell.c, тоже 800x600); все потребители
// (console.c, kernel_main.c, syscall.c's SYS_GFX_INFO, virtio_input.c) и
// все userspace GUI-программы уже параметризованы через эти константы
// или читают их динамически через gfx_info() - менять больше нигде не
// нужно.
#define GPU_FB_WIDTH  800
#define GPU_FB_HEIGHT 600

// Инициализирует VirtIO-GPU (2D-режим, без 3D/virgl) по MMIO на QEMU virt:
// сканирует 8 MMIO-слотов, создаёт resource GPU_FB_WIDTH x GPU_FB_HEIGHT
// B8G8R8A8, аллоцирует linear framebuffer в guest RAM, приаттачивает его
// как backing store и назначает на scanout 0.
// Возвращает 0 при успехе, -1 если устройство не найдено/init не удался.
int virtio_gpu_init(void);

// Указатель на framebuffer (linear, GPU_FB_WIDTH*GPU_FB_HEIGHT*4 байт,
// формат B8G8R8A8 — байты в памяти: B,G,R,A). Пиши в него напрямую (это
// обычная память, без virtqueue на каждый пиксель), затем зови
// virtio_gpu_flush(), чтобы host отрисовал новое содержимое.
void *virtio_gpu_fb(void);

// Отправляет TRANSFER_TO_HOST_2D + RESOURCE_FLUSH только на область,
// изменённую (через putpixel/fill_rect) с прошлого успешного flush() -
// dirty-rect трекинг, не весь фреймбуфер целиком. Если с прошлого
// flush() ничего не рисовали - не шлёт вообще ничего, возвращает 0
// сразу. Возвращает 0 при успехе, -1 при ошибке/таймауте.
int virtio_gpu_flush(void);

// 1 если virtio_gpu_init() прошёл успешно, 0 если GPU не найден/не поднят.
int virtio_gpu_ready(void);

// Пишет один пиксель (формат B8G8R8A8 — см. BGRA-макрос в kernel_main.c).
// Координаты за пределами GPU_FB_WIDTH/HEIGHT молча игнорируются.
void virtio_gpu_putpixel(unsigned int x, unsigned int y, unsigned int bgra);

// Заливает прямоугольник [x, x+w) x [y, y+h) одним цветом. Прямоугольник
// обрезается по границам фреймбуфера (не выходит за них).
void virtio_gpu_fill_rect(unsigned int x, unsigned int y,
                          unsigned int w, unsigned int h, unsigned int bgra);

// Reads back one pixel (for software cursor save/restore — the hardware
// cursor plane isn't reliably composited by every QEMU display frontend
// for absolute/tablet devices, so callers may need to draw their own).
// Returns the BGRA value, or 0 if out of bounds / GPU not ready.
unsigned int virtio_gpu_getpixel(unsigned int x, unsigned int y);

// Рисует один символ 8x8 битмап-шрифтом (ASCII 0x20-0x7F) левым верхним
// углом в (x, y). Непечатаемые/за диапазоном коды игнорируются.
void virtio_gpu_draw_char(unsigned int x, unsigned int y, char ch, unsigned int bgra);

// Рисует NUL-terminated строку начиная с (x, y), фиксированный шаг 8px
// на символ (без кернинга). Перенос строк ('\n') не поддерживается —
// вызывающий сам разбивает многострочный текст.
void virtio_gpu_draw_text(unsigned int x, unsigned int y, const char *s, unsigned int bgra);

// Moves the hardware cursor plane to (x, y). The host compositor draws it
// on top of the scanout independently — no framebuffer pixels are
// touched. No-op if cursor setup failed or GPU isn't ready.
void virtio_gpu_cursor_move(unsigned int x, unsigned int y);
