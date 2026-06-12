[bits 32]
extern _keyboard_handler_main ; GCC на Windows добавляет подчёркивание к C-функциям
extern _timer_handler_main
extern _page_fault_handler_main

global _keyboard_interrupt_handler
global keyboard_interrupt_handler
global _timer_interrupt_handler
global timer_interrupt_handler
global _page_fault_handler
global page_fault_handler

_keyboard_interrupt_handler:
keyboard_interrupt_handler:
    cld             ; <--- Очищаем флаг направления (важно для работы Си!)
    pusha           ; Сохраняем все регистры

    call _keyboard_handler_main

    mov al, 0x20    ; EOI
    out 0x20, al

    popa            ; Восстанавливаем регистры
    iret            ; Выход из прерывания

; --- Обработчик IRQ0 (таймер PIT) ---
_timer_interrupt_handler:
timer_interrupt_handler:
    cld
    pusha

    call _timer_handler_main

    mov al, 0x20    ; EOI
    out 0x20, al

    popa
    iret

; --- Обработчик исключения #14 (Page Fault) ---
; CPU кладёт в стек код ошибки перед EIP/CS/EFLAGS, и записывает
; адрес, вызвавший сбой, в регистр CR2.
_page_fault_handler:
page_fault_handler:
    cld
    pusha

    mov eax, cr2
    push eax
    call _page_fault_handler_main
    ; page_fault_handler_main не возвращается (вешает систему),
    ; но для порядка приводим стек в исходный вид
    add esp, 4

    popa
    add esp, 4      ; убираем код ошибки, который положил CPU
    iret