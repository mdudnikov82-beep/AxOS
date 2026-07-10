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
extern task_current_wants_resched ; int task_current_wants_resched(void) - tasking.c
extern schedule             ; unsigned long long schedule(unsigned long long current_rsp) - tasking.c
extern sys_fork_impl        ; void sys_fork_impl(unsigned long long parent_rsp) - kernel.c

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

    ; SYS_FORK (0x2A) - особый случай, минуя syscall_dispatch: нужен
    ; прямой доступ к живому регистровому кадру вызывающего (rsp прямо
    ; сейчас указывает на его начало - тот же формат, что и current_rsp
    ; у schedule()), чтобы клонировать его для потомка - обычные
    ; обработчики видят только ESI-аргумент. Результат sys_fork_impl
    ; пишет ПРЯМО в [rsp+0] (RAX-слот) сама - см. kernel.c.
    cmp cl, 0x2A
    jne .generic_dispatch

    mov rcx, rsp        ; sys_fork_impl(current_rsp) - Windows ABI: arg в RCX
    sub rsp, 32
    call sys_fork_impl
    add rsp, 32
    jmp .check_resched

.generic_dispatch:
    mov rdx, [rsp+32]          ; RSI = аргумент (сохранён выше в push rsi)

    sub rsp, 32         ; shadow space (Windows x64 ABI)
    call syscall_dispatch
    add rsp, 32

.check_resched:
    ; Если обработчик попросил немедленное переключение (сейчас
    ; единственный случай - SYS_SLEEP -> task_sleep_current, см.
    ; tasking.c) - делаем тот же обмен RSP через schedule(), что и
    ; timer_interrupt_handler (idt.asm): кадр GPR здесь той же раскладки
    ; (тот же порядок push выше = тот же порядок push в SAVE_REGS там).
    ; Без этого спящая задача продолжила бы выполняться до следующего
    ; таймерного тика вместо немедленной остановки.
    sub rsp, 32
    call task_current_wants_resched
    add rsp, 32
    test al, al
    jz .normal_return

    mov rcx, rsp        ; schedule(current_rsp) - Windows x64 ABI: arg в RCX
    sub rsp, 32
    call schedule
    add rsp, 32
    mov rsp, rax        ; RAX = RSP задачи, на которую переключились

.normal_return:
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
