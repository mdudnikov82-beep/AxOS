# AxISA FPGA synthesis check

Confirms `cpu_core.v` synthesizes to real gates (not just simulates)
and gives an honest worst-case area estimate. Requires
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)
(bundles Yosys) - on Windows, source `environment.ps1` from the
extracted archive before running `yosys` (the bare `.exe` fails
silently otherwise, missing its bundled DLL search paths).

## Confirm synthesizability (no target device, no area numbers needed)

```
yosys -p "read_verilog ../rtl/alu.v ../rtl/regbank.v ../rtl/instr_mem.v ../rtl/data_mem.v ../rtl/control_unit.v ../rtl/mmu.v ../rtl/cpu_core.v; hierarchy -top cpu_core; synth -top cpu_core"
```
Look for `Found and reported 0 problems.` from the CHECK pass.

## Honest worst-case FPGA area estimate (Lattice ECP5 target)

Use `instr_mem_worstcase.v` INSTEAD of `../rtl/instr_mem.v` (same
module name, blackboxed - see its own header comment for why this is
necessary, not optional: a real program-loaded or empty instr_mem
both cause Yosys to prune most of the datapath as "unreachable").

```
yosys -p "read_verilog ../rtl/alu.v ../rtl/regbank.v instr_mem_worstcase.v ../rtl/data_mem.v ../rtl/control_unit.v ../rtl/mmu.v ../rtl/cpu_core.v cpu_core_fpga_top.v; synth_ecp5 -top cpu_core_fpga_top -flatten; stat"
```

Last confirmed result (2026-08-10): ~10,587 cells (6968 LUT4, 1088
TRELLIS_DPR16X4, 2219 muxes, 165 CCU2C, 137 FFs) - comfortably fits a
Lattice ECP5-25 (24K LUT). Plus `instr_mem`'s own fixed ~2 block RAMs
(not included in that count, independent of its content). See
[[project_axisa_synthesis_check]] in project memory for the full
investigation that led to this methodology.

## Real place-and-route (actual physical LUT/FF placement + timing, not just a cell tally)

Requires `nextpnr-ecp5` (also bundled in OSS CAD Suite). Unlike the
area-estimate command above, place-and-route needs a fully concrete
netlist - `instr_mem_worstcase.v`'s blackbox has no implementation for
nextpnr to place, so use `cpu_core_fpga_top_pnr.v` (loads a real
program, `sw/test1.hex`) with the real `../rtl/instr_mem.v` instead:

```
yosys -p "read_verilog ../rtl/alu.v ../rtl/regbank.v ../rtl/instr_mem.v ../rtl/data_mem.v ../rtl/control_unit.v ../rtl/mmu.v ../rtl/cpu_core.v cpu_core_fpga_top_pnr.v; synth_ecp5 -top cpu_core_fpga_top -json cpu_core_pnr.json"

nextpnr-ecp5 --25k --package CABGA381 --json cpu_core_pnr.json --lpf-allow-unconstrained --freq 50
```

(`--lpf-allow-unconstrained` skips real board pin constraints, which
don't exist for this design yet - internal placement/routing/timing
still runs for real either way. `cpu_core_pnr.json` and any
`--textcfg` output are regenerated build artifacts, not committed -
regenerate with the commands above.)

Last confirmed result (2026-08-10), targeting a Lattice ECP5-25F
(LFE5U-25F, package CABGA381):
- **946 TRELLIS_COMB (LUT4-equivalent) / 24,288 available - 3% utilization**
- **40 TRELLIS_FF** (real flip-flops placed)
- **0 DP16KD block RAMs used** - the register banks (16x32 bits) fit
  entirely in distributed RAM (`TRELLIS_RAMW`), no dedicated block
  RAM needed
- **Max frequency: 83.42 MHz - PASS at the 50MHz target clock**
  (real static timing analysis on real routed nets)

This is genuine physical placement, routing, and timing closure on a
real chip - not an area estimate. 97% of the chip is still free at
this size. See [[project_axisa_synthesis_check]] in project memory
for the full investigation.
