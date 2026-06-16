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

#endif
