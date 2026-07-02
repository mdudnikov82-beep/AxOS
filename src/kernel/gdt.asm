; Физический адрес и размер TSS (см. src/kernel/tss.c)
; TSS64 = 104 байта = 0x68 байт, limit = 0x67.
TSS_BASE  equ 0x9B000
TSS_LIMIT equ 0x67

; RELOC_DELTA - поправка для gdt_descriptor ниже, если этот файл
; подключён загрузчиком, который сам себя релоцирует (см. boot.asm).
; boot_gfx.asm и другие, кто не релоцируется, его не определяют -
; дефолт 0 (без поправки) сохраняет их поведение неизменным.
%ifndef RELOC_DELTA
%define RELOC_DELTA 0
%endif

gdt_start:
    dq 0x0

; Дескриптор кода ядра 32-бит — используется только при переходе boot→long mode.
gdt_code:
    dw 0xffff
    dw 0x0
    db 0x0
    db 10011010b        ; P=1, DPL=0, S=1, тип=code R/X
    db 11001111b        ; G=1, D=1 (32-бит), L=0
    db 0x0

; Дескриптор данных (работает и в 32-бит и в 64-бит режиме ядра).
gdt_data:
    dw 0xffff
    dw 0x0
    db 0x0
    db 10010010b        ; P=1, DPL=0, S=1, тип=data R/W
    db 11001111b
    db 0x0

; 64-бит дескриптор кода ядра (L=1, D=0, DPL=0) — основной сегмент long mode.
gdt_code64:
    dw 0x0000           ; limit (игнорируется в 64-бит)
    dw 0x0000           ; base low
    db 0x00             ; base mid
    db 10011010b        ; P=1, DPL=0, S=1, тип=code R/X
    db 00100000b        ; G=0, D=0, L=1 (64-бит код!), AVL=0
    db 0x00             ; base high

; --- ring3-сегменты: user-mode в 32-бит режиме совместимости (DPL=11) ---
gdt_user_code:
    dw 0xffff
    dw 0x0
    db 0x0
    db 11111010b        ; P=1, DPL=3, S=1, тип=code R/X
    db 11001111b        ; G=1, D=1 (32-бит compat), L=0
    db 0x0

gdt_user_data:
    dw 0xffff
    dw 0x0
    db 0x0
    db 11110010b        ; P=1, DPL=3, S=1, тип=data R/W
    db 11001111b
    db 0x0

; TSS64: в 64-бит режиме дескриптор TSS занимает 16 байт (два слота GDT).
; Высшие 32 бита базы = 0 (TSS_BASE < 4GB).
gdt_tss:
    dw TSS_LIMIT
    dw TSS_BASE & 0xFFFF
    db (TSS_BASE >> 16) & 0xFF
    db 10001001b        ; P=1, DPL=0, S=0, тип=1001 (64-бит TSS, available)
    db 0x00             ; G=0, AVL=0, limit(19:16)=0
    db (TSS_BASE >> 24) & 0xFF
    ; Дополнительные 8 байт для 64-бит TSS-дескриптора:
    dd 0x00000000       ; base[63:32] = 0 (TSS_BASE < 4GB)
    dd 0x00000000       ; зарезервировано

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start + RELOC_DELTA

CODE_SEG      equ gdt_code     - gdt_start   ; 0x08 — 32-бит ядро (только boot)
DATA_SEG      equ gdt_data     - gdt_start   ; 0x10 — данные
CODE64_SEG    equ gdt_code64   - gdt_start   ; 0x18 — 64-бит ядро
USER_CODE_SEG equ gdt_user_code - gdt_start  ; 0x20 — 32-бит user compat
USER_DATA_SEG equ gdt_user_data - gdt_start  ; 0x28 — user данные
TSS_SEG       equ gdt_tss      - gdt_start   ; 0x30 — TSS64