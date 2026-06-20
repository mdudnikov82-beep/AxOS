// =================================================================
//  Рисовалка мышью AxOS - mode 13h (320x200, 256 цветов)
// =================================================================
//
// Отдельный, самостоятельный "мини-кернел", не связанный с основным
// kernel.c: своя точка входа (kernel_gfx_entry.asm), свой минимальный
// IDT (только IRQ12 - мышь), без FAT12/paging/tasking/heap. Грузится
// отдельным загрузчиком boot_gfx.asm, который включает видеорежим
// 0x13 в реальном режиме (BIOS-смена режима невозможна после прыжка
// в protected mode - см. комментарий там).
//
// Использует существующий драйвер мыши (src/drivers/mouse.c) как
// есть, без изменений - тот возвращает координаты в сетке 80x25
// (under the hood это контракт для текстового mouse.bin), здесь
// масштабируем их под 320x200 при отрисовке.
//
// Левая кнопка мыши - рисует текущим цветом. Цифры 1-9 - выбор цвета
// (9 - чёрный, как ластик). C - очистить холст. ESC - выход.
//
// Курсор - НЕ часть рисунка: перед тем как нарисовать его в новом
// месте, мы сохраняем то, что там было (cursor_backup), а перед уходом
// со старого места - восстанавливаем сохранённое. Иначе курсор стирал
// бы нарисованные мазки под собой при каждом движении.

#include "../drivers/mouse.h"

#define VGA_GFX    ((unsigned char*)0xA0000)
#define GFX_WIDTH  320
#define GFX_HEIGHT 200
#define BRUSH_SIZE 4
#define CANVAS_BG  0x00 // чёрный холст

struct idt_entry {
    unsigned short offset_low;
    unsigned short selector;
    unsigned char  zero;
    unsigned char  type_attr;
    unsigned short offset_high;
} __attribute__((packed));

static struct idt_entry IDT[256];

extern void mouse_interrupt_handler();

static void set_idt_gate(int n, unsigned long handler) {
    IDT[n].offset_low  = handler & 0xFFFF;
    IDT[n].selector    = 0x08; // CODE_SEG из gdt.asm
    IDT[n].zero        = 0;
    IDT[n].type_attr   = 0x8E; // present, ring0, 32-битный interrupt gate
    IDT[n].offset_high = (handler >> 16) & 0xFFFF;
}

static unsigned char port_byte_in(unsigned short port) {
    unsigned char result;
    __asm__ volatile("inb %%dx, %%al" : "=a"(result) : "d"(port));
    return result;
}

static void port_byte_out(unsigned short port, unsigned char data) {
    __asm__ volatile("outb %%al, %%dx" : : "a"(data), "d"(port));
}

static void init_idt_gfx() {
    set_idt_gate(0x2C, (unsigned long)mouse_interrupt_handler); // IRQ12

    struct { unsigned short limit; unsigned long base; } __attribute__((packed))
        idtr = { 256 * 8 - 1, (unsigned long)IDT };
    __asm__("lidt %0" : : "m"(idtr));

    // Перенастройка PIC (тот же протокол, что в kernel.c::init_idt).
    port_byte_out(0x20, 0x11);
    port_byte_out(0xA0, 0x11);
    port_byte_out(0x21, 0x20);
    port_byte_out(0xA1, 0x28);
    port_byte_out(0x21, 0x04);
    port_byte_out(0xA1, 0x02);
    port_byte_out(0x21, 0x01);
    port_byte_out(0xA1, 0x01);

    // Маскируем всё, кроме IRQ2 (каскад слейва) и IRQ12 (мышь) -
    // таймер и клавиатурные прерывания этой демке не нужны: ESC
    // опрашивается прямым чтением порта 0x60 в основном цикле.
    port_byte_out(0x21, 0xFB); // 11111011 - открыт бит2 (IRQ2)
    port_byte_out(0xA1, 0xEF); // 11101111 - открыт бит4 (IRQ12)

    __asm__ volatile("sti");
}

