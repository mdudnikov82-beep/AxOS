/* Linker script для AxOS/RV64 на QEMU virt board.
   OpenSBI прыгает на 0x80200000 после инициализации M-mode. */

OUTPUT_FORMAT("elf64-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS {
    . = 0x80200000;

    .text : {
        /* entry.S должен быть первым — здесь точка входа _start */
        KEEP(*(.text.entry))
        *(.text .text.*)
    }

    .rodata : {
        *(.rodata .rodata.*)
    }

    /* W^X boundary: everything below here is code+rodata (R+X, no W);
     * everything from here on is data (R+W, no X). Page-aligned so
     * paging_harden_kernel() can map each side with different PTE flags
     * without splitting a single page between the two. */
    . = ALIGN(4096);
    _rx_end = .;

    .data : {
        *(.data .data.*)
    }

    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)    /* маленькие глобалы RISC-V ABI — без этого они */
        *(.scommon)         /* ложатся после стека и alloc_page() их затирает */
        *(COMMON)
        _bss_end = .;
    }

    /* Стек ядра: 64 КБ сразу после BSS */
    . = ALIGN(4096);
    _stack_bottom = .;
    . += 0x10000;   /* 64 KB */
    _stack_top = .;

    _kernel_end = .;
}
