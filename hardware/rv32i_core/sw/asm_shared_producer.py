"""E-core (single-cycle) half of the cross-core communication test.
Writes a payload value, then a ready flag, into the shared memory
region at SHARED_MEM_BASE=0x2000 (see cpu_core.v/shared_bus.v) - the
P-core (asm_shared_consumer.py) polls for that flag and reads the
payload back. Reports its own payload (77) as tohost - an independent
sanity check that THIS core did its own part correctly, separate from
whether the P-core actually received it.

    lui  x1, 0x2        x1 = 0x2000 (shared region base)
    addi x3, x0, 77     x3 = 77 (payload)
    sw   x3, 4(x1)      mem[0x2004] = 77
    addi x4, x0, 1
    sw   x4, 0(x1)      mem[0x2000] = 1  (ready flag - published LAST)
    addi x10, x3, 0     tohost = 77
    ecall
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, addi, sw, ecall = _m.lui, _m.addi, _m.sw, _m.ecall

program = [
    lui(1, 0x2),
    addi(3, 0, 77),
    sw(3, 4, 1),
    addi(4, 0, 1),
    sw(4, 0, 1),
    addi(10, 3, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "shared_producer.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
