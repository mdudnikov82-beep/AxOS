"""RV32F hazard-stress program for the PIPELINED core - unlike
sw/asm_fp_test.py (which only proves the E-core's FPU works, and is
reused here as a cross-check that both cores agree), this specifically
exercises every FP pipeline hazard class the single-cycle port never
had to handle at all:

    lui   x1, 0x40200     x1 = 0x40200000 (2.5)
    sw    x1, 0(x0)
    lui   x2, 0x3fc00     x2 = 0x3fc00000 (1.5)
    sw    x2, 4(x0)
    flw   f1, 0(x0)       f1 = 2.5
    flw   f2, 4(x0)       f2 = 1.5
    fadd.s f3, f1, f2     f3 = 4.0   <- f2 used IMMEDIATELY after its
                                         own FLW: FP load-use hazard,
                                         must stall (the exact case
                                         hazard_unit's f0 fix protects,
                                         here with a non-zero register)
    fadd.s f4, f3, f3     f4 = 8.0   <- f3 used the cycle right after
                                         it's computed: EX/MEM FP
                                         forward (distance-1)
    fmul.s f5, f4, f2     f5 = 12.0  <- f4 is distance-1 (EX/MEM
                                         forward); f2 is distance-3+
                                         relative to when it was
                                         loaded (regfile/MEM-WB path)
    fsw   f5, 8(x0)       mem[8] = f5's bits <- f5 stored the cycle
                                         right after being computed:
                                         FP STORE-DATA forwarding
                                         (fp_fwd_rs2), not yet retired
                                         to fp_regfile
    lw    x10, 8(x0)      x10 = those raw bits
    ecall                 tohost = 0x41400000 (1094713344) if correct
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, sw, lw, flw, fsw = _m.lui, _m.sw, _m.lw, _m.flw, _m.fsw
fadd_s, fmul_s, ecall = _m.fadd_s, _m.fmul_s, _m.ecall

program = [
    lui(1, 0x40200),
    sw(1, 0, 0),
    lui(2, 0x3fc00),
    sw(2, 4, 0),
    flw(1, 0, 0),
    flw(2, 4, 0),
    fadd_s(3, 1, 2),
    fadd_s(4, 3, 3),
    fmul_s(5, 4, 2),
    fsw(5, 8, 0),
    lw(10, 8, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "fp_pipe_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
