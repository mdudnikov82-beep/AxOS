#include "keyboard.h" // Подключаем твои порты ввода-вывода и карту скан-кодов
#include "vfs.h" // VFS: тонкий слой перенаправления к драйверу ФС (сейчас - FAT12)
#include "../user/syscall.h" // ABI системных вызовов, общий с ring3-программами
#include "ide.h" // PIO-драйвер ATA/IDE (build/disk.img - настоящий диск)
#include "mouse.h" // PS/2-мышь, IRQ12
#include "speaker.h" // системный динамик (PC speaker)
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

// Буферы перенаправления stdout (объявлены здесь — on_task_exit использует их ниже)
#define REDIR_BUF_SIZE 4096
static unsigned char* slot_redir_buf[USER_PROGRAM_SLOTS];
static unsigned int   slot_redir_len[USER_PROGRAM_SLOTS];
static char           slot_redir_file[USER_PROGRAM_SLOTS][13];

// Системный буфер обмена - один общий слот для всех задач (как и реальный
// clipboard в однопользовательской системе). Переживает завершение задач.
static unsigned char clipboard_buf[CLIPBOARD_MAX_SIZE];
static unsigned int  clipboard_len = 0;
// MLS-уровень содержимого буфера обмена - выставляется в уровень ПИСАТЕЛЯ
// при каждом успешном SYS_CLIPBOARD_SET. SYS_CLIPBOARD_GET откажет читателю
// с более низким уровнем ("no read up", классический Bell-LaPadula) - см.
// ax_mac_check_mls() ниже.
static unsigned int clipboard_level = 0;

// Определена ниже, у fd_table (которая объявляется позже по файлу) -
// закрывает все fd, оставшиеся открытыми у завершившейся задачи. Без
// этого её слот освобождается и переиспользуется НОВОЙ задачей, а её
// fd в общей (на всю систему) таблице остаются valid с owner == номер
// слота - который теперь принадлежит этой новой, ни в чём не виноватой
// задаче, и она "наследует" доступ к чужим недозакрытым файлам.
static void fd_release_owner(int owner_slot);

// Вызывается из tasking.c::schedule() при реапе изолированной run-задачи.
void on_task_exit(int user_slot_index) {
    slot_free[user_slot_index] = 1;
    slot_heap_brk[user_slot_index] = 0;
    fd_release_owner(user_slot_index);
    if (slot_redir_buf[user_slot_index]) {
        vfs_write(slot_redir_file[user_slot_index],
                  slot_redir_buf[user_slot_index],
                  slot_redir_len[user_slot_index]);
        free(slot_redir_buf[user_slot_index]);
        slot_redir_buf[user_slot_index]  = 0;
        slot_redir_len[user_slot_index]  = 0;
    }
}

// Прототипы функций
void clear_screen();
void print_string(char* str);
void print_string_to(int tty, char* str);
void backspace();
void init_idt();
void init_ttys();
void tty_switch(int n);
int tty_active();
extern void keyboard_interrupt_handler();
extern void timer_interrupt_handler();
extern void ide_interrupt_handler(); // idt.asm - IRQ14, см. init_idt и ide.c
extern void mouse_interrupt_handler(); // idt.asm - IRQ12, см. init_idt и mouse.c
extern void syscall_handler();
extern void enter_usermode(void (*entry)(void)); // usermode.asm — переход в ring3

// Должно совпадать с TTY_COUNT в screen.c - там нет общего заголовка,
// поэтому константа продублирована (как TSS_SEG в tss.c/gdt.asm).
#define KERNEL_TTY_COUNT 2

// Всё ниже было одной общей переменной на всю систему, пока на каждой
// консоли мог быть только kernel shell. Теперь у каждой TTY (см. screen.c)
// свой независимый AxSH, так что и состояние ввода/shell'а должно быть
// своим на консоль - иначе ввод с одной консоли путался бы с другой.
int command_len[KERNEL_TTY_COUNT] = {0};
char command_buffer[KERNEL_TTY_COUNT][64];

// Последний нажатый символ для SYS_READ_KEY (неблокирующее чтение
// клавиатуры из ring3), отдельно на каждую консоль. Обновляется в
// keyboard_handler_main только для активной (см. tty_active()) и
// "потребляется" (обнуляется) при чтении - отдельный канал от
// command_buffer, не мешает работе shell.
volatile char tty_last_key[KERNEL_TTY_COUNT] = {0};

// tty_kernel_shell_inhibited[t] == 1: kernel shell консоли t не обрабатывает
// ввод — клавиатура принадлежит user-space shell (sh.bin) через SYS_SHELL_CLAIM.
static int tty_kernel_shell_inhibited[KERNEL_TTY_COUNT] = {0};

// Запущен ли уже на консоли t какой-нибудь shell (kernel или AxSH). tty 0
// получает его либо через autoboot(), либо как kernel shell сразу при
// загрузке - считаем, что он там уже "есть". Остальные консоли изначально
// пустые: первое же переключение на них (Ctrl+Alt+F2 и т.д., см.
// keyboard_handler_main) запускает там "run SH.BIN".
static int tty_shell_launched[KERNEL_TTY_COUNT] = {1};

// Привязка слота программы (run/exec) к консоли, на которой её запустили
// (tty_active() в момент запуска - см. do_exec и ветку "run " в
// execute_command). По ней SYS_READ_KEY/SYS_SHELL_CLAIM/SYS_SET_FOREGROUND
// узнают, какую консоль обслуживает текущая задача.
static int slot_tty[USER_PROGRAM_SLOTS];

