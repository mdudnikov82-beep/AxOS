; =================================================================
;  Загрузчик графической демо-сборки AxOS - копия boot.asm с одним
;  отличием: видеорежим 0x13 (320x200, 256 цветов, линейный буфер
;  0xA0000) вместо текстового 0x03. BIOS-смену режима можно делать
;  только в реальном режиме, до прыжка в protected mode - поэтому
;  это отдельный загрузчик, а не команда основного ядра.
; =================================================================
[org 0x7c00]

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000

    ; Режим 0x13: 320x200, 256 цветов, буфер по 0xA0000 (1 байт = 1 пиксель)
    mov ah, 0x00
    mov al, 0x13
    int 0x10

    ; --- Загружаем gfx-ядро с диска в память по адресу 0x1000 (как в boot.asm) ---
    mov bx, 0x1000
    mov ah, 0x02
    mov al, 17
    mov ch, 0
    mov dh, 0
    mov cl, 2
    int 0x13
    jc disk_error
    cmp al, 17
    jne disk_error

    mov bx, 0x1000 + 17 * 512
    mov ah, 0x02
    mov al, 18
    mov ch, 0
    mov dh, 1
    mov cl, 1
    int 0x13
    jc disk_error
    cmp al, 18
    jne disk_error

    mov bx, 0x1000 + 35 * 512
    mov ah, 0x02
    mov al, 18
    mov ch, 1
    mov dh, 0
    mov cl, 1
    int 0x13
    jc disk_error
    cmp al, 18
    jne disk_error

    jmp disk_done

disk_error:
    ; В графическом режиме int 0x10/ah=0x0E (teletype) не работает как в
    ; текстовом - просто останавливаемся молча.
    jmp $

disk_done:
    call switch_to_pm
    jmp $

%include "src/kernel/gdt.asm"
%include "src/boot/switch_to_pm.asm"

[bits 32]
BEGIN_PM:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov esp, 0x90000
    mov ebp, esp

    jmp 0x1000
    jmp $

times 510 - ($ - $$) db 0
dw 0xAA55
