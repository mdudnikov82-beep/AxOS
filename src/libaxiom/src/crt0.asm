; =================================================================
;  crt0 — точка входа кольца 3 (заменяет src/user/start.asm)
; =================================================================
;
; Ядро (task_create_user_isolated) кладёт перед стартом:
;   EBX = argc
;   ECX = виртуальный адрес argv[] (char*[], NULL-terminated)
;
; crt0 пушит их на стек и вызывает main(int argc, char** argv)
; через стандартный cdecl. После возврата автоматически вызывает
; SYS_EXIT — писать ax_exit() в конце main() больше не нужно.
; main() возвращает int в EAX (cdecl) - переносим его в ESI ДО того,
; как mov ah затронет верхний байт EAX (AH - часть EAX) - ESI становится
; кодом выхода программы (см. sys_exit, kernel.c), доступным родителю
; через SYS_LAST_EXIT_CODE/ax_exit_code().

[bits 32]

global _start
extern _main
extern _ax_init_stack_guard

_start:
    call _ax_init_stack_guard   ; инициализировать канарейку до пролога main()
    push ecx        ; argv (char**)
    push ebx        ; argc (int)
    call _main
    add esp, 8      ; cdecl: caller cleans up
    mov esi, eax    ; код выхода = возврат main()
    mov ah, 0x06    ; SYS_EXIT
    int 0x80
.hang:
    jmp .hang