// Ctrl-флаг и foreground slot (для Ctrl+C) - тоже на каждую консоль.
// tty_foreground_slot[t] >= 0: shell консоли t ждёт завершения этой задачи.
// tty_foreground_slot[t] == -1: нет активного foreground-процесса на t.
static int ctrl_held       = 0;
static int shift_held      = 0;
static int alt_held        = 0;
static int e0_prefix       = 0;
static int tty_foreground_slot[KERNEL_TTY_COUNT] = {-1, -1};

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
    set_idt_gate(0x2E, (unsigned long)ide_interrupt_handler); // IRQ14 (slave PIC) — см. ide.c
    set_idt_gate(0x2C, (unsigned long)mouse_interrupt_handler); // IRQ12 (slave PIC) — см. mouse.c
    set_idt_gate(0x80, (unsigned long)syscall_handler); // int 0x80 — системные вызовы AxOS
    IDT[0x80].type_attr = 0xEE; // DPL=3 — int 0x80 разрешён из ring3
    // type_attr у 0x80 (как и у 32/33 выше) оканчивается на E - interrupt
    // gate, CPU сам обнуляет IF на входе. heap.c (malloc/free) рассчитывает
    // именно на это - см. ENTER_CRITICAL/LEAVE_CRITICAL и комментарий там.
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

    // Маскируем все IRQ, кроме таймера (IRQ0), клавиатуры (IRQ1), IDE
    // (IRQ14, slave PIC) и мыши (IRQ12, slave PIC) — для остальных у нас
    // нет обработчиков, их срабатывание без IDT-записи приводит к
    // тройному сбою.
    //
    // IRQ14/IRQ12 идут через slave PIC, а slave каскадирован в master
    // через IRQ2 - значит, IRQ2 тоже должен быть размаскирован на
    // master, иначе сигнал со slave физически не дойдёт до CPU. Маска
    // мастера: 0xF8 = 11111000 - открыты биты 0,1,2 (IRQ0,1,2). Маска
    // слейва: 0xAF = 10101111 - открыты биты 4 (IRQ8+4 = IRQ12) и 6
    // (IRQ8+6 = IRQ14), всё остальное на слейве для нас пока не нужно.
    __asm__("outb %0, %1" : : "a"((unsigned char)0xF8), "Nd"(0x21));
    __asm__("outb %0, %1" : : "a"((unsigned char)0xAF), "Nd"(0xA1));

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

