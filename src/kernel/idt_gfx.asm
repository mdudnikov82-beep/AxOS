; IDT-обработчик IRQ12 (мышь) для графической демки - минимальная копия
; mouse_interrupt_handler из idt.asm. Отдельный файл, а не переиспользование
; idt.asm целиком: тот тянет extern'ы на page_fault/ide/schedule, которых
; в этой маленькой демке просто нет.
[bits 32]
extern _mouse_irq_handler_main

global _mouse_interrupt_handler
global mouse_interrupt_handler

_mouse_interrupt_handler:
mouse_interrupt_handler:
    cld
    pusha

    mov al, 0x20
    out 0xA0, al    ; EOI слейву (сам IRQ12)
    out 0x20, al    ; EOI мастеру (каскадная линия IRQ2)

    call _mouse_irq_handler_main

    popa
    iret
