#include "keyboard.h" // Подключаем твои порты ввода-вывода и карту скан-кодов
#include "vfs.h" // VFS: тонкий слой перенаправления к драйверу ФС (сейчас - FAT12)
#include "../user/syscall.h" // ABI системных вызовов, общий с ring3-программами
#include "ide.h" // PIO-драйвер ATA/IDE (build/disk.img - настоящий диск)
#include "paging.h" // Защита памяти: paging + read-only код ядра
#include "tss.h" // TSS: переключение стека ring3 -> ring0
#include "heap.h" // kmalloc/kfree - простой кучевой аллокатор
#include "tasking.h" // простой preemptive round-robin планировщик
#include "selftest.h" // команда "selftest" - регрессионные тесты heap/paging/FAT12

#define SCREEN_WIDTH 80
#define VIDEO_MEMORY 0xB8000
#define DEFAULT_COLOR 0x1F

// Слоты загрузки пользовательских программ командой "run" (см. user.ld).
// 1 МБ - внутри identity-mapped region (paging.c), далеко от ядра, кучи,
// стеков и видеопамяти, уже PRESENT|USER|RW. USER_PROGRAM_SLOTS слотов по
// USER_PROGRAM_SLOT_SIZE байт каждый (0x100000-0x120000), каждый со своим
// приватным Page Directory (paging.c) - несколько программ могут работать
// одновременно в изоляции друг от друга.
#define USER_PROGRAM_SLOTS     4
#define USER_PROGRAM_SLOT_SIZE 0x8000
#define USER_PROGRAM_BASE      0x100000

// Аргументы командной строки для run-программ.
// Блок sizeof(char*)*8 + строки живёт в конце каждого слота:
//   физический:  phys_slot_base + USER_ARGS_OFFSET
//   виртуальный: USER_ARGS_VADDR (одинаков для всех задач — разные PD)
// Ядро пишет char*[] указатели и строки по физическому адресу (identity-map),
// задача видит их по USER_ARGS_VADDR через свой приватный PD.
#define USER_ARGS_OFFSET   0x7C00
#define USER_ARGS_VADDR    (USER_WINDOW_BASE + USER_ARGS_OFFSET)
#define USER_ARGS_MAX_ARGC 7       // максимум 7 аргументов (argv[0]..argv[6] + NULL)
#define USER_ARGS_STR_OFF  32      // строки после 8 указателей (8 * sizeof(char*) = 32)

// slot_free[i] == 1, если слот i свободен. "run" занимает первый свободный
// слот; при завершении задачи (SYS_EXIT или killed page fault, см.
// tasking.c::schedule) on_task_exit() освобождает его обратно.
static int slot_free[USER_PROGRAM_SLOTS] = {1, 1, 1, 1};

// Виртуальный адрес текущего heap break для каждого слота.
// Инициализируется при запуске задачи (после загрузки кода), сбрасывается при выходе.
static unsigned int slot_heap_brk[USER_PROGRAM_SLOTS];

// Heap не должен перекрывать argv-блок. Оставляем 0x200 байт зазора.
#define USER_HEAP_LIMIT (USER_ARGS_VADDR - 0x200)

// Вызывается из tasking.c::schedule() при реапе изолированной run-задачи.
void on_task_exit(int user_slot_index) {
    slot_free[user_slot_index] = 1;
    slot_heap_brk[user_slot_index] = 0;
}

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

// Когда равно 1, kernel shell не обрабатывает ввод — клавиатура принадлежит
// user-space shell (sh.bin) через SYS_SHELL_CLAIM.
static int kernel_shell_inhibited = 0;

// Ctrl-флаг и foreground slot для реализации Ctrl+C.
// foreground_slot >= 0: sh.bin ждёт завершения этой задачи (Ctrl+C убьёт её).
// foreground_slot == -1: нет активного foreground-процесса (Ctrl+C игнорируется).
static int ctrl_held       = 0;
static int shift_held      = 0;
static int e0_prefix       = 0;
static int foreground_slot = -1;

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
    vfs_write(a->filename, a->data, a->size);
}

// SYS_READ_FILE: ESI -> struct read_file_args. Фактический размер
// записывается обратно в a->out_size.
void sys_read_file(char* arg) {
    struct read_file_args* a = (struct read_file_args*)arg;
    a->out_size = vfs_read(a->filename, a->buffer, a->max_size);
}