// Читает час/мин/сек/день/месяц/год из RTC, переводя из BCD при
// необходимости. Используется SYS_GET_DATETIME (userspace date.bin) -
// дата/время в kernel-shell больше нет, см. "date" в help выше.
static void read_rtc(int* second, int* minute, int* hour, int* day, int* month, int* year) {
    // Ждём, пока RTC закончит обновление своих регистров
    while (cmos_read(0x0A) & 0x80);

    *second = cmos_read(0x00);
    *minute = cmos_read(0x02);
    *hour   = cmos_read(0x04);
    *day    = cmos_read(0x07);
    *month  = cmos_read(0x08);
    *year   = cmos_read(0x09);
    unsigned char status_b = cmos_read(0x0B);

    if (!(status_b & 0x04)) { // регистры в формате BCD — переводим в десятичное
        *second = bcd_to_bin(*second);
        *minute = bcd_to_bin(*minute);
        *hour   = bcd_to_bin(*hour & 0x7F);
        *day    = bcd_to_bin(*day);
        *month  = bcd_to_bin(*month);
        *year   = bcd_to_bin(*year);
    }
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

// Объявлены ниже (рядом с caller_tty) - нужны уже здесь, sys_print_string
// идёт раньше по файлу.
static int validate_user_ptr(void* ptr, unsigned int size);
static int validate_user_str(char* s);

void sys_print_string(char* arg) {
    if (!validate_user_str(arg)) return;
    int slot = task_current_slot_index();
    if (slot >= 0 && slot < USER_PROGRAM_SLOTS && slot_redir_buf[slot]) {
        char* s = arg;
        while (*s && slot_redir_len[slot] < REDIR_BUF_SIZE - 1)
            slot_redir_buf[slot][slot_redir_len[slot]++] = *s++;
        return;
    }
    print_string(arg);
}

void sys_clear_screen(char* arg) {
    int slot = task_current_slot_index();
    if (slot >= 0 && slot < USER_PROGRAM_SLOTS && slot_redir_buf[slot]) return;
    clear_screen();
}

// Консоль, которой принадлежит ВЫЗЫВАЮЩАЯ задача (run/exec-слот -> tty,
// см. slot_tty). Для задач без слота (kernel-демо без изоляции) считаем,
// что речь про активную консоль - они не вызывают эти syscall'ы напрямую.
static int caller_tty() {
    int slot = task_current_slot_index();
    if (slot >= 0 && slot < USER_PROGRAM_SLOTS) return slot_tty[slot];
    return tty_active();
}

// Проверяет, что весь диапазон [ptr, ptr+size) лежит внутри легитимного
// "пользовательского окна" вызывающей задачи (USER_WINDOW_BASE..+SIZE,
// см. paging.h) - то есть туда, куда ring3-код мог бы добраться сам,
// без привилегий ring0.
//
// БЕЗ этой проверки: syscall-обработчики читают указатель прямо из
// аргумента, переданного программой (ESI), и разыменовывают его, работая
// с CPL=0. CPL=0 игнорирует бит PAGE_USER в page table - значит, ядро
// готово прочитать/записать ЛЮБУЮ физическую память (другую изолированную
// задачу, .data/.bss/кучу самого ядра - не .text, та read-only даже для
// ring0 из-за CR0.WP), если ring3-программа просто передаст "удобный"
// адрес в качестве buf/data/model. Сама задача такой адрес прочитать не
// смогла бы (её собственная page table не даёт PAGE_USER за пределами
// окна - CPU убил бы её #PF), но через syscall эта защита не работает,
// пока мы явно не проверим адрес здесь.
//
// Только для ИЗОЛИРОВАННЫХ задач (run/exec, task_current_is_isolated()) -
// у task0/heartbeat/ring3demo/usermode_demo нет своего окна и приватной
// page table, это доверенный код ядра, а не загруженные бинарники.
static int validate_user_ptr(void* ptr, unsigned int size) {
    if (!task_current_is_isolated()) return 1; // доверенный (не изолированный) вызывающий
    unsigned int addr = (unsigned int)ptr;
    if (addr + size < addr) return 0; // переполнение диапазона
    return addr >= USER_WINDOW_BASE && addr + size <= USER_WINDOW_BASE + USER_WINDOW_SIZE;
}

// Та же идея, что у validate_user_ptr, но для NUL-terminated строк
// неизвестной заранее длины (имена файлов, командные строки): начало
// строки должно лежать в окне, и '\0' должен встретиться до его конца -
// иначе sys_open/sys_exec и т.п. либо прочитали бы байт за пределами
// окна как часть имени файла, либо ушли построчно искать '\0' в чужой
// памяти, если строка там не закончится вовсе.
static int validate_user_str(char* s) {
    if (!task_current_is_isolated()) return 1;
    unsigned int addr = (unsigned int)s;
    if (addr < USER_WINDOW_BASE || addr >= USER_WINDOW_BASE + USER_WINDOW_SIZE) return 0;
    unsigned int max = USER_WINDOW_BASE + USER_WINDOW_SIZE - addr;
    for (unsigned int i = 0; i < max; i++) {
        if (s[i] == '\0') return 1;
    }
    return 0; // нет '\0' до конца окна
}

// =================================================================
//  MAC (Mandatory Access Control) - в духе SELinux Type Enforcement
// =================================================================
//
// Настоящий SELinux - Linux Security Module: хуки на inode/dentry/socket/
// capability внутри Linux-ядра, security-контексты, политика, которую
// грузит userspace (load_policy). Ничего из этого в AxOS нет и не может
// быть буквально - это не Linux. Ниже - тот же ПРИНЦИП (Type Enforcement:
// субъект в домене, объект - в классе, политика "домен x класс ->
// разрешено/запрещено", default-deny для всего, чего нет в таблице),
// реализованный нативно для собственных ресурсов ядра (syscall'ы),
// без претензии на совместимость с настоящим SELinux.
//
// Домены - как security context процесса: изолированные run-задачи
// (task_current_is_isolated()) - confined "user_t" (вообще ВСЕ загруженные
// программы, AxSH в том числе - см. "Изоляция памяти" в README); ядро и
// неизолированные демо-задачи (heartbeat/ring3demo) - unconfined
// "kernel_t", доверенный код, не загруженный с диска.
typedef enum { AX_DOMAIN_KERNEL = 0, AX_DOMAIN_USER = 1, AX_DOMAIN_COUNT } ax_domain_t;

// Классы объектов - как target_type в SELinux, по одному на каждый
// syscall, который решили confine. Добавление новой записи в политику
// ниже не требует трогать остальные - ровно как добавление allow-правила
// в .te-файл.
//
// disk_raw/system_reboot запрещены user_t - это и было первой демонстрацией
// механизма. Остальные пять классов ниже РАЗРЕШЕНЫ user_t: это не
// "красивые, но бесполезные" хуки - открытие файла на запись, unlink, exec,
// fs_lock и буфер обмена - повседневные операции AxSH и демо-программ
// (write.bin/rm.bin/lock/unlock), запрещать их по умолчанию означало бы
// ломать рекламируемую функциональность без необходимости. Ценность здесь
// та же, что у большинства allow-правил в настоящей политике SELinux:
// явная, проверяемая граница для каждой операции, которую можно сузить
// позже (новый домен, более узкая политика) без единой правки в самих
// sys_*-обработчиках.
typedef enum {
    AX_CLASS_DISK_RAW = 0,
    AX_CLASS_REBOOT,
    AX_CLASS_FILE_WRITE,
    AX_CLASS_FILE_UNLINK,
    AX_CLASS_FS_LOCK,
    AX_CLASS_EXEC,
    AX_CLASS_CLIPBOARD,
    AX_CLASS_TASK_INFO,
    AX_CLASS_COUNT
} ax_class_t;

// policy[domain][class]: 1 - allow, 0 - deny. Default-deny: новый класс,
// для которого забыли дописать строку, у confined-домена откажет сам
// (массив инициализирован нулями), а не "тихо разрешит" по умолчанию -
// та же осторожность, что и у настоящей политики SELinux.
//
// mkdir переиспользует FILE_WRITE (та же категория риска, что и write/
// unlink - изменение содержимого FAT12), disk_identify переиспользует
// DISK_RAW (то же обращение к IDE в обход FAT12, что и read/write sector
// - раньше "disktool info" непоследовательно проходил без проверки, пока
// "disktool read/write" уже были под политикой). task_info - отдельный
// класс для SYS_PS (раскрывает имена/heap_brk ДРУГИХ задач - честная
// info-disclosure поверхность, но ps.bin - рекламируемая демо-команда,
// поэтому allow, как и остальные неновые denial'ы выше).
static const unsigned char ax_policy[AX_DOMAIN_COUNT][AX_CLASS_COUNT] = {
    /* AX_DOMAIN_KERNEL */ {1, 1, 1, 1, 1, 1, 1, 1}, // unconfined - разрешено всё
    /* AX_DOMAIN_USER   */ {0, 0, 1, 1, 1, 1, 1, 1}, // confined - см. комментарий выше
};

static char* ax_domain_name(ax_domain_t d) {
    return d == AX_DOMAIN_KERNEL ? "kernel_t" : "user_t";
}

static char* ax_class_name(ax_class_t c) {
    switch (c) {
        case AX_CLASS_DISK_RAW:    return "disk_raw";
        case AX_CLASS_REBOOT:      return "system_reboot";
        case AX_CLASS_FILE_WRITE:  return "file_write";
        case AX_CLASS_FILE_UNLINK: return "file_unlink";
        case AX_CLASS_FS_LOCK:     return "fs_lock";
        case AX_CLASS_EXEC:        return "exec";
        case AX_CLASS_CLIPBOARD:   return "clipboard";
        case AX_CLASS_TASK_INFO:   return "task_info";
        default:                   return "?";
    }
}

static ax_domain_t ax_current_domain() {
    return task_current_is_isolated() ? AX_DOMAIN_USER : AX_DOMAIN_KERNEL;
}

// Проверяет политику для текущей задачи и запрошенного класса. При
// отказе печатает audit-подобную строку (формат - привет от настоящего
// "avc: denied" в dmesg/auditd) и возвращает 0; syscall-обработчик решает
// сам, как отказать вызывающему (обычно result=0/-1, как при любой другой
// ошибке - без явного индикатора "это MAC", как и в реальном SELinux: с
// точки зрения вызывающего denied неотличим от обычного отказа).
static int ax_mac_check(ax_class_t cls) {
    ax_domain_t d = ax_current_domain();
    if (ax_policy[d][cls]) return 1;

    print_string("\033[31mavc:  denied  { "); // красный - отказ в доступе
    print_string(ax_class_name(cls));
    print_string(" }  for comm=\"");
    print_string(task_current_name());
    print_string("\"  scontext=axos:");
    print_string(ax_domain_name(d));
    print_string("  tclass=");
    print_string(ax_class_name(cls));
    print_string("\033[0m\n");
    return 0;
}

// MLS dominance: 1, если текущая задача может ПРОЧЕСТЬ объект с уровнем
// object_level ("no read up" - Bell-LaPadula: читатель должен доминировать
// над объектом, т.е. его уровень >= уровня объекта). Неизолированные
// (kernel_t) задачи доминируют над любым уровнем - так же, как они
// unconfined для ax_mac_check() выше.
static int ax_mls_dominates(unsigned int object_level) {
    if (!task_current_is_isolated()) return 1;
    unsigned int subj = task_current_mls_level();
    if (subj >= object_level) return 1;

    print_string("\033[31mavc:  denied  { read }  for comm=\""); // красный
    print_string(task_current_name());
    print_string("\"  scontext=axos:user_t:s");
    print_uint(subj);
    print_string("  tcontext=axos:object_r:clipboard:s");
    print_uint(object_level);
    print_string("  (MLS: no read up)\033[0m\n");
    return 0;
}

// SYS_READ_KEY: неблокирующее чтение клавиатуры. ESI -> char, куда
// записывается последний нажатый символ (0, если ничего не нажато
// с прошлого опроса). Прочитанный символ "потребляется" - last_key
// сбрасывается в 0. Читает канал ИМЕННО своей консоли (caller_tty),
// поэтому AxSH на неактивной консоли не видит чужих нажатий.
void sys_read_key(char* arg) {
    int t = caller_tty();
    if (arg && validate_user_ptr(arg, 1)) {
        *arg = tty_last_key[t];
        tty_last_key[t] = 0;
    }
}

// SYS_WRITE_FILE: ESI -> struct write_file_args
void sys_write_file(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct write_file_args))) return;
    struct write_file_args* a = (struct write_file_args*)arg;
    if (!validate_user_str(a->filename) || !validate_user_ptr(a->data, a->size)) return;
    if (!ax_mac_check(AX_CLASS_FILE_WRITE)) return;
    vfs_write(a->filename, a->data, a->size);
}

