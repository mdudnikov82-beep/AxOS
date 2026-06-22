// =================================================================
//  ABI системных вызовов AxOS (int 0x80)
// =================================================================
//
// Общий заголовок для ring3-программ (src/user/*.c) и диспетчера
// в kernel.c. Коды функций передаются в AH, аргумент - указатель в ESI.

#ifndef AXOS_SYSCALL_H
#define AXOS_SYSCALL_H

#define SYS_PRINT_STRING 0x01 // ESI -> строка с '\0'
#define SYS_CLEAR_SCREEN 0x02 // ESI не используется
#define SYS_READ_KEY     0x03 // ESI -> char: последний нажатый символ (0, если нет)
#define SYS_WRITE_FILE   0x04 // ESI -> struct write_file_args
#define SYS_READ_FILE    0x05 // ESI -> struct read_file_args
#define SYS_EXIT         0x06 // ESI не используется - текущая задача завершается
#define SYS_GET_TICKS    0x0F // ESI -> struct get_ticks_args

// Аргумент SYS_WRITE_FILE: создаёт/перезаписывает файл filename
// содержимым data (size байт).
struct write_file_args {
    char* filename;
    unsigned char* data;
    unsigned int size;
};

// Аргумент SYS_READ_FILE: загружает файл filename в buffer (макс.
// max_size байт). Ядро записывает фактический размер в out_size.
struct read_file_args {
    char* filename;
    unsigned char* buffer;
    unsigned int max_size;
    unsigned int out_size;
};

// --- fd-based file API (0x07-0x0A) ---
#define SYS_OPEN    0x07  // ESI -> struct open_args
#define SYS_FREAD   0x08  // ESI -> struct fread_args
#define SYS_FWRITE  0x09  // ESI -> struct fwrite_args
#define SYS_CLOSE   0x0A  // ESI -> struct close_args

#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT  4

// SYS_OPEN: открыть файл; result = fd (>= 0) или -1 при ошибке.
struct open_args {
    char* filename;
    int   flags;
    int   result;
};

// SYS_FREAD: прочитать count байт из fd в buf; result = фактически прочитано (-1 при ошибке).
struct fread_args {
    int            fd;
    unsigned char* buf;
    unsigned int   count;
    int            result;
};

// SYS_FWRITE: записать count байт из buf в fd; result = фактически записано (-1 при ошибке).
struct fwrite_args {
    int            fd;
    unsigned char* buf;
    unsigned int   count;
    int            result;
};

// SYS_CLOSE: закрыть fd (при O_WRONLY сбрасывает данные на диск).
struct close_args {
    int fd;
};

// --- Управление процессами и shell (0x0B-0x0D) ---
#define SYS_EXEC        0x0B  // ESI -> struct exec_args
#define SYS_TASK_ALIVE  0x0C  // ESI -> struct task_alive_args
#define SYS_SHELL_CLAIM 0x0D  // ESI = 1 (захват), 0 (освобождение) — не указатель

// SYS_EXEC: запустить бинарник из FAT12; result = slot (>= 0) или -1/-2.
struct exec_args {
    char* cmdline;   // "filename arg1 arg2..."
    int   result;    // >= 0: slot-индекс, -1: файл не найден, -2: нет слотов
};

// SYS_TASK_ALIVE: проверить, жива ли задача в слоте (без блокировки).
struct task_alive_args {
    int slot;
    int result;  // 1 = ещё работает, 0 = завершена
};

// SYS_SET_FOREGROUND: сообщить ядру, какой слот на переднем плане.
// slot >= 0: sh.bin ждёт задачу в этом слоте (Ctrl+C убьёт её).
// slot = -1: foreground сброшен (Ctrl+C игнорируется).
#define SYS_SET_FOREGROUND 0x0E

struct set_fg_args {
    int slot;
};

// --- Системное время (0x0F-0x10) ---
#define SYS_GET_TICKS 0x0F  // ESI -> struct get_ticks_args
#define SYS_SLEEP     0x10  // ESI -> struct sleep_args

