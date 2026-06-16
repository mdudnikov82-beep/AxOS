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

#endif
