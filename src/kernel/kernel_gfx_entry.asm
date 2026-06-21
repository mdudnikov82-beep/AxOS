[bits 32]
global _start
extern _gfx_main
extern __bss_start
extern __bss_end

_start:
    mov esp, 0x90000

    ; См. kernel_entry.asm - .bss не грузится с диска и не обнуляется
    ; ничем, кроме нас.
    mov edi, __bss_start
    mov ecx, __bss_end
    sub ecx, edi
    xor eax, eax
    rep stosb

    call _gfx_main
    jmp $
