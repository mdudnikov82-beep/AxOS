/* Harvard-style split matching cpu_core.v's separate instr_mem/
 * data_mem: TEXT is its own address-0-based memory (loaded into
 * instr_mem via elf2hex.py), DATA is a SEPARATE address-0-based
 * memory (data_mem) that this test never bothers pre-loading (it's
 * zeroed at reset and the program only ever writes to it at
 * runtime) - so only .text/.rodata need to end up in the hex file. */
ENTRY(_start)

MEMORY {
    TEXT (rx) : ORIGIN = 0x00000000, LENGTH = 4K
    DATA (rw) : ORIGIN = 0x00001000, LENGTH = 4K
}

SECTIONS {
    .text : { *(.text*) } > TEXT
    .rodata : { *(.rodata*) } > TEXT
    .data : { *(.data*) } > DATA
    .bss : { *(.bss*) *(COMMON) } > DATA
}
