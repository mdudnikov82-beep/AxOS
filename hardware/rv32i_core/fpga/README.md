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
