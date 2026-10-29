# AxISA v2.3 — Instruction Set Architecture Specification

A from-scratch 32-bit ISA (not RISC-V, not derived from it) built
around quantum chromodynamics (QCD). This document is the single
source of truth for encoding and semantics — RTL, the assembler, and
testbenches all must match it exactly.

## The physics AxISA is built on

QCD is the theory of the strong force. Its rules map onto the ISA
directly:

- **Color charge.** Quarks carry one of three colors — red, green,
  blue. These are the `R`, `G`, `B` register banks. Antiquarks carry
  the matching anticolors.
- **SU(3).** Color is a 3-dimensional complex space, and the strong
  force is the symmetry group SU(3) acting on it: 3×3 unitary matrices
  with determinant 1.
- **Gluons.** The force carriers. There are exactly 8 — one for each
  generator of SU(3) (the Gell-Mann matrices λ1…λ8). Six of them carry
  a color and a different anticolor and *change* a quark's color; two
  (λ3, λ8) are diagonal and leave the color alone.
- **Confinement.** A lone colored quark is never observed. Only
  colorless (color-singlet) combinations exist freely: a **baryon**
  (red + green + blue, e.g. the proton and neutron) or a **meson**
  (color + its anticolor). In AxISA, only the colorless `N` bank can
  reach memory or the outside world.
- **Asymptotic freedom.** The strong force is weak at short distance
  and grows with distance; pull two quarks far enough apart and the
  "string" between them breaks, creating a new quark–antiquark pair.

## What's new in v2.0

v0.1 used QCD names over placeholder arithmetic (every GLUON was an XOR
with a constant). v2.0 gives the names real physical meaning, one step
at a time — each step lands with its own tests before the next starts:

| Step | Feature | Status |
|------|---------|--------|
| 1 | **Real gluons**: the 8 GLUON codes are the 8 real gluons, with color rules enforced in hardware | **done** |
| 2 | **BARYON/MESON combine rules + antiquarks**: `MAJ`, `EPS`, `SINGLET`, `ANTI` | **done** |
| 3 | **Protons, neutrons and hadrons**: quark flavor codes, `BARYON QN` / `MESON QN` quantum numbers | **done** |
| 4 | **Asymptotic freedom**: `STRING` — interaction time grows with distance, the string breaks into new pairs | **done** |
| 5 | **`SU3MUL`**: SU(3) matrix × color vector on the FPU — the core operation of lattice-QCD supercomputers | **done** |

**v2.0 is complete.** Next up is **v2.1** (planned, same one-step-at-a-time rule):

| Step | Feature | Status |
|------|---------|--------|
| 1 | **Hardware memory tagging (MTE-style)**: tag bits in pointers and per memory granule, `LOAD`/`STORE` trap on mismatch | **done** |
| 2 | **Hardened malloc** in AxISA assembly on the MTE tags, plus what it needed: `JALR`, a calling convention (ABI), `.include` | **done** |
| 3 | **String theory**: `REGGE` — Regge trajectories of the rotating string, checked against real hadrons | **done** |

**v2.2** — the lattice itself:

| Step | Feature | Status |
|------|---------|--------|
| 1 | **`PLAQ`**: the plaquette of one lattice square, `(1/3) Re Tr(U1 U2 U3† U4†)` — what lattice QCD's action is made of | **done** |
| 2 | **`METRO`**: the Metropolis step — Boltzmann weight `exp(−ΔS)` and the accept/reject draw; a real Markov chain runs on the core | **done** |

Building `PLAQ`'s bit-exact test also found a real rounding bug in the
shared FPU's subtraction (see `PLAQ` below); it is fixed.

**v2.3** — away from von Neumann. A von Neumann machine moves every
operand and every instruction through one narrow path between processor
and memory, and lattice QCD feels that more than most programs: `U·ψ`
reads ~96 bytes for ~66 floating-point operations. v2.3 adds
instructions that keep whole matrices, whole lattices and neighbouring
cores' data off that path:

| Step | Feature | Status |
|------|---------|--------|
| 1 | **`LINKMUL`**: SU(3) × SU(3) straight from memory to memory, with optional daggers — what every link update needs | **done** |
| 2 | **`REUNIT`**: pull a matrix back onto SU(3) after rounding drift — microcoded | **done** |
| 3 | **`SWEEP`**: one instruction walks a whole lattice — no instruction stream at all | planned |
| 4 | **`HOP`**: send a vector or link to a neighbouring core over the mesh, QCDOC-style | planned |

**Breaking change in step 1:** GLUON's encoding and semantics changed
completely (see below). v0.1 GLUON programs must be rewritten.

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
into a colorless value via `BARYON` or `MESON`. (In v0.1, `GLUON` could
also write `N`; v2.0's real gluons only ever move quarks between color
banks.) This is structural, not
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
| `00010`          | GLUON    | quark absorbs one of the 8 gluons (v2.0)   |
| `00011`          | BARYON   | 3-quark (R+G+B) combine → N               |
| `00100`          | MESON    | 2-quark combine → N                       |
| `00101`          | LOAD     | N-bank load from memory                   |
| `00110`          | STORE    | N-bank store to memory                    |
| `00111`          | BRANCH   | conditional branch (same-bank compare)    |
| `01000`          | JAL      | jump and link (link written to N)         |
| `01001`          | HALT     | stop, report tohost from a named N reg    |
| `01010`          | RFT      | return from trap (privileged)             |
| `01011`          | SYSCALL  | deliberate trap (user→kernel door)        |
| `01100`          | MVSR     | move to/from trap state (privileged)      |
| `01101`          | PTB      | move to/from page table base (privileged) |
| `01110`          | QHAD     | classical quantum-circuit-sim: Hadamard mix |
| `01111`          | QCNOT    | classical quantum-circuit-sim: CNOT swap  |
| `10000`          | QMEASURE | classical quantum-circuit-sim: probabilistic measurement/collapse |
| `10001`          | STRING   | color flux tube: distance-dependent latency, string breaking (v2.0) |
| `10010`          | SU3MUL   | lattice QCD: SU(3) matrix × color vector on the FPU (v2.0) |
| `10011`          | MTAG     | memory tagging: `IRG` / `STG` / `LDG` (v2.1) |
| `10100`          | JALR     | indirect jump and link — function return / call through a pointer (v2.1) |
| `10101`          | REGGE    | string theory: Regge trajectories, spin ↔ mass of hadrons (v2.1) |
| `10110`          | PLAQ     | lattice QCD: plaquette of one lattice square (v2.2) |
| `10111`          | METRO    | lattice QCD: Metropolis accept/reject, Boltzmann weight (v2.2) |
| `11000`          | LINKMUL  | lattice QCD: C = A′·B′, 3×3 complex matrices memory → memory (v2.3) |
| `11001`          | REUNIT   | lattice QCD: pull a matrix back onto SU(3), in place, microcoded (v2.3) |
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

### GLUON — `opcode[31:27] gluon[26:24] rd[23:21] rs_bank[20:19] rs[18:16] (unused[15:0])` (v2.0)

A quark `rs` (bank `rs_bank`) absorbs one of the 8 gluons. The result —
the same quark after the interaction — is written to register `rd` of
the bank the quark ends up in. `rs` itself is left unchanged.

**Off-diagonal gluons** carry color *c1* and anticolor *c̄2*. Only a
quark of color *c2* can absorb one, and it comes out with color *c1*.
The value passes through unchanged — only the color (bank) changes:

| `gluon` | Name | Assembler | Absorbed by | Quark becomes |
|---------|------|-----------|-------------|---------------|
| `000` | r ḡ | `RG` | green | red   |
| `001` | g r̄ | `GR` | red   | green |
| `010` | r b̄ | `RB` | blue  | red   |
| `011` | b r̄ | `BR` | red   | blue  |
| `100` | g b̄ | `GB` | blue  | green |
| `101` | b ḡ | `BG` | green | blue  |

**Diagonal gluons** keep the quark's color (destination bank =
`rs_bank`) and multiply the value by the Gell-Mann eigenvalue for that
color:

| `gluon` | Name | Assembler | red | green | blue |
|---------|------|-----------|-----|-------|------|
| `110` | λ3 | `L3` | ×1 | ×−1 | ×0 |
| `111` | λ8 | `L8` | ×1 | ×1 | ×−2 |

λ8 is really `diag(1, 1, −2)/√3`; AxISA drops the `1/√3` to stay in
exact integers. Both matrices are **traceless** (eigenvalues sum to 0),
so if red, green and blue quarks hold the same value, applying either
diagonal gluon to all three and then `BARYON`-summing gives exactly 0.
`sw/gluon_test.axasm` checks this invariant.

**Color rules (trap `ILLEGAL`, CAUSE=0, nothing written):**
- `rs_bank` = `N`: gluons couple only to color charge, and `N` holds
  colorless hadrons.
