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
global _ax_open
global _ax_fread
global _ax_fwrite
global _ax_close
global _ax_exec
global _ax_task_alive
global _ax_shell_claim
global _ax_set_foreground
global _ax_get_ticks
global _ax_sleep_ms
global _ax_readdir

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

; int ax_open(char* name, int flags)
; Строит struct open_args { filename, flags, result=-1 } на стеке.
; Возвращает result (fd >= 0 или -1).
_ax_open:
    push esi
    push ebx
    ; после двух push: [esp+12]=name, [esp+16]=flags
    mov eax, [esp+12]       ; name
    mov ecx, [esp+16]       ; flags
    push dword -1           ; struct.result = -1
    push ecx                ; struct.flags
    push eax                ; struct.filename  <- esp = &struct
    mov esi, esp
    mov ah, 0x07            ; SYS_OPEN
    int 0x80
    mov eax, [esp+8]        ; result (offset 8)
    add esp, 12
    pop ebx
    pop esi
    ret

; int ax_fread(int fd, void* buf, unsigned int n)
; Строит struct fread_args { fd, buf, count, result=-1 }.
_ax_fread:
    push esi
    push ebx
    ; после двух push: [esp+12]=fd, [esp+16]=buf, [esp+20]=n
    mov eax, [esp+12]       ; fd
    mov ecx, [esp+16]       ; buf
    mov edx, [esp+20]       ; count
    push dword -1           ; struct.result = -1
    push edx                ; struct.count
    push ecx                ; struct.buf
    push eax                ; struct.fd  <- esp = &struct
    mov esi, esp
    mov ah, 0x08            ; SYS_FREAD
    int 0x80
    mov eax, [esp+12]       ; result (offset 12)
    add esp, 16
    pop ebx
    pop esi
    ret

; int ax_fwrite(int fd, const void* buf, unsigned int n)
; Строит struct fwrite_args { fd, buf, count, result=-1 }.
_ax_fwrite:
    push esi
    push ebx
    ; после двух push: [esp+12]=fd, [esp+16]=buf, [esp+20]=n
    mov eax, [esp+12]
    mov ecx, [esp+16]
    mov edx, [esp+20]
    push dword -1           ; struct.result = -1
    push edx                ; struct.count
    push ecx                ; struct.buf
    push eax                ; struct.fd
    mov esi, esp
    mov ah, 0x09            ; SYS_FWRITE
    int 0x80
    mov eax, [esp+12]       ; result
    add esp, 16
    pop ebx
    pop esi
    ret

; void ax_close(int fd)
; Строит struct close_args { fd }.
_ax_close:
    push esi
    ; после push: [esp+8]=fd
    mov eax, [esp+8]
    push eax                ; struct.fd  <- esp = &struct
    mov esi, esp
    mov ah, 0x0A            ; SYS_CLOSE
    int 0x80
    add esp, 4
    pop esi
    ret

; int ax_exec(char* cmdline)
; Строит struct exec_args { cmdline, result=-1 } на стеке.
; Возвращает slot >= 0 или -1 (не найден) или -2 (нет слотов).
_ax_exec:
    push esi
    push ebx
    ; после двух push: [esp+12]=cmdline
    mov eax, [esp+12]
    push dword -1           ; struct.result = -1  (offset 4)
    push eax                ; struct.cmdline       (offset 0 = esp)
    mov esi, esp
    mov ah, 0x0B            ; SYS_EXEC
    int 0x80
    mov eax, [esp+4]        ; result (offset 4)
    add esp, 8
    pop ebx
    pop esi
    ret

; int ax_task_alive(int slot)
; Строит struct task_alive_args { slot, result } на стеке.
; Возвращает 1 = работает, 0 = завершена.
_ax_task_alive:
    push esi
    push ebx
    ; после двух push: [esp+12]=slot
    mov eax, [esp+12]
    push dword 0            ; struct.result = 0  (offset 4)
    push eax                ; struct.slot         (offset 0 = esp)
    mov esi, esp
    mov ah, 0x0C            ; SYS_TASK_ALIVE
    int 0x80
    mov eax, [esp+4]        ; result (offset 4)
    add esp, 8
    pop ebx
    pop esi
    ret

; void ax_shell_claim(int claim)
; Передаёт claim (0 или 1) напрямую в ESI — ядро не разыменовывает его.
; claim=1: захватить клавиатуру (kernel shell пассивен).
; claim=0: вернуть клавиатуру ядру.
_ax_shell_claim:
    push esi
    mov esi, [esp+8]        ; esi = claim (0 или 1, не указатель!)
    mov ah, 0x0D            ; SYS_SHELL_CLAIM
    int 0x80
    pop esi
    ret

; void ax_set_foreground(int slot)
; Строит struct set_fg_args { slot } на стеке.
; slot >= 0: ядро убьёт эту задачу при Ctrl+C.
; slot = -1: сброс (нет foreground).
_ax_set_foreground:
    push esi
    push ebx
    ; после двух push: [esp+12]=slot
    mov eax, [esp+12]
    push eax                ; struct.slot  <- esp = &struct
    mov esi, esp
    mov ah, 0x0E            ; SYS_SET_FOREGROUND
    int 0x80
    add esp, 4
    pop ebx
    pop esi
    ret

; unsigned int ax_get_ticks(void)
; Строит struct get_ticks_args { result=0 } на стеке; ядро пишет timer_ticks.
_ax_get_ticks:
    push esi
    push ebx
    push dword 0            ; struct.result = 0  <- esp = &struct
    mov esi, esp
    mov ah, 0x0F            ; SYS_GET_TICKS
    int 0x80
    mov eax, [esp]          ; result (offset 0)
    add esp, 4
    pop ebx
    pop esi
    ret

; void ax_sleep_ms(unsigned int ms)
; Строит struct sleep_args { ms } на стеке; ядро вызывает sleep_ms(ms).
_ax_sleep_ms:
    push esi
    push ebx
    ; после двух push: [esp+12]=ms
    mov eax, [esp+12]
    push eax                ; struct.ms  <- esp = &struct
    mov esi, esp
    mov ah, 0x10            ; SYS_SLEEP
    int 0x80
    add esp, 4
    pop ebx
    pop esi
    ret

; int ax_readdir(struct readdir_args* a)
; ESI = указатель на struct readdir_args (передаётся напрямую).
; Возвращает a->result (1 = запись есть, 0 = конец директории).
; Раскладка struct: index(0) name[13](4) pad(17-19) size(20) result(24)
_ax_readdir:
    push esi
    push ebx
    ; после двух push: [esp+12] = указатель на struct readdir_args
    mov esi, [esp+12]       ; ESI -> struct напрямую
    mov ah, 0x11            ; SYS_READDIR
    int 0x80
    mov eax, [esi+24]       ; a->result (offset 24)
    pop ebx
    pop esi
    ret