// SYS_EXIT: текущая задача завершилась - schedule() уберёт её из кольца
// планировщика и освободит её ресурсы (kernel-стек, task_t, слот run)
// на следующем тике (см. tasking.c).
void sys_exit(char* arg) {
    task_mark_current_exiting();
}

// --- fd-based file API (SYS_OPEN/SYS_FREAD/SYS_FWRITE/SYS_CLOSE) ---

#define MAX_FDS       4
#define MAX_FILE_BUF  4096

struct fd_entry {
    int            valid;
    int            flags;
    char           name[13];
    unsigned char* buf;
    unsigned int   size;
    unsigned int   pos;
};

static struct fd_entry fd_table[MAX_FDS];
static int fd_table_inited = 0;

static void fd_table_ensure_init(void) {
    if (!fd_table_inited) {
        for (int i = 0; i < MAX_FDS; i++) fd_table[i].valid = 0;
        fd_table_inited = 1;
    }
}

// SYS_OPEN: открыть файл. O_RDONLY — загружает содержимое в буфер;
// O_WRONLY|O_CREAT — создаёт пустой буфер для записи.
// Возвращает fd (>= 0) через open_args.result, или -1 при ошибке.
void sys_open(char* arg) {
    struct open_args* a = (struct open_args*)arg;
    a->result = -1;
    fd_table_ensure_init();

    int slot = -1;
    for (int i = 0; i < MAX_FDS; i++) {
        if (!fd_table[i].valid) { slot = i; break; }
    }
    if (slot < 0) return;

    char* name = a->filename;
    int ni = 0;
    while (name[ni] && ni < 12) { fd_table[slot].name[ni] = name[ni]; ni++; }
    fd_table[slot].name[ni] = '\0';

    fd_table[slot].flags = a->flags;
    fd_table[slot].pos   = 0;
    fd_table[slot].size  = 0;
    fd_table[slot].buf   = (unsigned char*)malloc(MAX_FILE_BUF);
    if (!fd_table[slot].buf) return;

    if (a->flags == O_RDONLY) {
        unsigned int n = vfs_read(fd_table[slot].name,
                                  fd_table[slot].buf, MAX_FILE_BUF);
        if (n == 0) { free(fd_table[slot].buf); fd_table[slot].buf = 0; return; }
        fd_table[slot].size = n;
    }
    // O_WRONLY|O_CREAT: буфер пустой, данные пишутся через sys_fwrite

    fd_table[slot].valid = 1;
    a->result = slot;
}

// SYS_FREAD: прочитать до count байт из fd в пользовательский buf.
// fread_args.result = фактически прочитанные байты; 0 = EOF; -1 = ошибка.
void sys_fread(char* arg) {
    struct fread_args* a = (struct fread_args*)arg;
    a->result = -1;
    int fd = a->fd;
    if (fd < 0 || fd >= MAX_FDS || !fd_table[fd].valid) return;
    if (fd_table[fd].flags != O_RDONLY) return;

    unsigned int remaining = fd_table[fd].size - fd_table[fd].pos;
    unsigned int to_copy   = a->count < remaining ? a->count : remaining;

    unsigned char* src = fd_table[fd].buf + fd_table[fd].pos;
    unsigned char* dst = a->buf;
    for (unsigned int i = 0; i < to_copy; i++) dst[i] = src[i];
    fd_table[fd].pos += to_copy;
    a->result = (int)to_copy;
}

// SYS_FWRITE: записать count байт из buf в fd (накапливается в буфере
// ядра; на диск сбрасывается только при SYS_CLOSE).
void sys_fwrite(char* arg) {
    struct fwrite_args* a = (struct fwrite_args*)arg;
    a->result = -1;
    int fd = a->fd;
    if (fd < 0 || fd >= MAX_FDS || !fd_table[fd].valid) return;
    if (fd_table[fd].flags == O_RDONLY) return;

    unsigned int space    = MAX_FILE_BUF - fd_table[fd].pos;
    unsigned int to_copy  = a->count < space ? a->count : space;

    unsigned char* src = a->buf;
    unsigned char* dst = fd_table[fd].buf + fd_table[fd].pos;
    for (unsigned int i = 0; i < to_copy; i++) dst[i] = src[i];
    fd_table[fd].pos += to_copy;
    if (fd_table[fd].pos > fd_table[fd].size) fd_table[fd].size = fd_table[fd].pos;
    a->result = (int)to_copy;
}