// SYS_READ_FILE: ESI -> struct read_file_args. Фактический размер
// записывается обратно в a->out_size.
void sys_read_file(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct read_file_args))) return;
    struct read_file_args* a = (struct read_file_args*)arg;
    if (!validate_user_str(a->filename) || !validate_user_ptr(a->buffer, a->max_size)) {
        a->out_size = 0;
        return;
    }
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
    int            owner; // task_current_slot_index() задачи, открывшей fd (см. fd_owned_by_caller)
};

// ОДНА на всю систему таблица из MAX_FDS дескрипторов, общая для ВСЕХ
// изолированных задач (а не своя у каждой) - поэтому валидность fd одна
// проверка недостаточна: без owner ничто не мешало задаче B читать/писать
// файл, открытый задачей A, просто угадав/повторив тот же номер fd (0-3,
// диапазон тесный). owner делает SYS_FREAD/FWRITE/CLOSE отказывать всем,
// кроме задачи, которая сама вызвала SYS_OPEN для этого fd.
static struct fd_entry fd_table[MAX_FDS];
static int fd_table_inited = 0;

static void fd_table_ensure_init(void) {
    if (!fd_table_inited) {
        for (int i = 0; i < MAX_FDS; i++) fd_table[i].valid = 0;
        fd_table_inited = 1;
    }
}

// true, если fd валиден И принадлежит ВЫЗЫВАЮЩЕЙ задаче.
static int fd_owned_by_caller(int fd) {
    if (fd < 0 || fd >= MAX_FDS || !fd_table[fd].valid) return 0;
    return fd_table[fd].owner == task_current_slot_index();
}

// Закрывает (с тем же сбросом на диск, что у SYS_CLOSE) все fd, которые
// принадлежали слоту owner_slot - вызывается из on_task_exit(), пока
// слот ещё не отдан следующей задаче.
static void fd_release_owner(int owner_slot) {
    for (int fd = 0; fd < MAX_FDS; fd++) {
        if (!fd_table[fd].valid || fd_table[fd].owner != owner_slot) continue;
        if (fd_table[fd].flags != O_RDONLY && fd_table[fd].size > 0) {
            vfs_write(fd_table[fd].name, fd_table[fd].buf, fd_table[fd].size);
        }
        free(fd_table[fd].buf);
        fd_table[fd].buf   = 0;
        fd_table[fd].valid = 0;
    }
}