// Возвращает timer_ticks (100 Гц с момента загрузки).
// Секунды = result / 100; мс ≈ result * 10.
struct get_ticks_args {
    unsigned int result;
};

// Блокирует вызывающую задачу на ms миллисекунд (другие задачи получают CPU).
struct sleep_args {
    unsigned int ms;
};

// --- Перечисление файлов директории (0x11) ---
#define SYS_READDIR 0x11  // ESI -> struct readdir_args

struct readdir_args {
    unsigned int index;    // вход: 0-based порядковый номер файла
    char         name[13]; // выход: "NAME.EXT\0"
    unsigned int size;     // выход: размер файла в байтах
    int          result;   // выход: 1 = запись найдена, 0 = конец директории
    int          is_dir;   // выход: 1 = директория, 0 = файл
};

#define SYS_SBRK 0x12  // ESI -> struct sbrk_args

struct sbrk_args {
    int          increment; // вход: байт добавить к break (0 = запрос текущего)
    unsigned int result;    // выход: старый break, или (unsigned int)-1 при ошибке
};

// --- Перенаправление вывода (0x14) ---
#define SYS_EXEC_REDIR 0x14  // ESI -> struct exec_redir_args

// Запускает программу, перенаправляя её stdout в файл redir_out.
// redir_out должен быть в FAT12-формате (uppercase, max 12 символов).
// Диск должен быть разблокирован командой unlock.
struct exec_redir_args {
    char* cmdline;   // имя программы + аргументы
    char* redir_out; // имя выходного файла (uppercase FAT12, e.g. "OUT.TXT")
    int   result;    // >= 0: slot, -1: не найден, -2: нет слотов
};

// --- Удаление файла (0x15) ---
#define SYS_UNLINK 0x15  // ESI -> struct unlink_args

// Удаляет файл с диска. Диск должен быть разблокирован.
// result=1: удалён, 0: не найден или диск заблокирован.
struct unlink_args {
    char* filename;  // имя файла (uppercase FAT12, e.g. "OUT.TXT")
    int   result;
};

// --- Создание директории (0x16) ---
#define SYS_MKDIR 0x16  // ESI -> struct mkdir_args

// Создаёт директорию в корне. Диск должен быть разблокирован.
// result=1: создана, 0: уже существует, нет места, или диск заблокирован.
struct mkdir_args {
    char* dirname;
    int   result;
};

// --- Блокировка файловой системы (0x17) ---
#define SYS_FS_LOCK 0x17  // ESI = 0 (разблокировать) или 1 (заблокировать), не указатель

// --- Низкоуровневый доступ к IDE-диску, минуя FAT12 (0x18-0x1A) ---
// Для диагностических инструментов (disktool.bin) - читает/пишет сырые
// секторы или опрашивает модель диска напрямую через ide.c, без какой-либо
// интерпретации содержимого. Координировать с FAT12 (lock/unlock) - дело
// вызывающего: эти syscall'ы пишут в любой LBA, включая занятые файлами.
#define SYS_DISK_IDENTIFY     0x18  // ESI -> struct disk_identify_args
#define SYS_DISK_READ_SECTOR  0x19  // ESI -> struct disk_sector_args
#define SYS_DISK_WRITE_SECTOR 0x1A  // ESI -> struct disk_sector_args

// SYS_DISK_IDENTIFY: model - буфер не менее 41 байта (заполняется строкой
// модели). result=1: успех, result=0: диск не отвечает.
struct disk_identify_args {
    char* model;
    int   result;
};

// SYS_DISK_READ_SECTOR / SYS_DISK_WRITE_SECTOR: buf - буфер ровно
// IDE_SECTOR_SIZE (512) байт. result=1: успех, result=0: ошибка/нет диска.
struct disk_sector_args {
    unsigned int   lba;
    unsigned char* buf;
    int            result;
};

// --- Дата/время и перезагрузка (0x1B-0x1C) ---
#define SYS_GET_DATETIME 0x1B  // ESI -> struct datetime_args
#define SYS_REBOOT       0x1C  // ESI не используется

