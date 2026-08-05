"""AxISA milestone-2 test program (see docs/ISA.md): exercises GLUON/
BARYON/MESON/LOAD/STORE/JAL on top of milestone 1's proven ALUR/ALUI/
BRANCH/HALT. Every new instruction folds its result into a running
N-bank accumulator (n1) via ordinary ALUR adds (already proven
correct in milestone 1) - the final tohost value can only match if
EVERY step upstream computed correctly, not just the last one.

Also deliberately exercises the "explicitly legal, easy to get wrong"
degenerate cases flagged by this project's own design review before
any RTL was written:
  - MESON with q1_bank==q2_bank==N (a real same-bank double-read)
  - GLUON with rs1_bank==rs2_bank==rd_bank (worst-case 2R+1W to ONE
    bank in a single cycle - written to R, checked via direct
    hierarchical peek like milestone 1 did for R/G/B)
  - STORE with base_bank==N (STORE's own double-read: the value-to-
    store `ns` and the address register `base_reg` are two DIFFERENT
    N registers read in the same cycle - the asymmetric case LOAD
    never hits, since LOAD has no `ns` to compete with)
  - JAL's link value (PC+4) verified by requiring the skipped
    instruction's bogus write (999) to NOT survive into the final sum
"""
import sys
from asm_test1 import (
    R, G, B, N, ADD,
    addi, add, gluon, baryon, meson, load, store, jal, halt, write_hex,
)

if __name__ == "__main__":
    program = [
        addi(R, 1, 0, 5),         # r1 = 5
        addi(R, 2, 0, 7),         # r2 = 7
        addi(G, 1, 0, 3),         # g1 = 3
        addi(G, 2, 0, 4),         # g2 = 4
        addi(B, 1, 0, 10),        # b1 = 10
        addi(B, 2, 0, 20),        # b2 = 20
        addi(N, 1, 0, 0),         # n1 = accumulator = 0

        baryon(0, 2, 1, 1, 1),        # n2 = r1+g1+b1 = 5+3+10 = 18
        add(N, 1, 1, 2),               # n1 = 0+18 = 18

        meson(0, 2, R, 2, G, 2),      # n2 = r2-g2 = 7-4 = 3 (general, different banks)
        add(N, 1, 1, 2),               # n1 = 18+3 = 21

        addi(N, 3, 0, 50),        # n3 = 50 (2nd operand for the N/N double-read test)
        meson(0, 2, N, 3, N, 1),      # n2 = n3-n1 = 50-21 = 29 (same-bank==N double-read)
        add(N, 1, 1, 2),               # n1 = 21+29 = 50

        gluon(0, N, 2, R, 1, G, 1),   # n2 = r1^g1^CONST[0] = 5^3^0 = 6 (general, different banks)
        add(N, 1, 1, 2),               # n1 = 50+6 = 56

        gluon(1, R, 3, R, 1, R, 2),   # r3 = r1^r2^CONST[1] = 5^7^1 = 3 (same-bank R, 2R+1W worst case - checked via peek)

        addi(N, 4, 0, 300),       # n4 = 300 (address constant for the N-base LOAD/STORE test)

        store(1, R, 1, 100),       # mem[(r1+100)] = n1 = 56          (base_bank=R, general)
        load(2, R, 1, 100),        # n2 = mem[(r1+100)] = 56          (round-trip readback)
        add(N, 1, 1, 2),               # n1 = 56+56 = 112

        store(1, N, 4, 0),         # mem[n4] = n1 = 112               (base_bank=N: STORE's real double-read, ns=n1 base_reg=n4)
        load(2, N, 4, 0),          # n2 = mem[n4] = 112                (base_bank=N: LOAD's single-read, no ns to compete with)
        add(N, 1, 1, 2),               # n1 = 112+112 = 224

        jal(2, 8),                 # n2 = PC_of_this+4 (link); PC = PC_of_this+8 (skip next instr)
        addi(N, 2, 0, 999),        # MUST be skipped - would corrupt n2 to 999 if JAL's skip failed
        add(N, 1, 1, 2),               # n1 = 224 + n2 (n2 must be the link address, 100, not 999)

        halt(1),                   # tohost = n1 (see tb/tb_cpu2.v for the hand-computed expected value)
    ]

    out_path = sys.argv[1] if len(sys.argv) > 1 else "test2.hex"
    write_hex(program, out_path)
