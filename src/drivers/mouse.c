// =================================================================
//  Драйвер PS/2-мыши (вторичный канал контроллера 8042, IRQ12)
// =================================================================
//
// Протокол: 3-байтовый пакет на каждое движение/нажатие.
//   байт0: бит0=левая кнопка, бит1=правая, бит2=средняя, бит3=1 (всегда -
//          признак начала пакета, остальное мусор), бит4=знак dx,
//          бит5=знак dy, биты6/7=overflow (игнорируем).
//   байт1: |dx| (8 бит, без знака, знак - в байте 0)
//   байт2: |dy| (8 бит, без знака, знак - в байте 0)
//
// IRQ12 срабатывает на КАЖДЫЙ байт, а не на весь пакет сразу - копим 3
// байта в mouse_packet[]/mouse_byte_index, прежде чем собрать готовое
// движение (тот же принцип "набираем по кусочку", что у клавиатурного
// E0-префикса в kernel.c, только тут фиксированная длина в 3 байта).

#include "mouse.h"

static unsigned char port_byte_in(unsigned short port) {
    unsigned char result;
    __asm__ volatile("inb %%dx, %%al" : "=a"(result) : "d"(port));
    return result;
}

static void port_byte_out(unsigned short port, unsigned char data) {
    __asm__ volatile("outb %%al, %%dx" : : "a"(data), "d"(port));
}

#define PS2_DATA   0x60
#define PS2_STATUS 0x64
#define PS2_CMD    0x64

#define PS2_WAIT_LIMIT 100000

// Бит 1 статус-регистра = "входной буфер контроллера занят" - ждём 0
// перед тем, как писать команду/данные (иначе контроллер их потеряет).
static void ps2_wait_input_clear() {
    for (int i = 0; i < PS2_WAIT_LIMIT && (port_byte_in(PS2_STATUS) & 0x02); i++);
}

// Бит 0 = "есть байт для чтения из 0x60" - ждём перед его чтением.
static void ps2_wait_output_full() {
    for (int i = 0; i < PS2_WAIT_LIMIT && !(port_byte_in(PS2_STATUS) & 0x01); i++);
}

static void ps2_send_command(unsigned char cmd) {
    ps2_wait_input_clear();
    port_byte_out(PS2_CMD, cmd);
}

static void ps2_send_data(unsigned char data) {
    ps2_wait_input_clear();
    port_byte_out(PS2_DATA, data);
}

// Отправляет байт САМОЙ МЫШИ (не контроллеру 8042) - команда 0xD4 говорит
// контроллеру "следующий байт в 0x60 - для AUX-порта", без неё байт ушёл
// бы клавиатуре.
static void mouse_send(unsigned char data) {
    ps2_send_command(0xD4);
    ps2_send_data(data);
}

static unsigned char mouse_packet[3];
static int mouse_byte_index = 0;

// Стартуем в центре сетки 80x25 - первое движение мыши сразу видно,
// независимо от направления.
static volatile int mouse_x = 40;
static volatile int mouse_y = 12;
static volatile int mouse_buttons = 0;

void mouse_irq_handler_main() {
    unsigned char data = port_byte_in(PS2_DATA);

    // Ресинхронизация: если мы ждём байт0 (начало пакета), он ОБЯЗАН
    // иметь бит3=1 (см. протокол выше). Если нет - значит где-то раньше
    // уже потерялось/добавилось не кратное 3 число байт (например, один
    // случайный байт до начала чистого стриминга), и без этой проверки
    // расхождение было бы постоянным: группы по 3 байта продолжали бы
    // собираться со смещением навсегда, каждая проваливала бы проверку
    // bit3 ниже и так по кругу - НИ ОДНО движение мыши никогда не было
    // бы разобрано. Отбрасывая байты по одному, пока не найдём настоящую
    // границу пакета, мы самовосстанавливаемся за один лишний байт.
    if (mouse_byte_index == 0 && !(data & 0x08)) return;

    mouse_packet[mouse_byte_index++] = data;
    if (mouse_byte_index < 3) return;
    mouse_byte_index = 0;

    unsigned char flags = mouse_packet[0];

    int dx = mouse_packet[1];
    int dy = mouse_packet[2];
    if (flags & 0x10) dx -= 256; // знак dx (бит 4)
    if (flags & 0x20) dy -= 256; // знак dy (бит 5)

    mouse_x += dx;
    mouse_y -= dy; // у PS/2 положительный dy = "вверх", у нас Y растёт вниз по экрану

    if (mouse_x < 0) mouse_x = 0;
    if (mouse_x > 79) mouse_x = 79;
    if (mouse_y < 0) mouse_y = 0;
    if (mouse_y > 24) mouse_y = 24;

    mouse_buttons = flags & 0x07;
}

void init_mouse() {
    // 1. Включаем AUX-порт (мышь) на контроллере. IRQ12 в статус-байте
    //    (шаг 3) ПОКА НЕ включаем - см. ниже, почему порядок важен.
    ps2_send_command(0xA8);

    // 2. Настройки мыши по умолчанию, затем включаем потоковую отправку
    //    пакетов при движении/нажатии. ACK-байт (0xFA) после каждой
    //    команды читаем сами через polling и отбрасываем.
    //
    //    Критично сделать это ДО включения бита IRQ12 ниже: контроллер
    //    шлёт ACK через тот же AUX-канал, и если IRQ12 уже разрешён,
    //    каждый ACK тоже вызовет IRQ12, который накопит его как байт
    //    "пакета" в mouse_irq_handler_main() - 2 лишних байта сдвигают
    //    выравнивание 3-байтового пакета навсегда (не кратно 3), и
    //    дальше уже НИ ОДНО настоящее движение мыши не будет разобрано
    //    верно. Поэтому: сначала тихо (без IRQ) договариваемся с мышью
    //    через polling, потом разрешаем IRQ12 - к этому моменту в AUX-
    //    канале уже не будет ничего, кроме настоящих пакетов движения.
    mouse_send(0xF6); // Set Defaults
    ps2_wait_output_full();
    port_byte_in(PS2_DATA);

    mouse_send(0xF4); // Enable Data Reporting (стримить пакеты)
    ps2_wait_output_full();
    port_byte_in(PS2_DATA);

    // 3. Читаем "Compaq Status Byte" (команда 0x20 - не путать с
    //    командой 0x20 PIC EOI, это другой контроллер и другой смысл),
    //    включаем бит 1 (разрешить IRQ12) и сбрасываем бит 5 (0 = AUX-
    //    тактирование включено - бит инвертирован), не трогая остальное
    //    (в т.ч. перевод скан-кодов клавиатуры).
    ps2_send_command(0x20);
    ps2_wait_output_full();
    unsigned char status = port_byte_in(PS2_DATA);
    status |= 0x02;
    status &= ~0x20;
    ps2_send_command(0x60);
    ps2_send_data(status);
}

int mouse_get_x() { return mouse_x; }
int mouse_get_y() { return mouse_y; }
int mouse_get_buttons() { return mouse_buttons; }
