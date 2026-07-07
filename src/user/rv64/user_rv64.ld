/* Линкер-скрипт для пользовательских программ AxOS/RV64.
   Виртуальный адрес 0x40000000 — L2[1] (вторая гигастраница),
   не пересекается с MMIO (L2[0]) и ядром (L2[2]). */

OUTPUT_ARCH(riscv)
ENTRY(_start)

/* W^X: код+rodata идут в отдельный сегмент R+X (без W), данные+bss — в
 * отдельный R+W (без X). Границу выравниваем на страницу (4K), иначе
 * elf_loader.c замапит последнюю страницу кода с флагами данных (или
 * наоборот) — обе стороны отображаются целыми 4K-страницами. */
PHDRS {
    text PT_LOAD FLAGS(5);   /* R+X = 4|1 */
    data PT_LOAD FLAGS(6);   /* R+W = 4|2 */
}

SECTIONS {
    . = 0x40000000;

    .text : {
        KEEP(*(.text.start))    /* crt0 _start должен быть первым */
        *(.text .text.*)
    } :text

    .rodata : { *(.rodata .rodata.*) } :text

    . = ALIGN(4096);

    .data : { *(.data .data.*) } :data

    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } :data

    /* Отбрасываем отладочную информацию */
    /DISCARD/ : { *(.eh_frame) *(.comment) }
}
