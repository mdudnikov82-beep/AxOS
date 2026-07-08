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
global _ax_sbrk
global _ax_ps
global _ax_exec_redir
global _ax_unlink
global _ax_mkdir
global _ax_disk_lock
global _ax_disk_identify
global _ax_disk_read_sector
global _ax_disk_write_sector
global _ax_get_datetime
global _ax_reboot
global _ax_get_mouse
global _ax_beep
global _ax_clipboard_set
global _ax_clipboard_get
global _ax_set_level
global _ax_pci_get_device
global _ax_seccomp_raw
global _ax_set_priority
global _ax_net_mac
global _ax_net_send
global _ax_net_recv

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

; int ax_writefile(char* name, unsigned char* data, unsigned int size)
; Строит struct write_file_args { name, data, size, result=-1 } на стеке.
; Возвращает 1 (записан) или 0 (диск не готов/заблокирован/нет места).
_ax_writefile:
    push esi
    push ebx
    ; после двух push: [esp+12]=name, [esp+16]=data, [esp+20]=size
    mov eax, [esp+12]
    mov ecx, [esp+16]
    mov edx, [esp+20]
    push dword -1       ; struct.result (offset 12)
    push edx            ; struct.size
    push ecx            ; struct.data
    push eax            ; struct.filename
    mov esi, esp        ; ESI -> struct
    mov ah, 0x04        ; SYS_WRITE_FILE
    int 0x80
    mov eax, [esp+12]   ; result
    add esp, 16         ; убираем struct
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

; void* ax_sbrk(int increment)
; Строит struct sbrk_args { increment, result=0 } на стеке.
; Возвращает result (старый break) или (unsigned int)-1 при ошибке.
_ax_sbrk:
    push esi
    push ebx
    ; после двух push: [esp+12] = increment
    mov eax, [esp+12]
    push dword 0            ; struct.result = 0  (offset 4)
    push eax                ; struct.increment   (offset 0 = esp)
    mov esi, esp
    mov ah, 0x12            ; SYS_SBRK
    int 0x80
    mov eax, [esp+4]        ; result (offset 4)
    add esp, 8
    pop ebx
    pop esi
    ret

; int ax_exec_redir(char* cmdline, char* redir_out)
; Строит struct exec_redir_args { cmdline, redir_out, result=-1 } на стеке.
; Возвращает slot >= 0 или -1/-2.
_ax_exec_redir:
    push esi
    push ebx
    ; после двух push: [esp+12]=cmdline, [esp+16]=redir_out
    mov eax, [esp+12]       ; cmdline
    mov ecx, [esp+16]       ; redir_out
    push dword -1           ; struct.result = -1  (offset 8)
    push ecx                ; struct.redir_out    (offset 4)
    push eax                ; struct.cmdline      (offset 0 = esp)
    mov esi, esp
    mov ah, 0x14            ; SYS_EXEC_REDIR
    int 0x80
    mov eax, [esp+8]        ; result (offset 8)
    add esp, 12
    pop ebx
    pop esi
    ret

; int ax_ps(struct ps_entry* e)
; ESI = указатель на struct ps_entry (передаётся напрямую).
; Возвращает e->result (1=найдена, 0=конец).
; Раскладка struct: index(0) pid(4) name[16](8) ticks(24) slot(28) heap_brk(32) result(36)
_ax_ps:
    push esi
    push ebx
    mov esi, [esp+12]       ; ESI -> struct ps_entry
    mov ah, 0x13            ; SYS_PS
    int 0x80
    mov eax, [esi+36]       ; e->result (offset 36)
    pop ebx
    pop esi
    ret

