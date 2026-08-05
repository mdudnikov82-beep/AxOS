"""AxISA assembler helpers (milestone 1: ALUR/ALUI/BRANCH/HALT only -
see docs/ISA.md). Writes a $readmemh-compatible hex file (one 32-bit
word per line).
"""
import sys

R, G, B, N = 0, 1, 2, 3

ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU = range(10)
BEQ, BNE, BLT, BGE, BLTU, BGEU = range(6)

OP_ALUR = 0b00000
OP_ALUI = 0b00001
OP_GLUON = 0b00010
OP_BARYON = 0b00011
OP_MESON = 0b00100
OP_LOAD = 0b00101
OP_STORE = 0b00110
OP_BRANCH = 0b00111
OP_JAL = 0b01000
OP_HALT = 0b01001


def alur(bank, funct, rd, rs1, rs2):
    return (OP_ALUR << 27) | (bank << 25) | (funct << 21) | (rd << 18) | (rs1 << 15) | (rs2 << 12)


def alui(bank, funct, rd, rs1, imm):
    imm &= 0x7FFF
    return (OP_ALUI << 27) | (bank << 25) | (funct << 21) | (rd << 18) | (rs1 << 15) | imm


def addi(bank, rd, rs1, imm):
    return alui(bank, ADD, rd, rs1, imm)


def add(bank, rd, rs1, rs2):
    return alur(bank, ADD, rd, rs1, rs2)


def branch(bank, funct, rs1, rs2, imm):
    imm &= 0xFFFF
    return (OP_BRANCH << 27) | (bank << 25) | (funct << 22) | (rs1 << 19) | (rs2 << 16) | imm


def beq(bank, rs1, rs2, imm):
    return branch(bank, BEQ, rs1, rs2, imm)


def halt(tohost_reg):
    return (OP_HALT << 27) | (tohost_reg << 24)


# ==================== Milestone 2 (see docs/ISA.md) ====================

def gluon(funct, rd_bank, rd_reg, rs1_bank, rs1_reg, rs2_bank, rs2_reg):
    return ((OP_GLUON << 27) | (funct << 24) | (rd_bank << 22) | (rd_reg << 19) |
            (rs1_bank << 17) | (rs1_reg << 14) | (rs2_bank << 12) | (rs2_reg << 9))


def baryon(funct, nd, rr, gg, bb):
    return (OP_BARYON << 27) | (funct << 24) | (nd << 21) | (rr << 18) | (gg << 15) | (bb << 12)


def meson(funct, nd, q1_bank, q1_reg, q2_bank, q2_reg):
    return ((OP_MESON << 27) | (funct << 25) | (nd << 22) |
            (q1_bank << 20) | (q1_reg << 17) | (q2_bank << 15) | (q2_reg << 12))


def load(nd, base_bank, base_reg, imm):
    imm &= 0x7FFFF
    return (OP_LOAD << 27) | (nd << 24) | (base_bank << 22) | (base_reg << 19) | imm


def store(ns, base_bank, base_reg, imm):
    imm &= 0x7FFFF
    return (OP_STORE << 27) | (ns << 24) | (base_bank << 22) | (base_reg << 19) | imm


def jal(nd, imm):
    imm &= 0xFFFFFF
    return (OP_JAL << 27) | (nd << 24) | imm


def write_hex(program, out_path):
    with open(out_path, "w") as f:
        for word in program:
            f.write("%08x\n" % (word & 0xFFFFFFFF))
    print("wrote", len(program), "words to", out_path)


if __name__ == "__main__":
    # Milestone-1 smoke test: real arithmetic independently in R, G, B
    # (verified by the testbench peeking each bank's registers directly,
    # since milestone 1 has no cross-bank move instruction yet - that's
    # GLUON/BARYON/MESON, milestone 2), plus N-bank arithmetic AND a
    # real taken branch, reported via HALT/tohost.
    program = [
        addi(R, 1, 0, 5),
        addi(R, 2, 0, 7),
        add(R, 3, 1, 2),          # r3 = 12

        addi(G, 1, 0, 3),
        addi(G, 2, 0, 4),
        add(G, 3, 1, 2),          # g3 = 7

        addi(B, 1, 0, 10),
        addi(B, 2, 0, 20),
        add(B, 3, 1, 2),          # b3 = 30

        addi(N, 1, 0, 100),
        addi(N, 2, 0, 100),
        beq(N, 1, 2, 8),          # taken - skip the next instruction
        addi(N, 1, 0, 999),       # must be SKIPPED
        add(N, 3, 1, 2),          # n3 = 200 (only correct if branch worked)

        halt(3),                  # tohost = n3 = 200
    ]

    out_path = sys.argv[1] if len(sys.argv) > 1 else "test1.hex"
    write_hex(program, out_path)
