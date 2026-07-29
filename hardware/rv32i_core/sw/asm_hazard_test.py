"""Hand-written stress program exercising every pipeline hazard class
at once - the test that actually proves cpu_core_pipelined.v's
forwarding/stalling/flushing logic works, rather than just proving the
pipeline happens to produce correct results on programs that never
needed any of it (test1.hex/test_basic.hex have data dependencies, but
not necessarily ones close enough together to force forwarding, and no
load-use pattern at all).

    addi x1, x0, 5      x1=5
    addi x2, x1, 1      x2=6   <- EX/MEM forward (x1, distance 1)
    addi x3, x2, 1      x3=7   <- EX/MEM forward (x2, distance 1)
    lw   x4, 0(x0)      x4=0   (data mem starts zeroed)
    addi x5, x4, 1      x5=1   <- LOAD-USE hazard, must stall one cycle
    beq  x1, x1, +8     always taken -> flush the next instruction
    addi x6, x0, 999    SKIPPED (flushed - must never affect x6's user)
    addi x7, x0, 111    branch target
    add  x8, x3, x7     x8=118 <- x3 is a distance-4 dependency (regfile/
                                   write-through bypass by then), x7 is
                                   distance-1 (EX/MEM forward)
    add  x10, x8, x5    x10=119 <- combines values produced at very
                                   different pipeline distances
    ecall               tohost = 119
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
addi, add, lw, beq, ecall = _m.addi, _m.add, _m.lw, _m.beq, _m.ecall

program = [
    addi(1, 0, 5),
    addi(2, 1, 1),
    addi(3, 2, 1),
    lw(4, 0, 0),
    addi(5, 4, 1),
    beq(1, 1, 8),
    addi(6, 0, 999),   # skipped
    addi(7, 0, 111),   # branch target
    add(8, 3, 7),
    add(10, 8, 5),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "hazard_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
