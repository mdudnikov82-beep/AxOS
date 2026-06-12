#ifndef TSS_H
#define TSS_H

// Заполняет TSS (по фиксированному физическому адресу, см. gdt.asm) и
// загружает Task Register (ltr). После этого CPU знает, на какой стек
// (SS0:ESP0) переключаться при переходе ring3 -> ring0.
void init_tss();

#endif
