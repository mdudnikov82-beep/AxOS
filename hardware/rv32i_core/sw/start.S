/* Minimal startup: sets up the stack, calls main(), then halts the
 * core via the ECALL/tohost convention (see cpu_core.v) - main()'s
 * int return value is already sitting in a0/x10 per the standard
 * RISC-V calling convention the instant it returns, so this needs no
 * extra work to expose it. sp = 0x2000 is the top of the 8KB data
 * memory tb_cpu.v's cpu_core instantiation is sized for. */
.section .text
.global _start
_start:
    lui  sp, 0x2
    jal  ra, main
    ecall
