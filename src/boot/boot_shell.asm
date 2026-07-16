; =================================================================
;  Загрузчик графической ОБОЛОЧКИ (gfx_shell.c) - копия boot_gfx.asm,
;  но вместо BIOS mode 0x13 (320x200, 256 цветов, палитра) использует
;  VBE (VESA BIOS Extensions) linear framebuffer: 800x600, 32 бита на
;  пиксель, полный truecolor. boot_gfx.asm/os-image-gfx.bin (gfx_demo)
;  НЕ трогаем - он делит kernel_gfx_entry.asm/kernel_gfx.ld с этой
;  сборкой, но у него свой bootloader и он остаётся на mode 13h.
;
;  VBE, как и обычный BIOS video mode, можно менять только в реальном
;  режиме - поэтому это отдельный загрузчик, не команда ядра.
;
;  Ищем режим ПО РЕАЛЬНОМУ СПИСКУ, который вернул controller info
;  (функция 4F00h), а не гадаем номер режима: конкретные номера у
;  разных BIOS/vgabios отличаются, а список режимов - нет.
;
;  Самоперемещение на 0x0700 (см. boot.asm за тем же приёмом и его
;  причиной: растущий буфер чтения ядра иначе переписывает ещё
;  выполняющийся загрузчик в 0x7c00-0x7e00 - тихий hang без кода
;  ошибки). ВАЖНО: адрес релокации здесь НЕ 0x0600, как в boot.asm -
;  этот загрузчик сам использует 0x0600 как FB_INFO_ADDR (см.
;  vbe_set_800x600x32 ниже), куда пишет физ.адрес/разрешение LFB уже
;  ПОСЛЕ переезда на релоцированную копию. Если бы релоцировались на
;  сам 0x0600, этот же вызов затёр бы первые байты ещё выполняющейся
;  релоцированной копии загрузчика самим собой (self-modifying code
;  гонка) - 0x0700 гарантированно не пересекается ни с FB_INFO_ADDR
;  (0x0600, 11 байт полезной нагрузки), ни с чем-либо ещё в реальном
;  режиме ниже 0x7c00.
%define RELOC_DELTA (0x0700 - 0x7c00)