; int ax_pci_get_device(struct pci_device_args* d)
; ESI = указатель на struct pci_device_args (передаётся напрямую).
; Возвращает d->result (1=найдено, 0=конец списка).
; Раскладка struct (все поля по 4 байта, см. syscalls.h):
;   index(0) bus(4) device(8) function(12) vendor_id(16) device_id(20)
;   class_code(24) subclass(28) class_name[32](32) result(64)
_ax_pci_get_device:
    push esi
    push ebx
    mov esi, [esp+12]       ; ESI -> struct pci_device_args
    mov ah, 0x22            ; SYS_PCI_GET_DEVICE
    int 0x80
    mov eax, [esi+64]       ; d->result (offset 64)
    pop ebx
    pop esi
    ret

; int ax_unlink(char* filename)
; Строит struct unlink_args { filename, result=-1 } на стеке.
; Возвращает 1 (удалён) или 0 (не найден / диск заблокирован).
_ax_unlink:
    push esi
    push ebx
    ; после двух push: [esp+12]=filename
    mov eax, [esp+12]
    push dword -1           ; struct.result = -1  (offset 4)
    push eax                ; struct.filename      (offset 0 = esp)
    mov esi, esp
    mov ah, 0x15            ; SYS_UNLINK
    int 0x80
    mov eax, [esp+4]        ; result (offset 4)
    add esp, 8
    pop ebx
    pop esi
    ret

; int ax_mkdir(char* dirname)
; Строит struct mkdir_args { dirname, result=-1 } на стеке.
; Возвращает 1 (создана) или 0 (ошибка).
_ax_mkdir:
    push esi
    push ebx
    ; после двух push: [esp+12]=dirname
    mov eax, [esp+12]
    push dword -1           ; struct.result = -1  (offset 4)
    push eax                ; struct.dirname      (offset 0 = esp)
    mov esi, esp
    mov ah, 0x16            ; SYS_MKDIR
    int 0x80
    mov eax, [esp+4]        ; result (offset 4)
    add esp, 8
    pop ebx
    pop esi
    ret

; void ax_disk_lock(int locked)
; ESI = locked (0 или 1, не указатель) — та же схема, что ax_shell_claim.
_ax_disk_lock:
    push esi
    mov esi, [esp+8]        ; esi = locked (0 или 1)
    mov ah, 0x17            ; SYS_FS_LOCK
    int 0x80
    pop esi
    ret

; int ax_disk_identify(char* model)
; Строит struct disk_identify_args { model, result=0 } на стеке.
; model - буфер не менее 41 байта. Возвращает 1 (успех) или 0 (нет диска).
_ax_disk_identify:
    push esi
    push ebx
    ; после двух push: [esp+12]=model
    mov eax, [esp+12]
    push dword 0            ; struct.result = 0  (offset 4)
    push eax                ; struct.model        (offset 0 = esp)
    mov esi, esp
    mov ah, 0x18            ; SYS_DISK_IDENTIFY
    int 0x80
    mov eax, [esp+4]        ; result (offset 4)
    add esp, 8
    pop ebx
    pop esi
    ret

; int ax_disk_read_sector(unsigned int lba, unsigned char* buf)
; Строит struct disk_sector_args { lba, buf, result=0 } на стеке.
; buf - буфер не менее 512 байт (IDE_SECTOR_SIZE). 1=успех, 0=ошибка.
_ax_disk_read_sector:
    push esi
    push ebx
    ; после двух push: [esp+12]=lba, [esp+16]=buf
    mov eax, [esp+12]
    mov ecx, [esp+16]
    push dword 0            ; struct.result = 0  (offset 8)
    push ecx                ; struct.buf          (offset 4)
    push eax                ; struct.lba          (offset 0 = esp)
    mov esi, esp
    mov ah, 0x19            ; SYS_DISK_READ_SECTOR
    int 0x80
    mov eax, [esp+8]        ; result (offset 8)
    add esp, 12
    pop ebx
    pop esi
    ret

