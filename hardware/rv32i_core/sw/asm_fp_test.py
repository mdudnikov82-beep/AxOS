"""Full-core integration test for the minimal RV32F extension
(FLW/FSW/FADD.S/FSUB.S/FMUL.S). Since the single-cycle core has no
pre-loaded data section, the program itself first writes two float
bit-patterns into memory using plain LUI+SW (both 2.5 and 1.5 happen
to have all-zero low 12 bits, so a single LUI produces the exact
32-bit pattern with no ADDI needed), then exercises all 3 new
arithmetic ops in a short dependency chain, stores the final result,
and reads its raw bits back with an ordinary integer LW - memory
doesn't distinguish "float bits" from "integer bits", so this verifies
real FP computation through the existing ECALL/tohost convention
without needing FMV.X.W/FMV.W.X (out of scope for this minimal pass).

    lui   x1, 0x40200     x1 = 0x40200000 (2.5)
    sw    x1, 0(x0)       mem[0] = 2.5's bits
    lui   x2, 0x3fc00     x2 = 0x3fc00000 (1.5)
    sw    x2, 4(x0)       mem[4] = 1.5's bits
    flw   f1, 0(x0)       f1 = 2.5
    flw   f2, 4(x0)       f2 = 1.5
    fadd.s f3, f1, f2     f3 = 4.0
    fsub.s f4, f1, f2     f4 = 1.0
    fmul.s f5, f3, f4     f5 = 4.0 * 1.0 = 4.0
    fsw   f5, 8(x0)       mem[8] = f5's raw bits (expect 0x40800000)
    lw    x10, 8(x0)      x10 = those same raw bits, read as an integer
    ecall                 tohost = 0x40800000 (1082130432) if correct
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, sw, lw, flw, fsw = _m.lui, _m.sw, _m.lw, _m.flw, _m.fsw
fadd_s, fsub_s, fmul_s, ecall = _m.fadd_s, _m.fsub_s, _m.fmul_s, _m.ecall

program = [
    lui(1, 0x40200),
    sw(1, 0, 0),
    lui(2, 0x3fc00),
    sw(2, 4, 0),
    flw(1, 0, 0),
    flw(2, 4, 0),
    fadd_s(3, 1, 2),
    fsub_s(4, 1, 2),
    fmul_s(5, 3, 4),
    fsw(5, 8, 0),
    lw(10, 8, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "fp_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