// SYS_OPEN: открыть файл. O_RDONLY — загружает содержимое в буфер;
// O_WRONLY|O_CREAT — создаёт пустой буфер для записи.
// Возвращает fd (>= 0) через open_args.result, или -1 при ошибке.
void sys_open(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct open_args))) return;
    struct open_args* a = (struct open_args*)arg;
    a->result = -1;
    if (!validate_user_str(a->filename)) return;
    // Проверяем на ОТКРЫТИИ, не на каждом sys_fwrite - запись определяется
    // флагом O_WRONLY здесь, дальнейшие sys_fwrite на этом fd уже доверяют
    // праву, выданному при open() (та же модель, что у permission check
    // на open() в Linux/SELinux - не на каждый write()).
    if (a->flags != O_RDONLY && !ax_mac_check(AX_CLASS_FILE_WRITE)) return;
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
    fd_table[slot].owner = task_current_slot_index();
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
    if (!validate_user_ptr(arg, sizeof(struct fread_args))) return;
    struct fread_args* a = (struct fread_args*)arg;
    a->result = -1;
    int fd = a->fd;
    if (!fd_owned_by_caller(fd)) return;
    if (fd_table[fd].flags != O_RDONLY) return;
    if (!validate_user_ptr(a->buf, a->count)) return;

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
    if (!validate_user_ptr(arg, sizeof(struct fwrite_args))) return;
    struct fwrite_args* a = (struct fwrite_args*)arg;
    a->result = -1;
    int fd = a->fd;
    if (!fd_owned_by_caller(fd)) return;
    if (fd_table[fd].flags == O_RDONLY) return;
    if (!validate_user_ptr(a->buf, a->count)) return;

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
    if (!validate_user_ptr(arg, sizeof(struct close_args))) return;
    struct close_args* a = (struct close_args*)arg;
    int fd = a->fd;
    if (!fd_owned_by_caller(fd)) return;

    if (fd_table[fd].flags != O_RDONLY && fd_table[fd].size > 0)
        vfs_write(fd_table[fd].name, fd_table[fd].buf, fd_table[fd].size);

    free(fd_table[fd].buf);
    fd_table[fd].buf   = 0;
    fd_table[fd].valid = 0;
}

// Общая логика запуска бинарника. Возвращает slot >= 0 или -1/-2.
static int do_exec(char* cmdline) {
    if (!cmdline) return -1;

    char filename[24];
    int fi = 0;
    char* p = cmdline;
    while (*p && *p != ' ' && fi < 23) filename[fi++] = *p++;
    filename[fi] = '\0';
    if (fi == 0) return -1;

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
    if (slot < 0) return -2;

    unsigned int addr = USER_PROGRAM_BASE + slot * USER_PROGRAM_SLOT_SIZE;
    unsigned int size = vfs_read(filename, (unsigned char*)addr, USER_ARGS_OFFSET);
    if (size == 0) return -1;

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
    // Слот наследует консоль вызывающей задачи (caller_tty уже определена
    // ниже по файлу для syscall'ов, но do_exec идёт раньше - дублируем
    // ту же логику здесь напрямую через task_current_slot_index()).
    {
        int caller_slot = task_current_slot_index();
        slot_tty[slot] = (caller_slot >= 0 && caller_slot < USER_PROGRAM_SLOTS)
            ? slot_tty[caller_slot] : tty_active();
    }
    task_create_user_isolated(filename, addr, slot, argc, USER_ARGS_VADDR);
    return slot;
}

void sys_exec(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct exec_args))) return;
    struct exec_args* a = (struct exec_args*)arg;
    if (!validate_user_str(a->cmdline)) { a->result = -1; return; }
    if (!ax_mac_check(AX_CLASS_EXEC)) { a->result = -1; return; }
    a->result = do_exec(a->cmdline);
}

// SYS_EXEC_REDIR: запустить программу, перенаправив её stdout в файл.
// Атомарно: буфер создаётся до первого тика планировщика новой задачи.
void sys_exec_redir(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct exec_redir_args))) return;
    struct exec_redir_args* a = (struct exec_redir_args*)arg;
    // Порядок важен: validate_user_str ничего не разыменовывает, пока не
    // убедится, что адрес в окне - проверяем ЕЁ раньше, чем a->redir_out[0]
    // (redir_out=NULL - валидный "без перенаправления", поэтому не сам
    // факт указателя, а его обращение нужно защищать).
    if (!validate_user_str(a->cmdline) ||
        (a->redir_out && !validate_user_str(a->redir_out))) {
        a->result = -1;
        return;
    }
    if (!ax_mac_check(AX_CLASS_EXEC)) { a->result = -1; return; }
    a->result = do_exec(a->cmdline);
    if (a->result >= 0 && a->redir_out && a->redir_out[0]) {
        int slot = a->result;
        unsigned char* buf = (unsigned char*)malloc(REDIR_BUF_SIZE);
        if (buf) {
            slot_redir_buf[slot] = buf;
            slot_redir_len[slot] = 0;
            int fi = 0;
            char* fn = a->redir_out;
            while (*fn && fi < 12) slot_redir_file[slot][fi++] = *fn++;
            slot_redir_file[slot][fi] = '\0';
        }
    }
}

// SYS_TASK_ALIVE: неблокирующая проверка — завершена ли задача в слоте.
// sh.bin вызывает в цикле busy-wait, пока дочерняя задача работает.
void sys_task_alive(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct task_alive_args))) return;
    struct task_alive_args* a = (struct task_alive_args*)arg;
    int slot = a->slot;
    a->result = (slot >= 0 && slot < USER_PROGRAM_SLOTS && !slot_free[slot]) ? 1 : 0;
}

// SYS_SHELL_CLAIM: захват/освобождение клавиатуры НА СВОЕЙ консоли (caller_tty).
// arg = (char*)1 — захват (kernel shell этой консоли пассивен, sh.bin обрабатывает ввод).
// arg = (char*)0 — освобождение (kernel shell консоли снова активен).
void sys_shell_claim(char* arg) {
    int t = caller_tty();
    int was_inhibited = tty_kernel_shell_inhibited[t];
    tty_kernel_shell_inhibited[t] = (arg != (char*)0);
    if (was_inhibited && !tty_kernel_shell_inhibited[t]) {
        command_len[t] = 0;
        print_string_to(t, "\nAxOS> ");
    }
}

