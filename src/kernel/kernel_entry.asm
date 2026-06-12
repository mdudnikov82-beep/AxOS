[bits 32]
global _start
extern _kernel_main

_start:
    mov esp, 0x90000    ; <--- ВОТ ЭТА СТРОКА РЕШИТ ВСЁ
    call _kernel_main   ; Вызываем наше Си-ядро
    jmp $               ; Если Си-ядро вдруг завершится — зависаем тут