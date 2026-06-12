[org 0x7c00]

mov bp, 0x9000
mov sp, bp

call switch_to_pm        ; Переход в 32-битный режим
jmp $

%include "src\kernel\gdt.asm"
%include "src\boot\switch_to_pm.asm"
%include "src\lib\string.asm"

[bits 32]
BEGIN_PM:
    ; Прямая запись в видеопамять (адрес 0xB8000)
    ; 0x1F — это синий фон и белый текст
    mov byte [0xb8000], 'A'
    mov byte [0xb8001], 0x1F
    mov byte [0xb8002], 'x'
    mov byte [0xb8003], 0x1F
    mov byte [0xb8004], 'O'
    mov byte [0xb8005], 0x1F
    mov byte [0xb8006], 'S'
    mov byte [0xb8007], 0x1F
    jmp $

times 510-($-$$) db 0
dw 0xaa55