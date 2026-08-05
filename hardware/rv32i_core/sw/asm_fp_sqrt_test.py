"""Full-core integration test for FSQRT.S - proves the multi-cycle
start/busy/done handshake actually holds the single-cycle CPU correctly
for the ~26 cycles a real square root takes, not just that fp_sqrt.v is
arithmetically correct in isolation (already proven by tb_fp_sqrt.v).

    lui    x1, 0x40000    x1 = 0x40000000 (2.0)
    sw     x1, 0(x0)      mem[0] = 2.0's bits
    flw    f1, 0(x0)      f1 = 2.0
    fsqrt.s f2, f1        f2 = sqrt(2.0) (the CPU's PC stays frozen for
                                          ~26 cycles here while fp_sqrt.v
                                          runs)
    fsw    f2, 4(x0)      mem[4] = f2's raw bits (expect 0x3fb504f3)
    lw     x10, 4(x0)     x10 = those same raw bits, read as an integer
    ecall                 tohost = 0x3fb504f3 (1069973235) if correct
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, sw, lw, flw, fsw, fsqrt_s, ecall = (
    _m.lui, _m.sw, _m.lw, _m.flw, _m.fsw, _m.fsqrt_s, _m.ecall
)

program = [
    lui(1, 0x40000),
    sw(1, 0, 0),
    flw(1, 0, 0),
    fsqrt_s(2, 1),
    fsw(2, 4, 0),
    lw(10, 4, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "fp_sqrt_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
