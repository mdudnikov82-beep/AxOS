"""A real text assembler for AxISA (see docs/ISA.md) - mnemonics,
named registers (r0-r7/g0-g7/b0-b7/n0-n7), labels for BRANCH/JAL
targets, comments. Two-pass: pass 1 assigns each instruction's address
and records label positions; pass 2 encodes, resolving label
references to PC-relative offsets.

Deliberately does NOT reimplement bit-packing - every mnemonic bottoms
out in a call to asm_test1.py's own encoder functions (alur/alui/
branch/gluon/baryon/meson/load/store/jal/halt), which are already
proven correct (milestone 1 and 2's own testbenches matched their
hand-computed expected values on the first run against these exact
functions). This keeps the new code's blast radius limited to text
parsing and label resolution - genuinely new surface - instead of
re-risking the bit-layout logic that's already been verified.
"""
import re
import sys

from asm_test1 import (
    R, G, B, N,
    ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU,
    BEQ, BNE, BLT, BGE, BLTU, BGEU,
    alur, alui, branch, halt, gluon, baryon, meson, load, store, jal,
    write_hex,
)

BANK_NAMES = {'R': R, 'G': G, 'B': B, 'N': N}
BANK_LETTERS = {v: k for k, v in BANK_NAMES.items()}

ALU_FUNCT = {
    'ADD': ADD, 'SUB': SUB, 'AND': AND, 'OR': OR, 'XOR': XOR,
    'SLL': SLL, 'SRL': SRL, 'SRA': SRA, 'SLT': SLT, 'SLTU': SLTU,
}
BRANCH_FUNCT = {
    'BEQ': BEQ, 'BNE': BNE, 'BLT': BLT, 'BGE': BGE, 'BLTU': BLTU, 'BGEU': BGEU,
}

REG_RE = re.compile(r'^([RGBN])(\d)$')


class AsmError(Exception):
    pass


def parse_reg(tok):
    tok = tok.strip().upper()
    m = REG_RE.match(tok)
    if not m:
        raise AsmError(f"bad register '{tok}' (expected e.g. r0-r7/g0-g7/b0-b7/n0-n7)")
    bank = BANK_NAMES[m.group(1)]
    reg = int(m.group(2))
    if not (0 <= reg <= 7):
        raise AsmError(f"register index out of range: '{tok}' (0-7 only)")
    return bank, reg


def require_bank(bank, reg, expected, mnemonic, role):
    if bank != expected:
        raise AsmError(
            f"{mnemonic}: {role} must be a {BANK_LETTERS[expected]}-bank register, "
            f"got {BANK_LETTERS[bank]}{reg}"
        )


def parse_imm(tok):
    tok = tok.strip()
    return int(tok, 0)  # supports decimal and 0x.. , including a leading '-'


