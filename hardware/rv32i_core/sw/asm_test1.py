"""Tiny RV32I encoder + a hand-written test program, used to validate
cpu_core.v's wiring before trusting a full C-toolchain pipeline. Not a
general assembler - just enough instruction shapes for this one test.
Writes a $readmemh-compatible hex file (one 32-bit word per line).
"""
import sys


def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def i_type(imm, rs1, funct3, rd, opcode):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s_type(imm, rs2, rs1, funct3, opcode):
    imm &= 0xFFF
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode


def b_type(imm, rs2, rs1, funct3, opcode):
    # imm is a byte offset, must be even; bit 0 is always 0 and not encoded.
    imm &= 0x1FFF
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode


def addi(rd, rs1, imm):
    return i_type(imm, rs1, 0b000, rd, 0b0010011)


def add(rd, rs1, rs2):
    return r_type(0b0000000, rs2, rs1, 0b000, rd, 0b0110011)


def sw(rs2, imm, rs1):
    return s_type(imm, rs2, rs1, 0b010, 0b0100011)


def lw(rd, imm, rs1):
    return i_type(imm, rs1, 0b010, rd, 0b0000011)


def beq(rs1, rs2, imm):
    return b_type(imm, rs2, rs1, 0b000, 0b1100011)


def ecall():
    return i_type(0, 0, 0b000, 0, 0b1110011)


def u_type(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def lui(rd, imm20):
    return u_type(imm20, rd, 0b0110111)


# Minimal RV32F (see control_unit.v/cpu_core.v): FLW/FSW use the exact
# same I-type/S-type shapes as LW/SW, just different opcodes; rd/rs1/
# rs2 for FLW/FSW/FADD.S/FSUB.S/FMUL.S address fp_regfile except FLW/
# FSW's rs1 (base address), which is still an integer register.
def flw(rd, imm, rs1):
    return i_type(imm, rs1, 0b010, rd, 0b0000111)


def fsw(rs2, imm, rs1):
    return s_type(imm, rs2, rs1, 0b010, 0b0100111)


def fadd_s(rd, rs1, rs2):
    return r_type(0b0000000, rs2, rs1, 0b000, rd, 0b1010011)


def fsub_s(rd, rs1, rs2):
    return r_type(0b0000100, rs2, rs1, 0b000, rd, 0b1010011)


def fmul_s(rd, rs1, rs2):
    return r_type(0b0001000, rs2, rs1, 0b000, rd, 0b1010011)


def fdiv_s(rd, rs1, rs2):
    return r_type(0b0001100, rs2, rs1, 0b000, rd, 0b1010011)


# x1=5, x2=10, x3=x1+x2=15, mem[0]=x3, x4=mem[0](=15),
# BEQ x3,x4,+8 (taken -> skip the next instruction),
# x5=999 (SKIPPED if branch worked), x10=42, ECALL (tohost=42 if
# the skip worked; tohost would differ if branch/skip logic is broken).
if __name__ == "__main__":
    program = [
        addi(1, 0, 5),
        addi(2, 0, 10),
        add(3, 1, 2),
        sw(3, 0, 0),
        lw(4, 0, 0),
        beq(3, 4, 8),
        addi(5, 0, 999),   # PC=20, should be skipped
        addi(10, 0, 42),   # PC=24, branch target
        ecall(),
    ]

    out_path = sys.argv[1] if len(sys.argv) > 1 else "test1.hex"
    with open(out_path, "w") as f:
        for word in program:
            f.write("%08x\n" % (word & 0xFFFFFFFF))

    print("wrote", len(program), "words to", out_path)
