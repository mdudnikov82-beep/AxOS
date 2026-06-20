// =================================================================
//  Системный динамик (PC speaker) - канал 2 PIT + порт 0x61
// =================================================================
//
// Канал 0 PIT (порты 0x40/0x43) занят системным таймером (IRQ0,
// 100 Гц) - звук идёт через ОТДЕЛЬНЫЙ канал 2 (порты 0x42/0x43),
// который не генерирует прерываний, просто крутит square wave на
// заданной частоте. Порт 0x61 - "гейт": бит0 разрешает каналу 2 PIT
// считать, бит1 пропускает его сигнал непосредственно на динамик.
// Без бита1 канал 2 тикал бы молча.

#include "speaker.h"

static unsigned char port_byte_in(unsigned short port) {
    unsigned char result;
    __asm__ volatile("inb %%dx, %%al" : "=a"(result) : "d"(port));
    return result;
}

static void port_byte_out(unsigned short port, unsigned char data) {
    __asm__ volatile("outb %%al, %%dx" : : "a"(data), "d"(port));
}

void speaker_on(unsigned int freq) {
    if (freq == 0) { speaker_off(); return; }

    unsigned int divisor = 1193182 / freq;
    port_byte_out(0x43, 0xB6); // канал 2, lobyte/hibyte, режим 3 (square wave)
    port_byte_out(0x42, (unsigned char)(divisor & 0xFF));
    port_byte_out(0x42, (unsigned char)((divisor >> 8) & 0xFF));

    unsigned char gate = port_byte_in(0x61);
    port_byte_out(0x61, gate | 0x03); // бит0 (гейт канала 2) + бит1 (динамик)
}

void speaker_off() {
    unsigned char gate = port_byte_in(0x61);
    port_byte_out(0x61, gate & ~0x03);
}
