#include "keyboard.h" // Подключаем твои порты ввода-вывода и карту скан-кодов

#define SCREEN_WIDTH 80
#define VIDEO_MEMORY 0xB8000
#define DEFAULT_COLOR 0x1F

// Прототипы функций
void clear_screen();
void print_string(char* str);
void backspace();
void init_idt();
extern void keyboard_interrupt_handler();
extern void syscall_handler();
int command_len = 0;
char command_buffer[64];

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

void init_idt() {
    set_idt_gate(33, (unsigned long)keyboard_interrupt_handler);
    set_idt_gate(0x80, (unsigned long)syscall_handler); // int 0x80 — системные вызовы AxOS
    struct { unsigned short limit; unsigned long base; } __attribute__((packed)) idtr = { 256 * 8 - 1, (unsigned long)IDT };
    __asm__("lidt %0" : : "m"(idtr));
    
    // Перенастройка PIC
    __asm__("outb %0, %1" : : "a"((unsigned char)0x11), "Nd"(0x20));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x11), "Nd"(0xA0));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x20), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x28), "Nd"(0xA1));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x04), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x02), "Nd"(0xA1));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x01), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0x01), "Nd"(0xA1));

    // Маскируем все IRQ, кроме клавиатуры (IRQ1): у нас нет обработчика
    // таймера (IRQ0) и других прерываний, их срабатывание без IDT-записи
    // приводит к тройному сбою.
    __asm__("outb %0, %1" : : "a"((unsigned char)0xFD), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0xFF), "Nd"(0xA1));

    __asm__("sti");
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

// Разбирает и выполняет введённую команду
void execute_command(char* cmd) {
    if (str_eq(cmd, "")) {
        // Пустая команда — ничего не делаем
    } else if (str_eq(cmd, "help")) {
        print_string("Available commands:\n");
        print_string("  help        - show this help\n");
        print_string("  clear       - clear the screen\n");
        print_string("  about       - show OS info\n");
        print_string("  echo <text> - print text\n");
    } else if (str_eq(cmd, "clear")) {
        clear_screen();
    } else if (str_eq(cmd, "about")) {
        print_string("AxOS v0.5 - hobby OS in C and x86 Assembly\n");
    } else if (str_starts_with(cmd, "echo ")) {
        print_string(cmd + 5);
        print_string("\n");
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