def encode_one(mnemonic, ops, iaddr, labels):
    m = mnemonic.upper()

    if m in ALU_FUNCT:
        if len(ops) != 3:
            raise AsmError(f"{m}: expected 3 operands (rd, rs1, rs2), got {len(ops)}")
        rd_bank, rd = parse_reg(ops[0])
        rs1_bank, rs1 = parse_reg(ops[1])
        rs2_bank, rs2 = parse_reg(ops[2])
        if not (rd_bank == rs1_bank == rs2_bank):
            raise AsmError(f"{m}: rd/rs1/rs2 must all be the same bank")
        return alur(rd_bank, ALU_FUNCT[m], rd, rs1, rs2)

    if m.endswith('I') and m[:-1] in ALU_FUNCT:
        funct = ALU_FUNCT[m[:-1]]
        if len(ops) != 3:
            raise AsmError(f"{m}: expected 3 operands (rd, rs1, imm), got {len(ops)}")
        rd_bank, rd = parse_reg(ops[0])
        rs1_bank, rs1 = parse_reg(ops[1])
        if rd_bank != rs1_bank:
            raise AsmError(f"{m}: rd/rs1 must be the same bank")
        imm = parse_imm(ops[2])
        return alui(rd_bank, funct, rd, rs1, imm)

    if m in BRANCH_FUNCT:
        if len(ops) != 3:
            raise AsmError(f"{m}: expected 3 operands (rs1, rs2, target), got {len(ops)}")
        rs1_bank, rs1 = parse_reg(ops[0])
        rs2_bank, rs2 = parse_reg(ops[1])
        if rs1_bank != rs2_bank:
            raise AsmError(f"{m}: rs1/rs2 must be the same bank")
        target = resolve_target(ops[2], labels)
        return branch(rs1_bank, BRANCH_FUNCT[m], rs1, rs2, target - iaddr)

    if m == 'GLUON':
        if len(ops) != 4:
            raise AsmError("GLUON: expected 4 operands (funct, rd, rs1, rs2)")
        funct = parse_imm(ops[0])
        rd_bank, rd = parse_reg(ops[1])
        rs1_bank, rs1 = parse_reg(ops[2])
        rs2_bank, rs2 = parse_reg(ops[3])
        return gluon(funct, rd_bank, rd, rs1_bank, rs1, rs2_bank, rs2)

    if m == 'BARYON':
        if len(ops) != 5:
            raise AsmError("BARYON: expected 5 operands (funct, nd, rr, gg, bb)")
        funct = parse_imm(ops[0])
        nd_bank, nd = parse_reg(ops[1])
        rr_bank, rr = parse_reg(ops[2])
        gg_bank, gg = parse_reg(ops[3])
        bb_bank, bb = parse_reg(ops[4])
        require_bank(nd_bank, nd, N, m, "nd")
        require_bank(rr_bank, rr, R, m, "rr (3rd operand)")
        require_bank(gg_bank, gg, G, m, "gg (4th operand)")
        require_bank(bb_bank, bb, B, m, "bb (5th operand)")
        return baryon(funct, nd, rr, gg, bb)

    if m == 'MESON':
        if len(ops) != 4:
            raise AsmError("MESON: expected 4 operands (funct, nd, q1, q2)")
        funct = parse_imm(ops[0])
        nd_bank, nd = parse_reg(ops[1])
        q1_bank, q1 = parse_reg(ops[2])
        q2_bank, q2 = parse_reg(ops[3])
        require_bank(nd_bank, nd, N, m, "nd")
        return meson(funct, nd, q1_bank, q1, q2_bank, q2)

    if m == 'LOAD':
        if len(ops) != 3:
            raise AsmError("LOAD: expected 3 operands (nd, base, imm)")
        nd_bank, nd = parse_reg(ops[0])
        base_bank, base = parse_reg(ops[1])
        imm = parse_imm(ops[2])
        require_bank(nd_bank, nd, N, m, "nd")
        return load(nd, base_bank, base, imm)

    if m == 'STORE':
        if len(ops) != 3:
            raise AsmError("STORE: expected 3 operands (ns, base, imm)")
        ns_bank, ns = parse_reg(ops[0])
        base_bank, base = parse_reg(ops[1])
        imm = parse_imm(ops[2])
        require_bank(ns_bank, ns, N, m, "ns")
        return store(ns, base_bank, base, imm)

    if m == 'JAL':
        if len(ops) != 2:
            raise AsmError("JAL: expected 2 operands (nd, target)")
        nd_bank, nd = parse_reg(ops[0])
        require_bank(nd_bank, nd, N, m, "nd")
        target = resolve_target(ops[1], labels)
        return jal(nd, target - iaddr)

    if m == 'HALT':
        if len(ops) != 1:
            raise AsmError("HALT: expected 1 operand (tohost_reg)")
        nd_bank, nd = parse_reg(ops[0])
        require_bank(nd_bank, nd, N, m, "tohost_reg")
        return halt(nd)

    raise AsmError(f"unknown mnemonic '{mnemonic}'")


def resolve_target(tok, labels):
    tok = tok.strip()
    if tok in labels:
        return labels[tok]
    return parse_imm(tok)  # a raw literal is a direct byte address, not PC-relative


LABEL_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def assemble(lines):
    # Pass 1: strip comments, split off labels, assign each real
    # instruction's byte address. A line may be "label:" alone,
    # "label: MNEM ops" together, or just "MNEM ops".
    instrs = []
    labels = {}
    addr = 0
    for lineno, raw in enumerate(lines, 1):
        line = raw.split('#', 1)[0].split(';', 1)[0].strip()
        if not line:
            continue
        while ':' in line:
            label, _, rest = line.partition(':')
            label = label.strip()
            if not LABEL_RE.match(label):
                raise AsmError(f"line {lineno}: bad label '{label}'")
            if label in labels:
                raise AsmError(f"line {lineno}: duplicate label '{label}'")
            labels[label] = addr
            line = rest.strip()
            if not line:
                break
        if not line:
            continue
        parts = line.split(None, 1)
        mnemonic = parts[0]
        operand_str = parts[1] if len(parts) > 1 else ''
        operands = [o.strip() for o in operand_str.split(',')] if operand_str else []
        instrs.append((addr, mnemonic, operands, lineno))
        addr += 4

    # Pass 2: encode, now that every label's address is known.
    words = []
    for (iaddr, mnemonic, operands, lineno) in instrs:
        try:
            words.append(encode_one(mnemonic, operands, iaddr, labels))
        except AsmError as e:
            raise AsmError(f"line {lineno}: {e}")
    return words


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("usage: axasm.py <in.axasm> <out.hex>")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        src_lines = f.readlines()
    try:
        program = assemble(src_lines)
    except AsmError as e:
        print("ASSEMBLY ERROR:", e)
        sys.exit(1)
    write_hex(program, sys.argv[2])
