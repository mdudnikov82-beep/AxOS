; =================================================================
;  AxOS syscall wrappers для кольца 3
; =================================================================
;
; ABI ядра: AH = номер syscall, ESI = указатель на аргумент, int 0x80.
; Соглашение вызова C (cdecl): аргументы на стеке справа-налево,
; возврат в EAX, вызывающий чистит стек, сохраняем EBX/ESI/EDI.

[bits 32]

global _ax_print
global _ax_clear
global _ax_readkey
global _ax_writefile
global _ax_readfile
global _ax_exit

; void ax_print(char* msg)
_ax_print:
    push esi
    mov esi, [esp+8]    ; после push: [esp+4]=ret, [esp+8]=msg
    mov ah, 0x01        ; SYS_PRINT_STRING
    int 0x80
    pop esi
    ret

; void ax_clear(void)
_ax_clear:
    mov ah, 0x02        ; SYS_CLEAR_SCREEN
    int 0x80
    ret

; char ax_readkey(void)  — 0 если нет нажатий, иначе ASCII-код
_ax_readkey:
    push esi
    sub esp, 4          ; 1-байтовый буфер на стеке (выровнен до 4)
    mov byte [esp], 0
    mov esi, esp        ; ESI -> буфер
    mov ah, 0x03        ; SYS_READ_KEY
    int 0x80
    movzx eax, byte [esp]
    add esp, 4
    pop esi
    ret

; void ax_writefile(char* name, unsigned char* data, unsigned int size)
; Строит struct write_file_args на стеке и передаёт указатель в ESI.
_ax_writefile:
    push esi
    push ebx
    ; после двух push: [esp+12]=name, [esp+16]=data, [esp+20]=size
    mov eax, [esp+12]
    mov ecx, [esp+16]
    mov edx, [esp+20]
    push edx            ; struct.size
    push ecx            ; struct.data
    push eax            ; struct.filename
    mov esi, esp        ; ESI -> struct
    mov ah, 0x04        ; SYS_WRITE_FILE
    int 0x80
    add esp, 12         ; убираем struct
    pop ebx
    pop esi
    ret

; unsigned int ax_readfile(char* name, unsigned char* buf, unsigned int max)
; Строит struct read_file_args на стеке; возвращает out_size в EAX.
_ax_readfile:
    push esi
    push ebx
    ; после двух push: [esp+12]=name, [esp+16]=buf, [esp+20]=max
    mov eax, [esp+12]
    mov ecx, [esp+16]
    mov edx, [esp+20]
    push dword 0        ; struct.out_size = 0 (ядро запишет сюда результат)
    push edx            ; struct.max_size
    push ecx            ; struct.buffer
    push eax            ; struct.filename
    mov esi, esp        ; ESI -> struct
    mov ah, 0x05        ; SYS_READ_FILE
    int 0x80
    mov eax, [esp+12]   ; возвращаем out_size
    add esp, 16         ; убираем struct
    pop ebx
    pop esi
    ret

; void ax_exit(void)
_ax_exit:
    mov ah, 0x06        ; SYS_EXIT
    int 0x80
.hang:
    jmp .hang
