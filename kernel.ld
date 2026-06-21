OUTPUT_FORMAT("pe-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
    . = 0x1000;
    .text : { *(.text) }
    __text_end = .; /* GCC добавляет подчёркивание: extern char _text_end[] в Си */

    .data : { *(.data) }
    .bss : {
        __bss_start = .;
        *(.bss)
        __bss_end = .;
    }
}