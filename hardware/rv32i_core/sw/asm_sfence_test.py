"""Real TLB-invalidation test - proves SFENCE.VMA actually flushes the
TLB, not just that it decodes without crashing. The program legitimately
self-modifies its OWN page table (via a normal, translated store into an
identity-mapped alias of the L0 table's physical page - exactly the "OS
identity-maps its own page tables" convention real kernels use, since
this project has no separate physical-addressing mode), then executes
SFENCE.VMA, then re-reads the SAME virtual address a second time.

Page table (built by the testbench, same layout both variants share):
  L1[0] (VA VPN1=0)  -> L0 table at physical 0x2000
  L0[0] (VA 0x0000)  -> physical 0x3000, holds SENTINEL_A = 1111
  L0[5] (VA 0x5000)  -> physical 0x2000 (IDENTITY map of the L0 table's
                        own page - lets this program legally rewrite
                        L0[0] via an ordinary translated store). VA 0x5000
                        was chosen deliberately to stay clear of
                        [SHARED_MEM_BASE, SHARED_MEM_BASE+SHARED_MEM_BYTES)
                        = [0x2000, 0x2100) - an EARLIER version of this
                        test used VA 0x2000 for the alias and silently
                        broke: that VA landed inside the shared-bus
                        window, so the "store" was routed to bus_req
                        instead of private data_mem and never touched
                        L0[0] at all - found live via a cycle-by-cycle
                        trace of dmem_write/mmu_paddr, not a real MMU bug.
  physical 0x4000 holds SENTINEL_B = 2222

    lw    x10, 0(x0)      x10 = mem[translate(VA 0)] = SENTINEL_A
                          (first touch - walks and fills the TLB for VA 0)
    lui   x2, 0x4         x2 = 0x00004000
    addi  x2, x2, 7       x2 = 0x00004007 (new L0[0]: PPN=4, R=1,W=1,V=1)
    lui   x3, 0x5         x3 = 0x00005000 (VA of L0[0], via the identity
                          alias at L0[5])
    sw    x2, 0(x3)       L0[0] <- new PTE (a real, translated write - this
                          instruction's OWN VA 0x5000 must ALSO walk/fill
                          on its first touch, exercising the store-miss
                          path the mem_size/mmu_stall fixes cover)
    sfence.vma            flush the TLB - VA 0's stale cached entry
                          (pointing at the OLD physical 0x3000) must be
                          discarded, or the next read below would
                          incorrectly still hit it
    lw    x10, 0(x0)      x10 = mem[translate(VA 0)] AGAIN - must now walk
                          fresh and see the NEW mapping (physical 0x4000)
    ecall                 tohost = SENTINEL_B (2222) if invalidation
                          genuinely worked; SENTINEL_A (1111) if the
                          stale TLB entry was incorrectly still served
"""
import sys

sys.path.insert(0, ".")
from importlib import import_module

_m = import_module("asm_test1")
lw, sw, lui, addi, ecall, r_type = _m.lw, _m.sw, _m.lui, _m.addi, _m.ecall, _m.r_type


def sfence_vma():
    return r_type(0b0000001, 0, 0, 0b000, 0, 0b1110011)


include_sfence = "--no-sfence" not in sys.argv

program = [
    lw(10, 0, 0),
    lui(2, 0x4),
    addi(2, 2, 7),
    lui(3, 0x5),
    sw(2, 0, 3),
]
if include_sfence:
    program.append(sfence_vma())
program += [
    lw(10, 0, 0),
    ecall(),
]

args = [a for a in sys.argv[1:] if not a.startswith("--")]
out_path = args[0] if args else "sfence_test.hex"
with open(out_path, "w") as f:
    for word in program:
        f.write("%08x\n" % (word & 0xFFFFFFFF))

print("wrote", len(program), "words to", out_path, "(sfence included)" if include_sfence else "(sfence OMITTED - negative control)")