- An off-diagonal gluon on a quark of the wrong color (e.g. `RG` on a
  red quark).

Assembler: `GLUON <gluon>, rd, rs` — e.g. `GLUON RG, R4, G1` turns green
quark `g1` red into `r4`. The assembler rejects the illegal cases; use
`.word` to emit one deliberately.

### BARYON — `opcode[31:27] funct[26:24] nd[23:21] rr[20:18] gg[17:15] bb[14:12] (unused[11:0])`

Source banks are IMPLICIT (not encoded): `rr` always addresses R,
`gg` always addresses G, `bb` always addresses B — mirrors a real
baryon always being exactly one quark of each color. Result always
goes to `N` bank register `nd`. `funct` (3 bits) selects the combine
rule:

| `funct` | Assembler | Result | Notes |
|---------|-----------|--------|-------|
| `000` | `SUM` | `rr + gg + bb` | v0.1's rule, 32-bit wraparound |
| `001` | `MAJ` | bitwise majority `(r&g) \| (g&b) \| (r&b)` | v2.0. "Color vote": each bit is what at least 2 of the 3 colors say. Same function as SHA-256's `Maj`. |
| `010` | `EPS` | +1, −1 or 0 | v2.0. Levi-Civita symbol of the three values' order (below). |
| `011` | `QN` | packed quantum numbers | v2.0 step 3, see "Quark flavor and hadrons" |
| `100`–`111` | — | — | reserved → `ILLEGAL` |

**EPS.** A real baryon's color wavefunction is the totally
antisymmetric `ε_ijk q_i q_j q_k` — swapping any two quarks flips its
sign, and it vanishes if two quarks are identical. `EPS` computes the
same symbol on the *order* of the values:
`sgn(r−g) · sgn(g−b) · sgn(b−r)`, compared as signed integers. It is
+1 when `r < g < b` up to a cyclic rotation, −1 for an odd permutation
of that order, 0 if any two values are equal. (Signed vs. unsigned
comparison can never change the answer: reinterpreting the sign bit
moves the negative values above the positive ones as a block, which is
a cyclic rotation of three ranks — an even permutation.)

### MESON — `opcode[31:27] funct[26:25] nd[24:22] q1_bank[21:20] q1_reg[19:17] q2_bank[16:15] q2_reg[14:12] (unused[11:0])`

Two explicit bank+register operands combine to `N` bank register `nd`:

| `funct` | Assembler | Result | Rule |
|---------|-----------|--------|------|
| `00` | `DIFF` | `q1 − q2` | v0.1's rule, any banks (including N) |
| `01` | `SINGLET` | `q1 + q2` | v2.0. A quark `q1` and an antiquark `q2` of the **same color**. Different colors, or either operand in N → `ILLEGAL`. |
| `10` | `QN` | packed quantum numbers | v2.0 step 3. Same color rule as `SINGLET`; see "Quark flavor and hadrons" |
| `11` | — | — | reserved → `ILLEGAL` |

`SINGLET` is the real meson: color *c* plus anticolor *c̄* is the only
colorless quark–antiquark pair. Red + anti-green is a color **octet** —
literally the charge an r ḡ gluon carries — so it can't be a free
particle, and the hardware traps it.

### Antiquarks — `ANTI rd, rs` (assembler pseudo-instruction, v2.0)

An antiquark is the **charge conjugate** of a quark. In AxISA it is
stored in the same color bank as the quark, with its value negated
(two's complement) — consistent with the diagonal gluons: in the
conjugate representation the generators' eigenvalues flip sign, so
anti-red has λ3 eigenvalue −1 where red has +1.

`ANTI rd, rs` assembles to two real instructions in the same bank:
`XORI rd, rs, -1` then `ADDI rd, rd, 1` (the R/G/B banks have no
hardwired zero register to subtract from). Because `q2` of `SINGLET`
holds an already-conjugated antiquark,
`SINGLET(q, ANTI(x))` always equals `DIFF(q, x)` —
`sw/hadron_combine_test.axasm` checks exactly that.

### Quark flavor and hadrons (v2.0 step 3)

Besides color, every quark has a **flavor**. A quark register can hold a
flavor code — an antiquark holds the negated code (exactly what `ANTI`
produces):

| Code | Flavor | Assembler | Charge | Other quantum number |
|------|--------|-----------|--------|----------------------|
| 1 | up      | `UP`      | +2/3 | isospin I3 = +1/2 |
| 2 | down    | `DOWN`    | −1/3 | isospin I3 = −1/2 |
| 3 | strange | `STRANGE` | −1/3 | strangeness S = −1 |
| 4 | charm   | `CHARM`   | +2/3 | charm C = +1 |
| 5 | bottom  | `BOTTOM`  | −1/3 | bottomness B′ = −1 |
| 6 | top     | `TOP`     | +2/3 | (never in a hadron, see below) |

The names work anywhere an immediate does: `ADDI R1, R0, UP`,
`ADDI R2, R0, -STRANGE`.

`BARYON QN, nd, rr, gg, bb` and `MESON QN, nd, q1, q2` build a hadron
from those quarks and write its quantum numbers to `nd`, packed as
4-bit two's-complement fields:

| Bits | `[3:0]` | `[7:4]` | `[11:8]` | `[15:12]` | `[19:16]` | `[23:20]` | `[27:24]` | `[31:28]` |
|------|---------|---------|----------|-----------|-----------|-----------|-----------|-----------|
| Field | charge Q | baryon number B | strangeness S | charm C | bottomness B′ | topness T (always 0) | 2·I3 | 0 |

Examples (all checked by `sw/hadrons_test.axasm`):

| Hadron | Quarks | Result word | Meaning |
|--------|--------|-------------|---------|
| proton p | u u d | `0x01000011` | Q=+1, B=1, 2·I3=+1 |
| neutron n | u d d | `0x0F000010` | Q=0, B=1, 2·I3=−1 |
| Δ⁺⁺ | u u u | `0x03000012` | Q=+2 |
| Ω⁻ | s s s | `0x00000D1F` | Q=−1, S=−3 |
| antiproton | ū ū d̄ | `0x0F0000FF` | Q=−1, B=−1 |
| π⁺ | u d̄ | `0x02000001` | Q=+1, B=0, 2·I3=+2 |
| K⁺ | u s̄ | `0x01000101` | Q=+1, S=+1 |

**`ILLEGAL` (CAUSE=0, nothing written)** — unlike every other illegal
case in AxISA, these depend on the register *values*, not just the
instruction bits, so `cpu_core.v` raises them (`hadron_bad`) alongside
`control_unit.v`'s decode-time ones:

- an operand that isn't a flavor code (0, 7, −7, …);
- `BARYON QN` mixing quarks and antiquarks (q q q̄ is not a color singlet);
- `MESON QN` that isn't exactly one quark and one antiquark (either
  order), or whose two operands are different colors / in `N`;
- any **top** quark or antiquark. The top decays in about 5·10⁻²⁵ s,
  before the strong force can bind it, so no top hadron exists in
  nature. That is why the T field is always 0.

The charge is computed in thirds and divided by 3; for any legal
hadron the sum is always a multiple of 3 (each quark is ≡ 2 mod 3 in
thirds, three of them sum to ≡ 0, and a quark plus an antiquark
cancel mod 3).

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
`halted_r` is sticky forever once set - structurally unrelated to the
trap mechanism below, which is definitely-resumable by design.

### RFT — `opcode[31:27] (unused[26:0])`

