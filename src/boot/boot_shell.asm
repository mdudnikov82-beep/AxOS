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
; =================================================================
[org 0x7c00]

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000

    ; --- VBE: найти 800x600x32 ПЕРЕД загрузкой ядра с диска -------
    ; ВАЖНО: делаем это ДО чтения ядра в 0x1000, иначе временные буферы
    ; VBE (0x7000/0x7E00) окажутся внутри уже загруженного образа ядра
    ; (он занимает 0x1000..~0x7A00) и всё испортят.
    call vbe_set_800x600x32

    ; --- Загружаем gfx-ядро с диска в память по адресу 0x1000 (как в boot_gfx.asm) ---
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
;  0x0600 - фиксированный адрес НИЖЕ образа ядра (0x1000+), который
;  ядро (gfx_shell.c) читает уже в защищённом режиме как обычную
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

    jmp 0x1000
    jmp $

times 510 - ($ - $$) db 0
dw 0xAA55