// SYS_CLOSE: закрыть fd. Если был открыт на запись — сбросить на диск.
void sys_close(char* arg) {
    struct close_args* a = (struct close_args*)arg;
    int fd = a->fd;
    if (fd < 0 || fd >= MAX_FDS || !fd_table[fd].valid) return;

    if (fd_table[fd].flags != O_RDONLY && fd_table[fd].size > 0)
        vfs_write(fd_table[fd].name, fd_table[fd].buf, fd_table[fd].size);

    free(fd_table[fd].buf);
    fd_table[fd].buf   = 0;
    fd_table[fd].valid = 0;
}

// SYS_EXEC: загрузить и запустить бинарник из FAT12 по имени.
// Разбирает cmdline на токены (первый — имя файла, остальные — argv).
// Возвращает slot-индекс (>= 0) или -1 (файл не найден) / -2 (нет слотов).
void sys_exec(char* arg) {
    struct exec_args* a = (struct exec_args*)arg;
    a->result = -1;

    char* cmdline = a->cmdline;
    if (!cmdline) return;

    char filename[24];
    int fi = 0;
    char* p = cmdline;
    while (*p && *p != ' ' && fi < 23) filename[fi++] = *p++;
    filename[fi] = '\0';
    if (fi == 0) return;

    // Если в имени нет точки — подставляем ".bin" (ls → ls.bin)
    int has_dot = 0;
    for (int i = 0; i < fi; i++) if (filename[i] == '.') { has_dot = 1; break; }
    if (!has_dot && fi <= 19) {
        filename[fi++] = '.';
        filename[fi++] = 'b';
        filename[fi++] = 'i';
        filename[fi++] = 'n';
        filename[fi]   = '\0';
    }

    int slot = -1;
    for (int i = 0; i < USER_PROGRAM_SLOTS; i++) {
        if (slot_free[i]) { slot = i; break; }
    }
    if (slot < 0) { a->result = -2; return; }

    unsigned int addr = USER_PROGRAM_BASE + slot * USER_PROGRAM_SLOT_SIZE;
    unsigned int size = vfs_read(filename, (unsigned char*)addr, USER_ARGS_OFFSET);
    if (size == 0) return;

    char** argv_phys = (char**)(addr + USER_ARGS_OFFSET);
    char*  sp        = (char*)(addr + USER_ARGS_OFFSET + USER_ARGS_STR_OFF);
    unsigned int sv  = USER_ARGS_VADDR + USER_ARGS_STR_OFF;
    int argc = 0;

    argv_phys[argc++] = (char*)sv;
    for (int i = 0; filename[i]; i++) { *sp++ = filename[i]; sv++; }
    *sp++ = '\0'; sv++;

    while (*p == ' ') p++;
    while (*p && argc <= USER_ARGS_MAX_ARGC) {
        argv_phys[argc++] = (char*)sv;
        while (*p && *p != ' ') { *sp++ = *p++; sv++; }
        *sp++ = '\0'; sv++;
        while (*p == ' ') p++;
    }
    argv_phys[argc] = 0;

    slot_heap_brk[slot] = USER_WINDOW_BASE + ((size + 15) & ~15u);
    slot_free[slot] = 0;
    task_create_user_isolated(filename, addr, slot, argc, USER_ARGS_VADDR);
    a->result = slot;
}

// SYS_TASK_ALIVE: неблокирующая проверка — завершена ли задача в слоте.
// sh.bin вызывает в цикле busy-wait, пока дочерняя задача работает.
void sys_task_alive(char* arg) {
    struct task_alive_args* a = (struct task_alive_args*)arg;
    int slot = a->slot;
    a->result = (slot >= 0 && slot < USER_PROGRAM_SLOTS && !slot_free[slot]) ? 1 : 0;
}

