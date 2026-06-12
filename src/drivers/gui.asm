; gui.asm — библиотека для рисования UI
; Вход: AH = цвет (атрибут), CL = ширина, CH = высота, DX = координаты (row:col)

draw_rect:
    pusha
    mov ax, 0xB800
    mov es, ax
    
    ; Считаем смещение (DI = (row * 80 + col) * 2)
    mov ax, dx          ; DL = col, DH = row
    mov al, dh
    mov bl, 80
    mul bl
    add al, dl
    adc ah, 0
    shl ax, 1           ; Умножаем на 2 (для байтов атрибутов)
    mov di, ax          ; Теперь DI указывает на начало карточки
    
    mov al, 0x20        ; Символ пробела (заливка)
    mov bl, ch          ; Высота (количество строк)
.row_loop:
    push di
    mov cl, cl          ; Ширина (количество символов)
.col_loop:
    mov [es:di], ax     ; Записываем цвет и символ
    add di, 2
    loop .col_loop
    pop di
    add di, 160         ; Переходим на следующую строку экрана (80*2 байта)
    dec bl
    jnz .row_loop
    
    popa
    ret