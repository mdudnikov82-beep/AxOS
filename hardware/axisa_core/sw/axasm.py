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
import os
import sys

from asm_test1 import (
    R, G, B, N,
    ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU,
    BEQ, BNE, BLT, BGE, BLTU, BGEU,
    SEL_EPC, SEL_CAUSE, SEL_SMODE, SEL_SIE,
    alur, alui, branch, halt, gluon, baryon, meson, load, store, jal,
    rft, syscall, mvsr, ptb, qhad, qcnot, qmeasure, string, su3mul, mtag, jalr, regge, plaq, metro, linkmul, reunit, sweep,
    GLUON_FUNCT, GLUON_COLORS,
    write_hex,
)

BANK_NAMES = {'R': R, 'G': G, 'B': B, 'N': N}
BANK_LETTERS = {v: k for k, v in BANK_NAMES.items()}

# v2.0 combine rules (docs/ISA.md). A bare number is still accepted.
BARYON_FUNCT = {'SUM': 0, 'MAJ': 1, 'EPS': 2, 'QN': 3}
MESON_FUNCT = {'DIFF': 0, 'SINGLET': 1, 'QN': 2}
# v2.0 step 3: quark flavor codes, usable anywhere an immediate is
# (ADDI R1, R0, UP). An antiquark is the negated code: -UP, or ANTI.
FLAVOR = {'UP': 1, 'DOWN': 2, 'STRANGE': 3, 'CHARM': 4, 'BOTTOM': 5, 'TOP': 6}

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
    name = tok.lstrip('-').upper()
    if name in FLAVOR:
        return -FLAVOR[name] if tok.startswith('-') else FLAVOR[name]
    return int(tok, 0)  # supports decimal and 0x.. , including a leading '-'


