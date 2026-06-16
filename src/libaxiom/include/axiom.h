#ifndef AXIOM_H
#define AXIOM_H

#include "syscalls.h"

// Базовые syscall-обёртки (реализованы в syscalls.asm)
void         ax_print(char* msg);
void         ax_clear(void);
char         ax_readkey(void);
void         ax_writefile(char* name, unsigned char* data, unsigned int size);
unsigned int ax_readfile(char* name, unsigned char* buf, unsigned int max);
void         ax_exit(void);

// fd-based file API
int  ax_open(char* name, int flags);          // возвращает fd или -1
int  ax_fread(int fd, void* buf, unsigned int n);   // возвращает прочитанные байты
int  ax_fwrite(int fd, const void* buf, unsigned int n); // возвращает записанные байты
void ax_close(int fd);

// Уровень stdio (реализован в stdio.c)
void ax_putchar(char c);
void ax_print_uint(unsigned int n);

#endif
