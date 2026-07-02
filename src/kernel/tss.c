// =================================================================
//  TSS: переключение стека при переходе ring3 -> ring0
// =================================================================
//
// При прерывании/исключении/int 0x80, случившемся в ring3, CPU берёт
// новый SS:ESP из TSS (поля SS0/ESP0) — на этот стек кладутся старые
// SS/ESP/EFLAGS/CS/EIP, и в нём работает обработчик в ring0. Сама
// структура TSS размещается по фиксированному физическому адресу
// (см. TSS_BASE в gdt.asm), как и таблицы страниц — чтобы не раздувать
// kernel.bin статическими массивами.

#define TSS_BASE 0x9B000
#define TSS_SEG  0x28 // gdt_tss - gdt_start (5-я запись GDT)

// Стек ядра для обработчиков, попадающих в ring0 из ring3.
// Тот же адрес, что использует BEGIN_PM для начального ESP — оба
// случая не пересекаются по времени.
#define KERNEL_STACK 0x90000
#define KERNEL_DATA_SEG 0x10 // DATA_SEG из gdt.asm

void init_tss() {
    unsigned char* tss = (unsigned char*)TSS_BASE;

    for (int i = 0; i < 104; i++) {
        tss[i] = 0;
    }

    *(unsigned int*)(tss + 4) = KERNEL_STACK;     // ESP0
    *(unsigned short*)(tss + 8) = KERNEL_DATA_SEG; // SS0

    __asm__ volatile("ltr %%ax" :: "a"((unsigned short)TSS_SEG));
}

void tss_set_esp0(unsigned int esp0) {
    *(unsigned int*)(TSS_BASE + 4) = esp0;
}