// SYS_GET_DATETIME: текущее время RTC (CMOS), уже переведённое из BCD.
// year - две последние цифры (0-99, т.е. без "20" спереди).
struct datetime_args {
    int second;
    int minute;
    int hour;
    int day;
    int month;
    int year;
};

// --- PS/2-мышь (0x1D) ---
#define SYS_GET_MOUSE 0x1D  // ESI -> struct mouse_args

// x/y - координаты курсора, ограниченные сеткой 80x25 (текстовый режим).
// buttons - бит0=левая кнопка, бит1=правая, бит2=средняя.
struct mouse_args {
    int x;
    int y;
    int buttons;
};

// --- Системный динамик (0x1E) ---
#define SYS_BEEP 0x1E  // ESI -> struct beep_args

// SYS_BEEP: играет тон freq Гц в течение duration_ms миллисекунд, затем
// выключает динамик и возвращает управление (блокирующий вызов - внутри
// использует тот же sleep_ms(), что и SYS_SLEEP, другие задачи получают
// CPU). freq=0 - тишина на это время (пауза между нотами).
struct beep_args {
    unsigned int freq;
    unsigned int duration_ms;
};

// --- Буфер обмена (0x1F-0x20) ---
#define SYS_CLIPBOARD_SET 0x1F  // ESI -> struct clipboard_set_args
#define SYS_CLIPBOARD_GET 0x20  // ESI -> struct clipboard_get_args

// SYS_CLIPBOARD_SET: копирует data (size байт, максимум CLIPBOARD_MAX_SIZE)
// в общий буфер обмена ядра, заменяя его прежнее содержимое.
struct clipboard_set_args {
    unsigned char* data;
    unsigned int   size;
};

// SYS_CLIPBOARD_GET: копирует содержимое буфера обмена в buffer (максимум
// max_size байт). Ядро записывает фактический размер в out_size.
struct clipboard_get_args {
    unsigned char* buffer;
    unsigned int   max_size;
    unsigned int   out_size;
};

// 1 КБ - не от щедрости: .bss ядра физически близко к загрузочному сектору
// (0x7c00), где живёт GDT (см. kernel_entry.asm) - сильно больший буфер
// рискует затереть её при обнулении .bss и уронить систему в #GP.
#define CLIPBOARD_MAX_SIZE 1024

// --- MLS (Multi-Level Security) уровень задачи (0x21) ---
#define SYS_SET_LEVEL 0x21  // ESI -> struct set_level_args

// SYS_SET_LEVEL: задача поднимает СЕБЕ MLS-уровень (s0..s15, см. "MAC" в
// README) - самодекларация без проверки полномочий (в AxOS нет ни
// аутентификации, ни ролей, которые могли бы её ограничить), не путать с
// настоящим SELinux MLS, где переход уровня сам подчинён политике.
// Используется для демонстрации dominance-проверки буфера обмена
// (sys_clipboard_get откажет, если уровень читателя ниже уровня, на
// котором был сделан последний sys_clipboard_set - "no read up").
struct set_level_args {
    unsigned int level; // зажимается в [0, 15] на стороне ядра
};

// --- Список задач (0x13) ---
#define SYS_PS 0x13  // ESI -> struct ps_entry

// Возвращает информацию о задаче с порядковым номером index (0-based).
// result=1: запись найдена; result=0: конец списка.
// slot=-1 для ядровых задач; для ring3-задач slot = user_slot_index (0..3).
struct ps_entry {
    unsigned int  index;     // вход:  0-based порядковый номер задачи
    int           pid;       // выход: уникальный ID задачи
    char          name[16];  // выход: имя задачи
    unsigned int  ticks;     // выход: тики планировщика
    int           slot;      // выход: user_slot_index, или -1 для ядра
    unsigned int  heap_brk;  // выход: текущий heap break (0 для ядровых задач)
    int           result;    // выход: 1=найдена, 0=конец
};

#endif
