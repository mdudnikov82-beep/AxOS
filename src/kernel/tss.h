#ifndef TSS_H
#define TSS_H

// Заполняет TSS64 (по фиксированному физическому адресу, см. gdt.asm) и
// загружает Task Register (ltr). В 64-бит режиме TSS.RSP0 = 8 байт по
// смещению 4; SS0 отсутствует.
void init_tss();

// Меняет RSP0 в TSS64 — вызывается планировщиком при каждом переключении
// задачи, чтобы у каждой задачи был свой стек для ring3 -> ring0 переходов.
void tss_set_rsp0(unsigned long long rsp0);

#endif
