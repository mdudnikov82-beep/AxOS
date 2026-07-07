#pragma once
// UART 16550 — стандартный для QEMU virt board (адрес 0x10000000)
// Polling-режим: нет прерываний, просто пишем в регистр THR.

#define UART0_BASE 0x10000000UL

// Ждём пока TX FIFO не освободится (бит 5 LSR = THRE)
static inline void uart_putc(char c) {
    volatile unsigned char *uart = (volatile unsigned char *)UART0_BASE;
    while (!(uart[5] & 0x20));  // LSR[5] = Transmitter Holding Register Empty
    uart[0] = (unsigned char)c;
}

static inline void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

// Блокирующее чтение: ждёт пока LSR[0] (Data Ready) станет 1
static inline char uart_getc(void) {
    volatile unsigned char *uart = (volatile unsigned char *)UART0_BASE;
    while (!(uart[5] & 0x01));
    return (char)uart[0];
}

// Инициализация: QEMU запускает UART уже настроенным, но на всякий случай
// выставляем делитель baud = 38400 (предполагаем clock 1.8432 MHz)
static inline void uart_init(void) {
    volatile unsigned char *uart = (volatile unsigned char *)UART0_BASE;
    uart[3] = 0x80;             // LCR: включаем DLAB (доступ к делителю)
    uart[0] = 0x03;             // DLL = 3  (делитель 38400)
    uart[1] = 0x00;             // DLM = 0
    uart[3] = 0x03;             // LCR: 8N1, DLAB выключен
    uart[2] = 0xC7;             // FCR: FIFO enable + clear
    uart[4] = 0x0B;             // MCR: RTS + DTR + OUT2
}
