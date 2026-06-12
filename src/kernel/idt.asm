[bits 32]
extern _keyboard_handler_main ; GCC на Windows добавляет подчёркивание к C-функциям

global _keyboard_interrupt_handler
global keyboard_interrupt_handler
_keyboard_interrupt_handler:
keyboard_interrupt_handler:
    cld             ; <--- Очищаем флаг направления (важно для работы Си!)
    pusha           ; Сохраняем все регистры
    
    call _keyboard_handler_main 
    
    mov al, 0x20    ; EOI
    out 0x20, al    
    
    popa            ; Восстанавливаем регистры
    iret            ; Выход из прерывания