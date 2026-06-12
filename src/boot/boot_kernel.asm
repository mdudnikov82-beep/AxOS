[org 0x7c00]

mov bp, 0x9000
mov sp, bp

call switch_to_pm
jmp $

%include "src/kernel/gdt.asm"
%include "src/boot/switch_to_pm.asm"

[bits 32]
BEGIN_PM:
    ; 1. Очистка экрана (заполняем видеопамять пробелами с синим фоном)
    mov edi, 0xb8000    ; Начало видеопамяти
    mov ecx, 2000       ; 80 * 25 = 2000 ячеек на экране
    mov ax, 0x1F20      ; 0x1F — атрибут (синий фон/белый текст), 0x20 — символ ' ' (пробел)
    rep stosw           ; Заполнить всю память

    ; 2. Вывод текста "AxOS" (только 4 символа)
    mov word [0xb8000], 0x1F41 ; 'A'
    mov word [0xb8002], 0x1F78 ; 'x'
    mov word [0xb8004], 0x1F4F ; 'O'
    mov word [0xb8006], 0x1F53 ; 'S'

    jmp 0x1200          ; Передаём управление ядру (boot_kernel.bin = 512 байт по 0x1000, ядро с 0x1200)

times 510-($-$$) db 0    ; Заполнение до 512 байт (требование загрузочного сектора)
dw 0xaa55                ; Сигнатура загрузочного сектора (boot sector signature)