Return from trap. **Privileged** (traps with `cause=PRIV_VIOLATION` if
executed in user mode). Restores `mode <= saved_mode`, `ie <= saved_ie`,
and jumps to EXACTLY `epc` (no automatic +4) - matching real
precedent (RISC-V's `mret`/`mepc`): a synchronous trap's own handler
is responsible for advancing `EPC` past the faulting/`SYSCALL`
instruction itself (via `MVSR` read-modify-write on `EPC`) if it wants
to skip it, which also leaves room for a future fault a handler wants
to *retry* (by leaving `EPC` unchanged) rather than skip - baking a
fixed `+4` into hardware would foreclose that for no benefit today. An
external interrupt's `EPC` already holds the address of the
NOT-yet-executed instruction that was preempted (see "Traps" below),
so its handler correctly needs no adjustment at all before `RFT`. This
is the smallest possible instruction this
ISA can encode - there is nothing to encode, since the target comes
from the hardware-latched `epc` register, not the instruction word.
(v2.1 note: `JALR` now exists — see below. This paragraph describes
the v0.1 design.) AxISA had no indirect-jump instruction (`JAL`'s target is always a
fixed PC-relative offset baked in at assemble time - see `JAL` above),
so a dedicated hardware-latched return address is the only way this
ISA can express "return to wherever execution was interrupted,"
confirmed by design review before this was written.

### SYSCALL — `opcode[31:27] (unused[26:0])`

Deliberate, in-band trap request - the user→kernel door. **Not**
privileged (it must work in both modes; it's the *only* way user code
can ever enter kernel mode short of an actual fault). Traps with
`cause=SYSCALL`. Software convention for passing a syscall number/
arguments (e.g. a fixed N register) is left to the OS, not the ISA.

### MVSR — `opcode[31:27] dir[26] selreg[25:24] n_reg[23:21] (unused[20:0])`

Move to/from trap state. **Privileged** (traps with
`cause=PRIV_VIOLATION` if executed in user mode). `dir=0`: read a
special register's value into N-bank register `n_reg`. `dir=1`: write
N-bank register `n_reg`'s value into the special register. `n_reg` is
a bare 3-bit N-bank index, same structural shape as `LOAD`'s `nd`/
`STORE`'s `ns` - only the `N` bank can ever be the operand, matching
every other memory/control-touching instruction in this ISA.

`selreg` (2 bits): `00`=`EPC` (the trap return address - software-
writable, not just hardware-latched-and-read-only, specifically to
bootstrap the very first drop into user mode: the kernel can never
reach user mode via `RFT` until *something* has staged `EPC`+
`SAVED_MODE`, and the first time, nothing has actually trapped yet);
`01`=`CAUSE` (why the most recent trap fired - see the cause table
below; writable for symmetry, though only ever meaningfully read);
`10`=`SAVED_MODE` (the privilege mode `RFT` will restore - 1 bit,
`0`=user `1`=kernel); `11`=`SAVED_IE` (the interrupt-enable state
`RFT` will restore). There is deliberately no way to write the *live*
`mode`/`ie` directly outside of `RFT` consuming `SAVED_MODE`/
`SAVED_IE` - kernel code that wants interrupts enabled while staying
in kernel mode (e.g. an idle loop) is an explicit v0.2+ gap, not an
oversight.

### PTB — `opcode[31:27] dir[26] n_reg[25:23] (unused[22:0])`

Move to/from the page table base register (see "Virtual memory"
below). **Privileged**, same rule as `MVSR`. Split into its own opcode
rather than a third `MVSR` selreg value because `MVSR`'s 2-bit
`selreg` field is already fully populated (all 4 encodings assigned
above) - `PTB` has exactly one register to move, so it needs no
selreg field at all, just `dir` (`0`=read `PTB`→`n_reg`, `1`=write
`n_reg`→`PTB`) and a bare 3-bit `n_reg`, the same shape as `MVSR`'s own
`n_reg`.

### STRING — `opcode[31:27] nd[26:24] bank[23:22] qa[21:19] qb[18:16] (unused[15:0])` (v2.0 step 4)

Asymptotic freedom and confinement in one instruction. Two quarks of
the same color sit at positions `qa` and `qb` (signed integers) with a
gluon flux tube — a "string" — between them. Their distance is
`d = |qa − qb|` (computed with a 33-bit difference, so it is exact for
any two 32-bit values; max `2³²−1`).

**Timing is the physics.** The strong coupling α_s is weak at short
distance (asymptotic freedom — quarks close together behave almost
free) and grows with distance. `STRING` takes **`1 + E` cycles**, where
`E` is the number of significant bits of `d` — a logarithmic stand-in
for the running coupling, which in real QCD also changes
logarithmically with the distance scale:

| `d` | cycles |
|-----|--------|
| 0 | 1 |
| 1 | 2 |
| 5 | 4 |
| 1000 | 11 |
| `0x7FFF` | 16 |
| ≥ `0xFFFF` | 17 (max) |

**String breaking.** Stretch the string far enough and it doesn't get
stronger forever: its stored energy creates a new quark–antiquark pair
from the vacuum and it snaps in two (this is how real collisions
produce jets of hadrons). AxISA's break energy is `2¹⁶`: from
`d ≥ 2¹⁶` on, `E` stops growing (saturates at 16), because the extra
energy goes into pairs instead of a longer, slower string.

**Result** in `nd` (N bank): `{pairs[31:16], segment[15:0]}` — the
number of quark–antiquark pairs created (`d >> 16`) and the length of
the last unbroken segment (`d & 0xFFFF`). With a power-of-two break
energy this packing is bit-for-bit `d` itself.

`bank` is shared by both ends: a flux tube joins a color and its own
anticolor, so mismatched colors are not even encodable. `bank` = `N`
→ `ILLEGAL` (colorless hadrons have no string). Like `QHAD`/`QMEASURE`,
an external IRQ arriving while `STRING` runs — on its first cycle,
mid-stall, or on its terminal cycle — is deferred until it commits
(`sw/trap_irq_string.axasm` checks all three).

Assembler: `STRING N1, R1, R2`.

### SU3MUL — `opcode[31:27] ns[26:24] dst[23:21] src[20:18] (unused[17:0])` (v2.0 step 5)

The core operation of lattice QCD: a quark's color vector `ψ` is
transported along a link of the space-time lattice by multiplying it
with that link's **gauge field**, an SU(3) matrix `U`: `ψ' = U·ψ`.
Lattice-QCD supercomputers (QCDOC, APEnet, and the GPUs that replaced
them) spend most of their time doing exactly this.

- **`ψ` lives in the color banks.** Its red, green and blue components
  are complex numbers, each a register pair (Re = `idx`, Im = `idx+1`,
  binary32) in bank R, G and B respectively. `src`/`dst` name the pair,
  `0`…`6`; `7` has no Im partner → `ILLEGAL`. `dst` may equal `src`
  (in place).
- **`U` lives in memory** at the address in `N[ns]` (only N touches
  memory — confinement): 18 binary32 words, row-major, element `(i,j)`
  as Re at `base + 8·(3i+j)` and Im at `+4`. The base must be
  word-aligned and the whole matrix must lie below the UART window
  (`base ≤ 0xFB8`), otherwise `ILLEGAL`.
- **Kernel mode only** (privilege violation in user mode): it reads
  physical memory directly, bypassing the MMU.

**Exact rounding order** (so software and test models can reproduce
every bit). For each row `i`, starting from `acc = +0.0 + 0.0i`, for
`j = 0, 1, 2` with `U_ij = a + bi` and `ψ_j = c + di`:

```
tRe = fl(fl(a·c) − fl(b·d))      accRe = fl(accRe + tRe)
tIm = fl(fl(a·d) + fl(b·c))      accIm = fl(accIm + tIm)
```

`fl` is binary32 round-to-nearest-even on the shared `fp_mul` /
`fp_addsub` (the same units as `QHAD`/`QMEASURE`). Like them, it flushes
subnormal results to zero and does not handle NaN/∞.

**Timing:** 133 cycles (14 per matrix element — 8 states, 6 of which
wait one extra cycle for the two-stage FPU, see "Timing" below — plus
decode and 6 write-back cycles — one register per cycle through the single write
port). External IRQs are deferred until it finishes, like
`QHAD`/`QMEASURE`/`STRING`.

`sw/su3mul_test.axasm` uses real SU(3) matrices — products of
`exp(iθλ_k)` over the Gell-Mann matrices, checked unitary with
determinant 1 — and compares every output bit with an independent
binary32 model (`tools/gen_su3mul_test.py`), including a chained
`U·U·ψ`, an in-place multiply, the highest legal base and all four
traps.

Assembler: `SU3MUL N1, 2, 0` (ns, dst, src).

### PLAQ — `opcode[31:27] nd[26:24] ns[23:21] (unused[20:0])` (v2.2 step 1)

Lattice QCD puts space-time on a grid. Quarks sit on the sites; the
gluon field lives on the **links** between neighbouring sites, one
SU(3) matrix per link (the `U` of `SU3MUL`). The smallest closed loop
on the grid is one square, the **plaquette**: go along `μ`, then `ν`,
then back along `μ`, then back along `ν`:

```
 x+ν  ←── U3† ───  x+μ+ν
  │                  ↑
 U4†                U2
  ↓                  │
  x   ─── U1 ───→  x+μ
```

`P = (1/3) Re Tr(U1 · U2 · U3† · U4†)`, with `U1 = U_μ(x)`,
`U2 = U_ν(x+μ)`, `U3 = U_μ(x+ν)`, `U4 = U_ν(x)`. `P = 1` when there is
no field at all (every link = 1, a "cold" lattice); random links (a
"hot" lattice) give `P` near 0. Wilson's action, the thing every
lattice-QCD simulation samples, is `S = β · Σ (1 − P)` over all
plaquettes. `P` is **gauge invariant**: rotating the colors
independently at every site (`U_μ(x) → g(x) U_μ(x) g(x+μ)†`) changes
every link but not `P`. A colorless quantity, so it goes to the `N`
bank.

- **The 4 links live in memory** back to back at the address in
  `N[ns]`: `U1` at `base`, `U2` at `base+72`, `U3` at `base+144`, `U4`
  at `base+216`, each in `SU3MUL`'s layout (18 binary32 words,
  row-major, Re then Im). The base must be word-aligned and all 288
  bytes must lie below the UART window (`base ≤ 0xEE0`), otherwise
  `ILLEGAL`.
- **Result**: binary32 `P` in `N[nd]`. `nd = ns` works (the base is
  read on the first cycle, `nd` is written on the last).
- **Kernel mode only** (privilege violation in user mode), like
  `SU3MUL`: it reads physical memory directly.

**How the hardware does it — and the exact rounding order.** No 3×3
product is ever stored. `Tr M = Σ_k (M e_k)_k`, and `M e_k` is three
matrix × vector products, so `PLAQ` runs on `SU3MUL`'s own sequencer
and per-element states, with one color vector `v` of extra state.
Complex conjugation `conj(a+bi) = a−bi` is a sign flip of the loaded
Im word, so every term is rounded exactly like `SU3MUL`'s
(`tRe = fl(fl(a·c) − fl(b·d))`, `tIm = fl(fl(a·d) + fl(b·c))`, each
vector component accumulated from `+0.0` over `j = 0, 1, 2`):

```
tr = +0.0
for k = 0, 1, 2:
    v_j = conj(U4[k][j])                   # U4† e_k: just loads
    v   = U3† v                            # element (i,j) = conj(U3[j][i])
    v   = U2 v
    for j = 0, 1, 2: tr = fl(tr + tRe(U1[k][j], v_j))
P = fl(tr · fl(1/3))                       # fl(1/3) = 0x3EAAAAAB
```

**Timing:** 913 cycles: decode, then per `k` 9 (loads) + 126 + 126 + 42,
then the `1/3` scaling and the write. External IRQs are deferred until
it writes, like `SU3MUL`.

`sw/plaq_test.axasm` (generated by `tools/gen_plaq_test.py`, which
checks its links are real SU(3) and every `P` against float64) checks
every result bit against an independent binary32 model: a cold square
(`P = 1` exactly), a hot one (`−0.1464413`), **the same square after a
random gauge transformation (the same `P`, bit for bit)**, a warm one
near 1 (`0.9897849`), `U1 = U2 = U3 = U4` at the highest legal base, and
all three traps.

**The FPU bug it found.** The warm square came out 1 ulp off. Tracing
every term showed the culprit was not `PLAQ` but `fp_addsub` itself,
ported from the RV32I core: on effective subtraction it dropped the
bits shifted out of the smaller operand before subtracting, so the
difference came out slightly too big and sometimes rounded the wrong
way (`0x3F7DF37E + 0xB966594C` gave `…519` instead of `…518`). Fixed by
subtracting with the sticky bit as a 27th bit. A fuzz test of 200,000
random additions/subtractions against an exact model: 14,418 wrong
before, 0 after. Every earlier test still passes: their cases just
never hit it.

Assembler: `PLAQ N2, N1` (nd, ns).

### REUNIT — `opcode[31:27] ns[26:24] (unused[23:0])` (v2.3 step 2)

Every product of SU(3) matrices in binary32 lands a little off SU(3);
after enough `LINKMUL`s the links are visibly not unitary any more, and
every real lattice code periodically pulls them back. `REUNIT` does that
in place for the matrix at `N[ns]` (`SU3MUL`'s layout), the standard way:

1. `u ← u / |u|` (row 0)
2. `v ← v − (u†v)·u`, then `v ← v / |v|` (row 1, Gram–Schmidt)
3. `w ← conj(u × v)` (row 2 is *rebuilt*, so `det = 1` exactly in exact
   arithmetic and `w` is orthogonal to both)

**Microcoded.** That is 127 floating-point steps, so instead of one more
hand-written state machine `REUNIT` runs a microprogram from a ROM
(`rtl/reunit_rom.v`) on 23 scratch registers: load 18 words, run
micro-ops `MUL`/`ADD`/`SUB` (on the shared two-stage FPU) and
`SQRT`/`DIV` (on the shared `fp_sqrt`/`fp_div`, both correctly rounded —
`fp_div` checked against 20,000 random divisions), store 18 words. The
microprogram has **one source**, `tools/reunit_ucode.py`: it generates the
ROM, and the test model executes the very same list, so the rounding
order is defined by that file and RTL and model cannot drift apart.

- The base must be word-aligned and the matrix must lie below the UART
  window (`≤ 0xFB8`), otherwise `ILLEGAL`. **Kernel mode only.**
- **Timing:** 443 cycles, the same for any data. External IRQs are
  deferred until the last word is written.

`sw/reunit_test.axasm` (generated by `tools/gen_reunit_test.py`) checks
every word bit for bit and, in float64, that each result is in SU(3):

| input | `‖UU†−1‖` before → after | `|det−1|` before → after |
|---|---|---|
| a link that drifted off SU(3) | 6·10⁻³ → 8·10⁻⁸ | 3·10⁻³ → 9·10⁻⁸ |
| a random, far-from-unitary matrix | 2.0 → 9·10⁻⁸ | 0.7 → 9·10⁻⁸ |
| a link after 30 × `LINKMUL U ← X·U` on the core | 1.8·10⁻⁶ → 3.5·10⁻⁷ | 1.8·10⁻⁶ → 3.5·10⁻⁷ |

plus the highest legal base, three traps and IRQ deferral
(`trap_irq_reunit`). Mutation testing: 8 of 8 killed.

Assembler: `REUNIT N1`.

### LINKMUL — `opcode[31:27] dagA[26] dagB[25] nc[24:22] na[21:19] nb[18:16] (unused[15:0])` (v2.3 step 1)

`C = A′ · B′`, where `A′` is `A` or its Hermitian conjugate `A†` (bit 26)
and `B′` is `B` or `B†` (bit 25). `A`, `B` and `C` are 3×3 complex
matrices in memory at `N[na]`, `N[nb]`, `N[nc]`, each in `SU3MUL`'s
layout (18 binary32 words, row-major, Re then Im). Nothing passes
through a register: the whole product goes from memory to memory.

This is what a lattice update is made of: a Metropolis proposal
`U′ = X·U`, the staples `U·V·W†` around a link, `A†A = 1` checks. Before
v2.3 a program could not build such products at all: only `N` touches
memory, and nothing moves from `N` or memory into `R`/`G`/`B`, so
`SU3MUL`'s results could never be stored back as a matrix.

- **Any overlap is fine**: `C` may be `A` or `B` (in-place `U ← X·U`).
  All nine elements go to a 18-word result buffer first and are written
  to `C` only after every read.
- All three bases are checked on the decode cycle — the `N` bank has a
  third read port for this: each must be word-aligned and lie below the
  UART window (`≤ 0xFB8`), otherwise `ILLEGAL`.
- **Kernel mode only** (privilege violation in user mode): it reads and
  writes physical memory, without the MMU or memory tags.

**Exact order.** Column by column on `SU3MUL`'s sequencer: for
`j = 0, 1, 2`, `v = column j of B′` (just loads; a dagger is a
transposed address plus a sign flip of Im), then for each row `i`,
`C[i][j] = Σ_k A′[i][k]·v_k` with `SU3MUL`'s term rounding, accumulated
from `+0.0` over `k = 0, 1, 2`.

**Timing:** 424 cycles: decode, then per column 9 loads + 9 terms × 14,
then 18 writes (the last is the terminal cycle). External IRQs are
deferred until all of `C` is written.

`sw/linkmul_test.axasm` (generated by `tools/gen_linkmul_test.py`)
checks all 144 result words bit for bit: `A·B`, `A†·B`, `A·B†`,
`B†·A†`, `A†·A` (= 1 to 10⁻⁶ in float64 — unitarity), in place with
`C = B` (`U ← X·U`) and with `C = A`, the highest legal base, and four
traps; `trap_irq_linkmul` checks IRQ deferral on the first cycle, in the
middle and on the last write.

Assembler: `LINKMUL N3, N1, N2` (C, A, B); a trailing `^` is a dagger:
`LINKMUL N3, N1^, N2` is `C = A†·B`.

### METRO — `opcode[31:27] funct[26] nd[25:23] na[22:20] nb[19:17] nbeta[16:14] (unused[13:0])` (v2.2 step 2)

How a lattice-QCD simulation actually moves. It proposes changing one
link, works out how much the action `S = β · Σ (1 − P)` would change,
and takes the change with the probability Metropolis, Rosenbluth and
Teller wrote down in 1953: always if `S` goes down, with probability
`exp(−ΔS)` if it goes up. Repeat, and the lattice ends up visiting each
configuration as often as Boltzmann's `exp(−S)` says — that is how
lattice QCD averages over the gluon field.

With `na` = `P_old`, `nb` = `P_new` (from `PLAQ`) and `nbeta` = `β`, all
binary32 in the `N` bank:

```
dS = fl(β · fl(P_old − P_new))          # S_new − S_old for one plaquette
w  = min(1, exp(−dS))                   # the Boltzmann weight
```

| `funct` | Assembler | `nd` gets |
|---------|-----------|-----------|
| `0` | `METRO ACCEPT, nd, na, nb, nbeta` | `1` with probability `w` (take the new link), else `0` |
| `1` | `METRO WEIGHT, nd, na, nb, nbeta` | `w` itself |

`ACCEPT` draws `r = fl(1.b − 1)`, `b` = 23 bits of the free-running LFSR
(the one `QMEASURE` and `IRG` use — fine for a simulation, not for
cryptography), so `r` is uniform on `{0, 2⁻²³, …, 1 − 2⁻²³}`, and answers
`r < w` (strictly: `w = 0` never accepts, `w = 1` always does). `nd` may
be any of the operands: it is written only on the last cycle.

**`exp` in hardware, exact order.** For `x = dS > 0`, `exp(−x) = 2^(−y)`
with `y = fl(x · fl(log₂ e))`. If `y ≥ 128`, `w = 0`. Otherwise
`y = n + t` (`n` integer, `0 ≤ t < 1`) — both exact, just bit slicing:
for `y ≥ 1`, `1 + t` is `y`'s mantissa shifted left past its integer
bits, and `t = fl((1 + t) − 1)` is exact. Then a degree-6 polynomial on
the shared FPU, Horner from `c₆`:

```
q = c6;  for k = 5 .. 0:  q = fl(fl(q · t) + c_k)       # q ≈ 2^(−t)
w = q · 2^(−n)                                         # exponent field − n; 0 if it would leave the normal range
```

`c₀ … c₆` = `0x3F800000 0xBF317216 0x3E75FD5C 0xBD634A03 0x3C1CF011
0xBAA70867 0x38E4607B` (fitted by `tools/gen_metro_test.py`): `2^(−t)` to
1.8·10⁻⁷. Rounding `y` costs another `≈ 6·10⁻⁸ · y` of relative error
(`5·10⁻⁶` at `dS = 87`) — far below anything a Markov chain notices. If
`dS ≤ 0`, `w = 1` with no arithmetic.

**Timing:** `WEIGHT` 35 cycles (8 if `dS ≤ 0`, 10 if `w = 0`); `ACCEPT`
also draws `r` on the adder (37 / 10 / 12). Every FPU step takes 2
cycles (see "Timing" below). The first cycle only latches
`P_old`/`P_new` and the second latches `β`: the FPU never takes an
operand straight off the register file (see "Timing" below). Not privileged — it touches no
memory. External IRQs are deferred until it writes.

**Tested two ways.** `sw/metro_test.axasm` checks 36 weights bit for bit
against a binary32 model (`dS < 0`, `= 0`, `β = 0`, `y < 1`, `ln 2 → ½`,
`1 → 1/e`, the edge of the normal range, `w = 0`, random cases, and
`nd = nbeta`), the accept rate over 2000 draws each for `w = 1, 0, ¼, ¾`
(`w = 0` with the LFSR forced to 0, so `r = 0` must still be rejected),
and every cycle count. And `sw/metro_chain.axasm` is a **real Markov
chain on the core**: one link of a square can be any of 8 SU(3)
matrices; the program measures all 8 plaquettes with `PLAQ`, then runs
3000 Metropolis steps at **β = 6.0** (a value real lattice studies use)
— propose `m ± 1` with a `METRO` coin flip (`dS = ln 2`), accept with
`METRO`, histogram where the chain is:

| candidate | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| `P` | 1.000 | 0.977 | 0.910 | 0.807 | 0.679 | 0.538 | 0.400 | 0.277 |
| Boltzmann `3000·exp(−S)/Z` | 994 | 866 | 580 | 313 | 145 | 62 | 27 | 13 |
| **the core's chain** | **992** | **897** | **588** | **301** | **143** | **54** | **16** | **9** |

The allowed band per candidate is 1.5× the worst deviation of 400
chains simulated in Python with a perfect random source — measured, not
guessed. Mutation testing: 10 of 10 mutants killed.

### Timing: the FPU only sees flip-flops (v2.2)

The first real synthesis of the whole core (sky130, 2026-10-28) gave
≈12 MHz in the slow corner. A logic-depth map of its netlist showed why:
every product of the shared `fp_mul` was timed through `fp_addsub` as
well, because `QHAD` fed the sum straight into the multiplier in the
same cycle, and that mux path exists no matter which instruction runs.
On top of that, `QHAD` and `METRO` fed register-file reads straight into
`fp_addsub` (decode → register file → FPU in one cycle). v2.2 cuts both:

- `QHAD` latches α (decode cycle) and β (S1), adds/subtracts in S2–S5
  into a register, and multiplies by `1/√2` and writes in S3–S6:
  **7 cycles** (was 5; 12 once the FPU got two stages, below). `QCNOT` has no arithmetic and keeps 5.
- `METRO` latches `P_old`/`P_new`, then `β`, before using them: +1 cycle.
- `METRO`'s two small shifts are written as `case` muxes: as `<<`/`>>`
  Yosys merged them into the ALU's barrel shifter (they never run
  together) and dragged the ALU's operand path into METRO's.

Longest register-to-register path (Yosys `ltp`, generic gates):
**215 → 124** levels. What was left was `fp_addsub` itself (~106 levels).

**Two-stage adder.** `fp_addsub2.v` is the same arithmetic, bit for bit,
with a register after the subtraction (stage 1: exponent compare,
alignment, add/subtract; stage 2: leading-zero count, normalize, round).
Every sequencer state that uses the adder's result now takes two
cycles: a shared `fa_wait` freezes all sequencers for the first one
while the operands — all flip-flops — hold still. Results are
unchanged. `SU3MUL`/`PLAQ` also latch `ψ_j` in their LIM state instead
of multiplying straight off a register bank. Longest path: **124 → 94**,
then `fp_mul` alone.

**Two-stage multiplier.** `fp_mul2.v` likewise splits `fp_mul` after the
24×24 significand product; the same `fa_wait` covers states that use
the product. `fa_wait` is part of the CPU stall, because `QHAD`'s
terminal cycle writes a product, and `QHAD`/`QMEASURE`'s product writes
are gated until the product is out. `SU3MUL`'s state A keeps the
matrix's Im address on `data_mem` for both of its cycles (the
synchronous read must still hold it in the second). Cycle counts since
v2.1: `QHAD` 5 → 12, `SU3MUL` 79 → 133, `PLAQ` 534 → 913, `REGGE` `SPIN`
5 → 8, `METRO` `ACCEPT` 37, `QMEASURE` ~96 → ~108; everything else is
still one cycle. Longest path: **94 → 93**, now the integer path decode
→ register file → address → trap check → write enable. Per stage, the
adder is 68 levels and the multiplier 38.

### REGGE — `opcode[31:27] funct[26:25] nd[24:22] ns[21:19] (unused[18:0])` (v2.1 step 3)

Where string theory came from. In the 1960s physicists noticed that
hadrons made of the same quarks but spinning faster line up on straight
**Regge trajectories**: spin `J` grows linearly with mass squared,
`J = α₀ + α′·M²`. In 1968–70 Veneziano, Nambu, Nielsen and Susskind
explained it with a **rotating relativistic string**: a string of
tension `σ` spinning with its ends at the speed of light has exactly
`J = α′·M²` with `α′ = 1/(2πσ)` — the birth of string theory. And that
string *is* the QCD flux tube of `STRING`: AxISA's `α′ = 0.9 GeV⁻²`
means `σ = 1/(2π·0.9) ≈ 0.177 GeV²`, the string tension lattice QCD
measures between real quarks.

Masses (GeV) and spins are properties of whole hadrons, so both live in
the colorless `N` bank, as binary32:

| `funct` | Assembler | Computes | Trajectory |
|---------|-----------|----------|------------|
| `00` | `SPIN.M` | `J = fl(α₀ + fl(α′·fl(M·M)))` | leading mesons (ρ, a₂, ρ₃, a₄…), `α₀ = 0.5` |
| `01` | `SPIN.B` | same | Δ baryons, `α₀ = 0.15` |
| `10` | `MASS.M` | `M = sqrt(fl(fl(J − α₀)·fl(1/α′)))` | mesons |
| `11` | `MASS.B` | same | Δ baryons |

`α′ = 0.9` (`0x3F666666`), `1/α′` rounded once (`0x3F8E38E4`),
`α₀ = 0.5` / `0.15`. A spin below the intercept has no real mass: the
shared `fp_sqrt` returns its canonical NaN `0x7FC00000`. `SPIN` takes 8
cycles; `MASS` goes through the multi-cycle `fp_sqrt` (shared with
`QMEASURE`). `nd = ns` works: `nd` is only written on the terminal
cycle, after the result is computed. (The operand is also latched on
the first cycle; a mutation test showed that latch is redundant, since
nothing else can write `ns` while `REGGE` runs.) External IRQs are
deferred until it writes.

Checked against real particles (PDG masses) by `tools/gen_regge_test.py`
before any RTL runs, and bit-exactly in `sw/regge_test.axasm`:

| Hadron | Mass (GeV) | `SPIN` gives | Real spin |
|--------|-----------|--------------|-----------|
| ρ(770) | 0.775 | 1.04 | 1 |
| a₂(1320) | 1.318 | 2.06 | 2 |
| ρ₃(1690) | 1.689 | 3.07 | 3 |
| a₄(1970) | 1.967 | 3.98 | 4 |
| Δ(1232) | 1.232 | 1.52 | 3/2 |
| Δ(1950) | 1.930 | 3.50 | 7/2 |
| Δ(2420) | 2.420 | 5.42 | 11/2 |

And backwards, `MASS.M` of `J = 5` predicts 2.24 GeV for the next meson
on the trajectory; the measured ρ₅(2350) is at 2.33 GeV.

Assembler: `REGGE SPIN.M, N2, N1`.

## QHAD / QCNOT / QMEASURE (classical quantum-circuit-simulator extension)

**Explicitly not real quantum hardware** - a real qubit needs a
physical substrate (superconducting circuits, trapped ions, photonics)
incompatible with the classical CMOS flows this project actually
targets (sky130 ASIC, ECP5 FPGA). These three instructions instead give
AxISA real, classical arithmetic for simulating a small quantum
circuit in hardware - the same computation a software simulator
(Qiskit-style) would do, executed for real on real gates, continuing
this ISA's QCD-themed naming into a new "quantum" register convention
rather than literal physics.

**State representation**: a classical 2-qubit state vector (4 complex
amplitudes) lives entirely in the `R` bank, one register pair per
amplitude, `Re` on the even register: `amp0=(r0,r1)` `amp1=(r2,r3)`
`amp2=(r4,r5)` `amp3=(r6,r7)`, amplitude index = `{q1,q0}` (`q0`/`q1`
each contribute one bit). Every value is IEEE-754 binary32
(`fp_addsub.v`/`fp_mul.v`, ported from `rv32i_core`'s own real RV32F
FPU - same scope limitation: normal-finite-or-zero inputs only,
NaN/infinity/subnormal are out of scope). There is no dedicated `LOAD`
32-bit-immediate instruction, so a test program builds a float32
constant via `ADDI`+`SLLI` (see `sw/qhad_test.axasm`).

**`QHAD`/`QCNOT` were the first genuinely multi-cycle instructions in
this ISA** (5 cycles each; `QHAD` is 12 since v2.2 - see "Timing" below) - AxISA's register banks have exactly 2
read + 1 write port per bank, and only one write port total
system-wide, so neither instruction (each touches 4 `R`-bank
registers) can complete in one cycle. `QMEASURE` (below) is the third
member of this family and by far the longest at ~108 cycles (96 before v2.2's two-stage FPU), since it
also needs real division and square-root hardware, neither of which
existed anywhere in AxISA before it. See the "Implementation notes"
section's port-count footnote below.

### QHAD — `opcode[31:27] qubit[26] half[25] (unused[24:0])`

A classical Hadamard-gate mix on one qubit: `new_alpha=(alpha+beta)*k`,
`new_beta=(alpha-beta)*k`, `k=1/sqrt(2)` (float32 `0x3F3504F3`),
applied component-wise to each amplitude's Re/Im. `qubit` selects
which qubit's Hadamard butterfly (`q0`'s pairs differ only in bit 0,
`q1`'s pairs differ only in bit 1); `half` selects which of the 2
independent pairs for that qubit. Both bits are always meaningful (all
4 encodings assigned) - no illegal case, same style as `GLUON`'s
fully-populated `funct` field.

| `qubit` | `half` | Pair mixed |
|---|---|---|
| 0 | 0 | `amp0` <-> `amp1` |
| 0 | 1 | `amp2` <-> `amp3` |
| 1 | 0 | `amp0` <-> `amp2` |
| 1 | 1 | `amp1` <-> `amp3` |

**Deliberate, documented semantic concession**: a *real* single-qubit
Hadamard touches BOTH independent pairs for that qubit at once (all 8
registers); one `QHAD` instruction only mixes ONE pair (4 registers) -
software applies a full single-qubit Hadamard by issuing `QHAD` twice
(once per `half` value). This keeps the instruction's own register
footprint within the same 4-register/5-cycle shape `QCNOT` needs,
rather than doubling the sequencer's complexity for a single opcode.

### QCNOT — `opcode[31:27] ctrl[26] (unused[25:0])`

A classical CNOT: swaps the two amplitudes that share `ctrl`'s qubit
value = 1 (a real CNOT's control=0 branch is identity - nothing to
represent - so with only 2 qubits there are exactly 2 real
(control,target) assignments, both meaningful, no illegal case).

| `ctrl` (control qubit) | Swap |
|---|---|
| 0 (`q0`) | `amp1` <-> `amp3` (`r2,r3` <-> `r6,r7`) |
| 1 (`q1`) | `amp2` <-> `amp3` (`r4,r5` <-> `r6,r7`) |

Pure register move, no arithmetic - the 5-cycle floor here is entirely
the write-port constraint, not computation.

### QMEASURE — `opcode[31:27] qubit[26] nd[25:23] (unused[22:0])`

A classical probabilistic measurement of one qubit: computes that
qubit's outcome-0 probability, draws a random sample, collapses the
state vector to the surviving 2-amplitude group (renormalized back to
unit probability), zeroes the losing group, and reports the 1-bit
outcome (zero-extended) to N-bank register `nd`. Unlike `QHAD`, there
is no `half` field - computing `P0` inherently sums over both
amplitudes sharing the qubit's 0-value, so `qubit` alone determines
both outcome groups (all 8 `R` registers are touched every time):

| `qubit` | Outcome-0 group | Outcome-1 group |
|---|---|---|
| 0 (`q0`) | `amp0`(`r0,r1`), `amp2`(`r4,r5`) | `amp1`(`r2,r3`), `amp3`(`r6,r7`) |
| 1 (`q1`) | `amp0`(`r0,r1`), `amp1`(`r2,r3`) | `amp2`(`r4,r5`), `amp3`(`r6,r7`) |

**Algorithm**: `P0 = |A0|^2 + |A1|^2` (outcome-0 group), `P1 = 1-P0`;
draw a uniform float32 `r` in `[0, 1-2^-23]` from a new hardware LFSR
(see below); `outcome = 0` iff `r < P0` (else `1`) - standard
inverse-CDF sampling, so `P(outcome=0)=P0` exactly, including the
`P0=0` tie always correctly yielding outcome=1. The surviving group is
rescaled by `1/sqrt(P_survived)` (real `fp_sqrt` then `fp_div`, both
new multi-cycle units ported from `rv32i_core`'s RV32F FDIV.S/FSQRT.S
work) so its total probability returns to 1.0; the losing group's 4
registers are explicitly zeroed rather than left stale.

**Random source**: a new free-running 32-bit Fibonacci XOR-LFSR
(`rtl/lfsr.v`, taps `[32,22,2,1]`, fixed nonzero seed), clocked
unconditionally (not gated by `cpu_stall`/`halted_r` - its value's
relationship to instruction timing is itself part of what makes it
unpredictable in practice). Converted to a uniform float32 by taking
the LFSR's top 23 bits as the fraction of a fixed-exponent value in
`[1.0,2.0)`, then subtracting `1.0` (exact, via the shared
`fp_addsub`) - no subnormal/precision edge case, since `[1,2)` has
exactly `2^23` evenly-spaced representable float32 values.

**Documented, deliberate limitation**: this is a real LFSR, not a
CSPRNG - deterministic given its fixed seed, `2^32-1` period, and
successive draws are linearly correlated (recoverable via
Berlekamp-Massey). Honest and sufficient for a classical *simulator's*
measurement flavor - the same "not real quantum hardware" framing this
whole extension already carries - but must never be described as
cryptographically rigorous, and software should not rely on it for
anything security-sensitive.

**Real cost: 96 cycles** (~108 since v2.2's two-stage FPU) (register reads + probability computation +
RNG draw/compare ≈10, `fp_sqrt` ≈27, `fp_div` ≈51, 8 register writes),
dominated (~81%) by the sqrt/div hardware - a real, bounded,
deterministic cost, the same category as RV32I's own FDIV.S.

**IRQ-deferral note, with an extra wrinkle beyond `QHAD`/`QCNOT`**: an
IRQ arriving anywhere during `QMEASURE`'s ~108-cycle sequence is held
pending until the sequence completes, exactly like `QHAD`/`QCNOT`
(see "Traps" below) - this alone prevents `RFT` from re-executing the
instruction against its own already-mutated registers. But `QMEASURE`
has a second, independent reason this matters: its LFSR keeps
advancing every single cycle regardless of `cpu_stall`, so an
undeferred IRQ would make a re-executed attempt draw a *different*
random sample than the aborted one - a silent non-reproducibility bug
layered on top of the register-corruption class `QHAD`/`QCNOT` already
guard against.

**Inherited FPU-scope limitation**: if the state vector fed to
`QMEASURE` is itself degenerate or mis-normalized (e.g.
`P_survived` underflows to an exact `0.0`), `fp_div(1.0, 0.0)` yields
`+Inf` and the subsequent `fp_mul(0.0, +Inf)` hits `fp_mul.v`'s own
zero-check first, silently returning `0` instead of `NaN`. This is the
same accepted scope limitation `QHAD`/`QCNOT` already carry from
reusing `fp_addsub.v`/`fp_mul.v` (normal-finite-or-zero inputs only),
not a new gap introduced by `QMEASURE`.

## Traps (interrupts + privileged/user mode)

AxISA v0.1's second execution mode: a single hardware `mode` bit
(`0`=user, `1`=kernel - NOT a register-bank value, exactly like `pc`/
`halted_r` are CPU-control state rather than data), reset to kernel.
On any trap, hardware atomically: latches `epc <= pc` (the trapping
instruction's own address for synchronous causes), `cause <= <code>`,
`saved_mode <= mode`, `mode <= kernel`, `saved_ie <= ie`, `ie <= 0`,
then jumps to a **fixed** hardware address, `TRAP_VECTOR_ADDR` (a
build-time constant for v0.1, not a configurable register - there is
only ever one thing that would want to reprogram it, so a writable
vector is deferred until that stops being true).

Cause codes (3 bits, in the `CAUSE` special register):
`000`=illegal instruction, `001`=`SYSCALL`, `010`=external interrupt,
`011`=privilege violation (`RFT`/`MVSR`/`PTB`/`SU3MUL`/`PLAQ`/`LINKMUL`/`REUNIT` executed in user mode),
`100`=page fault (see "Virtual memory" below), `101`=tag fault (v2.1, see "Memory tagging"), `110`-`111` reserved.

**Illegal instruction** reuses the ALREADY-EXISTING `illegal` decode
signal (reserved ALUR/ALUI funct, reserved BARYON/MESON funct, or an
unrecognized opcode) - previously computed and silently dropped
(`reg_write` just stayed 0, PC advanced as if it were a NOP, with zero
observable signal anything unusual happened). This is the cheapest
possible trap cause to wire up, since it needs no new instruction
encoding, and the first one this project actually implemented/tested.

**External interrupt** (`irq_in`, a new top-level `cpu_core` input) is
masked by `ie` (cleared on trap entry, restored by `RFT`) - required,
not just sufficient: without it, a second external IRQ arriving while
a handler is still running would clobber `epc`/`cause` before `RFT`
consumes them, silently losing the first trap's return address. This
does **not** protect against a **synchronous** double-fault (the
handler itself executing a reserved opcode or another `SYSCALL` before
its own `RFT`) - exceptions are conventionally never maskable by `ie`,
so handler code must not itself trigger a synchronous trap before
`RFT`. This is an explicit v0.1 policy, not a silently-assumed
invariant - real hardware would need nested-trap support (a trap
stack, or at minimum a second EPC/CAUSE pair) to handle this safely,
deferred to v0.2+.

An instruction that takes a trap never commits its register write -
`epc` points at it, so `RFT` will execute it again. (Until v2.0 an
external IRQ landing on an ordinary instruction let its write through
as well, so it effectively ran twice after `RFT`; every IRQ test now
checks that the instruction at `epc` left no trace.)

A pending external IRQ that arrives while a `LOAD`/`STORE` is stalled
waiting for `bus_grant` (see `SHARED_MEM_BASE`) is held pending and
only actually redirects `pc` once the stall clears - the stalled
access is never aborted mid-flight, so interrupt latency is bounded by
stall duration rather than needing a new "abort a grant" concept. The
same deferral applies to an in-flight `QHAD`/`QCNOT`/`QMEASURE`/`STRING`/`SU3MUL`/`PLAQ`/`LINKMUL`/`REUNIT`/`METRO`/`REGGE` (see
above) - an IRQ arriving anywhere during the sequence (12 cycles for
`QHAD`, 5 for `QCNOT`, ~108 for `QMEASURE`), including exactly on its terminal
write cycle, is held pending until the whole sequence completes, not
taken against the instruction's own address (which would make `RFT`
re-execute the entire sequence from scratch, reading its own
already-mutated registers as fresh inputs - and for `QMEASURE`
specifically, drawing a different random sample than the aborted
attempt, since its LFSR never stops advancing).

## Virtual memory

AxISA now translates a user-mode `LOAD`/`STORE`'s address against a
page table (`rtl/mmu.v`) instead of using it directly - the first real
memory *isolation* this ISA has, layered on top of the trap/privilege
*mechanism* above (a genuine improvement possible only because that
mechanism already exists: a page fault is delivered as an ordinary
synchronous trap, `CAUSE`=`100`, recoverable via the handler's own
`RFT` - unlike `rv32i_core`'s own MMU, built before that project had
any trap infrastructure, whose page faults freeze the core forever
with no way back).

**Scope** - only the core's own **private** `data_mem` is translated.
Kernel mode (`mode`=`1`) **always** bypasses translation entirely, not
just by convention: the kernel would otherwise need its own page table
correctly mapped before it could ever build one, a bootstrap problem
with no clean answer. The shared-bus window (`SHARED_MEM_BASE`) and
the UART addresses are decoded on the **raw** address before the MMU
is ever consulted, exactly as before - a translated access can never
alias either one.

**Page table** - a single flat, single-level table (not a 2-level
walk: AxISA's private memory is currently only 2 pages, so a second
level would be solving a problem this address space doesn't have),
`2^PT_INDEX_BITS` (default 16) 32-bit PTEs, indexed by
`vaddr[PT_INDEX_BITS+11:12]`. Any virtual address whose bits *above*
that index field are nonzero faults immediately - it can never
silently wrap or alias into the table's own first entries. PTE format
(byte layout identical to `rv32i_core/rtl/mmu.v`'s own, deliberately,
for zero new design cost): `[31:12]`=PPN (physical page number),
`[2]`=W (writable), `[1]`=R (readable), `[0]`=V (valid).

**No TLB** - a single-level table is only a 1-cycle-extra walk away,
so a real associative cache buys little a "fill once, use it, forget
it" single scratch entry doesn't already give for free. A fresh
translation costs a few extra stall cycles (walk + fill); re-touching
the *same* page on the very next access is free (folded into the
current instruction's own single cycle); touching a *different* page
re-walks from scratch every time - a deliberate v0.1 simplification,
not an oversight, and cheap to add real caching to later without any
ISA-visible change.

**Page fault** (`CAUSE`=`100`) fires on: a translation miss with
`V`=`0`, a permission mismatch (a `STORE` against a read-only page, or
a `LOAD`/`STORE` against a page whose target PPN maps outside the
private memory's real size), or a virtual address whose upper bits
exceed the table's own index range. `EPC` captures the faulting
`LOAD`/`STORE`'s own address (not yet advanced), exactly like every
other synchronous trap - the handler must itself advance `EPC` (via
`MVSR`) before `RFT` if it wants to skip rather than retry the
instruction (e.g. after fixing up the page table for a legitimate
lazily-mapped page).

Changing `PTB` (a `PTB` write) invalidates the single cached
translation - the table it points at may no longer agree with
whatever was last cached.

**Still no protection against a kernel-mode access** - `PTB`
write access is privileged, but kernel code, once running, can address
its own private memory directly with no page table at all (by design -
see "Scope" above). Multiple independent address spaces (one page
table per process) are possible today by swapping `PTB` on a context
switch, but there is no process/scheduler concept in v0.1 to drive
that - a real v0.2+ project, not a small follow-on to this one.

### JALR — `opcode[31:27] nd[26:24] ns[23:21] imm[20:0]` (v2.1 step 2)

`nd = PC + 4`, `PC = (N[ns] + sign_extend(imm)) & ~3`. Both registers are
in `N`. `ns` is read before `nd` is written, so `nd = ns` works.

Until v2.1 AxISA only had `JAL`, whose target is a fixed offset — so a
function could never return to more than one caller, and there could
be no libraries. `JALR` is the missing half of a function call:
`JAL N7, func` calls, `JALR N0, N7` returns, `JALR N7, Nk` calls through
a function pointer. The assembler accepts a label as an `ADDI`
immediate (its absolute address) to build such pointers.

### ABI — calling convention (v2.1)

| Register | Role | Who saves it |
|----------|------|--------------|
| `n0` | zero | — |
| `n1` | argument / return value | caller |
| `n2`–`n5` | scratch | caller (a function may clobber them) |
| `n6` | stack pointer (grows down) | callee (must be preserved) |
| `n7` | return address (`JAL N7, f` / `JALR N0, N7`) | caller |

A trap handler may use no register without saving it first (it can't
know what the interrupted code was doing) — `sw/hmalloc_test.axasm`'s
handler stores and restores `n3`/`n4`.

Assembler support added with it: `.include "file"` (relative to the
including file) to share code such as `sw/lib/hmalloc.axasm`.

## Hardened malloc (v2.1 step 2)

`sw/lib/hmalloc.axasm` — `malloc` / `free` in AxISA assembly, following
GrapheneOS's hardened_malloc on the v2.1 MTE hardware. One size class:
16 slots of 16 bytes (one granule each) at `0x800`–`0x8FF`; requests over
16 bytes get 0. Kernel mode (it uses `STG`/`LDG`).

- **Out-of-line metadata.** The in-use bitmap (`0x700`) and each slot's
  previous allocation tag (`0x710 + 4i`) live away from the heap, so
  overflowing a block can never corrupt the allocator.
- **Randomized slot choice** — the scan starts at a random slot (`IRG` is
  the program's window onto the hardware LFSR).
- **Tags.** Every allocation gets a fresh random tag that is never 0,
  never equal to either neighbour's tag (an overflow into the next slot
  *always* faults, not with probability 14/15), never the tag the slot
  had while free, and never the slot's previous allocation tag.
- **`free`** zeroes the block, then retags it with a tag that differs
  from the freed pointer's and from both neighbours', so every stale
  pointer faults (use after free).
- **`free` validates** its argument: outside the heap or not the start
  of a slot → returns 1; slot not in use, or the pointer's tag doesn't
  match (a double free, or a stale pointer to a slot that has since been
  handed out again) → returns 2. A real allocator would abort the
  program; returning a code lets the test check each case.

`sw/hmalloc_test.axasm` exercises all of these, then fills the heap and
runs 200 rounds of free + malloc; `tb/tb_hmalloc.v` monitors every one of
the ~420 `STG`s into the heap and checks each tag rule as an invariant.
Not done (honest limits): one size class only, and no MMU guard pages
— the kernel-mode allocator bypasses translation, so per-granule tags
are the guard instead.

## Memory tagging (v2.1 step 1, MTE-style)

Modelled on ARM's Memory Tagging Extension. It catches the two most
common memory-safety bugs in C-style code — writing past the end of an
allocation, and using memory after it was freed — in hardware, on the
access itself.

- **Pointer tag.** Bits `[31:28]` of every `LOAD`/`STORE` address are a
  4-bit tag, not address bits: they are stripped before any address
  decode (UART, shared window, MMU, data memory), like ARM's
  top-byte-ignore. Addresses are therefore 28 bits. Tag 0 means
  "untagged", so every program from before v2.1 runs unchanged.
- **Memory tag.** Every 16-byte **granule** of the private data memory
  has a 4-bit allocation tag in a separate tag memory (512 granules for
  the default 8 KB; reset value 0).
- **Check.** A `LOAD`/`STORE` to private data memory compares the
  pointer's tag with the tag of the **physical** granule it touches —
  after MMU translation in user mode. On a mismatch it traps with
  **`TAG_FAULT` (CAUSE `101`)**: nothing is written to memory or to the
  destination register, and `epc` points at the access. The UART
  addresses and the shared NoC window are not tagged.

`MTAG` — `opcode[31:27] funct[26:25] nd[24:22] ns[21:19] (unused[18:0])`,
pointers are `N` registers:

| `funct` | Assembler | Effect | Mode |
|---------|-----------|--------|------|
| `00` | `IRG nd, ns` | `nd = ns` with a random **nonzero** tag from the hardware LFSR | any |
| `01` | `STG ns` | the granule `ns` points at gets `ns`'s tag | kernel |
| `10` | `LDG nd, ns` | `nd = ns` with its tag replaced by the granule's tag | kernel |
| `11` | — | reserved → `ILLEGAL` | |

`STG`/`LDG` name a granule by physical address, so they are
kernel-only (privilege violation in user mode — tagging user memory
goes through the kernel), and the address must be inside the tag
memory (`< DATA_MEM_WORDS·4`, so not the shared window) or `ILLEGAL`.

How an allocator uses it: `IRG` a fresh tag for the new block, `STG`
each of its granules, hand out the tagged pointer. An overflow into the
next block hits a granule with a different tag; after `free`, retagging
the block makes every old pointer fault. With 15 possible tags a bug
escapes detection with probability 1/15 — like ARM MTE this is a
bug-catcher, not an isolation boundary (that's the MMU's job).

`sw/mte_test.axasm` shows exactly these: a tagged store/load, a stale
untagged pointer, an overflow past the granule, `LDG`, use-after-free
after retagging, the untagged UART window, and the illegal/privileged
cases. `sw/mte_mmu_test.axasm` proves the check uses the translated
physical granule.

The `cpu_core` parameter `MTE_ENABLE` (default 1) can be set to 0 for
area-constrained builds: the tag memory (`DATA_MEM_WORDS` bits — an
eighth of the data memory) and every check disappear, `LDG` reads tag
0 and `STG` does nothing.

## Reserved `funct` behavior (decided ahead of RTL, per design review)

A reserved `funct` value on ALUR/ALUI (`4'b1010`-`4'b1111`), BARYON
(`3'b100`-`3'b111` since v2.0), or MESON (`2'b11` since v2.0) is decoded as
`illegal` and blocks `reg_write` entirely - this is an explicit,
written decision, not left to "whatever the combinational logic's
`default` arm happens to compute" (an earlier version of this project
had a comment on `alu.v` claiming `control_unit` already covered this
for ALUR/ALUI when it actually didn't - fixed by adding the real
check, not by softening the comment). GLUON has no reserved `funct` -
all 8 codes are defined (real QCD has exactly 8 gluons), so there is
nothing to reject on that ground. (v2.0: GLUON now has illegal cases, but they come
from the color rules — wrong-color or colorless source — not from a
reserved `funct`; all 8 gluon codes are still defined.)

