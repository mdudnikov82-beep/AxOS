"""Full-core integration test for FDIV.S - proves the multi-cycle
start/busy/done handshake actually holds the single-cycle CPU correctly
for the ~50 cycles a real division takes, not just that fp_div.v is
arithmetically correct in isolation (already proven by tb_fp_div.v).

    lui   x1, 0x40e00     x1 = 0x40e00000 (7.0)
    sw    x1, 0(x0)       mem[0] = 7.0's bits
    lui   x2, 0x40000     x2 = 0x40000000 (2.0)
    sw    x2, 4(x0)       mem[4] = 2.0's bits
    flw   f1, 0(x0)       f1 = 7.0
    flw   f2, 4(x0)       f2 = 2.0
    fdiv.s f3, f1, f2     f3 = 7.0 / 2.0 = 3.5 (the CPU's PC stays
                                                frozen for ~50 cycles
                                                here while fp_div.v runs)
    fsw   f3, 8(x0)       mem[8] = f3's raw bits (expect 0x40600000)
    lw    x10, 8(x0)      x10 = those same raw bits, read as an integer
    ecall                 tohost = 0x40600000 (1080033280) if correct
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, sw, lw, flw, fsw, fdiv_s, ecall = (
    _m.lui, _m.sw, _m.lw, _m.flw, _m.fsw, _m.fdiv_s, _m.ecall
)

program = [
    lui(1, 0x40e00),
    sw(1, 0, 0),
    lui(2, 0x40000),
    sw(2, 4, 0),
    flw(1, 0, 0),
    flw(2, 4, 0),
    fdiv_s(3, 1, 2),
    fsw(3, 8, 0),
    lw(10, 8, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "fp_div_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
