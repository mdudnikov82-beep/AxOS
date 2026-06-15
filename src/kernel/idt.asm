[bits 32]
extern _keyboard_handler_main ; GCC на Windows добавляет подчёркивание к C-функциям
extern _timer_handler_main
extern _page_fault_handler_main
extern _schedule ; tasking.c - переключение задач (round-robin)

global _keyboard_interrupt_handler
global keyboard_interrupt_handler
global _timer_interrupt_handler
global timer_interrupt_handler
global _page_fault_handler
global page_fault_handler

_keyboard_interrupt_handler:
keyboard_interrupt_handler:
    cld             ; <--- Очищаем флаг направления (важно для работы Си!)
    pusha           ; Сохраняем все регистры

    ; EOI отправляем ДО вызова обработчика: keyboard_handler_main может
    ; выполнить команду "usermode", которая уходит в ring3 через iretd
    ; и сюда уже не возвращается. Если бы EOI отправлялся после call,
    ; PIC считал бы IRQ1 "в обработке" навсегда, и клавиатура умирала
    ; бы после первого "usermode".
    mov al, 0x20    ; EOI
    out 0x20, al

    call _keyboard_handler_main

    popa            ; Восстанавливаем регистры
    iret            ; Выход из прерывания

; --- Обработчик IRQ0 (таймер PIT) ---
_timer_interrupt_handler:
timer_interrupt_handler:
    cld
    pusha

    call _timer_handler_main

    mov al, 0x20    ; EOI
    out 0x20, al

    ; Переключение задач: после pusha esp указывает на кадр текущей
    ; задачи [pusha x8][EIP][CS][EFLAGS]. schedule(esp) сохраняет его
    ; в текущей задаче, выбирает следующую по кольцу и возвращает её
    ; esp (для task0 на первом тике, и до init_tasking(), schedule
    ; возвращает тот же esp - переключения не происходит).
    mov eax, esp
    push eax
    call _schedule
    add esp, 4
    mov esp, eax

    popa
    iret

; --- Обработчик исключения #14 (Page Fault) ---
; CPU кладёт в стек код ошибки перед EIP/CS/EFLAGS, и записывает
; адрес, вызвавший сбой, в регистр CR2.
_page_fault_handler:
page_fault_handler:
    cld
    pusha

    ; page_fault_handler_main(faulting_address, frame): frame - указатель
    ; на этот кадр pusha (нужен, чтобы переписать EIP/проверить CS при
    ; killе изолированной задачи, см. paging.c). EBX используется как
    ; скретч - его сохранённое здесь значение восстановит popa, текущее
    ; содержимое регистра уже не важно.
    mov ebx, esp
    mov eax, cr2
    push ebx
    push eax
    call _page_fault_handler_main
    add esp, 8
    ; page_fault_handler_main возвращается только для killed-задачи
    ; (изменив EIP в кадре); иначе вешает систему сама.

    popa
    add esp, 4      ; убираем код ошибки, который положил CPU
    iret