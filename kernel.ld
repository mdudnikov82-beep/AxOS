OUTPUT_FORMAT("pe-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SECTIONS
{
    . = 0x1000;
    .text : { *(.text) }
    .rdata : { *(.rdata*) *(.rodata*) }
    . = ALIGN(0x1000);
    /* В 64-бит PE символы не получают _ prefix: C "extern char _text_end[]"
       ищет "_text_end". В 32-бит PE было "__text_end". Оба нужны: __text_end
       для kernel_entry.asm (NASM), _text_end — для paging.c. */
    __text_end = .;
    _text_end  = .;

    .data : { *(.data*) }
    .bss : {
        __bss_start = .;
        *(.bss)
        *(COMMON)
        __bss_end = .;
    }

    /* SEH/unwind секции не нужны голому ядру; выбрасываем чтобы избежать
       relocation truncated (IMAGE_REL_AMD64_ADDR32NB) при больших бинарях. */
    /DISCARD/ : {
        *(.pdata)
        *(.xdata*)
        *(.eh_frame*)
        *(.comment)
        *(.note*)
    }
}
