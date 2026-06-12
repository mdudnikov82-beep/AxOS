; =================================================================
;  СИСТЕМНЫЕ ВЫЗОВЫ AxOS (API v1.0)
; =================================================================

[bits 32]

extern _print_string ; void print_string(char* str) из src/kernel/screen.c
extern _clear_screen ; void clear_screen() из src/kernel/screen.c

global syscall_handler
global _syscall_handler ; GCC на Windows добавляет подчёркивание к C-функциям

_syscall_handler:
syscall_handler:
    pusha               ; Сохраняем все регистры вызвавшей программы, чтобы не сломать её работу

    ; --- МЕНЮ ФУНКЦИЙ ---
    cmp ah, 0x01        ; Функция 0x01: Печать строки
    je .api_print_string

    cmp ah, 0x02        ; Функция 0x02: Очистить экран
    je .api_clear_screen

    ; Если функция неизвестна — просто выходим
    popa
    iret

; --- Реализация Функции 0x01 (Печать строки) ---
; Вход: ESI = указатель на строку с нулевым символом в конце
.api_print_string:
    push esi
    call _print_string  ; Зовём C-функцию из screen.c (учитывает курсор и границы экрана)
    add esp, 4           ; cdecl: сами убираем аргумент со стека
    popa                ; Восстанавливаем регистры
    iret                ; Возвращаемся в программу, которая нас вызвала

; --- Реализация Функции 0x02 (Очистка экрана) ---
.api_clear_screen:
    call _clear_screen   ; Зовём C-функцию из screen.c (сбрасывает курсор и очищает экран)
    popa
    iret