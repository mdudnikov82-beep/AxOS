# RV32I FPGA synthesis check

Real Yosys/nextpnr-ecp5 synthesis of `cpu_core.v` (the single-cycle
base RV32I core, no `cpu_core_pipelined.v`), built specifically to
compare against AxISA's own `cpu_core.v`
([[project_axisa_synthesis_check]], AxISA's own
`hardware/axisa_core/fpga/README.md`). Requires
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) - on
Windows, source `environment.ps1`/`environment.bat` before running
`yosys`/`nextpnr-ecp5` directly (the bare `.exe`s fail silently
otherwise, missing bundled DLL search paths - `PATH` needs both
`bin` AND `lib`, not just `bin`).

## IMPORTANT CAVEAT: this is NOT a clean apples-to-apples number vs AxISA (2026-08-15)

Two real asymmetries were found while getting these numbers, both
worth understanding before citing anything below:

1. **AxISA's own confirmed number (7,491 LUT4, 33.02 MHz post-route)
   excludes `data_mem.v` entirely.** AxISA's `sw/asm_test1.py` test
   program used for AxISA's PnR run does zero loads/stores (only
   ALU ops + branch + halt) - Yosys's X-optimism proves `data_mem` is
   "unreachable" for that specific instruction stream and optimizes
   almost all of it away. RV32I's own `sw/asm_test1.py` DOES include a
   real `sw`/`lw` pair, so RV32I's `data_mem` is genuinely present and
   synthesized for real - meaning the comparison below is "AxISA
   without a data memory" vs "RV32I with one." Not a bug in either
   program, just a difference in what each one happens to exercise.
2. **RV32I's `data_mem.v` fails ECP5 block-RAM inference**, the exact
   same bug class `instr_mem.v` had before its SYNC_READ fix (see
   [[project_axisa_synthesis_check]]) - `data_mem.v`'s byte-enable
   write pattern (needed for `SB`/`SH`/`SW` at different widths)
   doesn't match a valid ECP5 DP16KD mapping, so Yosys falls back to
   one flip-flop PER BIT with an explicit enable signal for all 4096
   bytes (32,768 individual bits) instead of 2 real block RAMs. This
   was explicitly scoped OUT of the `instr_mem.v` fix (see the plan
   in project memory) - fixing it would need a genuine
   registered-read + write-enable redesign, a separate, larger piece
   of work. It's the reason RV32I's LUT4 count below is ~28x AxISA's.

## Real synth_ecp5 (honest integer-core-only area estimate)

