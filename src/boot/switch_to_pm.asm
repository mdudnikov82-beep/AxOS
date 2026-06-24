; RELOC_DELTA - поправка ниже на самоперемещение загрузчика (см.
; boot.asm); без неё [gdt_descriptor] и far jump указали бы на старый
; (до-релокационный) адрес, где уже не код, а данные с диска. Дефолт 0
; для тех, кто не релоцируется (boot_gfx.asm) - см. gdt.asm.
%ifndef RELOC_DELTA
%define RELOC_DELTA 0
%endif

[bits 16]
switch_to_pm:
    cli
    lgdt [gdt_descriptor + RELOC_DELTA]
    mov eax, cr0
    or eax, 0x1
    mov cr0, eax
    jmp CODE_SEG:(init_pm + RELOC_DELTA)

[bits 32]
init_pm:
    mov ax, DATA_SEG
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ebp, 0x90000
    mov esp, ebp
    call BEGIN_PM