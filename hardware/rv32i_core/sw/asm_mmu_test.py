"""Real virtual-memory integration test - proves the MMU actually
translates, not just that it compiles. Loads from VIRTUAL address 0,
which the testbench's page table maps to a DIFFERENT physical page
holding a distinctive sentinel value; if translation is silently
bypassed (MMU disabled, or identity-mapping by accident), the read
would instead land on physical address 0, which the testbench
deliberately fills with a DIFFERENT sentinel - so a passing test proves
a real address swap happened, not just "some value came back."

    lw   x10, 0(x0)     x10 = mem[translate(0)]
    ecall               tohost = x10
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lw, ecall = _m.lw, _m.ecall

program = [
    lw(10, 0, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "mmu_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