## Explicitly deferred to v0.2+ (not blocking a first working core)

- Additional BARYON/MESON `funct` combine rules and antiquarks landed
  in v2.0 step 2, quark flavor in step 3, asymptotic freedom (`STRING`)
  in step 4 (see "What's new in v2.0").
- BRANCH/JAL immediates could be treated as pre-shifted by 2 (like
  RV32I's own branch/jump immediates), doubling their real-world range
  (±32KB→±64KB, ±8MB→±16MB) for free, since the bottom 2 bits of any
  4-byte-aligned target are always zero anyway - not done in v0.1
  since the current range is already generous and this isn't fixing
  anything broken.
- UART RX (see `cpu_core.v`'s `UART_RX_DATA_ADDR`/`UART_RX_READY_ADDR`)
  has NO real FIFO or overrun flag - the testbench driving it is
  currently the sole, fully-cooperative source of RX stimulus, and it
  waits for software's ready-clear (`uart_rx_ack`) before ever
  presenting the next byte. This is honest and sufficient for
  Icarus-only, script-driven testing, but stops being true the moment
  input becomes genuinely asynchronous (a real keyboard/PTY bridge, or
  real hardware where the serial line runs on its own clock) - a real
  FIFO with an overrun flag is a real v0.2+ requirement, not an
  oversight, the day this needs to run interactively.

## Implementation notes (register file design, decided ahead of RTL)

Confirmed by design review before any RTL was written:

- **Port count**: 2 read ports + 1 write port per bank is provably
  sufficient for every instruction in this spec - no single
  instruction ever needs a 3rd simultaneous access to one bank (worked
  out by checking peak per-bank demand across every format: ALUR/
  BRANCH need 2R+1W or 2R+0W to one bank; GLUON (v2.0) needs only 1R
  from one bank + 1W to one bank; BARYON needs only 1R from each of R/G/B plus
  1W to N; LOAD/STORE/JAL/HALT all need less). **This claim is true
  PER CYCLE, not per instruction** - `QHAD`/`QCNOT` (see above) each
  need 4 registers of the `R` bank across their whole 5-cycle sequence,
  and `QMEASURE` needs all 8 across its ~96-cycle sequence, spread
  across multiple cycles via a dedicated multi-cycle sequencer in
  `cpu_core.v` rather than exceeding the port count in any single
  cycle. They are the first instructions in this ISA that need more
  than one cycle to retire. `QMEASURE` additionally needed a second,
  independent write path into the `N` bank (mirroring the one already
  built for `R`) to report its 1-bit outcome mid-sequence, since the
  normal opcode-decoded write path is driven by a static decode of the
  frozen instruction and can't fire partway through a sequencer's own
  run.
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
