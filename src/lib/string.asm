; Функция для получения длины строки (на языке ассемблера)
; Входящие параметры: SI = указатель на строку
; Возвращаемые значения: AX = длина строки

strlen:
    push si
    mov ax, 0
.loop:
    cmp byte [si], 0
    je .done
    inc si
    inc ax
    jmp .loop
.done:
    pop si
    ret