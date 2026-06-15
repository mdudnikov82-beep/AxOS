#ifndef TSS_H
#define TSS_H

// Заполняет TSS (по фиксированному физическому адресу, см. gdt.asm) и
// загружает Task Register (ltr). После этого CPU знает, на какой стек
// (SS0:ESP0) переключаться при переходе ring3 -> ring0.
void init_tss();

// Меняет ESP0 в уже заполненном TSS - вызывается планировщиком
// (tasking.c) при каждом переключении задачи, чтобы у каждой задачи
// был свой стек для ring3 -> ring0 переходов.
void tss_set_esp0(unsigned int esp0);

#endif