static void put_pixel(int x, int y, unsigned char color) {
    if (x < 0 || x >= GFX_WIDTH || y < 0 || y >= GFX_HEIGHT) return;
    VGA_GFX[y * GFX_WIDTH + x] = color;
}

static void fill_screen(unsigned char color) {
    for (int i = 0; i < GFX_WIDTH * GFX_HEIGHT; i++) VGA_GFX[i] = color;
}

static void draw_brush(int x, int y, unsigned char color) {
    for (int dy = 0; dy < BRUSH_SIZE; dy++) {
        for (int dx = 0; dx < BRUSH_SIZE; dx++) {
            put_pixel(x + dx, y + dy, color);
        }
    }
}

// Палитра по цифрам 1-9 (стандартные индексы VGA в mode 13h).
static const unsigned char palette[9] = {
    0x0F, // 1: белый
    0x04, // 2: красный
    0x02, // 3: зелёный
    0x01, // 4: синий
    0x0E, // 5: жёлтый
    0x05, // 6: пурпурный
    0x03, // 7: голубой
    0x06, // 8: коричневый
    0x00, // 9: чёрный (ластик)
};

void gfx_main() {
    init_idt_gfx();
    init_mouse();

    fill_screen(CANVAS_BG);

    unsigned char cursor_backup[BRUSH_SIZE * BRUSH_SIZE];
    int last_x = -1, last_y = -1;
    unsigned char current_color = palette[0]; // старт - белый

    while (1) {
        // Восстанавливаем то, что было под курсором на старом месте -
        // курсор не должен затирать уже нарисованные мазки.
        if (last_x >= 0) {
            int i = 0;
            for (int dy = 0; dy < BRUSH_SIZE; dy++)
                for (int dx = 0; dx < BRUSH_SIZE; dx++)
                    put_pixel(last_x + dx, last_y + dy, cursor_backup[i++]);
        }

        // mouse_get_x/y() - координаты в сетке 80x25 (контракт driverа,
        // общий с текстовым mouse.bin) - масштабируем до 320x200:
        // 320/80=4 пикселя по X, 200/25=8 пикселей по Y на "клетку".
        int x = mouse_get_x() * 4;
        int y = mouse_get_y() * 8;

        // Левая кнопка (бит0) - рисуем текущим цветом. Это уже часть
        // холста, не курсора - сохранённый "под курсором" фрагмент
        // ниже захватит и этот мазок, так что курсор его не сотрёт.
        if (mouse_get_buttons() & 0x01) {
            draw_brush(x, y, current_color);
        }

        // Сохраняем то, что сейчас на новом месте (включая только что
        // нарисованный мазок, если кнопка была зажата), и рисуем курсор.
        int i = 0;
        for (int dy = 0; dy < BRUSH_SIZE; dy++) {
            for (int dx = 0; dx < BRUSH_SIZE; dx++) {
                int px = x + dx, py = y + dy;
                cursor_backup[i++] = (px >= 0 && px < GFX_WIDTH && py >= 0 && py < GFX_HEIGHT)
                                          ? VGA_GFX[py * GFX_WIDTH + px]
                                          : CANVAS_BG;
            }
        }
        draw_brush(x, y, 0x0F); // курсор - белая рамка-заливка сверху

        last_x = x;
        last_y = y;

        // Клавиатуру опрашиваем прямо здесь (без IRQ1 - этой демке
        // больше ничего от клавиатуры не нужно).
        if (port_byte_in(0x64) & 1) {
            unsigned char scancode = port_byte_in(0x60);
            if (scancode == 0x01) break; // ESC - выход
            if (scancode >= 0x02 && scancode <= 0x0A) { // 1-9
                current_color = palette[scancode - 0x02];
            } else if (scancode == 0x2E) { // C - очистить холст
                fill_screen(CANVAS_BG);
                last_x = -1; // иначе следующий кадр "восстановит" старые пиксели поверх очистки
            }
        }
    }

    while (1) {
        __asm__ volatile("hlt");
    }
}
