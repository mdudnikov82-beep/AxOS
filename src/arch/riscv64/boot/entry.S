# AxOS/RV64 — точка входа + обработчик trap'ов
#
# Ядро (S-mode): sscratch == 0
# Пользователь (U-mode): sscratch == _stack_top (верхушка стека ядра)
#
# Переключение стека при трапе из U-mode:
#   csrrw sp, sscratch, sp  → sp = _stack_top, sscratch = user_sp
# При трапе из S-mode:
#   csrrw sp, sscratch, sp  → sp = 0 (sscratch был 0), sscratch = kernel_sp
#   beqz → восстанавливаем sp обратно

.section .text.entry
.globl _start
_start:
    csrw    sie, zero

    la      t0, trap_entry
    csrw    stvec, t0

    # Обнуляем BSS (включает .sbss — иначе sbss попадает за стеком и затирает данные)
    la      t0, _bss_start
    la      t1, _bss_end
.Lbss_loop:
    bgeu    t0, t1, .Lbss_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .Lbss_loop
.Lbss_done:

    la      sp, _stack_top
    call    kernel_main

.Lhalt:
    wfi
    j       .Lhalt

# ---------------------------------------------------------------------------
# trap_entry — обработчик всех trap'ов (исключения + прерывания + ecall)
# ---------------------------------------------------------------------------
.section .text
.globl trap_entry
.align 2
trap_entry:
    # sscratch == 0    → трап из S-mode (ядро)
    # sscratch != 0    → трап из U-mode (sscratch = _stack_top)
    csrrw   sp, sscratch, sp         # sp ↔ sscratch
    beqz    sp, .Ls_trap             # sp==0 → S-mode

# ---- Трап из U-mode ----
    # sp = _stack_top (стек ядра), sscratch = user_sp
    addi    sp, sp, -256

    # Сохраняем user_sp через ra как temp:
    sd      x1,   8(sp)             # сохраняем ra
    csrr    x1,   sscratch          # x1 = user_sp
    csrw    sscratch, zero          # sscratch = 0 (теперь в S-mode)
    sd      x1,  16(sp)             # сохраняем user_sp в слот x2
    ld      x1,   8(sp)             # восстанавливаем ra

    # x1 и x2 (user_sp) сохранены — прыгаем в общую секцию сохранения x3..x31
    j       .Lsave_x3_x31

.Ls_trap:
    # ---- Трап из S-mode ----
    # sp = 0; sscratch = kernel_sp → возвращаем назад
    csrrw   sp, sscratch, sp        # sp = kernel_sp, sscratch = 0
    addi    sp, sp, -256
    sd      x1,   8(sp)             # ra
    sd      x2,  16(sp)             # kernel sp (уменьшен на 256, но это нормально)

.Lsave_x3_x31:
    sd      x3,  24(sp)
    sd      x4,  32(sp)
    sd      x5,  40(sp)
    sd      x6,  48(sp)
    sd      x7,  56(sp)
    sd      x8,  64(sp)
    sd      x9,  72(sp)
    sd      x10, 80(sp)
    sd      x11, 88(sp)
    sd      x12, 96(sp)
    sd      x13,104(sp)
    sd      x14,112(sp)
    sd      x15,120(sp)
    sd      x16,128(sp)
    sd      x17,136(sp)
    sd      x18,144(sp)
    sd      x19,152(sp)
    sd      x20,160(sp)
    sd      x21,168(sp)
    sd      x22,176(sp)
    sd      x23,184(sp)
    sd      x24,192(sp)
    sd      x25,200(sp)
    sd      x26,208(sp)
    sd      x27,216(sp)
    sd      x28,224(sp)
    sd      x29,232(sp)
    sd      x30,240(sp)
    sd      x31,248(sp)

    csrr    a0, scause
    csrr    a1, sepc
    csrr    a2, stval
    mv      a3, sp
    call    trap_handler

    # ---- Возврат: определяем режим по sstatus.SPP (бит 8) ----
    # SPP=1 → S-mode, SPP=0 → U-mode
    csrr    t0, sstatus
    andi    t0, t0, (1 << 8)
    bnez    t0, .Lret_s

.Lret_u:
    # Возврат в U-mode:
    # Устанавливаем sscratch = _stack_top для следующего трапа из U-mode
    addi    t0, sp, 256              # t0 = frame_base + 256 = _stack_top
    csrw    sscratch, t0

    # Восстанавливаем все регистры (x5/t0 после csrw — sscratch уже записан)
    ld      x1,   8(sp)
    # x2 (sp) восстановим последним
    ld      x3,  24(sp)
    ld      x4,  32(sp)
    ld      x5,  40(sp)             # t0: перезаписывает x5 (sscratch уже сохранён)
    ld      x6,  48(sp)
    ld      x7,  56(sp)
    ld      x8,  64(sp)
    ld      x9,  72(sp)
    ld      x10, 80(sp)             # a0: возвращаемое значение syscall
    ld      x11, 88(sp)
    ld      x12, 96(sp)
    ld      x13,104(sp)
    ld      x14,112(sp)
    ld      x15,120(sp)
    ld      x16,128(sp)
    ld      x17,136(sp)
    ld      x18,144(sp)
    ld      x19,152(sp)
    ld      x20,160(sp)
    ld      x21,168(sp)
    ld      x22,176(sp)
    ld      x23,184(sp)
    ld      x24,192(sp)
    ld      x25,200(sp)
    ld      x26,208(sp)
    ld      x27,216(sp)
    ld      x28,224(sp)
    ld      x29,232(sp)
    ld      x30,240(sp)
    ld      x31,248(sp)
    ld      sp,  16(sp)             # восстанавливаем user sp — ПОСЛЕДНИЙ шаг
    sret

.Lret_s:
    # Возврат в S-mode: просто восстанавливаем регистры и сдвигаем стек
    ld      x1,   8(sp)
    ld      x3,  24(sp)
    ld      x4,  32(sp)
    ld      x5,  40(sp)
    ld      x6,  48(sp)
    ld      x7,  56(sp)
    ld      x8,  64(sp)
    ld      x9,  72(sp)
    ld      x10, 80(sp)
    ld      x11, 88(sp)
    ld      x12, 96(sp)
    ld      x13,104(sp)
    ld      x14,112(sp)
    ld      x15,120(sp)
    ld      x16,128(sp)
    ld      x17,136(sp)
    ld      x18,144(sp)
    ld      x19,152(sp)
    ld      x20,160(sp)
    ld      x21,168(sp)
    ld      x22,176(sp)
    ld      x23,184(sp)
    ld      x24,192(sp)
    ld      x25,200(sp)
    ld      x26,208(sp)
    ld      x27,216(sp)
    ld      x28,224(sp)
    ld      x29,232(sp)
    ld      x30,240(sp)
    ld      x31,248(sp)
    addi    sp, sp, 256
    sret
