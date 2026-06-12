#ifndef KEYBOARD_H // Защита от двойного включения
#define KEYBOARD_H

// Исправленная функция: добавили volatile и исправили in на inb
unsigned char port_byte_in(unsigned short port)
{
    unsigned char result;
    __asm__ volatile("inb %%dx, %%al" : "=a"(result) : "d"(port)); // Используем inb для чтения байта из порта
    return result;
}

// Запись байта в порт (нужна, например, для выбора регистра CMOS/RTC)
void port_byte_out(unsigned short port, unsigned char data)
{
    __asm__ volatile("outb %%al, %%dx" : : "a"(data), "d"(port));
}

// Карта перевода аппаратных кодов клавиатуры в обычные английские буквы
static char scancode_to_char[128] = {
    0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\b',
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n',
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,
    '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' '};

// Функция получения нажатой клавиши
char get_input_char()
{
    while ((port_byte_in(0x64) & 1) == 0)
        ;

    unsigned char scancode = port_byte_in(0x60);

    if (scancode < 128)
    {
        return scancode_to_char[scancode];
    }

    return 0;
}

#endif