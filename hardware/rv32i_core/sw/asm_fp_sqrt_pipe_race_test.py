"""Adversarial race test for FSQRT.S on the pipelined P-core: proves the
fpu_sqrt_result_ready_r buffer (see cpu_core_pipelined.v) actually
rescues a completed square root that can't be captured into EX/MEM the
instant it finishes, rather than silently discarding it and restarting
from scratch - the exact same bug CLASS this project already found and
fixed once for FDIV.S (see sw/asm_fp_div_pipe_race_test.py), now
independently verified for FSQRT.S's own, separate instance of the same
ready-buffer pattern (built in from day one per the design review, not
found live).

    lui   x3, 0x2          x3 = 0x2000 (SHARED_MEM_BASE)
    lui   x1, 0x40000      x1 = 0x40000000 (2.0)
    sw    x1, 0(x0)        mem[0] = 2.0's bits (PRIVATE)
    flw   f1, 0(x0)        f1 = 2.0
    sw    x1, 0(x3)        SHARED store - the testbench denies bus_grant
                           for a long window starting near this instruction,
                           forcing it to sit stuck in EX/MEM (mem_stall)
                           for MUCH longer than FSQRT.S right behind it
                           takes to finish computing.
    fsqrt.s f2, f1         f2 = sqrt(2.0) - by design, this finishes
                           (fp_sqrt reaches its DONE state) WHILE the
                           older shared store above is still stuck in
                           EX/MEM, so EX/MEM can't accept the result the
                           instant it's ready. Without the ready-buffer,
                           fp_sqrt would return to IDLE next cycle and
                           (id_ex still frozen on this FSQRT.S) restart
                           the whole ~25-cycle square root from scratch -
                           possibly forever, if bus_grant stayed denied
                           long enough (a real livelock).
    fsw   f2, 4(x0)        mem[4] = f2's raw bits (expect 0x3fb504f3)
    lw    x10, 4(x0)       x10 = those same raw bits, read as an integer
    ecall                  tohost = 0x3fb504f3 (1068827891) if the
                           buffered result survived the race correctly
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, sw, lw, flw, fsw, fsqrt_s, ecall = (
    _m.lui, _m.sw, _m.lw, _m.flw, _m.fsw, _m.fsqrt_s, _m.ecall
)

program = [
    lui(3, 0x2),
    lui(1, 0x40000),
    sw(1, 0, 0),
    flw(1, 0, 0),
    sw(1, 0, 3),
    fsqrt_s(2, 1),
    fsw(2, 4, 0),
    lw(10, 4, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "fp_sqrt_pipe_race_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
