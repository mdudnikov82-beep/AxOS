# AxISA v0.1 — Instruction Set Architecture Specification

A from-scratch 32-bit ISA (not RISC-V, not derived from it) themed
around quantum chromodynamics (QCD). This document is the single
source of truth for encoding and semantics — RTL, the assembler, and
testbenches all must match it exactly.

## Registers

Four register banks, 8 registers each (32 total), each register 32
bits wide:

| Bank | Name    | Registers | Role                                            |
|------|---------|-----------|--------------------------------------------------|
| `R`  | Red     | r0-r7     | quark register (color charge)                    |
| `G`  | Green   | g0-g7     | quark register (color charge)                    |
| `B`  | Blue    | b0-b7     | quark register (color charge)                    |
| `N`  | Neutral | n0-n7     | colorless (hadron) register                       |

**`n0` is hardwired to zero** — "the vacuum has no net color charge"
is literally a true statement in QCD, so this is both a thematically
fitting and practically convenient constant-zero register (mirrors
`x0` in RISC-V). `r0`-`r7`, `g0`-`g7`, `b0`-`b7`, and `n1`-`n7` are all
ordinary read/write registers.

**Confinement rule**: only the `N` bank can touch memory (`LOAD`/
`STORE`) or report a result via `HALT`. A raw quark value (`R`/`G`/`B`)
can never leave the register file directly — it must first be combined
into a colorless value via `GLUON` (partial, still not confirmed
colorless — see below), `BARYON`, or `MESON`. This is structural, not
a runtime check: `LOAD`'s `nd`, `STORE`'s `ns`, and `HALT`'s
`tohost_reg` are all bare 3-bit indices with no bank-tag field
anywhere near them (confirmed by design review) - they can only ever
address the N bank's own register file. There is nothing to reject at
decode time, because a quark-bank value is not encodable in these
positions in the first place.

Bank encoding (2 bits, used throughout): `00`=R, `01`=G, `10`=B, `11`=N.

## Instruction word

Fixed 32-bit instructions, opcode always in bits `[31:27]` (5 bits, 32
possible classes). Every other field's position is fixed per
instruction class (no format-dependent reinterpretation of the same
bit range across classes, to keep decode simple).

| Opcode (binary) | Mnemonic | Class                                  |
|------------------|----------|------------------------------------------|
| `00000`          | ALUR     | bank-tagged register-register ALU        |
| `00001`          | ALUI     | bank-tagged register-immediate ALU       |
| `00010`          | GLUON    | inter-bank (quark-quark) combine          |
| `00011`          | BARYON   | 3-quark (R+G+B) combine → N               |
| `00100`          | MESON    | 2-quark combine → N                       |
| `00101`          | LOAD     | N-bank load from memory                   |
| `00110`          | STORE    | N-bank store to memory                    |
| `00111`          | BRANCH   | conditional branch (same-bank compare)    |
| `01000`          | JAL      | jump and link (link written to N)         |
| `01001`          | HALT     | stop, report tohost from a named N reg    |
| others           | —        | reserved for v0.2+                        |

### ALUR — `opcode[31:27] bank[26:25] funct[24:21] rd[20:18] rs1[17:15] rs2[14:12] (unused[11:0])`