// SYS_SET_FOREGROUND: сообщает ядру, какой слот сейчас на переднем плане
// НА СВОЕЙ консоли (caller_tty). sh.bin вызывает перед busy-wait (slot >= 0)
// и после него (slot = -1). keyboard_handler_main использует
// tty_foreground_slot[tty_active()] для Ctrl+C.
void sys_set_foreground(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct set_fg_args))) return;
    struct set_fg_args* a = (struct set_fg_args*)arg;
    tty_foreground_slot[caller_tty()] = a->slot;
}

// SYS_GET_TICKS: возвращает текущее значение timer_ticks (100 Гц).
// Секунды от загрузки = result / 100.
void sys_get_ticks(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct get_ticks_args))) return;
    struct get_ticks_args* a = (struct get_ticks_args*)arg;
    a->result = (unsigned int)timer_ticks;
}

// SYS_SLEEP: блокирует вызывающую задачу на ms миллисекунд.
// sleep_ms включает прерывания через sti — другие задачи получают CPU во время ожидания.
void sys_sleep(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct sleep_args))) return;
    struct sleep_args* a = (struct sleep_args*)arg;
    sleep_ms((unsigned long)a->ms);
}

void sys_readdir(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct readdir_args))) return;
    struct readdir_args* a = (struct readdir_args*)arg;
    int is_dir = 0;
    a->result = vfs_readdir(a->index, a->name, &a->size, &is_dir);
    a->is_dir = is_dir;
}

void sys_mkdir(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct mkdir_args))) return;
    struct mkdir_args* a = (struct mkdir_args*)arg;
    if (!validate_user_str(a->dirname)) { a->result = 0; return; }
    if (!ax_mac_check(AX_CLASS_FILE_WRITE)) { a->result = 0; return; }
    a->result = vfs_mkdir(a->dirname);
}

void sys_fs_lock(char* arg) {
    if (!ax_mac_check(AX_CLASS_FS_LOCK)) return;
    vfs_set_locked(arg != (char*)0);
}

// Низкоуровневый доступ к IDE-диску, минуя FAT12 - для disktool.bin
// (диагностика, см. ide.c). a->model/a->buf - буферы, выделенные вызывающей
// userspace-программой; ядро только читает/пишет в них через указатель.
void sys_disk_identify(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct disk_identify_args))) return;
    struct disk_identify_args* a = (struct disk_identify_args*)arg;
    if (!validate_user_ptr(a->model, 41)) { a->result = 0; return; }
    if (!ax_mac_check(AX_CLASS_DISK_RAW)) { a->result = 0; return; }
    a->result = ide_identify(a->model);
}

void sys_disk_read_sector(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct disk_sector_args))) return;
    struct disk_sector_args* a = (struct disk_sector_args*)arg;
    if (!validate_user_ptr(a->buf, IDE_SECTOR_SIZE)) { a->result = 0; return; }
    if (!ax_mac_check(AX_CLASS_DISK_RAW)) { a->result = 0; return; }
    a->result = ide_read_sector(a->lba, a->buf);
}

void sys_disk_write_sector(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct disk_sector_args))) return;
    struct disk_sector_args* a = (struct disk_sector_args*)arg;
    if (!validate_user_ptr(a->buf, IDE_SECTOR_SIZE)) { a->result = 0; return; }
    if (!ax_mac_check(AX_CLASS_DISK_RAW)) { a->result = 0; return; }
    a->result = ide_write_sector(a->lba, a->buf);
}

void sys_ps(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct ps_entry))) return;
    struct ps_entry* e = (struct ps_entry*)arg;
    if (!ax_mac_check(AX_CLASS_TASK_INFO)) { e->result = 0; return; }
    e->result = task_get_info(e->index, &e->pid, e->name, &e->ticks, &e->slot);
    if (e->result && e->slot >= 0 && e->slot < USER_PROGRAM_SLOTS)
        e->heap_brk = slot_heap_brk[e->slot];
    else
        e->heap_brk = 0;
}

// SYS_SBRK: сдвигает heap break задачи на increment байт вперёд.
// Возвращает старый break (начало выделенного региона) или -1 при переполнении.
void sys_sbrk(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct sbrk_args))) return;
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

void sys_unlink(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct unlink_args))) return;
    struct unlink_args* a = (struct unlink_args*)arg;
    if (!validate_user_str(a->filename)) { a->result = 0; return; }
    if (!ax_mac_check(AX_CLASS_FILE_UNLINK)) { a->result = 0; return; }
    a->result = vfs_delete(a->filename);
}

// SYS_GET_DATETIME: текущее время RTC - userspace-версия print_datetime()
// (kernel-shell "date"), см. date.bin.
void sys_get_datetime(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct datetime_args))) return;
    struct datetime_args* a = (struct datetime_args*)arg;
    read_rtc(&a->second, &a->minute, &a->hour, &a->day, &a->month, &a->year);
}

// SYS_REBOOT: перезагружает систему через контроллер клавиатуры (8042) -
// см. reboot(). Не возвращается.
void sys_reboot(char* arg) {
    (void)arg;
    if (!ax_mac_check(AX_CLASS_REBOOT)) return;
    reboot();
}

// SYS_GET_MOUSE: текущая позиция курсора (сетка 80x25) и кнопки -
// см. mouse.c (накопление пакетов в IRQ12) и mouse.bin.
void sys_get_mouse(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct mouse_args))) return;
    struct mouse_args* a = (struct mouse_args*)arg;
    a->x = mouse_get_x();
    a->y = mouse_get_y();
    a->buttons = mouse_get_buttons();
}

