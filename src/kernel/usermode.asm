; =================================================================
;  Переход в ring3 (32-бит compatibility mode) из 64-бит ядра
; =================================================================
;
; void enter_usermode(void (*entry)(void));
;
; Windows x64 ABI: аргумент entry в RCX.
; Строит iretq-кадр (SS, RSP, RFLAGS, CS, RIP) с селекторами
; ring3 32-битного compat-режима и уходит в user через iretq.
; Функция не возвращается.

[bits 64]

global enter_usermode

; Селекторы ring3 из gdt.asm (DPL=3 → RPL=11b в младших 2 битах).
USER_CODE32_SEG equ 0x20    ; gdt_user_code (D=1, L=0 → 32-бит compat)
USER_DATA_SEG   equ 0x28    ; gdt_user_data

; Стек для ring3-кода в identity-mapped регионе (страница с USER|RW).
; Не совпадает с TSS.RSP0 или стеком ядра — отдельная страница.
USER_STACK_TOP  equ 0x9B000

enter_usermode:
    ; RCX = entry point (первый аргумент, Windows x64 ABI).
    cli

    ; Настраиваем сегменты данных на ring3-значения.
    mov ax, (USER_DATA_SEG | 3)
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Строим iretq кадр на текущем стеке:
    ;   [RSP+32] SS
    ;   [RSP+24] RSP_user
    ;   [RSP+16] RFLAGS
    ;   [RSP+8]  CS (compat)
    ;   [RSP+0]  RIP
    push qword (USER_DATA_SEG | 3)     ; SS
    push qword USER_STACK_TOP           ; RSP
    pushfq
    or qword [rsp], 0x200               ; RFLAGS.IF = 1
    push qword (USER_CODE32_SEG | 3)   ; CS (32-бит compat, DPL=3)
    push rcx                            ; RIP = entry

    iretq