`rd`, `rs1`, `rs2` all address the SAME bank (given by `bank`). Result
`rd = rs1 OP rs2` within that bank, per real RISC-V-style ALU
semantics (chosen for buildability, not thematic — the ALU op set
itself isn't QCD-flavored).

`funct` (4 bits — 16 encodings, mirrors RV32I's ALU op set):
`0000`=ADD `0001`=SUB `0010`=AND `0011`=OR `0100`=XOR `0101`=SLL
`0110`=SRL `0111`=SRA `1000`=SLT (signed) `1001`=SLTU (unsigned)
— `1010`-`1111` reserved.

### ALUI — `opcode[31:27] bank[26:25] funct[24:21] rd[20:18] rs1[17:15] imm[14:0]`

Same `funct` encoding as ALUR. `imm` is **sign-extended to 32 bits
uniformly for every funct** (design review corrected a wrong
assumption here: real RV32I sign-extends ANDI/ORI/XORI's immediate
too, not zero-extends - there was never a real precedent for the
split this spec originally had, so AxISA just does the simpler
uniform thing). SLL/SRL/SRA use **`imm[4:0]`** (5 bits, covering the
full 0-31 shift range a 32-bit register needs) as the shift amount;
the rest of the 15-bit immediate is unused for shifts.

### GLUON — `opcode[31:27] funct[26:24] rd_bank[23:22] rd_reg[21:19] rs1_bank[18:17] rs1_reg[16:14] rs2_bank[13:12] rs2_reg[11:9] (unused[8:0])`

Real QCD has exactly 8 gluons (the SU(3) adjoint representation) —
`funct` is 3 bits, one code per gluon, each defining a distinct
combining rule for `rs1 OP rs2 -> rd`. `rd_bank`, `rs1_bank`,
`rs2_bank` are independently encoded (any of R/G/B/N) — **v0.1
deliberately does NOT enforce `rs1_bank != rs2_bank`**: design review
confirmed the same-bank case is computationally harmless (it needs
no more read/write ports than ALUR already requires) and forbidding
it would cost real decode logic for a case that can't cause any actual
hardware problem, so it's a decided permanent non-feature, not an
open question. All 8 gluon functions compute `rd = rs1 ^ rs2 ^ CONST[funct]`
for v0.1 (a fixed per-gluon XOR constant) — deliberately the simplest
possible real operation that still gives each of the 8 gluons a
distinct, checkable behavior; richer per-gluon semantics are a
natural v0.2 extension once the basic plumbing is proven.

`CONST` table (arbitrary but fixed, chosen for easy hand-verification
in tests — low popcount, distinct):
`funct=0: 0x00000000` (this "gluon" is a plain XOR combine)
`funct=1: 0x00000001` `funct=2: 0x00000002` `funct=3: 0x00000004`
`funct=4: 0x00000008` `funct=5: 0x00000010` `funct=6: 0x00000020`
`funct=7: 0x00000040`

### BARYON — `opcode[31:27] funct[26:24] nd[23:21] rr[20:18] gg[17:15] bb[14:12] (unused[11:0])`

Source banks are IMPLICIT (not encoded): `rr` always addresses R,
`gg` always addresses G, `bb` always addresses B — mirrors a real
baryon always being exactly one quark of each color. Result always
goes to `N` bank register `nd`. `funct` (3 bits) selects the combine
rule — v0.1 defines only `funct=000`: `nd = rr + gg + bb` (plain
32-bit wraparound sum); `funct=001`-`111` reserved for v0.2.

### MESON — `opcode[31:27] funct[26:25] nd[24:22] q1_bank[21:20] q1_reg[19:17] q2_bank[16:15] q2_reg[14:12] (unused[11:0])`

Two explicit bank+register operands (any bank, including N) combine
to `N` bank register `nd`. This is a simplification of real meson
physics (a real meson is a quark and ITS OWN flavor's antiquark, which
this ISA doesn't model as a distinct concept) — `MESON` here just
means "the 2-source colorless-combine sibling of `BARYON`." `funct`
(2 bits): `funct=00`: `nd = q1 - q2` (v0.1's only defined rule;
`01`-`11` reserved).

### LOAD — `opcode[31:27] nd[26:24] base_bank[23:22] base_reg[21:19] imm[18:0]`

`nd = mem[base + sign_extend(imm)]` (word load, 32 bits). `base_reg`
may be from ANY bank (R/G/B/N) — computing an address is not itself a
"color-violating" observation, only the loaded DATA (which always
lands in N) is confinement-relevant. `imm` is 19 bits, sign-extended,
byte address offset.

### STORE — `opcode[31:27] ns[26:24] base_bank[23:22] base_reg[21:19] imm[18:0]`

`mem[base + sign_extend(imm)] = ns` (word store). Same base-address
addressing freedom as LOAD; `ns` (the stored VALUE) is a bare N-bank
index like `LOAD`'s `nd` - see the Confinement rule above for why this
needs no decode-time check.

### BRANCH — `opcode[31:27] bank[26:25] funct[24:22] rs1[21:19] rs2[18:16] imm[15:0]`

`rs1`, `rs2` both address the SAME bank (like ALUR). `funct` (3 bits):
`000`=BEQ `001`=BNE `010`=BLT (signed) `011`=BGE (signed) `100`=BLTU
`101`=BGEU — `110`-`111` reserved. `imm` is a 16-bit signed byte offset
from the branch's own PC (RISC-V-style PC-relative), giving a real,
generous ±32KB range.

### JAL — `opcode[31:27] nd[26:24] imm[23:0]`

`nd = PC + 4` (written to N bank), `PC = PC + sign_extend(imm)`. 24-bit
signed PC-relative offset (±8MB range).

### HALT — `opcode[31:27] tohost_reg[26:24] (unused[23:0])`

Stop; the testbench convention's `tohost` value is `N` bank register
`tohost_reg`'s current value (matches rv32i_core's own `ECALL`/`a0`
convention, generalized to a named register instead of a fixed one
specifically because `n0` is hardwired zero and can't serve that role).

## Reserved `funct` behavior (decided ahead of RTL, per design review)

A reserved `funct` value on ALUR/ALUI (`4'b1010`-`4'b1111`), BARYON
(`3'b001`-`3'b111`), or MESON (`2'b01`-`2'b11`) is decoded as
`illegal` and blocks `reg_write` entirely - this is an explicit,
written decision, not left to "whatever the combinational logic's
`default` arm happens to compute" (an earlier version of this project
had a comment on `alu.v` claiming `control_unit` already covered this
for ALUR/ALUI when it actually didn't - fixed by adding the real
check, not by softening the comment). GLUON has no reserved `funct` -
all 8 codes are defined (real QCD has exactly 8 gluons), so there is
nothing to reject.

## Explicitly deferred to v0.2+ (not blocking a first working core)

- Additional BARYON/MESON `funct` combine rules beyond the one each
  defined here.
- "Asymptotic freedom" as a real timing effect (interaction latency
  that varies with operand value difference) - a fun idea, not
  attempted until the core datapath itself is proven.
- Any notion of an actual antiquark register or flavor beyond color.
- BRANCH/JAL immediates could be treated as pre-shifted by 2 (like
  RV32I's own branch/jump immediates), doubling their real-world range
  (±32KB→±64KB, ±8MB→±16MB) for free, since the bottom 2 bits of any
  4-byte-aligned target are always zero anyway - not done in v0.1
  since the current range is already generous and this isn't fixing
  anything broken.

## Implementation notes (register file design, decided ahead of RTL)

Confirmed by design review before any RTL was written:

- **Port count**: 2 read ports + 1 write port per bank is provably
  sufficient for every instruction in this spec - no single
  instruction ever needs a 3rd simultaneous access to one bank (worked
  out by checking peak per-bank demand across every format: ALUR/
  BRANCH need 2R+1W or 2R+0W to one bank; GLUON's same-bank case tops
  out at the same 2R+1W; BARYON needs only 1R from each of R/G/B plus
  1W to N; LOAD/STORE/JAL/HALT all need less).
- **One parameterized register-file module, instantiated 4 times**
  (address width 3, depth 8, optional hardwired-register-0 parameter
  for N only) rather than four near-duplicate files - R/G/B/N are
  identical in shape except for that one option.
- **No same-cycle write-bypass mux in the register file.** `rv32i_core`'s
  own `regfile.v` documents a real historical bug here: a single
  instruction routinely has `rd == rs1` in the SAME bank (e.g. an
  ALUR add-into-itself), and a "harmless-looking" bypass meant to let
  a write show up on a same-cycle read created a genuine combinational
  loop (the ALU's about-to-be-computed output feeding back into its
  own input) in that project's own history. AxISA's register file
  must do a plain combinational read of the storage array only, never
  synthesize a same-cycle write value into a read.
