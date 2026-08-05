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
| `01010`          | RFT      | return from trap (privileged)             |
| `01011`          | SYSCALL  | deliberate trap (user→kernel door)        |
| `01100`          | MVSR     | move to/from trap state (privileged)      |
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
AxISA has no indirect-jump instruction (`JAL`'s target is always a
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
`011`=privilege violation (`RFT`/`MVSR` executed in user mode),
`100`-`111` reserved.

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

A pending external IRQ that arrives while a `LOAD`/`STORE` is stalled
waiting for `bus_grant` (see `SHARED_MEM_BASE`) is held pending and
only actually redirects `pc` once the stall clears - the stalled
access is never aborted mid-flight, so interrupt latency is bounded by
stall duration rather than needing a new "abort a grant" concept.

**No memory protection in v0.1** - the mode bit and 2 privileged
instructions (`RFT`, `MVSR`) prove the trap/privilege *mechanism*,
they do not yet provide real isolation: user-mode code can `LOAD`/
`STORE` anywhere kernel-mode code can, including the UART and
shared-bus ranges. An MMU/page-table concept is a real, separate,
much larger v0.2+ project, not a small follow-on to this one.

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