; int ax_disk_write_sector(unsigned int lba, unsigned char* buf)
; Та же раскладка struct, что и у ax_disk_read_sector.
_ax_disk_write_sector:
    push esi
    push ebx
    ; после двух push: [esp+12]=lba, [esp+16]=buf
    mov eax, [esp+12]
    mov ecx, [esp+16]
    push dword 0            ; struct.result = 0  (offset 8)
    push ecx                ; struct.buf          (offset 4)
    push eax                ; struct.lba          (offset 0 = esp)
    mov esi, esp
    mov ah, 0x1A            ; SYS_DISK_WRITE_SECTOR
    int 0x80
    mov eax, [esp+8]        ; result (offset 8)
    add esp, 12
    pop ebx
    pop esi
    ret

; void ax_get_datetime(struct datetime_args* a)
; ESI = указатель на struct datetime_args (передаётся напрямую, как ax_ps).
_ax_get_datetime:
    push esi
    push ebx
    mov esi, [esp+12]      ; ESI -> struct
    mov ah, 0x1B            ; SYS_GET_DATETIME
    int 0x80
    pop ebx
    pop esi
    ret

; void ax_reboot(void) - не возвращается.
_ax_reboot:
    mov ah, 0x1C            ; SYS_REBOOT
    int 0x80
.hang:
    jmp .hang

; void ax_get_mouse(struct mouse_args* a)
; ESI = указатель на struct mouse_args (передаётся напрямую, как ax_ps).
_ax_get_mouse:
    push esi
    push ebx
    mov esi, [esp+12]
    mov ah, 0x1D            ; SYS_GET_MOUSE
    int 0x80
    pop ebx
    pop esi
    ret

; void ax_beep(unsigned int freq, unsigned int duration_ms)
; Строит struct beep_args { freq, duration_ms } на стеке.
_ax_beep:
    push esi
    push ebx
    ; после двух push: [esp+12]=freq, [esp+16]=duration_ms
    mov eax, [esp+12]
    mov ecx, [esp+16]
    push ecx                ; struct.duration_ms (offset 4)
    push eax                ; struct.freq         (offset 0 = esp)
    mov esi, esp
    mov ah, 0x1E            ; SYS_BEEP
    int 0x80
    add esp, 8
    pop ebx
    pop esi
    ret

; void ax_clipboard_set(unsigned char* data, unsigned int size)
; Строит struct clipboard_set_args { data, size } на стеке - та же
; раскладка, что у ax_writefile без поля filename.
_ax_clipboard_set:
    push esi
    push ebx
    ; после двух push: [esp+12]=data, [esp+16]=size
    mov eax, [esp+12]
    mov ecx, [esp+16]
    push ecx                ; struct.size  (offset 4)
    push eax                ; struct.data  (offset 0 = esp)
    mov esi, esp
    mov ah, 0x1F             ; SYS_CLIPBOARD_SET
    int 0x80
    add esp, 8
    pop ebx
    pop esi
    ret

; unsigned int ax_clipboard_get(unsigned char* buf, unsigned int max)
; Строит struct clipboard_get_args { buf, max, out_size=0 } на стеке;
; возвращает out_size в EAX - та же схема, что у ax_readfile.
_ax_clipboard_get:
    push esi
    push ebx
    ; после двух push: [esp+12]=buf, [esp+16]=max
    mov eax, [esp+12]
    mov ecx, [esp+16]
    push dword 0            ; struct.out_size = 0  (offset 8)
    push ecx                ; struct.max_size       (offset 4)
    push eax                ; struct.buffer         (offset 0 = esp)
    mov esi, esp
    mov ah, 0x20             ; SYS_CLIPBOARD_GET
    int 0x80
    mov eax, [esp+8]        ; out_size (offset 8)
    add esp, 12
    pop ebx
    pop esi
    ret

; void ax_set_level(unsigned int level)
; Строит struct set_level_args { level } на стеке - та же раскладка, что
; у ax_set_foreground (один dword-аргумент).
_ax_set_level:
    push esi
    push ebx
    ; после двух push: [esp+12]=level
    mov eax, [esp+12]
    push eax                ; struct.level  <- esp = &struct
    mov esi, esp
    mov ah, 0x21             ; SYS_SET_LEVEL
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

