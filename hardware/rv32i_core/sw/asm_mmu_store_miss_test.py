"""Regression test for a real bug: a STORE that misses the TLB on first
touch used to corrupt physical page 0 (dmem_write was gated by
!mmu_walk_active alone, but walk_active only covers S_L1/S_L0 - the
S_IDLE miss-detection cycle and the S_FILL cycle both left mmu_paddr
resolved to a bogus physical address near page 0, and dmem_write stayed
asserted through them). Fixed by also gating dmem_write on !mmu_stall.

    lui  x1, 0xABCDE     x1 = 0xABCDE000 (arbitrary recognizable pattern)
    sw   x1, 0(x0)       VA 0 <- x1 (first-touch TLB miss, translates to
                         a private data page far from physical page 0)
    lw   x10, 0(x0)      x10 = VA 0 (now a TLB hit) - should read back
                         the same 0xABCDE000 if the translated store
                         landed at the RIGHT physical address and didn't
                         also corrupt page 0 along the way
    ecall                tohost = 0xABCDE000 if correct
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lui, sw, lw, ecall = _m.lui, _m.sw, _m.lw, _m.ecall

program = [
    lui(1, 0xABCDE),
    sw(1, 0, 0),
    lw(10, 0, 0),
    ecall(),
]

out_path = sys.argv[1] if len(sys.argv) > 1 else "mmu_store_miss_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path)
