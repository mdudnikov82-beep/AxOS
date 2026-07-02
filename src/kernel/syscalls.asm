; =================================================================
;  СИСТЕМНЫЕ ВЫЗОВЫ AxOS (int 0x80) — 64-бит мост
; =================================================================
;
; 32-битные user-программы вызывают "int 0x80" в режиме совместимости.
; CPU переключает нас в 64-бит режим ядра и сохраняет:
;   SS_user, RSP_user, RFLAGS, CS_user (compat 0x23), RIP_user (32-bit)
;
; Конвенция от user crt0.asm (32-bit compat):
;   AH = номер функции, ESI = аргумент (указатель или значение)
;
; Windows x64 ABI: первый аргумент в RCX, второй в RDX.

[bits 64]

extern syscall_dispatch     ; void syscall_dispatch(unsigned char func, char* arg)

global syscall_handler

syscall_handler:
    cld
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    push rbp
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    push rax        ; [rsp] = RAX; AH лежит в байте [rsp+1]

    ; Windows x64 ABI:
    ;   arg1 (RCX) = код функции (AH из user RAX)
    ;   arg2 (RDX) = аргумент (ESI user, ноль-расширен в RSI)
    ; Стек после pushes: [rsp+0]=rax [rsp+8]=rbx [rsp+16]=rcx [rsp+24]=rdx [rsp+32]=rsi
    movzx ecx, byte [rsp+1]   ; func code из AH: память-операнд, без REX-конфликта
    mov rdx, [rsp+32]          ; RSI = аргумент (сохранён выше в push rsi)

    sub rsp, 32         ; shadow space (Windows x64 ABI)
    call syscall_dispatch
    add rsp, 32

    pop rax
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15
    iretq
