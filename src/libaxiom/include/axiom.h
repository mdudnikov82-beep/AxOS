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

// Уровень stdio (реализован в stdio.c)
void ax_putchar(char c);
void ax_print_uint(unsigned int n);

#endif
