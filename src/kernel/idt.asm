; =================================================================
;  Обработчики прерываний для x86-64 long mode
; =================================================================
;
; В 64-бит режиме:
;  - CPU всегда кладёт SS, RSP, RFLAGS, CS, RIP (5 × 8Б = 40Б)
;    даже при same-privilege (ring0→ring0) прерывании.
;  - pusha/popa НЕТ — сохраняем 15 регистров вручную (RAX..R15, без RSP).
;  - iret → iretq.
;  - schedule(): первый аргумент в RCX (Windows x64 ABI), возврат в RAX.
;  - Имена C-функций без подчёркивания (64-bit PE не добавляет _prefix).

[bits 64]

extern keyboard_handler_main
extern timer_handler_main
extern page_fault_handler_main
extern ide_irq_handler_main
extern mouse_irq_handler_main
extern schedule

global keyboard_interrupt_handler
global timer_interrupt_handler
global page_fault_handler
global ide_interrupt_handler
global mouse_interrupt_handler

; -----------------------------------------------------------------
;  Макрос: сохранить/восстановить 15 GPR (порядок pop = обратный push).
;  После SAVE_REGS RSP указывает на RAX (нижний адрес).
;  После RESTORE_REGS RSP восстанавливается на уровень до SAVE_REGS.
; -----------------------------------------------------------------
%macro SAVE_REGS 0
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
    push rax
%endmacro

%macro RESTORE_REGS 0
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
%endmacro

; -----------------------------------------------------------------
;  IRQ1: Клавиатура
; -----------------------------------------------------------------
keyboard_interrupt_handler:
    cld
    SAVE_REGS

    ; EOI ПЕРЕД обработчиком: keyboard_handler_main может запустить
    ; команду, которая уйдёт в ring3 через iretq и не вернётся сюда.
    ; Если EOI после — PIC считает IRQ1 занятым навсегда → клавиатура умрёт.
    mov al, 0x20
    out 0x20, al

    ; Windows x64 ABI: нет аргументов, нужен shadow space (32Б).
    sub rsp, 32
    call keyboard_handler_main
    add rsp, 32

    RESTORE_REGS
    iretq

; -----------------------------------------------------------------
;  IRQ0: Таймер PIT — также точка переключения задач.
; -----------------------------------------------------------------
timer_interrupt_handler:
    cld
    SAVE_REGS

    ; Вызов основного обработчика таймера (обновляет счётчик тиков).
    sub rsp, 32
    call timer_handler_main
    add rsp, 32

    ; EOI мастер-PIC.
    mov al, 0x20
    out 0x20, al

    ; schedule(current_rsp): текущий RSP — указатель на RAX в кадре GPR.
    ; Windows x64 ABI: arg в RCX, возврат в RAX.
    mov rcx, rsp
    sub rsp, 32
    call schedule
    add rsp, 32
    ; RAX = RSP следующей задачи (или того же, если переключения нет).
    mov rsp, rax

    RESTORE_REGS
    iretq

; -----------------------------------------------------------------
;  #14: Page Fault — CPU кладёт код ошибки ПЕРЕД RIP в кадре.
;
;  Кадр (от низшего адреса = RSP после SAVE_REGS):
;   [0..14]  = RAX..R15  (15 GPR, индексы 0..14)
;   [15]     = Error code (CPU-pushed, перед RIP)
;   [16]     = RIP
;   [17]     = CS
;   [18]     = RFLAGS
;   [19]     = RSP_old
;   [20]     = SS
;
;  page_fault_handler_main(faulting_addr, frame*):
;    arg1 = CR2 (RCX), arg2 = RSP (RDX) — Windows x64 ABI.
; -----------------------------------------------------------------
page_fault_handler:
    cld
    SAVE_REGS

    mov rcx, cr2        ; arg1: адрес, вызвавший сбой
    mov rdx, rsp        ; arg2: указатель на кадр (RAX в его начале)
    sub rsp, 32
    call page_fault_handler_main
    add rsp, 32
    ; page_fault_handler_main возвращается ТОЛЬКО при kill изолированной задачи
    ; (она переписывает RIP в кадре на USER_SPIN_ADDR).

    RESTORE_REGS
    add rsp, 8          ; убираем код ошибки, который CPU положил перед RIP
    iretq

; -----------------------------------------------------------------
;  IRQ14: IDE (первичный канал) — slave PIC, двойной EOI.
; -----------------------------------------------------------------
ide_interrupt_handler:
    cld
    SAVE_REGS

    mov al, 0x20
    out 0xA0, al        ; EOI slave PIC
    out 0x20, al        ; EOI master PIC

    sub rsp, 32
    call ide_irq_handler_main
    add rsp, 32

    RESTORE_REGS
    iretq

; -----------------------------------------------------------------
;  IRQ12: PS/2-мышь — slave PIC, двойной EOI.
; -----------------------------------------------------------------
mouse_interrupt_handler:
    cld
    SAVE_REGS

    mov al, 0x20
    out 0xA0, al        ; EOI slave PIC
    out 0x20, al        ; EOI master PIC

    sub rsp, 32
    call mouse_irq_handler_main
    add rsp, 32

    RESTORE_REGS
    iretq
