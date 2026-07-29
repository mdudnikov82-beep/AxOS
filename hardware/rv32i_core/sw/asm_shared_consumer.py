"""P-core (pipelined) half of the cross-core communication test. Polls
the shared ready-flag at 0x2000 (see cpu_core_pipelined.v/shared_bus.v)
in a tight lw/beq loop - genuinely exercising the bus arbiter and
mem_stall logic on every poll, not just the address decode - until the
E-core (asm_shared_producer.py) sets it, then reads the payload at
0x2004 and combines it with a local constant. The result (127) can
only be correct if the cross-core read actually observed the OTHER
core's write, not a coincidence of two cores running similar code.

    lui  x1, 0x2        x1 = 0x2000 (shared region base)
poll:
    lw   x2, 0(x1)      x2 = mem[0x2000] (ready flag)
    beq  x2, x0, poll   loop back while still zero
    lw   x3, 4(x1)      x3 = mem[0x2004] (payload, expect 77)
    addi x4, x3, 50     x4 = payload + 50 (expect 127)
    addi x10, x4, 0     tohost = 127
    ecall
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, lw, beq, addi, ecall = _m.lui, _m.lw, _m.beq, _m.addi, _m.ecall

program = [
    lui(1, 0x2),
    lw(2, 0, 1),
    beq(2, 0, -4),
    lw(3, 4, 1),
    addi(4, 3, 50),
    addi(10, 4, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "shared_consumer.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