// SYS_SHELL_CLAIM: захват/освобождение клавиатуры.
// arg = (char*)1 — захват (kernel shell пассивен, sh.bin обрабатывает ввод).
// arg = (char*)0 — освобождение (kernel shell снова активен).
void sys_shell_claim(char* arg) {
    int was_inhibited = kernel_shell_inhibited;
    kernel_shell_inhibited = (arg != (char*)0);
    if (was_inhibited && !kernel_shell_inhibited) {
        command_len = 0;
        print_string("\nAxOS> ");
    }
}

// SYS_SET_FOREGROUND: сообщает ядру, какой слот сейчас на переднем плане.
// sh.bin вызывает перед busy-wait (slot >= 0) и после него (slot = -1).
// keyboard_handler_main использует foreground_slot для Ctrl+C.
void sys_set_foreground(char* arg) {
    struct set_fg_args* a = (struct set_fg_args*)arg;
    foreground_slot = a->slot;
}

// SYS_GET_TICKS: возвращает текущее значение timer_ticks (100 Гц).
// Секунды от загрузки = result / 100.
void sys_get_ticks(char* arg) {
    struct get_ticks_args* a = (struct get_ticks_args*)arg;
    a->result = (unsigned int)timer_ticks;
}

// SYS_SLEEP: блокирует вызывающую задачу на ms миллисекунд.
// sleep_ms включает прерывания через sti — другие задачи получают CPU во время ожидания.
void sys_sleep(char* arg) {
    struct sleep_args* a = (struct sleep_args*)arg;
    sleep_ms((unsigned long)a->ms);
}

void sys_readdir(char* arg) {
    struct readdir_args* a = (struct readdir_args*)arg;
    a->result = vfs_readdir(a->index, a->name, &a->size);
}

// SYS_SBRK: сдвигает heap break задачи на increment байт вперёд.
// Возвращает старый break (начало выделенного региона) или -1 при переполнении.
void sys_sbrk(char* arg) {
    struct sbrk_args* a = (struct sbrk_args*)arg;
    int slot = task_current_slot_index();
    if (slot < 0) { a->result = (unsigned int)-1; return; }

    unsigned int old_brk = slot_heap_brk[slot];
    unsigned int new_brk = old_brk + (unsigned int)a->increment;
    if (a->increment > 0 && new_brk > USER_HEAP_LIMIT) {
        a->result = (unsigned int)-1;
        return;
    }
    slot_heap_brk[slot] = new_brk;
    a->result = old_brk;
}

