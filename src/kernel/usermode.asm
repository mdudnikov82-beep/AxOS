; =================================================================
;  Переход в ring3 (user mode)
; =================================================================
;
; void enter_usermode(void (*entry)(void));
;
; Готовит на стеке кадр для iretd: SS, ESP, EFLAGS, CS, EIP — все с
; селекторами ring3-сегментов (USER_*_SEG | 3). После iretd процессор
; переключается в CPL=3 и продолжает выполнение с адреса entry.
; Функция не возвращается (нет ret) — это билет в один конец.

[bits 32]

global enter_usermode
global _enter_usermode

USER_CODE_SEG equ 0x18
USER_DATA_SEG equ 0x20

; Отдельный стек для ring3-кода (внутри identity-mapped региона,
; страница помечена PRESENT|USER|RW в paging.c).
USER_STACK_TOP equ 0x9B000

_enter_usermode:
enter_usermode:
    cli
    mov eax, [esp+4]    ; cdecl: единственный аргумент (entry point)

    mov cx, (USER_DATA_SEG | 3)
    mov ds, cx
    mov es, cx
    mov fs, cx
    mov gs, cx

    push dword (USER_DATA_SEG | 3) ; SS
    push dword USER_STACK_TOP       ; ESP
    pushfd
    or dword [esp], 0x200            ; EFLAGS.IF=1 — таймер/клавиатура работают и в ring3
    push dword (USER_CODE_SEG | 3) ; CS
    push eax                          ; EIP = entry

    iretd