// SYS_BEEP: играет тон через системный динамик (speaker.c) duration_ms
// миллисекунд, потом выключает его. Блокирующий - использует тот же
// sleep_ms(), что и SYS_SLEEP, остальные задачи получают CPU всё это
// время (sleep_ms сама делает sti(), см. комментарий там).
void sys_beep(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct beep_args))) return;
    struct beep_args* a = (struct beep_args*)arg;
    speaker_on(a->freq);
    sleep_ms(a->duration_ms);
    speaker_off();
}

// SYS_CLIPBOARD_SET: копирует a->data (a->size байт, обрезая до
// CLIPBOARD_MAX_SIZE) в общий буфер обмена, заменяя прежнее содержимое.
void sys_clipboard_set(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct clipboard_set_args))) return;
    struct clipboard_set_args* a = (struct clipboard_set_args*)arg;
    unsigned int size = a->size;
    if (size > CLIPBOARD_MAX_SIZE) size = CLIPBOARD_MAX_SIZE;
    if (!validate_user_ptr(a->data, size)) return;
    if (!ax_mac_check(AX_CLASS_CLIPBOARD)) return;
    for (unsigned int i = 0; i < size; i++) clipboard_buf[i] = a->data[i];
    clipboard_len = size;
    // Буфер "окрашивается" уровнем писателя - см. ax_mls_dominates() и
    // комментарий у clipboard_level. Неизолированные (kernel_t) задачи не
    // имеют MLS-уровня в обычном смысле - считаем их запись s0, чтобы не
    // навсегда "запереть" буфер на максимальном уровне, если, например,
    // kernel-shell сам когда-нибудь вызовет SYS_CLIPBOARD_SET.
    clipboard_level = task_current_is_isolated() ? task_current_mls_level() : 0;
}

// SYS_CLIPBOARD_GET: копирует содержимое буфера обмена в a->buffer (не
// больше a->max_size байт). Фактический размер пишется в a->out_size.
// Откажет (out_size=0), если MLS-уровень читателя ниже уровня, на котором
// буфер был заполнен последний раз - см. ax_mls_dominates().
void sys_clipboard_get(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct clipboard_get_args))) return;
    struct clipboard_get_args* a = (struct clipboard_get_args*)arg;
    if (!ax_mls_dominates(clipboard_level)) { a->out_size = 0; return; }
    unsigned int size = clipboard_len;
    if (size > a->max_size) size = a->max_size;
    if (!validate_user_ptr(a->buffer, size)) { a->out_size = 0; return; }
    for (unsigned int i = 0; i < size; i++) a->buffer[i] = clipboard_buf[i];
    a->out_size = size;
}

