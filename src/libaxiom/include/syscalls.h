#ifndef AXOS_SYSCALLS_H
#define AXOS_SYSCALLS_H

// ABI системных вызовов AxOS: int 0x80, AH = номер, ESI = аргумент.

#define SYS_PRINT_STRING 0x01   // ESI -> char* (строка с '\0')
#define SYS_CLEAR_SCREEN 0x02   // ESI не используется
#define SYS_READ_KEY     0x03   // ESI -> char: ядро пишет туда последний символ (0 если нет)
#define SYS_WRITE_FILE   0x04   // ESI -> struct write_file_args
#define SYS_READ_FILE    0x05   // ESI -> struct read_file_args
#define SYS_EXIT         0x06   // ESI не используется — задача завершается

struct write_file_args {
    char*          filename;
    unsigned char* data;
    unsigned int   size;
};

struct read_file_args {
    char*          filename;
    unsigned char* buffer;
    unsigned int   max_size;
    unsigned int   out_size;    // ядро записывает сюда фактический размер
};

#endif
