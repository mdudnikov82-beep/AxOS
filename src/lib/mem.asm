[bits 32]
; memset(EDI=dest, AL=value, ECX=count)
memset:
    pusha                   ; Сохраняем все регистры (32 байта в стеке)
    mov edi, [esp + 36]     ; dest (аргумент передан до pusha)
    mov al, [esp + 40]      ; value
    mov ecx, [esp + 44]     ; count
    rep stosb               ; Выполняем заполнение
    popa                    ; Восстанавливаем все регистры
    ret                     ; Возвращаемся к вызывающей функции