[org 0x7c00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00          ; временный стек ниже своего же кода - только на время копирования

    mov si, 0x7c00
    mov di, 0x0700
    mov cx, 512
    cld
    rep movsb

    jmp relocated_start + RELOC_DELTA

relocated_start:
    ; Выше конца буфера чтения ядра (0x1000 + 89*512 = 0xC200) - см.
    ; boot.asm за тем же выбором и тем же обоснованием.
    mov sp, 0xF000

    ; --- VBE: найти 800x600x32 ПЕРЕД загрузкой ядра с диска -------
    ; ВАЖНО: делаем это ДО чтения ядра в 0x1000, иначе временные буферы
    ; VBE (0x7000/0x7E00) окажутся внутри уже загруженного образа ядра
    ; и всё испортят. К этому моменту мы уже выполняемся из релоцированной
    ; копии (0x0700+), так что запись VBE-результата в FB_INFO_ADDR
    ; (0x0600) ничего не затирает - см. комментарий про RELOC_DELTA выше.
    call vbe_set_800x600x32

    ; --- Загружаем gfx-ядро с диска в память по адресу 0x1000 -----
    ; Тот же геометрический расклад, что и в boot.asm: 89 секторов
    ; (45568 байт) вместо прежних 53 (27136) - у файлового менеджера
    ; (fat12_shell.o + IDE-чтение + UI) заметно выросла кодовая часть,
    ; и именно этот более широкий бюджет чтения и требовал релокации
    ; выше (иначе рост секторов заново задел бы тот же самый баг).
    mov bx, 0x1000
    mov ah, 0x02
    mov al, 17
    mov ch, 0
    mov dh, 0
    mov cl, 2
    int 0x13
    jc disk_error
    cmp al, 17
    jne disk_error

    mov bx, 0x1000 + 17 * 512
    mov ah, 0x02
    mov al, 18
    mov ch, 0
    mov dh, 1
    mov cl, 1
    int 0x13
    jc disk_error
    cmp al, 18
    jne disk_error

    mov bx, 0x1000 + 35 * 512
    mov ah, 0x02
    mov al, 18
    mov ch, 1
    mov dh, 0
    mov cl, 1
    int 0x13
    jc disk_error
    cmp al, 18
    jne disk_error

    mov bx, 0x1000 + 53 * 512
    mov ah, 0x02
    mov al, 18
    mov ch, 1
    mov dh, 1
    mov cl, 1
    int 0x13
    jc disk_error
    cmp al, 18
    jne disk_error

    mov bx, 0x1000 + 71 * 512
    mov ah, 0x02
    mov al, 18
    mov ch, 2
    mov dh, 0
    mov cl, 1
    int 0x13
    jc disk_error
    cmp al, 18
    jne disk_error

    jmp disk_done

disk_error:
vbe_error:
    ; Нет ни текстового режима, ни teletype здесь - молча стоим.
    jmp $

disk_done:
    call switch_to_pm
    jmp $

; =================================================================
;  VBE: найти режим 800x600x32bpp по СПИСКУ режимов контроллера,
;  включить его с линейным фреймбуфером, и сохранить нужные поля
;  ModeInfoBlock (физ. адрес LFB, pitch, разрешение, bpp) по адресу
;  0x0600 - фиксированный адрес НИЖЕ образа ядра (0x1000+) и НИЖЕ
;  релоцированной копии загрузчика (0x0700+), который ядро
;  (gfx_shell.c) читает уже в защищённом режиме как обычную
;  физическую память.
; =================================================================
VBE_INFO_BUF   equ 0x7000   ; VbeInfoBlock (512 байт) - временный
VBE_MODE_BUF   equ 0x7E00   ; ModeInfoBlock (512 байт) - временный
FB_INFO_ADDR   equ 0x0600   ; куда копируем итоговые поля для ядра

vbe_set_800x600x32:
    ; --- Get Controller Info (4F00h): нужен префикс "VBE2" для VBE 2.0+
    ; (иначе некоторые BIOS не заполнят 32-битный PhysBasePtr) ---
    mov di, VBE_INFO_BUF
    mov word [di], 'VB'
    mov word [di+2], 'E2'
    mov ax, 0x4F00
    int 0x10
    cmp ax, 0x004F
    jne vbe_error

    ; VideoModePtr - 32-битный far-указатель: offset (word) @ +0x0E,
    ; segment (word) @ +0x10.
    mov si, [VBE_INFO_BUF + 0x0E]
    mov ax, [VBE_INFO_BUF + 0x10]
    mov fs, ax                      ; fs:si -> список 16-битных номеров режимов, 0xFFFF = конец

.next_mode:
    mov cx, [fs:si]
    add si, 2
    cmp cx, 0xFFFF
    je vbe_error                    ; список кончился, 800x600x32 не найден

    ; Get Mode Info (4F01h) для этого номера
    push si
    push cx
    mov di, VBE_MODE_BUF
    mov ax, 0x4F01
    int 0x10
    pop cx
    pop si
    cmp ax, 0x004F
    jne .next_mode                  ; этот номер не смог отдать инфу - пропускаем

    ; Проверяем XResolution (+0x12), YResolution (+0x14), BitsPerPixel (+0x19)
    mov ax, [VBE_MODE_BUF + 0x12]
    cmp ax, 800
    jne .next_mode
    mov ax, [VBE_MODE_BUF + 0x14]
    cmp ax, 600
    jne .next_mode
    mov al, [VBE_MODE_BUF + 0x19]
    cmp al, 32
    jne .next_mode

    ; Нашли! cx = номер режима. Включаем с битом LFB (14).
    mov bx, cx
    or bx, 0x4000
    mov ax, 0x4F02
    int 0x10
    cmp ax, 0x004F
    jne vbe_error

    ; ModeInfoBlock для НАЙДЕННОГО режима уже лежит в VBE_MODE_BUF -
    ; копируем нужные поля в FB_INFO_ADDR для ядра:
    ;   +0x00 (dword) PhysBasePtr      <- ModeInfoBlock +0x28
    ;   +0x04 (word)  XResolution      <- ModeInfoBlock +0x12
    ;   +0x06 (word)  YResolution      <- ModeInfoBlock +0x14
    ;   +0x08 (word)  BytesPerScanLine <- ModeInfoBlock +0x10
    ;   +0x0A (byte)  BitsPerPixel     <- ModeInfoBlock +0x19
    mov eax, [VBE_MODE_BUF + 0x28]
    mov [FB_INFO_ADDR + 0x00], eax
    mov ax, [VBE_MODE_BUF + 0x12]
    mov [FB_INFO_ADDR + 0x04], ax
    mov ax, [VBE_MODE_BUF + 0x14]
    mov [FB_INFO_ADDR + 0x06], ax
    mov ax, [VBE_MODE_BUF + 0x10]
    mov [FB_INFO_ADDR + 0x08], ax
    mov al, [VBE_MODE_BUF + 0x19]
    mov [FB_INFO_ADDR + 0x0A], al
    ret

%include "src/kernel/gdt.asm"
%include "src/boot/switch_to_pm.asm"

[bits 32]
BEGIN_PM:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov esp, 0x90000
    mov ebp, esp

    ; jmp 0x1000 (bare immediate) would assemble as a RELATIVE near
    ; jump (E9 rel32) - NASM computes that displacement assuming this
    ; code still executes from its original, non-relocated 0x7c00+
    ; address. Since this file self-relocates to 0x0700 (see the
    ; RELOC_DELTA comment up top), that relative encoding would land
    ; at completely the wrong (garbage) address once actually run from
    ; the relocated copy - confirmed live as a triple fault at
    ; EIP=0xffff9b1d. Fix: absolute indirect jump via a register,
    ; exactly like boot.asm's own `mov rax,0x1000 / jmp rax` (there in
    ; 64-bit long mode, here in 32-bit protected mode) - a register
    ; jump target is a literal value, immune to relative-encoding bugs.
    mov eax, 0x1000
    jmp eax
    jmp $

times 510 - ($ - $$) db 0
dw 0xAA55
