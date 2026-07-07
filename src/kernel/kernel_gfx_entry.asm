[bits 32]
global _start
extern _gfx_main
extern __bss_start
extern __bss_end

_start:
    mov esp, 0x90000

    ; Zero BSS — NOTE: this also wipes the boot sector GDT at 0x7C59
    ; because the BSS range [__bss_start, __bss_end) covers that address.
    ; We rebuild a fresh GDT (embedded in .text below) right afterwards.
    mov edi, __bss_start
    mov ecx, __bss_end
    sub ecx, edi
    xor eax, eax
    rep stosb

    ; Reload GDT from the copy embedded in .text (lives below BSS, never zeroed).
    lgdt [gdt_ptr]
    ; Far jump to flush the CS descriptor cache with the new GDT entry.
    jmp 0x08:flush_cs
flush_cs:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    call _gfx_main
    jmp $

; ── GDT embedded in .text so it is NOT in BSS and survives zeroing ───
align 8
gdt_base:
    dq 0x0000000000000000   ; [0x00] null
    dq 0x00CF9A000000FFFF   ; [0x08] code32: base=0, limit=4GB, DPL=0, R/X
    dq 0x00CF92000000FFFF   ; [0x10] data32: base=0, limit=4GB, DPL=0, R/W
gdt_end:

gdt_ptr:
    dw gdt_end - gdt_base - 1   ; limit = 23 (3 entries × 8 bytes − 1)
    dd gdt_base                  ; linear base address of gdt_base
