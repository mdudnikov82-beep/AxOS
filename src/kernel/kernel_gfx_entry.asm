[bits 32]
global _start
extern _gfx_main

_start:
    mov esp, 0x90000
    call _gfx_main
    jmp $
