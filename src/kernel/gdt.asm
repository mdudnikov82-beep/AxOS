; Физический адрес и размер TSS (см. src/kernel/tss.c)
TSS_BASE  equ 0x9E000
TSS_LIMIT equ 0x67 ; 104 байта - 1

gdt_start:
    dq 0x0

gdt_code:
    dw 0xffff
    dw 0x0
    db 0x0
    db 10011010b
    db 11001111b
    db 0x0

gdt_data:
    dw 0xffff
    dw 0x0
    db 0x0
    db 10010010b
    db 11001111b
    db 0x0

; --- ring3-сегменты для user-mode (DPL=11) ---
gdt_user_code:
    dw 0xffff
    dw 0x0
    db 0x0
    db 11111010b ; P=1, DPL=11, S=1, код, чтение+исполнение
    db 11001111b
    db 0x0

gdt_user_data:
    dw 0xffff
    dw 0x0
    db 0x0
    db 11110010b ; P=1, DPL=11, S=1, данные, чтение+запись
    db 11001111b
    db 0x0

; --- TSS: нужен, чтобы CPU знал, какой стек (SS0:ESP0) использовать
; при переходе ring3 -> ring0 (например, по int 0x80 или прерыванию) ---
gdt_tss:
    dw TSS_LIMIT
    dw TSS_BASE & 0xFFFF
    db (TSS_BASE >> 16) & 0xFF
    db 10001001b ; P=1, DPL=00, S=0, type=1001 (32-bit TSS, available)
    db 0x00      ; G=0, AVL=0, limit(19:16)=0
    db (TSS_BASE >> 24) & 0xFF

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start
USER_CODE_SEG equ gdt_user_code - gdt_start
USER_DATA_SEG equ gdt_user_data - gdt_start
TSS_SEG equ gdt_tss - gdt_start