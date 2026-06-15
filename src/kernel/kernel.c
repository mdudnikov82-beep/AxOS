#include "keyboard.h" // Подключаем твои порты ввода-вывода и карту скан-кодов
#include "../fs/fat12.h" // Драйвер FAT12 для RAM-диска (конфиги/скрипты/файлы программ)
#include "../user/syscall.h" // ABI системных вызовов, общий с ring3-программами
#include "ide.h" // PIO-драйвер ATA/IDE (build/disk.img - настоящий диск)
#include "paging.h" // Защита памяти: paging + read-only код ядра
#include "tss.h" // TSS: переключение стека ring3 -> ring0
#include "heap.h" // kmalloc/kfree - простой кучевой аллокатор
#include "tasking.h" // простой preemptive round-robin планировщик

#define SCREEN_WIDTH 80
#define VIDEO_MEMORY 0xB8000
#define DEFAULT_COLOR 0x1F

// Слоты загрузки пользовательских программ командой "run" (см. user.ld).
// 1 МБ - внутри identity-mapped region (paging.c), далеко от ядра, кучи,
// стеков и видеопамяти, уже PRESENT|USER|RW. USER_PROGRAM_SLOTS слотов по
// USER_PROGRAM_SLOT_SIZE байт каждый (0x100000-0x120000), выдаются по
// кругу: каждый "run" занимает следующий слот, так что несколько программ
// могут работать одновременно. Слот переиспользуется после полного круга -
// "run" перезапишет программу, занимавшую этот слот ранее, если она ещё
// работает (без отдельных адресных пространств на задачу иначе никак).
#define USER_PROGRAM_SLOTS     4
#define USER_PROGRAM_SLOT_SIZE 0x8000
#define USER_PROGRAM_BASE      0x100000

static int next_user_slot = 0;

// Прототипы функций
void clear_screen();
void print_string(char* str);
void backspace();
void init_idt();
extern void keyboard_interrupt_handler();
extern void timer_interrupt_handler();
extern void syscall_handler();
extern void enter_usermode(void (*entry)(void)); // usermode.asm — переход в ring3
int command_len = 0;
char command_buffer[64];

// Последний нажатый символ для SYS_READ_KEY (неблокирующее чтение
// клавиатуры из ring3). Обновляется в keyboard_handler_main и
// "потребляется" (обнуляется) при чтении - отдельный канал от
// command_buffer, не мешает работе shell.
volatile char last_key = 0;

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
    set_idt_gate(14, (unsigned long)page_fault_handler); // #PF — для отладки paging
    set_idt_gate(32, (unsigned long)timer_interrupt_handler);
    set_idt_gate(33, (unsigned long)keyboard_interrupt_handler);
    set_idt_gate(0x80, (unsigned long)syscall_handler); // int 0x80 — системные вызовы AxOS
    IDT[0x80].type_attr = 0xEE; // DPL=3 — int 0x80 разрешён из ring3
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