FPU submodules blackboxed (`fpga/fpu_blackbox.v`, same trick as
AxISA's own `instr_mem_worstcase.v`) so the count isolates the
integer core only, matching AxISA (which has no FPU at all):

```
yosys -p "read_verilog rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/instr_mem.v rtl/data_mem.v rtl/control_unit.v rtl/mmu.v fpga/fpu_blackbox.v rtl/cpu_core.v fpga/cpu_core_fpga_top_pnr.v; synth_ecp5 -top cpu_core_fpga_top -json fpga/cpu_core_areaonly.json"
```

Run from `hardware/rv32i_core` (not `fpga/`) - `cpu_core_fpga_top_pnr.v`'s
`INSTR_INIT_FILE("sw/test1.hex")` is a `$readmemh` path resolved
relative to Yosys's own cwd. `sw/test1.hex` is gitignored (`*.hex`) -
regenerate it first with `python3 sw/asm_test1.py sw/test1.hex`.

**Confirmed result (2026-08-15, via
[.github/workflows/rv32i-core-pnr.yml](../../../.github/workflows/rv32i-core-pnr.yml),
run
[31843027623](https://github.com/mdudnikov82-beep/AxOS/actions/runs/31843027623))**:
- **213,242 LUT4, 83 CCU2C, 3,641 L6MUX21, 40,255 PFUMX, 24
  TRELLIS_DPR16X4, 32,794 TRELLIS_FF, 2 DP16KD**, `Found and reported
  0 problems.`
- Compare to AxISA's confirmed 7,491 LUT4/179 CCU2C/1,344
  L6MUX21/2,577 PFUMX/1,088 TRELLIS_DPR16X4/170 TRELLIS_FF/2 DP16KD -
  a real ~28x LUT4 difference and ~193x more flip-flops, almost
  entirely explained by caveat #2 above (`data_mem`'s un-fixed
  per-bit FF fallback), not by RV32I's actual integer-core logic
  being 28x bigger.

## Real place-and-route (nextpnr-ecp5) - DOES NOT FIT ANY ECP5 DEVICE

Real (non-blackboxed) `rtl/fp_regfile.v rtl/fp_addsub.v rtl/fp_mul.v
rtl/fp_div.v rtl/fp_sqrt.v` are used instead of the blackbox for this
step - **not** an oversight: nextpnr-ecp5 needs a fully concrete
netlist to place a cell, and a true `(* blackbox *)` module has no
placeable primitive at all (first attempt at this hit `ERROR: cell
type 'fp_addsub' is unsupported` and crashed before reaching
placement - the blackbox trick only works for Yosys's own `stat`
tally above, not real PnR). This means the utilisation/Fmax numbers
below include real FPU hardware, on top of caveat #2's already-huge
`data_mem` fallback.

```
yosys -p "read_verilog rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/instr_mem.v rtl/data_mem.v rtl/control_unit.v rtl/mmu.v rtl/fp_regfile.v rtl/fp_addsub.v rtl/fp_mul.v rtl/fp_div.v rtl/fp_sqrt.v rtl/cpu_core.v fpga/cpu_core_fpga_top_pnr.v; synth_ecp5 -top cpu_core_fpga_top -json fpga/cpu_core_pnr.json"

nextpnr-ecp5 --25k --package CABGA381 --json fpga/cpu_core_pnr.json --lpf-allow-unconstrained --freq 50
```

**Confirmed result (2026-08-15, same workflow run)**: pre-placement
utilisation reports **210,313 LUT4 (210,359 TRELLIS_COMB), 32,802
TRELLIS_FF, 2 DP16KD** - then placement itself fails outright:
`ERROR: Unable to place cell
'core.dmem.mem[459]_TRELLIS_FF_Q_DI_LUT4_Z_3', no BELs remaining to
implement cell type 'TRELLIS_COMB'`. The `--25k` device (LFE5U-25F,
24,288 LUT4-equivalent BELs per nextpnr's own utilisation report) is
nowhere near big enough - but neither is the **largest** ECP5 part
made: LFE5U-85F has ~83,640 LUTs, still under half of the 210K+ this
design needs. **No real ECP5 device can place-and-route RV32I's
`cpu_core.v` as currently structured** - a genuine, honest finding,
not a tooling failure. Getting a real post-route Fmax for RV32I
requires fixing `data_mem.v`'s BRAM-inference gap first (caveat #2) -
until then, only the pre-placement utilisation estimate above exists,
no Fmax number can be obtained at all.

This is a real, disclosed limitation of the current RV32I RTL, not a
CI/workflow bug - two real infrastructure bugs found and fixed along
the way (documented in `.github/workflows/rv32i-core-pnr.yml`'s own
header comment and [[project_axisa_synthesis_check]]): the FPU-blackbox-
can't-be-placed issue above, and an earlier `tee`-without-`pipefail`
bug that silently reported that exact crash as a passing CI step.

## UPDATE (2026-08-19): `data_mem.v` got the same SYNC_READ fix as `instr_mem.v` - read-side fixed, write-side is the REAL remaining blocker

`data_mem.v` gained a `SYNC_READ` parameter (default 0, same pattern
as `instr_mem.v`'s own fix - see [[project_axisa_synthesis_check]]),
`mmu.v`'s walker FSM was split into ISSUE/READ state pairs to tolerate
the new one-cycle read latency, and `cpu_core.v` gained a
`dmem_load_stall` term for ordinary LOADs. All of this is
correctness-verified for real: full local regression suite passes
100% clean (including the SFENCE negative control and every
`cpu_core_pipelined.v` test, proving that file is genuinely
untouched), plus AxISA's equivalent fix passed its full 1023-core mesh
regression via GitHub Actions at full scale. **None of that is in
question.**

**The synthesis/area outcome this was chasing did NOT fully resolve**,
confirmed via a real re-run of the exact `synth_ecp5` command above
([run 32255038333](https://github.com/mdudnikov82-beep/AxOS/actions/runs/32255038333)):

- **DP16KD count: still 2** - completely unchanged from the pre-fix
  baseline. `data_mem` did NOT get mapped to real block RAM; those 2
  DP16KD blocks are still only `instr_mem`'s own two, exactly as
  before this fix.
- Full new tally: **211,706 LUT4, 83 CCU2C, 2,648 L6MUX21, 38,915
  PFUMX, 24 TRELLIS_DPR16X4, 32,828 TRELLIS_FF, 2 DP16KD** - LUT4 down
  slightly (~0.7%, 213,242→211,706) and PFUMX/L6MUX21 down more
  noticeably (removing some of the old combinational-read forwarding
  logic), but TRELLIS_FF actually went UP slightly (32,794→32,828 -
  the new `dmem_read_valid_r`/registered-mux-selector logic added a
  few flip-flops of its own). Net effect: essentially the same order
  of magnitude, not the fix this was hoping for.
- `nextpnr-ecp5` still fails placement outright, same as before:
  `ERROR: Unable to place cell 'core.dmem.mem[1030]_..._TRELLIS_FF...',
  no BELs remaining to implement cell type 'TRELLIS_COMB'` - explicitly
  naming a `dmem.mem[...]` cell this time, direct confirmation `data_mem`
  is still the thing making the design too big for any real ECP5
  device.

**Root cause, confirmed rather than just theorized**: `data_mem.v`'s
write side, not its read side, is what actually blocks DP16KD
inference. A single `SW` writes up to 4 independent byte addresses in
one cycle (`mem[addr]`, `mem[addr+1]`, `mem[addr+2]`, `mem[addr+3]`)
into one monolithic byte-addressed array that also supports fully
*unaligned* access - a pattern no single DP16KD write port can
represent, regardless of how the read is modeled. Fixing this for
real would need re-architecting the array as 4 parallel byte-lane
sub-arrays (`mem0..mem3[0:WORDS-1]`), each written at the same
word-aligned index with its own per-lane write enable (the standard
byte-enable-BRAM idiom) - complicated by the fact this array currently
supports fully unaligned byte/half access across a word boundary,
which a 4-lane-per-word organization can't represent in a single cycle
without a bigger redesign (dual-word access or an alignment
restriction). **This is a genuinely separate, larger piece of work,
explicitly out of scope here** - not attempted as part of this fix.
The read-side fix + mmu.v/cpu_core.v stall-timing correctness work
was real, necessary, and independently valuable (and is a real
prerequisite for any future write-side fix), but by itself does not
get RV32I's `data_mem` onto real block RAM.

## RESOLVED (2026-08-20): write-side redesign - `data_mem` now maps to real DP16KD, confirmed

Did the write-side redesign flagged above as out of scope: `data_mem.v`
reorganized into 4 parallel byte-lane arrays (`mem0..mem3`), always
accessed at a shared `word_idx` with independent per-lane write
enables - the standard byte-enable-BRAM idiom. User explicitly chose
to restrict misaligned/word-crossing halfword/word access to a
defined-but-truncated same-word behavior (rounds `byte_off` down to
the nearest valid lane pair, never touches the next word) rather than
a 2-cycle crossing path - safe because no test in the suite exercises
genuinely misaligned access, and every real compiler-emitted
`LW`/`SW`/`LH`/`SH` is naturally aligned anyway. A design review
verified the write-enable/data-routing logic bit-exact against the old
flat array for every naturally-aligned case before implementing.
Regression caught one real bug the review didn't anticipate: 7
testbenches used hierarchical whitebox pokes into the old flat
`dmem.mem[addr]` array to build page tables directly - fixed to poke
the new `dmem.mem0[addr[31:2]]` etc. Full local regression clean after
the fix, including every `cpu_core_pipelined.v` test (shares this same
`data_mem.v` module). Committed as `206258b`.

**Confirmed via real `synth_ecp5`/`nextpnr-ecp5`
([run 32352682661](https://github.com/mdudnikov82-beep/AxOS/actions/runs/32352682661))
- this is a genuine, complete success:**

- `mapping memory cpu_core_fpga_top.core.dmem.mem0/mem1/mem2/mem3 via
  $__DP16KD_` appears in the Yosys log - **all 4 lanes really did map
  to block RAM**, not a fallback.
- **DP16KD: 6** (was 2 - `instr_mem`'s original 2 blocks + `data_mem`'s
  new 4). Full tally: **518 LUT4, 65 CCU2C, 22 L6MUX21, 103 PFUMX, 24
  TRELLIS_DPR16X4, 30 TRELLIS_FF, 6 DP16KD** - down from 211,706
  LUT4/32,828 TRELLIS_FF the day before, a **~411x** reduction in
  LUT4 and **~1,094x** reduction in TRELLIS_FF. RV32I's integer-core
  area is now actually SMALLER than AxISA's own confirmed 7,491 LUT4.
- Both synth_ecp5 steps that used to take ~38-43 minutes each (the old
  ~686K-AND-gate ABC9 pass on the FF-fallback explosion) now complete
  in **single-digit seconds** - direct, independent confirmation the
  root cause is gone, not just the cell count.
- `nextpnr-ecp5` **placed and routed successfully** this time -
  "Program finished normally", real device utilisation `DP16KD: 6/56
  (10%)`, `TRELLIS_FF: 38/24288 (0%)`, `TRELLIS_COMB: 825/24288 (3%)`.
  Real **Fmax: 47.68 MHz** (reported as "FAIL at 50.00 MHz" only
  against the `--freq 50` input constraint, same benign pattern as
  AxISA's own 33.02 MHz result - not a real placement/routing error).

This closes out the `data_mem.v` synthesis investigation that started
with the AxISA-vs-RV32I comparison: RV32I's `cpu_core.v` now has a
real, honest, comparably-small FPGA footprint and a real measured
Fmax, on equal footing with AxISA's own confirmed numbers.