// SYS_SET_LEVEL: задача поднимает СЕБЕ MLS-уровень (s0..s15) - см.
// struct set_level_args и task_set_current_mls_level().
void sys_set_level(char* arg) {
    if (!validate_user_ptr(arg, sizeof(struct set_level_args))) return;
    struct set_level_args* a = (struct set_level_args*)arg;
    task_set_current_mls_level(a->level);
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
    sys_ps,            // 0x13
    sys_exec_redir,    // 0x14
    sys_unlink,        // 0x15
    sys_mkdir,         // 0x16
    sys_fs_lock,       // 0x17
    sys_disk_identify,     // 0x18
    sys_disk_read_sector,  // 0x19
    sys_disk_write_sector, // 0x1A
    sys_get_datetime,      // 0x1B
    sys_reboot,            // 0x1C
    sys_get_mouse,         // 0x1D
    sys_beep,              // 0x1E
    sys_clipboard_set,     // 0x1F
    sys_clipboard_get,     // 0x20
    sys_set_level,         // 0x21
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
        print_string("  sleep <sec> - pause for N seconds (0-9)\n");
        print_string("  lock        - write-protect the FAT12 disk (default)\n");
        print_string("  unlock      - allow writes to the FAT12 disk\n");
        print_string("  run <file>  - load and run a program from FAT12 (ring3)\n");
        print_string("  usermode    - demo: jump to ring3, call syscall via int 0x80\n");
        print_string("  memtest     - test heap allocator (malloc/free)\n");
        print_string("  selftest    - run heap/paging/FAT12 regression tests\n");
        print_string("  Ctrl+Alt+F1/F2 - switch virtual console (TTY)\n");
        print_string("  (echo/ls/cat/ps/uptime/write/diskinfo/diskread/diskwrite/date/reboot\n");
        print_string("   moved to userspace - use \"run X.BIN\", e.g. \"run date.bin\")\n");
    } else if (str_eq(cmd, "clear")) {
        clear_screen();
    } else if (str_eq(cmd, "about")) {
        print_string("AxOS v0.6 - hobby OS in C and x86 Assembly\n");
        print_string("FAT12 disk: ");
        print_string(vfs_is_locked() ? "locked (read-only)\n" : "unlocked (read-write)\n");
    } else if (str_starts_with(cmd, "sleep ")) {
        char digit = cmd[6];
        if (digit >= '0' && digit <= '9') {
            print_string("Sleeping...\n");
            sleep_ms((unsigned long)(digit - '0') * 1000);
            print_string("Done.\n");
        } else {
            print_string("Usage: sleep <0-9>\n");
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
                // Запущенное отсюда (kernel-shell команда "run", в т.ч. из
                // autoboot() и из авто-запуска AxSH при первом переключении
                // на консоль) привязывается к консоли, с которой эта команда
                // пришла - см. KERNEL_TTY_COUNT/slot_tty выше.
                slot_tty[slot] = tty_active();
                task_create_user_isolated(filename, addr, slot, argc, USER_ARGS_VADDR);
                print_string("Started.\n");
            }
        }
    } else if (str_eq(cmd, "usermode")) {
        // enter_usermode() - билет в один конец (iretd без возврата), так
        // что код после execute_command() в keyboard_handler_main (сброс
        // command_len и печать приглашения) для этого вызова не выполнится.
        // Делаем это здесь заранее, иначе следующий ввод склеится с "usermode".
        command_len[tty_active()] = 0;
        print_string("Switching to ring3...\n");
        print_string("AxOS> ");
        enter_usermode(usermode_demo);
    } else if (str_eq(cmd, "memtest")) {
        memtest_demo();
    } else if (str_eq(cmd, "selftest")) {
        run_self_tests();
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

        // Alt (левый): 0x38 = нажатие, 0xB8 = отпускание.
        if (scancode == 0x38) { alt_held = 1; return; }
        if (scancode == 0xB8) { alt_held = 0; return; }

        // Ctrl+Alt+F1 / Ctrl+Alt+F2: переключение виртуальной консоли (TTY).
        // F1 = 0x3B, F2 = 0x3C. tty_switch (screen.c) подгружает буфер
        // целевой консоли в 0xB8000 - сохранять исходную не нужно, её
        // буфер обновлялся всё это время независимо от того, видна она
        // или нет (см. tty_putc в screen.c). Если на этой консоли ещё
        // никогда не было shell'а - запускаем там AxSH, как при autoboot().
        if (ctrl_held && alt_held && (scancode == 0x3B || scancode == 0x3C)) {
            int target = scancode - 0x3B;
            if (target != tty_active()) {
                tty_switch(target);
                if (!tty_shell_launched[target]) {
                    tty_shell_launched[target] = 1;
                    execute_command("run SH.BIN");
                }
            }
            return;
        }

        // Расширенные клавиши: E0-префикс, затем скан-код.
        // Стрелка вверх = E0 0x48, вниз = E0 0x50.
        // Передаём как спецсимволы 0x11/0x12 в last_key активной консоли
        // для ax_readkey().
        if (scancode == 0xE0) { e0_prefix = 1; return; }
        if (e0_prefix) {
            e0_prefix = 0;
            if (scancode == 0x48) tty_last_key[tty_active()] = '\x11';  // стрелка вверх (E0 path)
            if (scancode == 0x50) tty_last_key[tty_active()] = '\x12';  // стрелка вниз  (E0 path)
            return;
        }
        // Фоллбэк: если QEMU/SDL шлёт 0x48/0x50 без E0-префикса
        if (scancode == 0x48) { tty_last_key[tty_active()] = '\x11'; return; }
        if (scancode == 0x50) { tty_last_key[tty_active()] = '\x12'; return; }

        // Нам нужны только нажатия клавиш
        if (scancode < 128) {
            char letter = shift_held ? scancode_to_char_shifted[scancode]
                                     : scancode_to_char[scancode];
            int t = tty_active();

            if (letter != 0) {
                tty_last_key[t] = letter; // канал для SYS_READ_KEY (ring3)
            }

            // Ctrl+C: убиваем foreground-процесс активной консоли (если есть).
            // Scancode 0x2E = клавиша C независимо от Shift.
            if (ctrl_held && scancode == 0x2E) {
                if (tty_foreground_slot[t] >= 0) {
                    print_string("^C\n");
                    task_kill_by_slot(tty_foreground_slot[t]);
                    tty_foreground_slot[t] = -1;
                }
                return;
            }

            // Если user-space shell захватил клавиатуру этой консоли — не
            // обрабатываем команды.
            if (tty_kernel_shell_inhibited[t]) return;

            if (letter == '\n') {
                command_buffer[t][command_len[t]] = '\0';
                print_string("\n");
                execute_command(command_buffer[t]);
                command_len[t] = 0;
                print_string("AxOS> ");
            } else if (letter == '\b') {
                if (command_len[t] > 0) {
                    command_len[t]--;
                    backspace();
                }
            } else if (letter != 0) {
                if (command_len[t] < (int)sizeof(command_buffer[t]) - 1) {
                    command_buffer[t][command_len[t]] = letter;
                    command_len[t]++;
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

/* Diagnostic: write char at (row=24, col) with attribute */
#define VGA_MARK(col, ch, attr) do { \
    volatile unsigned char* _v = (volatile unsigned char*)0xB8000; \
    _v[(24*80+(col))*2]   = (ch); \
    _v[(24*80+(col))*2+1] = (attr); \
} while(0)

void kernel_main() {
    char* video_memory = (char*) 0xB8000;
    video_memory[0] = 'M';
    video_memory[1] = 0x0F;
    video_memory[2] = 'S';
    video_memory[3] = 0x0F;
    video_memory[4] = 'N';
    video_memory[5] = 0x0F;

    init_ttys(); // инициализирует все консоли (включая активную) и зеркалит в VGA
    VGA_MARK(70, 'A', 0x4F); /* pre-paging VGA write */

    init_idt();
    init_mouse(); // нужен размаскированный IRQ12 (см. init_idt) перед включением потоковой отправки пакетов
    init_paging();
    VGA_MARK(71, 'B', 0x4F); /* post-paging VGA write */

    init_tss();
    init_heap();
    init_tasking();
    task_create("heartbeat", heartbeat_task);
    task_create_user("ring3demo", ring3_spinner_task);

    VGA_MARK(72, 'C', 0x4F); /* pre-vfs_init */

    vfs_init();
    VGA_MARK(73, 'D', 0x4F); /* post-vfs_init */

    print_string("X");
    VGA_MARK(74, 'E', 0x4F); /* post-print_string-one-char */

    if (autoboot()) {
        execute_command("run SH.BIN");
        VGA_MARK(74, 'E', 0x4F); /* post-execute_command */
    } else {
        print_string("AxOS> ");
        VGA_MARK(74, 'F', 0x4F); /* post-fallback-prompt */
    }

    // БЕСКОНЕЧНЫЙ ЦИКЛ ОБЯЗАТЕЛЕН
    while(1) {
        __asm__("hlt");
    }
}