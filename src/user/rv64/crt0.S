# AxOS/RV64 — пользовательский startup (crt0)
# sp уже настроен ядром перед прыжком в U-mode.

.section .text.start
.globl _start
_start:
    call    main

    # main вернулся — вызываем sys_exit(0)
    li      a7, 3       # SYS_EXIT = 3
    li      a0, 0       # exit code 0
    ecall

.Lhang:
    j       .Lhang      # на случай если ядро не обработало exit