// Разбирает десятичное число из начала строки (нецифровые символы после
// числа игнорируются)
unsigned int parse_uint(char* s) {
    unsigned int val = 0;
    while (*s >= '0' && *s <= '9') {
        val = val * 10 + (unsigned int)(*s - '0');
        s++;
    }
    return val;
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

// Печатает беззнаковое число в виде 8-значного hex (с ведущими нулями)
static void print_hex(unsigned int val) {
    char hex_digits[] = "0123456789ABCDEF";
    char buf[9];
    buf[8] = '\0';
    for (int i = 7; i >= 0; i--) {
        buf[i] = hex_digits[val & 0xF];
        val >>= 4;
    }
    print_string(buf);
}

// Печатает один байт как 2-значный hex (без префикса)
static void print_hex_byte(unsigned char val) {
    char hex_digits[] = "0123456789ABCDEF";
    char buf[3] = { hex_digits[val >> 4], hex_digits[val & 0xF], '\0' };
    print_string(buf);
}

// Печатает первые size байт buf как hex, по 16 байт на строку
static void print_hex_dump(unsigned char* buf, unsigned int size) {
    for (unsigned int i = 0; i < size; i++) {
        print_hex_byte(buf[i]);
        print_string((i % 16 == 15) ? "\n" : " ");
    }
    if (size % 16 != 0) print_string("\n");
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

// SYS_READ_KEY: неблокирующее чтение клавиатуры. ESI -> char, куда
// записывается последний нажатый символ (0, если ничего не нажато
// с прошлого опроса). Прочитанный символ "потребляется" - last_key
// сбрасывается в 0.
void sys_read_key(char* arg) {
    if (arg) {
        *arg = last_key;
        last_key = 0;
    }
}

// SYS_WRITE_FILE: ESI -> struct write_file_args
void sys_write_file(char* arg) {
    struct write_file_args* a = (struct write_file_args*)arg;
    fat12_write(a->filename, a->data, a->size);
}

// SYS_READ_FILE: ESI -> struct read_file_args. Фактический размер
// записывается обратно в a->out_size.
void sys_read_file(char* arg) {
    struct read_file_args* a = (struct read_file_args*)arg;
    a->out_size = fat12_load(a->filename, a->buffer, a->max_size);
}

syscall_fn syscall_table[] = {
    0,                 // 0x00 — не используется
    sys_print_string,  // 0x01 — печать строки (ESI -> строка с '\0')
    sys_clear_screen,  // 0x02 — очистка экрана
    sys_read_key,      // 0x03 — чтение клавиатуры (ESI -> char)
    sys_write_file,    // 0x04 — запись файла (ESI -> struct write_file_args)
    sys_read_file,     // 0x05 — чтение файла (ESI -> struct read_file_args)
};

#define SYSCALL_TABLE_SIZE (sizeof(syscall_table) / sizeof(syscall_table[0]))

// Вызывается из syscalls.asm: ищет обработчик по коду функции и выполняет его
void syscall_dispatch(unsigned char func, char* arg) {
    if (func < SYSCALL_TABLE_SIZE && syscall_table[func]) {
        syscall_table[func](arg);
    }
}

// --- Демо-программа ring3 ---
// Выполняется с CPL=3: не имеет доступа к привилегированным
// инструкциям (cli/hlt/lgdt/...), но может вызывать ядро через
// int 0x80 (IDT[0x80] открыт для DPL=3 в init_idt).
void usermode_demo() {
    char* msg = "Hello from ring3 (user mode)! Syscall int 0x80 works.\n";

    __asm__ volatile(
        "mov $0x01, %%ah\n" // 0x01 — sys_print_string
        "mov %0, %%esi\n"
        "int $0x80\n"
        :: "r"(msg) : "eax", "esi"
    );

    while (1) {
        // ring3-код не может выполнить hlt (привилегированная инструкция),
        // поэтому просто крутимся — таймер/клавиатура продолжают работать
        // через прерывания.
    }
}

// --- Демо/тест кучи (malloc/free) ---
// Выделяет несколько блоков разного размера, записывает и проверяет
// данные, освобождает часть блоков, выделяет снова — проверяя
// повторное использование и слияние (coalescing). Печатает PASS/FAIL
// и диагностику (адреса, размеры).
void memtest_demo() {
    int ok = 1;

    print_string("Heap test:\n");

    char* a = (char*)malloc(64);
    char* b = (char*)malloc(128);
    char* c = (char*)malloc(32);

    print_string("  malloc(64)  -> 0x");
    print_hex((unsigned int)a);
    print_string("\n  malloc(128) -> 0x");
    print_hex((unsigned int)b);
    print_string("\n  malloc(32)  -> 0x");
    print_hex((unsigned int)c);
    print_string("\n");

    if (!a || !b || !c) {
        print_string("  FAIL: malloc returned NULL\n");
        return;
    }

    for (int i = 0; i < 64; i++)  a[i] = (char)i;
    for (int i = 0; i < 128; i++) b[i] = (char)(i ^ 0x55);
    for (int i = 0; i < 32; i++)  c[i] = (char)(255 - i);

    for (int i = 0; i < 64; i++)  if (a[i] != (char)i) ok = 0;
    for (int i = 0; i < 128; i++) if (b[i] != (char)(i ^ 0x55)) ok = 0;
    for (int i = 0; i < 32; i++)  if (c[i] != (char)(255 - i)) ok = 0;

    if (!ok) {
        print_string("  FAIL: data verification failed\n");
        return;
    }
    print_string("  Data write/read-back OK\n");

    free(b);
    print_string("  Freed block b (128 bytes)\n");

    char* d = (char*)malloc(100);
    print_string("  malloc(100) -> 0x");
    print_hex((unsigned int)d);
    print_string("\n");

    if (!d) {
        print_string("  FAIL: malloc(100) after free returned NULL\n");
        return;
    }

    if ((unsigned int)d != (unsigned int)b) {
        print_string("  WARNING: malloc(100) did not reuse freed block b's address\n");
    } else {
        print_string("  Reused freed block's address - OK\n");
    }

    free(a);
    free(c);
    free(d);

    char* big = (char*)malloc(300);
    print_string("  malloc(300) after freeing all -> 0x");
    print_hex((unsigned int)big);
    print_string("\n");

    if (!big) {
        print_string("  FAIL: malloc(300) after freeing all returned NULL (coalescing broken?)\n");
        return;
    }

    for (int i = 0; i < 300; i++) big[i] = (char)(i & 0xFF);
    for (int i = 0; i < 300; i++) if (big[i] != (char)(i & 0xFF)) ok = 0;

    if (!ok) {
        print_string("  FAIL: data verification failed on coalesced block\n");
        return;
    }

    free(big);

    print_string("PASS: heap allocator OK\n");
}

// --- Фоновая задача-демо для планировщика (tasking.c) ---
// Анимирует спиннер в правом верхнем углу экрана. Пишет напрямую в
// видеопамять (не через print_string/cursor_x/y), чтобы не конфликтовать
// с выводом shell — наглядное доказательство, что задача выполняется
// параллельно (по тикам таймера) независимо от основного потока.
void heartbeat_task() {
    char spinner[] = "|/-\\";
    unsigned int frame = 0;

    while (1) {
        unsigned char* vidmem = (unsigned char*)0xB8000;
        int offset = (0 * 80 + 79) * 2; // строка 0, столбец 79
        vidmem[offset] = spinner[frame % 4];
        vidmem[offset + 1] = 0x0A; // ярко-зелёный на чёрном

        frame++;
        for (volatile unsigned int i = 0; i < 200000; i++);
    }
}

// --- Фоновая ring3-задача-демо для планировщика (tasking.c) ---
// То же самое, что heartbeat_task, но выполняется с CPL=3 (создаётся
// через task_create_user) - доказывает, что планировщик корректно
// переключает и резюмирует задачи в ring3 (PAGE_USER разрешает доступ
// к видеопамяти из ring3, см. paging.c). Без привилегированных
// инструкций (hlt и т.п. недопустимы в ring3).
void ring3_spinner_task() {
    char spinner[] = "+x*.";
    unsigned int frame = 0;

    while (1) {
        unsigned char* vidmem = (unsigned char*)0xB8000;
        int offset = (0 * 80 + 78) * 2; // строка 0, столбец 78
        vidmem[offset] = spinner[frame % 4];
        vidmem[offset + 1] = 0x0B; // ярко-голубой на чёрном

        frame++;
        for (volatile unsigned int i = 0; i < 200000; i++);
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
        print_string("  write <file> <text> - create/overwrite a file\n");
        print_string("  run <file>  - load and run a program from FAT12 (ring3)\n");
        print_string("  diskinfo    - show IDE drive model (build/disk.img)\n");
        print_string("  diskread <lba>  - hexdump a sector from the IDE disk\n");
        print_string("  diskwrite <lba> <text> - write text to a sector on the IDE disk\n");
        print_string("  usermode    - demo: jump to ring3, call syscall via int 0x80\n");
        print_string("  memtest     - test heap allocator (malloc/free)\n");
        print_string("  ps          - list running tasks\n");
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
    } else if (str_starts_with(cmd, "write ")) {
        char* filename = cmd + 6;
        if (*filename == '\0') {
            print_string("Usage: write <file> <text>\n");
        } else {
            char* text = filename;
            while (*text != '\0' && *text != ' ') text++;
            if (*text == ' ') { *text = '\0'; text++; }

            unsigned int len = 0;
            while (text[len] != '\0') len++;

            if (fat12_write(filename, (unsigned char*)text, len)) {
                print_string("Written.\n");
            } else {
                print_string("Write failed (disk full?).\n");
            }
        }
    } else if (str_starts_with(cmd, "run ")) {
        unsigned int addr = USER_PROGRAM_BASE + next_user_slot * USER_PROGRAM_SLOT_SIZE;
        unsigned int size = fat12_load(cmd + 4, (unsigned char*)addr, USER_PROGRAM_SLOT_SIZE);
        if (size == 0) {
            print_string("File not found.\n");
        } else {
            task_create_user(cmd + 4, (void (*)(void))addr);
            next_user_slot = (next_user_slot + 1) % USER_PROGRAM_SLOTS;
            print_string("Started.\n");
        }
    } else if (str_eq(cmd, "diskinfo")) {
        char model[41];
        if (ide_identify(model)) {
            print_string("IDE primary master: ");
            print_string(model);
            print_string("\n");
        } else {
            print_string("No IDE drive found.\n");
        }
    } else if (str_starts_with(cmd, "diskread ")) {
        char* p = cmd + 9;
        if (*p < '0' || *p > '9') {
            print_string("Usage: diskread <lba>\n");
        } else {
            unsigned int lba = parse_uint(p);
            unsigned char buf[IDE_SECTOR_SIZE];
            if (ide_read_sector(lba, buf)) {
                print_hex_dump(buf, 128);
            } else {
                print_string("Disk read failed (no IDE drive?).\n");
            }
        }
    } else if (str_starts_with(cmd, "diskwrite ")) {
        char* p = cmd + 10;
        if (*p < '0' || *p > '9') {
            print_string("Usage: diskwrite <lba> <text>\n");
        } else {
            unsigned int lba = parse_uint(p);
            while (*p >= '0' && *p <= '9') p++;
            if (*p == ' ') p++;

            unsigned char buf[IDE_SECTOR_SIZE];
            for (unsigned int i = 0; i < IDE_SECTOR_SIZE; i++) buf[i] = 0;

            unsigned int i = 0;
            while (p[i] != '\0' && i < IDE_SECTOR_SIZE) {
                buf[i] = p[i];
                i++;
            }

            if (ide_write_sector(lba, buf)) {
                print_string("Written.\n");
            } else {
                print_string("Disk write failed (no IDE drive?).\n");
            }
        }
    } else if (str_eq(cmd, "usermode")) {
        // enter_usermode() - билет в один конец (iretd без возврата), так
        // что код после execute_command() в keyboard_handler_main (сброс
        // command_len и печать приглашения) для этого вызова не выполнится.
        // Делаем это здесь заранее, иначе следующий ввод склеится с "usermode".
        command_len = 0;
        print_string("Switching to ring3...\n");
        print_string("AxOS> ");
        enter_usermode(usermode_demo);
    } else if (str_eq(cmd, "memtest")) {
        memtest_demo();
    } else if (str_eq(cmd, "ps")) {
        print_task_list();
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

            if (letter != 0) {
                last_key = letter; // канал для SYS_READ_KEY (ring3)
            }

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
    init_paging();
    init_tss();
    init_heap();
    init_tasking();
    task_create("heartbeat", heartbeat_task);
    task_create_user("ring3demo", ring3_spinner_task);
    print_string("AxOS v0.5 [Interrupt Mode]\nAxOS> ");

    // БЕСКОНЕЧНЫЙ ЦИКЛ ОБЯЗАТЕЛЕН
    while(1) {
        __asm__("hlt"); // Процессор будет спать до прихода прерывания от клавиатуры
    }
}