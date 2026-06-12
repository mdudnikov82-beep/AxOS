#include "keyboard.h" // Подключаем твои порты ввода-вывода и карту скан-кодов
#include "../fs/fat12.h" // Read-only драйвер FAT12 для RAM-диска (конфиги/скрипты)

#define SCREEN_WIDTH 80
#define VIDEO_MEMORY 0xB8000
#define DEFAULT_COLOR 0x1F

// Прототипы функций
void clear_screen();
void print_string(char* str);
void backspace();
void init_idt();
extern void keyboard_interrupt_handler();
extern void timer_interrupt_handler();
extern void syscall_handler();
int command_len = 0;
char command_buffer[64];

// Счётчик тиков таймера (PIT, IRQ0). При частоте 100 Гц растёт на 1 каждые 10 мс.
volatile unsigned long timer_ticks = 0;

// Структуры для IDT
struct IDT_entry {
    unsigned short offset_lower;
    unsigned short selector;
    unsigned char zero;
    unsigned char type_attr;
    unsigned short offset_upper;
} __attribute__((packed));

struct IDT_entry IDT[256];

void set_idt_gate(int n, unsigned long handler) {
    IDT[n].offset_lower = handler & 0xFFFF;
    IDT[n].selector = 0x08;
    IDT[n].zero = 0;
    IDT[n].type_attr = 0x8E;
    IDT[n].offset_upper = (handler >> 16) & 0xFFFF;
}

// Программирует PIT (8253/8254), канал 0, на частоту ~100 Гц (тик каждые 10 мс)
void init_pit() {
    unsigned int divisor = 1193182 / 100; // базовая частота PIT / целевая частота

    port_byte_out(0x43, 0x36); // канал 0, режим доступа lobyte/hibyte, режим 3 (square wave)
    port_byte_out(0x40, (unsigned char)(divisor & 0xFF));
    port_byte_out(0x40, (unsigned char)((divisor >> 8) & 0xFF));
}

void init_idt() {
    set_idt_gate(32, (unsigned long)timer_interrupt_handler);
    set_idt_gate(33, (unsigned long)keyboard_interrupt_handler);
    set_idt_gate(0x80, (unsigned long)syscall_handler); // int 0x80 — системные вызовы AxOS
    struct { unsigned short limit; unsigned long base; } __attribute__((packed)) idtr = { 256 * 8 - 1, (unsigned long)IDT };
    __asm__("lidt %0" : : "m"(idtr));

    init_pit();

    // Перенастройка PIC
    __asm__("outb %0, %1" : : "a"((unsigned char)0x11), "Nd"(0x20));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x11), "Nd"(0xA0));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x20), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x28), "Nd"(0xA1));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x04), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x02), "Nd"(0xA1));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x01), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x01), "Nd"(0xA1));

    // Маскируем все IRQ, кроме таймера (IRQ0) и клавиатуры (IRQ1) —
    // для остальных у нас нет обработчиков, их срабатывание без
    // IDT-записи приводит к тройному сбою.
    __asm__("outb %0, %1" : : "a"((unsigned char)0xFC), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0xFF), "Nd"(0xA1));

    __asm__("sti");
}

// Обработчик прерывания таймера (IRQ0) — вызывается ~100 раз в секунду
void timer_handler_main() {
    timer_ticks++;
}

// Приостанавливает выполнение на заданное количество миллисекунд,
// не нагружая процессор (CPU "спит" через hlt до следующего прерывания)
void sleep_ms(unsigned long ms) {
    unsigned long target = timer_ticks + (ms / 10);

    // Эта функция может быть вызвана из обработчика прерывания
    // клавиатуры, где IF=0 (вход через interrupt gate). Без sti
    // таймер не сможет тикать, и hlt зависнет навсегда. iret в конце
    // обработчика всё равно восстановит исходный флаг прерываний.
    __asm__ volatile("sti");

    while (timer_ticks < target) {
        __asm__("hlt");
    }
}