; void ax_seccomp_raw(unsigned int mask_lo, unsigned int mask_hi)
; Строит struct seccomp_args { mask_lo, mask_hi } на стеке.
; Устанавливает/сужает seccomp-маску текущей задачи.
_ax_seccomp_raw:
    push esi
    push ebx
    ; после двух push: [esp+12]=mask_lo, [esp+16]=mask_hi
    mov eax, [esp+12]       ; mask_lo
    mov ecx, [esp+16]       ; mask_hi
    push ecx                ; struct.mask_hi (offset 4)
    push eax                ; struct.mask_lo (offset 0 = esp)
    mov esi, esp
    mov ah, 0x23            ; SYS_SECCOMP
    int 0x80
    add esp, 8
    pop ebx
    pop esi
    ret

; void ax_set_priority(int pid, int priority)
; Строит struct set_priority_args { pid, priority } на стеке.
; priority зажимается в [1,10] на стороне ядра (см. task_set_priority).
_ax_set_priority:
    push esi
    push ebx
    ; после двух push: [esp+12]=pid, [esp+16]=priority
    mov eax, [esp+12]       ; pid
    mov ecx, [esp+16]       ; priority
    push ecx                ; struct.priority (offset 4)
    push eax                ; struct.pid      (offset 0 = esp)
    mov esi, esp
    mov ah, 0x24            ; SYS_SET_PRIORITY
    int 0x80
    add esp, 8
    pop ebx
    pop esi
    ret

; int ax_net_mac(unsigned char* mac)
; Строит struct net_mac_args { mac, result=0 } на стеке (см. _ax_unlink -
; тот же приём для одного указателя-аргумента).
; Возвращает 1 (найден NIC, mac[6] заполнен) или 0 (нет NIC).
_ax_net_mac:
    push esi
    push ebx
    ; после двух push: [esp+12]=mac
    mov eax, [esp+12]
    push dword 0            ; struct.result = 0  (offset 4)
    push eax                ; struct.mac          (offset 0 = esp)
    mov esi, esp
    mov ah, 0x25            ; SYS_NET_MAC
    int 0x80
    mov eax, [esp+4]        ; result (offset 4)
    add esp, 8
    pop ebx
    pop esi
    ret

; int ax_net_send(const void* frame, unsigned int len)
; Строит struct net_send_args { frame, len, result=-1 } на стеке (см.
; _ax_fread/_ax_fwrite - тот же приём для двух скалярных аргументов).
; Возвращает 0 (ок) или -1 (ошибка/нет NIC).
_ax_net_send:
    push esi
    push ebx
    ; после двух push: [esp+12]=frame, [esp+16]=len
    mov eax, [esp+12]       ; frame
    mov ecx, [esp+16]       ; len
    push dword -1           ; struct.result = -1 (offset 8)
    push ecx                ; struct.len          (offset 4)
    push eax                ; struct.frame        (offset 0 = esp)
    mov esi, esp
    mov ah, 0x26            ; SYS_NET_SEND
    int 0x80
    mov eax, [esp+8]        ; result (offset 8)
    add esp, 12
    pop ebx
    pop esi
    ret

; unsigned int ax_net_recv(void* buf, unsigned int max_len)
; Строит struct net_recv_args { buf, max_len, result=0 } на стеке.
; Неблокирующий - возвращает 0 сразу, если кадра ещё нет (не ждёт).
_ax_net_recv:
    push esi
    push ebx
    ; после двух push: [esp+12]=buf, [esp+16]=max_len
    mov eax, [esp+12]       ; buf
    mov ecx, [esp+16]       ; max_len
    push dword 0            ; struct.result = 0  (offset 8)
    push ecx                ; struct.max_len      (offset 4)
    push eax                ; struct.buf          (offset 0 = esp)
    mov esi, esp
    mov ah, 0x27            ; SYS_NET_RECV
    int 0x80
    mov eax, [esp+8]        ; result (offset 8)
    add esp, 12
    pop ebx
    pop esi
    ret
