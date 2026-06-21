#ifndef AXOS_SYSCALLS_H
#define AXOS_SYSCALLS_H

// ABI системных вызовов AxOS: int 0x80, AH = номер, ESI = аргумент.

#define SYS_PRINT_STRING 0x01   // ESI -> char*
#define SYS_CLEAR_SCREEN 0x02
#define SYS_READ_KEY     0x03   // ESI -> char (ядро пишет последний нажатый символ)
#define SYS_WRITE_FILE   0x04   // ESI -> struct write_file_args  (one-shot)
#define SYS_READ_FILE    0x05   // ESI -> struct read_file_args   (one-shot)
#define SYS_EXIT         0x06
#define SYS_OPEN         0x07   // ESI -> struct open_args
#define SYS_FREAD        0x08   // ESI -> struct fread_args
#define SYS_FWRITE       0x09   // ESI -> struct fwrite_args
#define SYS_CLOSE        0x0A   // ESI -> struct close_args

#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT  4

struct write_file_args {
    char*          filename;
    unsigned char* data;
    unsigned int   size;
};

struct read_file_args {
    char*          filename;
    unsigned char* buffer;
    unsigned int   max_size;
    unsigned int   out_size;
};

struct open_args {
    char* filename;
    int   flags;
    int   result;
};

struct fread_args {
    int            fd;
    unsigned char* buf;
    unsigned int   count;
    int            result;
};

struct fwrite_args {
    int            fd;
    unsigned char* buf;
    unsigned int   count;
    int            result;
};

struct close_args {
    int fd;
};

// --- Управление процессами и shell (0x0B-0x0D) ---
#define SYS_EXEC        0x0B
#define SYS_TASK_ALIVE  0x0C
#define SYS_SHELL_CLAIM 0x0D

struct exec_args {
    char* cmdline;
    int   result;
};

struct task_alive_args {
    int slot;
    int result;
};

#define SYS_SET_FOREGROUND 0x0E

struct set_fg_args {
    int slot;
};

#define SYS_GET_TICKS 0x0F
#define SYS_SLEEP     0x10
#define SYS_READDIR   0x11
#define SYS_SBRK      0x12

struct get_ticks_args {
    unsigned int result;
};

struct sleep_args {
    unsigned int ms;
};

struct readdir_args {
    unsigned int index;   // вход: 0-based порядковый номер файла
    char         name[13]; // выход: "NAME.EXT\0"
    unsigned int size;    // выход: размер файла в байтах
    int          result;  // выход: 1 = запись найдена, 0 = конец директории
    int          is_dir;  // выход: 1 = директория, 0 = файл
};

struct sbrk_args {
    int          increment; // вход: байт добавить к break (0 = запрос текущего)
    unsigned int result;    // выход: старый break, или (unsigned int)-1 при ошибке
};

#define SYS_EXEC_REDIR 0x14

struct exec_redir_args {
    char* cmdline;
    char* redir_out;
    int   result;
};

#define SYS_UNLINK 0x15

struct unlink_args {
    char* filename;
    int   result;
};

#define SYS_MKDIR 0x16

struct mkdir_args {
    char* dirname;
    int   result;
};

#define SYS_FS_LOCK 0x17  // ESI = 0 (разблокировать) или 1 (заблокировать)

#define SYS_DISK_IDENTIFY     0x18  // ESI -> struct disk_identify_args
#define SYS_DISK_READ_SECTOR  0x19  // ESI -> struct disk_sector_args
#define SYS_DISK_WRITE_SECTOR 0x1A  // ESI -> struct disk_sector_args

struct disk_identify_args {
    char* model;
    int   result;
};

struct disk_sector_args {
    unsigned int   lba;
    unsigned char* buf;
    int            result;
};

#define SYS_GET_DATETIME 0x1B  // ESI -> struct datetime_args
#define SYS_REBOOT       0x1C

struct datetime_args {
    int second;
    int minute;
    int hour;
    int day;
    int month;
    int year;
};

#define SYS_GET_MOUSE 0x1D  // ESI -> struct mouse_args

struct mouse_args {
    int x;
    int y;
    int buttons;
};

#define SYS_BEEP 0x1E  // ESI -> struct beep_args

struct beep_args {
    unsigned int freq;
    unsigned int duration_ms;
};

// --- Буфер обмена (0x1F-0x20) ---
#define SYS_CLIPBOARD_SET 0x1F  // ESI -> struct clipboard_set_args
#define SYS_CLIPBOARD_GET 0x20  // ESI -> struct clipboard_get_args

#define CLIPBOARD_MAX_SIZE 1024 // см. предупреждение в kernel_entry.asm про 0x7c00/GDT

struct clipboard_set_args {
    unsigned char* data;
    unsigned int   size;
};

struct clipboard_get_args {
    unsigned char* buffer;
    unsigned int   max_size;
    unsigned int   out_size;
};

#define SYS_PS 0x13

struct ps_entry {
    unsigned int  index;
    int           pid;
    char          name[16];
    unsigned int  ticks;
    int           slot;
    unsigned int  heap_brk;
    int           result;
};

#endif
