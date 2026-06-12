OUTPUT_FORMAT("pe-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
    . = 0x1000;
    .text : { *(.text) }
 
    .data : { *(.data) }
    .bss : { *(.bss) }
}