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

#endif