// Сравнивает две строки. Возвращает 1, если они совпадают, иначе 0.
int str_eq(char* a, char* b) {
    int i = 0;
    while (a[i] != '\0' && b[i] != '\0') {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

// Проверяет, начинается ли строка str с префикса prefix
int str_starts_with(char* str, char* prefix) {
    int i = 0;
    while (prefix[i] != '\0') {
        if (str[i] != prefix[i]) return 0;
        i++;
    }
    return 1;
}

// Читает регистр CMOS/RTC (порт 0x70 — выбор регистра, 0x71 — чтение значения)
unsigned char cmos_read(unsigned char reg) {
    port_byte_out(0x70, reg);
    return port_byte_in(0x71);
}

// Переводит число из BCD (используется CMOS по умолчанию) в обычное десятичное
int bcd_to_bin(unsigned char val) {
    return (val & 0x0F) + ((val >> 4) * 10);
}

// Печатает текущую дату и время, считанные из RTC, в формате YYYY-MM-DD HH:MM:SS
void print_datetime() {
    // Ждём, пока RTC закончит обновление своих регистров
    while (cmos_read(0x0A) & 0x80);

    int second = cmos_read(0x00);
    int minute = cmos_read(0x02);
    int hour   = cmos_read(0x04);
    int day    = cmos_read(0x07);
    int month  = cmos_read(0x08);
    int year   = cmos_read(0x09);
    unsigned char status_b = cmos_read(0x0B);

    if (!(status_b & 0x04)) { // регистры в формате BCD — переводим в десятичное
        second = bcd_to_bin(second);
        minute = bcd_to_bin(minute);
        hour   = bcd_to_bin(hour & 0x7F);
        day    = bcd_to_bin(day);
        month  = bcd_to_bin(month);
        year   = bcd_to_bin(year);
    }

    char buf[20] = "0000-00-00 00:00:00";
    buf[0]  = '0' + (2000 + year) / 1000 % 10;
    buf[1]  = '0' + (2000 + year) / 100 % 10;
    buf[2]  = '0' + (2000 + year) / 10 % 10;
    buf[3]  = '0' + (2000 + year) % 10;
    buf[5]  = '0' + month / 10;
    buf[6]  = '0' + month % 10;
    buf[8]  = '0' + day / 10;
    buf[9]  = '0' + day % 10;
    buf[11] = '0' + hour / 10;
    buf[12] = '0' + hour % 10;
    buf[14] = '0' + minute / 10;
    buf[15] = '0' + minute % 10;
    buf[17] = '0' + second / 10;
    buf[18] = '0' + second % 10;
    buf[19] = '\0';

    print_string(buf);
    print_string("\n");
}

// Печатает беззнаковое число в десятичном виде
void print_uint(unsigned long val) {
    char buf[11];
    int i = 10;
    buf[10] = '\0';

    if (val == 0) {
        buf[--i] = '0';
    } else {
        while (val > 0) {
            buf[--i] = '0' + (val % 10);
            val /= 10;
        }
    }

    print_string(&buf[i]);
}

// Перезагружает машину через контроллер клавиатуры 8042 (impulse на линию reset)
void reboot() {
    unsigned char temp;

    __asm__("cli");

    // Опустошаем буфер контроллера клавиатуры перед отправкой команды
    do {
        temp = port_byte_in(0x64);
        if (temp & 1) port_byte_in(0x60);
    } while (temp & 2);

    port_byte_out(0x64, 0xFE); // команда сброса (pulse output line, импульс на CPU RESET)

    while (1) {
        __asm__("hlt");
    }
}

// --- Таблица системных вызовов (int 0x80) ---
// Каждый обработчик принимает один аргумент (ESI вызывающей программы).
// При портировании на другую архитектуру меняется только мост в
// syscalls.asm — эта таблица и обработчики переезжают как есть.
typedef void (*syscall_fn)(char*);

void sys_print_string(char* arg) {
    print_string(arg);
}

void sys_clear_screen(char* arg) {
    clear_screen();
}

syscall_fn syscall_table[] = {
    0,                 // 0x00 — не используется
    sys_print_string,  // 0x01 — печать строки (ESI -> строка с '\0')
    sys_clear_screen,  // 0x02 — очистка экрана
};

#define SYSCALL_TABLE_SIZE (sizeof(syscall_table) / sizeof(syscall_table[0]))

// Вызывается из syscalls.asm: ищет обработчик по коду функции и выполняет его
void syscall_dispatch(unsigned char func, char* arg) {
    if (func < SYSCALL_TABLE_SIZE && syscall_table[func]) {
        syscall_table[func](arg);
    }
}

// Разбирает и выполняет введённую команду
void execute_command(char* cmd) {
    if (str_eq(cmd, "")) {
        // Пустая команда — ничего не делаем
    } else if (str_eq(cmd, "help")) {
        print_string("Available commands:\n");
        print_string("  help        - show this help\n");
        print_string("  clear       - clear the screen\n");
        print_string("  about       - show OS info\n");
        print_string("  date        - show current date and time\n");
        print_string("  uptime      - show time since boot\n");
        print_string("  sleep <sec> - pause for N seconds (0-9)\n");
        print_string("  reboot      - restart the OS\n");
        print_string("  echo <text> - print text\n");
        print_string("  ls          - list files on FAT12 RAM-disk\n");
        print_string("  cat <file>  - show file contents\n");
    } else if (str_eq(cmd, "clear")) {
        clear_screen();
    } else if (str_eq(cmd, "about")) {
        print_string("AxOS v0.5 - hobby OS in C and x86 Assembly\n");
    } else if (str_eq(cmd, "date") || str_eq(cmd, "time")) {
        print_datetime();
    } else if (str_eq(cmd, "uptime")) {
        print_string("Uptime: ");
        print_uint(timer_ticks / 100);
        print_string(" sec (");
        print_uint(timer_ticks);
        print_string(" ticks)\n");
    } else if (str_starts_with(cmd, "sleep ")) {
        char digit = cmd[6];
        if (digit >= '0' && digit <= '9') {
            print_string("Sleeping...\n");
            sleep_ms((unsigned long)(digit - '0') * 1000);
            print_string("Done.\n");
        } else {
            print_string("Usage: sleep <0-9>\n");
        }
    } else if (str_eq(cmd, "reboot")) {
        print_string("Rebooting...\n");
        reboot();
    } else if (str_starts_with(cmd, "echo ")) {
        print_string(cmd + 5);
        print_string("\n");
    } else if (str_eq(cmd, "ls")) {
        fat12_list();
    } else if (str_starts_with(cmd, "cat ")) {
        if (!fat12_cat(cmd + 4)) {
            print_string("File not found.\n");
        }
    } else {
        print_string("Unknown command: ");
        print_string(cmd);
        print_string("\n");
    }
}

void keyboard_handler_main() {
    // Проверяем статус-регистр (0x64), готов ли контроллер отдать данные
    if (port_byte_in(0x64) & 1) {
        unsigned char scancode = port_byte_in(0x60);

        // Нам нужны только нажатия клавиш
        if (scancode < 128) {
            char letter = scancode_to_char[scancode];

            if (letter == '\n') {
                command_buffer[command_len] = '\0';
                print_string("\n");
                execute_command(command_buffer);
                command_len = 0;
                print_string("AxOS> ");
            } else if (letter == '\b') {
                if (command_len > 0) {
                    command_len--;
                    backspace();
                }
            } else if (letter != 0) {
                if (command_len < (int)sizeof(command_buffer) - 1) {
                    command_buffer[command_len] = letter;
                    command_len++;
                    char str[2] = {letter, '\0'};
                    print_string(str); // Печатаем символ асинхронно!
                }
            }
        }
    }
}

void kernel_main() {
    // Тестовый вывод для проверки вызова функции
    char* video_memory = (char*) 0xB8000;
    video_memory[0] = 'M';
    video_memory[1] = 0x0F;
    video_memory[2] = 'S';
    video_memory[3] = 0x0F;
    video_memory[4] = 'N';
    video_memory[5] = 0x0F;
    
    clear_screen();
    init_idt();
    print_string("AxOS v0.5 [Interrupt Mode]\nAxOS> ");

    // БЕСКОНЕЧНЫЙ ЦИКЛ ОБЯЗАТЕЛЕН
    while(1) {
        __asm__("hlt"); // Процессор будет спать до прихода прерывания от клавиатуры
    }
}