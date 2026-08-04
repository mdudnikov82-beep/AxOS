"""Adversarial race test for FDIV.S on the pipelined P-core: proves the
fpu_div_result_ready_r buffer (see cpu_core_pipelined.v) actually rescues
a completed division that can't be captured into EX/MEM the instant it
finishes, rather than silently discarding it and restarting from scratch
(a real bug a design review caught before this was ever built - see
project_rv32i_fdiv.md's pipelined-core follow-up notes).

    lui   x3, 0x2          x3 = 0x2000 (SHARED_MEM_BASE)
    lui   x1, 0x40e00      x1 = 0x40e00000 (7.0)
    sw    x1, 0(x0)        mem[0] = 7.0's bits (PRIVATE)
    lui   x2, 0x40000      x2 = 0x40000000 (2.0)
    sw    x2, 4(x0)        mem[4] = 2.0's bits (PRIVATE)
    flw   f1, 0(x0)        f1 = 7.0
    flw   f2, 4(x0)        f2 = 2.0
    sw    x1, 0(x3)        SHARED store - the testbench denies bus_grant
                           for a long window starting near this instruction,
                           forcing it to sit stuck in EX/MEM (mem_stall)
                           for MUCH longer than FDIV.S right behind it
                           takes to finish computing.
    fdiv.s f3, f1, f2      f3 = 7.0/2.0 = 3.5 - by design, this finishes
                           (fp_div reaches its DONE state) WHILE the
                           older shared store above is still stuck in
                           EX/MEM, so EX/MEM can't accept the result the
                           instant it's ready. Without the ready-buffer
                           fix, fp_div would return to IDLE next cycle
                           and (id_ex still frozen on this FDIV) restart
                           the whole ~50-cycle division from scratch -
                           possibly forever, if bus_grant stayed denied
                           long enough (a real livelock).
    fsw   f3, 8(x0)        mem[8] = f3's raw bits (expect 0x40600000)
    lw    x10, 8(x0)       x10 = those same raw bits, read as an integer
    ecall                  tohost = 0x40600000 (1080033280) if the
                           buffered result survived the race correctly
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, sw, lw, flw, fsw, fdiv_s, ecall = (
    _m.lui, _m.sw, _m.lw, _m.flw, _m.fsw, _m.fdiv_s, _m.ecall
)

program = [
    lui(3, 0x2),
    lui(1, 0x40e00),
    sw(1, 0, 0),
    lui(2, 0x40000),
    sw(2, 4, 0),
    flw(1, 0, 0),
    flw(2, 4, 0),
    sw(1, 0, 3),
    fdiv_s(3, 1, 2),
    fsw(3, 8, 0),
    lw(10, 8, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "fp_div_pipe_race_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