syscall_fn syscall_table[] = {
    0,                 // 0x00 — не используется
    sys_print_string,  // 0x01
    sys_clear_screen,  // 0x02
    sys_read_key,      // 0x03
    sys_write_file,    // 0x04
    sys_read_file,     // 0x05
    sys_exit,          // 0x06
    sys_open,          // 0x07
    sys_fread,         // 0x08
    sys_fwrite,        // 0x09
    sys_close,         // 0x0A
    sys_exec,          // 0x0B
    sys_task_alive,    // 0x0C
    sys_shell_claim,   // 0x0D
    sys_set_foreground,// 0x0E
    sys_get_ticks,     // 0x0F
    sys_sleep,         // 0x10
    sys_readdir,       // 0x11
    sys_sbrk,          // 0x12
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
int memtest_demo() {
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
        return 0;
    }

    for (int i = 0; i < 64; i++)  a[i] = (char)i;
    for (int i = 0; i < 128; i++) b[i] = (char)(i ^ 0x55);
    for (int i = 0; i < 32; i++)  c[i] = (char)(255 - i);

    for (int i = 0; i < 64; i++)  if (a[i] != (char)i) ok = 0;
    for (int i = 0; i < 128; i++) if (b[i] != (char)(i ^ 0x55)) ok = 0;
    for (int i = 0; i < 32; i++)  if (c[i] != (char)(255 - i)) ok = 0;

    if (!ok) {
        print_string("  FAIL: data verification failed\n");
        return 0;
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
        return 0;
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
        return 0;
    }

    for (int i = 0; i < 300; i++) big[i] = (char)(i & 0xFF);
    for (int i = 0; i < 300; i++) if (big[i] != (char)(i & 0xFF)) ok = 0;

    if (!ok) {
        print_string("  FAIL: data verification failed on coalesced block\n");
        return 0;
    }

    free(big);

    print_string("PASS: heap allocator OK\n");
    return 1;
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
        print_string("  write <file> <text> - create/overwrite a file (needs unlock)\n");
        print_string("  lock        - write-protect the FAT12 disk (default)\n");
        print_string("  unlock      - allow writes to the FAT12 disk\n");
        print_string("  run <file>  - load and run a program from FAT12 (ring3)\n");
        print_string("  diskinfo    - show IDE drive model (build/disk.img)\n");
        print_string("  diskread <lba>  - hexdump a sector from the IDE disk\n");
        print_string("  diskwrite <lba> <text> - write text to a sector on the IDE disk\n");
        print_string("  usermode    - demo: jump to ring3, call syscall via int 0x80\n");
        print_string("  memtest     - test heap allocator (malloc/free)\n");
        print_string("  selftest    - run heap/paging/FAT12 regression tests\n");
        print_string("  ps          - list running tasks\n");
    } else if (str_eq(cmd, "clear")) {
        clear_screen();
    } else if (str_eq(cmd, "about")) {
        print_string("AxOS v0.6 - hobby OS in C and x86 Assembly\n");
        print_string("FAT12 disk: ");
        print_string(vfs_is_locked() ? "locked (read-only)\n" : "unlocked (read-write)\n");
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
        vfs_list();
    } else if (str_starts_with(cmd, "cat ")) {
        if (!vfs_cat(cmd + 4)) {
            print_string("File not found.\n");
        }
    } else if (str_starts_with(cmd, "write ")) {
        char* filename = cmd + 6;
        if (*filename == '\0') {
            print_string("Usage: write <file> <text>\n");
        } else if (vfs_is_locked()) {
            print_string("Disk is locked. Use 'unlock' to enable writes.\n");
        } else {
            char* text = filename;
            while (*text != '\0' && *text != ' ') text++;
            if (*text == ' ') { *text = '\0'; text++; }

            unsigned int len = 0;
            while (text[len] != '\0') len++;

            if (vfs_write(filename, (unsigned char*)text, len)) {
                print_string("Written.\n");
            } else {
                print_string("Write failed (disk full?).\n");
            }
        }
    } else if (str_eq(cmd, "lock")) {
        vfs_set_locked(1);
        print_string("FAT12 disk locked (read-only).\n");
    } else if (str_eq(cmd, "unlock")) {
        vfs_set_locked(0);
        print_string("FAT12 disk unlocked (read-write).\n");
    } else if (str_starts_with(cmd, "run ")) {
        // Разбиваем "FILENAME [ARG1 ARG2 ...]"
        char* rest = cmd + 4;
        char filename[24];
        int fi = 0;
        while (rest[fi] && rest[fi] != ' ' && fi < 23) { filename[fi] = rest[fi]; fi++; }
        filename[fi] = '\0';

        int slot = -1;
        for (int i = 0; i < USER_PROGRAM_SLOTS; i++) {
            if (slot_free[i]) { slot = i; break; }
        }

        if (slot == -1) {
            print_string("No free program slots, try again later.\n");
        } else {
            unsigned int addr = USER_PROGRAM_BASE + slot * USER_PROGRAM_SLOT_SIZE;
            // Загружаем бинарник только в первые USER_ARGS_OFFSET байт слота
            unsigned int size = vfs_read(filename, (unsigned char*)addr, USER_ARGS_OFFSET);
            if (size == 0) {
                print_string("File not found.\n");
            } else {
                // Строим argv-блок по физическому адресу (identity-mapped ядром).
                // USER_ARGS_VADDR — виртуальный адрес того же места для задачи.
                char** argv_phys = (char**)(addr + USER_ARGS_OFFSET);
                char*  sp = (char*)(addr + USER_ARGS_OFFSET + USER_ARGS_STR_OFF);
                unsigned int sv = USER_ARGS_VADDR + USER_ARGS_STR_OFF;
                int argc = 0;

                // argv[0] = имя файла
                argv_phys[argc++] = (char*)sv;
                for (int i = 0; filename[i]; i++) { *sp++ = filename[i]; sv++; }
                *sp++ = '\0'; sv++;

                // argv[1..] — остаток командной строки, токен за токеном
                char* p = rest + fi;
                while (*p == ' ') p++;
                while (*p && argc <= USER_ARGS_MAX_ARGC) {
                    argv_phys[argc++] = (char*)sv;
                    while (*p && *p != ' ') { *sp++ = *p++; sv++; }
                    *sp++ = '\0'; sv++;
                    while (*p == ' ') p++;
                }
                argv_phys[argc] = 0;  // argv[argc] = NULL (POSIX)

                slot_heap_brk[slot] = USER_WINDOW_BASE + ((size + 15) & ~15u);
                slot_free[slot] = 0;
                task_create_user_isolated(filename, addr, slot, argc, USER_ARGS_VADDR);
                print_string("Started.\n");
            }
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
    } else if (str_eq(cmd, "selftest")) {
        run_self_tests();
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

        // Ctrl (левый): 0x1D = нажатие, 0x9D = отпускание.
        // Обрабатываем до фильтра scancode < 128, т.к. 0x9D >= 128.
        if (scancode == 0x1D) { ctrl_held = 1; return; }
        if (scancode == 0x9D) { ctrl_held = 0; return; }

        // Shift (левый 0x2A/0xAA, правый 0x36/0xB6)
        if (scancode == 0x2A || scancode == 0x36) { shift_held = 1; return; }
        if (scancode == 0xAA || scancode == 0xB6) { shift_held = 0; return; }

        // Расширенные клавиши: E0-префикс, затем скан-код.
        // Стрелка вверх = E0 0x48, вниз = E0 0x50.
        // Передаём как спецсимволы 0x11/0x12 в last_key для ax_readkey().
        if (scancode == 0xE0) { e0_prefix = 1; return; }
        if (e0_prefix) {
            e0_prefix = 0;
            if (scancode == 0x48) last_key = '\x11';  // стрелка вверх
            if (scancode == 0x50) last_key = '\x12';  // стрелка вниз
            return;
        }

        // Нам нужны только нажатия клавиш
        if (scancode < 128) {
            char letter = shift_held ? scancode_to_char_shifted[scancode]
                                     : scancode_to_char[scancode];

            if (letter != 0) {
                last_key = letter; // канал для SYS_READ_KEY (ring3)
            }

            // Ctrl+C: убиваем foreground-процесс (если есть).
            // Scancode 0x2E = клавиша C независимо от Shift.
            if (ctrl_held && scancode == 0x2E) {
                if (foreground_slot >= 0) {
                    print_string("^C\n");
                    task_kill_by_slot(foreground_slot);
                    foreground_slot = -1;
                }
                return;
            }

            // Если user-space shell захватил клавиатуру — не обрабатываем команды.
            if (kernel_shell_inhibited) return;

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

// Читает STARTUP.CFG, показывает MOTD.TXT и возвращает 1 если надо
// автоматически запустить shell (AUTOSTART=shell).
static int autoboot() {
    // Показываем MOTD если есть
    unsigned char motd[512];
    unsigned int motd_len = vfs_read("MOTD.TXT", motd, sizeof(motd) - 1);
    if (motd_len > 0) {
        motd[motd_len] = '\0';
        print_string((char*)motd);
        print_string("\n");
    }

    // Парсим STARTUP.CFG построчно в поисках AUTOSTART=shell
    unsigned char cfg[256];
    unsigned int cfg_len = vfs_read("STARTUP.CFG", cfg, sizeof(cfg) - 1);
    if (cfg_len == 0) return 0;
    cfg[cfg_len] = '\0';

    char* p = (char*)cfg;
    while (*p) {
        if (str_starts_with(p, "AUTOSTART=shell")) return 1;
        while (*p && *p != '\n') p++;
        if (*p == '\n') p++;
    }
    return 0;
}

void kernel_main() {
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

    if (!vfs_init()) {
        print_string("Warning: FAT12 disk (build/disk.img) not found - file commands disabled.\n");
    }

    print_string("AxOS v0.6 [Interrupt Mode]\n");

    if (autoboot()) {
        execute_command("run SH.BIN");
    } else {
        print_string("AxOS> ");
    }

    // БЕСКОНЕЧНЫЙ ЦИКЛ ОБЯЗАТЕЛЕН
    while(1) {
        __asm__("hlt");
    }
}