// =================================================================
//  TSS64: переключение стека при переходе ring3 -> ring0
// =================================================================
//
// В 64-бит режиме TSS имеет другую структуру: RSP0 лежит по смещению 4
// (8 байт), поля SS0 нет. CPU при прерывании из ring3 загружает RSP из
// TSS.RSP0. IOPM-смещение по offset 102 (=104 → нет IOPM).
// TSS-дескриптор в GDT теперь 16 байт (см. gdt.asm, gdt_tss).

#define TSS_BASE 0x9B000
#define TSS_SEG  0x30       // gdt_tss - gdt_start (6-й слот GDT, 64-бит дескриптор)

#define KERNEL_STACK 0x90000

void init_tss() {
    unsigned char* tss = (unsigned char*)TSS_BASE;

    for (int i = 0; i < 104; i++) tss[i] = 0;

    // RSP0 по смещению 4: стек ядра для ring3->ring0 (8 байт в TSS64).
    *(unsigned long long*)(tss + 4) = KERNEL_STACK;

    // IOPB offset = 104 (нет IOPM, все порты запрещены/разрешены по умолчанию).
    *(unsigned short*)(tss + 102) = 104;

    __asm__ volatile("ltr %%ax" :: "a"((unsigned short)TSS_SEG));
}

void tss_set_rsp0(unsigned long long rsp0) {
    *(unsigned long long*)(TSS_BASE + 4) = rsp0;
}
