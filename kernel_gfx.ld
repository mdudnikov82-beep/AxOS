OUTPUT_FORMAT("pe-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
    . = 0x1000;
    .text : { *(.text) }
    . = ALIGN(0x1000);
    __text_end = .;

    .data : { *(.data) }
    .bss : {
        __bss_start = .;
        *(.bss)
        __bss_end = .;
    }
}
