[bits 32]
extern _keyboard_handler_main ; GCC на Windows добавляет подчёркивание к C-функциям
extern _timer_handler_main

global _keyboard_interrupt_handler
global keyboard_interrupt_handler
global _timer_interrupt_handler
global timer_interrupt_handler

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