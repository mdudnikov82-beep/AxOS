; idt_shell.asm — IRQ handlers for AxOS graphical shell
; IRQ1  (keyboard) → INT 0x21
; IRQ12 (mouse)    → INT 0x2C
[bits 32]

extern _mouse_irq_handler_main
extern _keyboard_irq_handler

global _keyboard_interrupt_handler
global _mouse_interrupt_handler
global mouse_interrupt_handler
global _default_irq_handler
global _default_exc_handler

; Default handler for unused IRQs (spurious etc.) — just EOI and return
_default_irq_handler:
    pusha
    mov al, 0x20
    out 0xA0, al        ; EOI slave  (safe even if not a slave IRQ)
    out 0x20, al        ; EOI master
    popa
    iret

; Default handler for CPU exceptions — halt
_default_exc_handler:
    cli
    hlt
    jmp _default_exc_handler

_keyboard_interrupt_handler:
    cld
    pusha
    mov al, 0x20
    out 0x20, al        ; EOI master PIC
    call _keyboard_irq_handler
    popa
    iret

_mouse_interrupt_handler:
mouse_interrupt_handler:
    cld
    pusha
    mov al, 0x20
    out 0xA0, al        ; EOI slave PIC  (IRQ12)
    out 0x20, al        ; EOI master PIC (cascade IRQ2)
    call _mouse_irq_handler_main
    popa
    iret
