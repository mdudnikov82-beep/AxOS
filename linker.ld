ENTRY(start)

SECTIONS
{
    . = 0x7C00;

    .text :
    {
        build/boot.o(.text)
        *(.text)
    }

    .data : { *(.data) }
    .bss  : { *(.bss) }
    .rdata : { *(.rdata) }
    .idata : { *(.idata) }
    .reloc : { *(.reloc) }
}