def encode_one(mnemonic, ops, iaddr, labels):
    m = mnemonic.upper()

    if m == '.WORD':
        # A raw 32-bit word, not a real mnemonic - the only way to
        # place a deliberately-illegal instruction (a reserved opcode
        # this ISA has no real mnemonic for) into a test program.
        if len(ops) != 1:
            raise AsmError(".word: expected 1 operand (raw 32-bit value)")
        return parse_imm(ops[0]) & 0xFFFFFFFF

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
        # v2.1: a label is accepted as an immediate (its absolute byte
        # address) - how a program takes a function's address for JALR
        imm = labels[ops[2].strip()] if ops[2].strip() in labels else parse_imm(ops[2])
        if not -16384 <= imm <= 16383:
            raise AsmError(f"{m}: immediate {imm} does not fit in 15 signed bits")
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

    # v2.0 real gluons: GLUON <gluon>, rd, rs  e.g. GLUON RG, R4, G1
    # (an r-antig gluon turns green quark g1 into red quark r4). The
    # assembler enforces the color rules the hardware traps on; use
    # .word to deliberately emit an illegal one.
    if m == 'GLUON':
        if len(ops) != 3:
            raise AsmError("GLUON: expected 3 operands (gluon, rd, rs)")
        name = ops[0].upper()
        if name not in GLUON_FUNCT:
            raise AsmError(f"GLUON: unknown gluon '{ops[0]}' (one of {', '.join(GLUON_FUNCT)})")
        rd_bank, rd = parse_reg(ops[1])
        rs_bank, rs = parse_reg(ops[2])
        if rs_bank == N:
            raise AsmError("GLUON: gluons don't couple to colorless N registers")
        if name in GLUON_COLORS:
            need, becomes = GLUON_COLORS[name]
            if rs_bank != need or rd_bank != becomes:
                raise AsmError(f"GLUON {name}: needs a {'RGB'[need]} source and a {'RGB'[becomes]} destination")
        elif rd_bank != rs_bank:
            raise AsmError(f"GLUON {name}: diagonal gluons keep the color - rd/rs must be the same bank")
        return gluon(GLUON_FUNCT[name], rd, rs_bank, rs)

    if m == 'BARYON':
        if len(ops) != 5:
            raise AsmError("BARYON: expected 5 operands (funct, nd, rr, gg, bb)")
        funct = BARYON_FUNCT.get(ops[0].upper())
        if funct is None:
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
        funct = MESON_FUNCT.get(ops[0].upper())
        if funct is None:
            funct = parse_imm(ops[0])
        nd_bank, nd = parse_reg(ops[1])
        q1_bank, q1 = parse_reg(ops[2])
        q2_bank, q2 = parse_reg(ops[3])
        require_bank(nd_bank, nd, N, m, "nd")
        if funct in (MESON_FUNCT['SINGLET'], MESON_FUNCT['QN']) and (q1_bank != q2_bank or q1_bank == N):
            raise AsmError(f"MESON {ops[0]}: quark and antiquark must be the same color (R, G or B)")
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

    if m == 'RFT':
        if len(ops) != 0:
            raise AsmError("RFT: expected 0 operands")
        return rft()

    if m == 'SYSCALL':
        if len(ops) != 0:
            raise AsmError("SYSCALL: expected 0 operands")
        return syscall()

    # MVSR mnemonics (see docs/ISA.md's "Traps" section) - 8 distinct
    # single-operand mnemonics (MF*=read special->N, MT*=write N->
    # special) rather than one generic "MVSR dir,selreg,reg" - matches
    # this ISA's existing style of separate mnemonics per real operation
    # (ALUR/ALUI are separate, not one generic "ALU") and needs no new
    # operand-parsing code (each is just HALT's own single-N-register
    # shape).
    MVSR_MNEMONICS = {
        'MFEPC':   (0, SEL_EPC),   'MTEPC':   (1, SEL_EPC),
        'MFCAUSE': (0, SEL_CAUSE), 'MTCAUSE': (1, SEL_CAUSE),
        'MFSMODE': (0, SEL_SMODE), 'MTSMODE': (1, SEL_SMODE),
        'MFSIE':   (0, SEL_SIE),   'MTSIE':   (1, SEL_SIE),
    }
    if m in MVSR_MNEMONICS:
        if len(ops) != 1:
            raise AsmError(f"{m}: expected 1 operand (N register)")
        direction, selreg = MVSR_MNEMONICS[m]
        nreg_bank, nreg = parse_reg(ops[0])
        require_bank(nreg_bank, nreg, N, m, "operand")
        return mvsr(direction, selreg, nreg)

    # PTB mnemonics (see docs/ISA.md's "Virtual memory" section) - same
    # MF*/MT* read/write shape as MVSR's own mnemonics, just one
    # register instead of a selreg-picked one.
    PTB_MNEMONICS = {'MFPTB': 0, 'MTPTB': 1}
    if m in PTB_MNEMONICS:
        if len(ops) != 1:
            raise AsmError(f"{m}: expected 1 operand (N register)")
        direction = PTB_MNEMONICS[m]
        nreg_bank, nreg = parse_reg(ops[0])
        require_bank(nreg_bank, nreg, N, m, "operand")
        return ptb(direction, nreg)

    # QHAD/QCNOT (classical quantum-circuit-simulator extension - see
    # docs/ISA.md's QHAD/QCNOT sections). No register operands at all -
    # like BARYON's implicit rr/gg/bb, the actual R-bank addresses are
    # resolved in hardware from these small selector immediates.
    if m == 'QHAD':
        if len(ops) != 2:
            raise AsmError("QHAD: expected 2 operands (qubit, half)")
        qubit = parse_imm(ops[0])
        half = parse_imm(ops[1])
        if qubit not in (0, 1) or half not in (0, 1):
            raise AsmError("QHAD: qubit and half must each be 0 or 1")
        return qhad(qubit, half)

    if m == 'QCNOT':
        if len(ops) != 1:
            raise AsmError("QCNOT: expected 1 operand (ctrl)")
        ctrl = parse_imm(ops[0])
        if ctrl not in (0, 1):
            raise AsmError("QCNOT: ctrl must be 0 or 1")
        return qcnot(ctrl)

    # QMEASURE - third member of the same extension. Unlike QHAD/QCNOT,
    # `nd` IS a real register reference (the N-bank destination for the
    # 1-bit outcome), so this parses like MVSR/PTB's own operand, not
    # a plain immediate.
    # v2.0 step 4: STRING nd, qa, qb - both ends the same color (R/G/B)
    if m == 'STRING':
        if len(ops) != 3:
            raise AsmError("STRING: expected 3 operands (nd, qa, qb)")
        nd_bank, nd = parse_reg(ops[0])
        qa_bank, qa = parse_reg(ops[1])
        qb_bank, qb = parse_reg(ops[2])
        require_bank(nd_bank, nd, N, m, "nd")
        if qa_bank != qb_bank or qa_bank == N:
            raise AsmError("STRING: both ends must be the same color (R, G or B)")
        return string(nd, qa_bank, qa, qb)

    # v2.0 step 5: SU3MUL ns, dst, src - dst/src are register-PAIR indices
    # (Re = idx, Im = idx+1) shared by all three color banks
    if m == 'SU3MUL':
        if len(ops) != 3:
            raise AsmError("SU3MUL: expected 3 operands (ns, dst, src)")
        ns_bank, ns = parse_reg(ops[0])
        require_bank(ns_bank, ns, N, m, "ns")
        dst, src = parse_imm(ops[1]), parse_imm(ops[2])
        if not (0 <= dst <= 6 and 0 <= src <= 6):
            raise AsmError("SU3MUL: dst/src must be 0..6 (each names the pair idx, idx+1)")
        return su3mul(ns, dst, src)

    # v2.3 step 3: SWEEP nd, ns, L - average plaquette of the periodic L x L
    # lattice at N[ns] (L = 1..4) into N[nd]
    if m == 'SWEEP':
        if len(ops) != 3:
            raise AsmError("SWEEP: expected 3 operands (nd, ns, L)")
        nd_bank, nd = parse_reg(ops[0])
        ns_bank, ns = parse_reg(ops[1])
        require_bank(nd_bank, nd, N, m, "nd")
        require_bank(ns_bank, ns, N, m, "ns")
        l = parse_imm(ops[2])
        if not 1 <= l <= 4:
            raise AsmError("SWEEP: L must be 1..4")
        return sweep(nd, ns, l)

    # v2.3 step 2: REUNIT ns - the matrix at N[ns] back onto SU(3), in place
    if m == 'REUNIT':
        if len(ops) != 1:
            raise AsmError("REUNIT: expected 1 operand (ns)")
        bank, r = parse_reg(ops[0])
        require_bank(bank, r, N, m, "ns")
        return reunit(r)

    # v2.3 step 1: LINKMUL nc, na, nb - C = A * B, 3x3 complex matrices in
    # memory at the N registers' addresses; a trailing ^ means the
    # Hermitian conjugate (dagger): LINKMUL N3, N1^, N2 is C = A^dag * B
    if m == 'LINKMUL':
        if len(ops) != 3:
            raise AsmError("LINKMUL: expected 3 operands (nc, na[^], nb[^])")
        dag = []
        regs = []
        for name, tok in zip(("nc", "na", "nb"), ops):
            tok = tok.strip()
            d = tok.endswith('^')
            if d and name == "nc":
                raise AsmError("LINKMUL: the destination cannot carry ^")
            bank, r = parse_reg(tok[:-1] if d else tok)
            require_bank(bank, r, N, m, name)
            regs.append(r)
            dag.append(1 if d else 0)
        return linkmul(dag[1], dag[2], *regs)

    # v2.2 step 2: METRO ACCEPT|WEIGHT, nd, na, nb, nbeta - dS = beta*(na - nb)
    # (P_old, P_new); ACCEPT: nd = 1 with probability min(1, exp(-dS))
    if m == 'METRO':
        if len(ops) != 5:
            raise AsmError("METRO: expected 5 operands (ACCEPT|WEIGHT, nd, p_old, p_new, beta)")
        kinds = {'ACCEPT': 0, 'WEIGHT': 1}
        kind = ops[0].upper()
        if kind not in kinds:
            raise AsmError(f"METRO: unknown kind '{ops[0]}' (ACCEPT or WEIGHT)")
        regs = []
        for name, tok in zip(("nd", "p_old", "p_new", "beta"), ops[1:]):
            bank, r = parse_reg(tok)
            require_bank(bank, r, N, m, name)
            regs.append(r)
        return metro(kinds[kind], *regs)

    # v2.2: PLAQ nd, ns - (1/3) Re Tr(U1 U2 U3^dag U4^dag) of the 4 link
    # matrices at N[ns]; the result is colorless (N-bank binary32)
    if m == 'PLAQ':
        if len(ops) != 2:
            raise AsmError("PLAQ: expected 2 operands (nd, ns)")
        nd_bank, nd = parse_reg(ops[0])
        ns_bank, ns = parse_reg(ops[1])
        require_bank(nd_bank, nd, N, m, "nd")
        require_bank(ns_bank, ns, N, m, "ns")
        return plaq(nd, ns)

    # v2.1 step 1: memory tagging. IRG nd, ns / STG ns / LDG nd, ns -
    # pointers are N registers (only N touches memory)
    # v2.1 step 3: REGGE SPIN.M|SPIN.B|MASS.M|MASS.B, nd, ns (N-bank binary32)
    if m == 'REGGE':
        if len(ops) != 3:
            raise AsmError("REGGE: expected 3 operands (SPIN.M|SPIN.B|MASS.M|MASS.B, nd, ns)")
        kinds = {'SPIN.M': 0, 'SPIN.B': 1, 'MASS.M': 2, 'MASS.B': 3}
        kind = ops[0].upper()
        if kind not in kinds:
            raise AsmError(f"REGGE: unknown kind '{ops[0]}' (SPIN.M, SPIN.B, MASS.M or MASS.B)")
        nd_bank, nd = parse_reg(ops[1])
        ns_bank, ns = parse_reg(ops[2])
        require_bank(nd_bank, nd, N, m, "nd")
        require_bank(ns_bank, ns, N, m, "ns")
        return regge(kinds[kind], nd, ns)

    # v2.1 step 2: JALR nd, ns, imm (imm optional) - indirect call/return
    if m == 'JALR':
        if len(ops) not in (2, 3):
            raise AsmError("JALR: expected nd, ns[, imm]")
        nd_bank, nd = parse_reg(ops[0])
        ns_bank, ns = parse_reg(ops[1])
        require_bank(nd_bank, nd, N, m, "nd")
        require_bank(ns_bank, ns, N, m, "ns")
        return jalr(nd, ns, parse_imm(ops[2]) if len(ops) == 3 else 0)

    if m in ('IRG', 'STG', 'LDG'):
        want = 1 if m == 'STG' else 2
        if len(ops) != want:
            raise AsmError(f"{m}: expected {want} operand(s)")
        regs = [parse_reg(o) for o in ops]
        for (bk, r), role in zip(regs, ("nd", "ns") if want == 2 else ("ns",)):
            require_bank(bk, r, N, m, role)
        nd = regs[0][1] if want == 2 else 0
        ns = regs[-1][1]
        return mtag({'IRG': 0, 'STG': 1, 'LDG': 2}[m], nd, ns)

    if m == 'QMEASURE':
        if len(ops) != 2:
            raise AsmError("QMEASURE: expected 2 operands (qubit, nd)")
        qubit = parse_imm(ops[0])
        if qubit not in (0, 1):
            raise AsmError("QMEASURE: qubit must be 0 or 1")
        nd_bank, nd = parse_reg(ops[1])
        require_bank(nd_bank, nd, N, m, "nd")
        return qmeasure(qubit, nd)

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

        if mnemonic.upper() == '.ORG':
            # Pad with real NOP instructions (ADDI n0,n0,0 - n0 is
            # hardwired zero, so the write is silently dropped by
            # regbank.v) up to the target address - there is no sparse/
            # hole-filling mechanism in write_hex(), every word in the
            # output must be a real instruction. Needed to place a trap
            # handler at a fixed hardware address (TRAP_VECTOR_ADDR)
            # without hand-counting NOPs, the same off-by-one-prone
            # exercise this project has already been bitten by once
            # (register indices) - let the assembler count instead.
            if len(operands) != 1:
                raise AsmError(f"line {lineno}: .org expects 1 operand (target address)")
            target = parse_imm(operands[0])
            if target < addr:
                raise AsmError(f"line {lineno}: .org target 0x{target:x} is before the current address 0x{addr:x} (already passed)")
            if (target - addr) % 4 != 0:
                raise AsmError(f"line {lineno}: .org target 0x{target:x} is not word-aligned relative to current address 0x{addr:x}")
            while addr < target:
                instrs.append((addr, 'ADDI', ['N0', 'N0', '0'], lineno))
                addr += 4
            continue

        if mnemonic.upper() == 'ANTI':
            # v2.0 pseudo-instruction: antiquark = charge conjugate =
            # two's-complement negation, done as two real ALUI ops
            # (R/G/B have no hardwired zero register to SUB from).
            if len(operands) != 2:
                raise AsmError(f"line {lineno}: ANTI expects 2 operands (rd, rs)")
            instrs.append((addr, 'XORI', [operands[0], operands[1], '-1'], lineno))
            instrs.append((addr + 4, 'ADDI', [operands[0], operands[0], '1'], lineno))
            addr += 8
            continue

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


def read_source(path, _stack=()):
    """Read an .axasm file, expanding `.include "file"` lines (path
    relative to the including file) - v2.1, so a library such as
    sw/lib/hmalloc.axasm can be shared between programs. Note that
    assembler error line numbers count lines AFTER expansion."""
    path = os.path.abspath(path)
    if path in _stack:
        raise AsmError(f"recursive .include of {path}")
    out = []
    with open(path, encoding='utf-8') as f:
        for raw in f:
            code = raw.split('#', 1)[0].strip()
            if code.lower().startswith('.include'):
                name = code[len('.include'):].strip().strip('"')
                out += read_source(os.path.join(os.path.dirname(path), name), _stack + (path,))
            else:
                out.append(raw)
    return out


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("usage: axasm.py <in.axasm> <out.hex>")
        sys.exit(1)
    try:
        src_lines = read_source(sys.argv[1])
    except AsmError as e:
        print("ASSEMBLY ERROR:", e)
        sys.exit(1)
    try:
        program = assemble(src_lines)
    except AsmError as e:
        print("ASSEMBLY ERROR:", e)
        sys.exit(1)
    write_hex(program, sys.argv[2])
