; В 64-битном PE (pe-x86-64) GCC/ld не добавляет подчёркивание к символам.
[bits 64]
global _start
extern kernel_main
extern __bss_start
extern __bss_end

_start:
    ; boot.asm уже переключил нас в long mode и прыгнул сюда.
    ; Устанавливаем RSP - стек ядра, достаточно далеко от кода ядра.
    mov rsp, 0x90000

    ; Обнуляем .bss — данные не грузятся с диска, RAM может быть ненулевая
    ; (хотя QEMU обнуляет, реальное железо не обязано).
    mov rdi, __bss_start
    mov rcx, __bss_end
    sub rcx, rdi
    xor eax, eax
    rep stosb

    ; Windows x64 ABI: перед CALL RSP должен быть выровнен на 16 байт.
    ; RSP=0x90000 (кратно 16), CALL уберёт 8 байт - GCC-пролог правильно
    ; это компенсирует через push rbp.
    call kernel_main
    jmp $