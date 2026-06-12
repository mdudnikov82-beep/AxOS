; Рисует рамку окна
draw_window:
    ; DI - позиция, AH - атрибуты
    mov cx, 20      ; Ширина
.loop:
    mov [gs:di], ax ; Рисуем рамку
    add di, 2
    loop .loop
    ret