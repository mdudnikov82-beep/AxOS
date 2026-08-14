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

## IMPORTANT: `instr_mem.v` now has a registered-read mode (2026-08-14)

`rtl/instr_mem.v` gained a `SYNC_READ` parameter (default 0, old
combinational-read behavior unchanged) and a `clk`/`stall` port pair -
`cpu_core.v` now instantiates it with `SYNC_READ=1`, because the
original combinational read was found to fail ECP5 block-RAM
inference entirely at this depth (1024 words) and silently fall back
to ~32,000 wasted flip-flops instead of real memory - see
[[project_axisa_synthesis_check]] and [[project_router_pipelining]]-
adjacent session notes for the full investigation. `instr_mem_worstcase.v`'s
port list was updated to match (still blackboxed - `SYNC_READ`'s
actual value doesn't matter to a blackbox, only the port list needs to
line up for elaboration to succeed).

## Honest worst-case FPGA area estimate (Lattice ECP5 target)

Use `instr_mem_worstcase.v` INSTEAD of `../rtl/instr_mem.v` (same
module name, blackboxed - see its own header comment for why this is
necessary, not optional: a real program-loaded or empty instr_mem
both cause Yosys to prune most of the datapath as "unreachable").

```
yosys -p "read_verilog ../rtl/alu.v ../rtl/regbank.v instr_mem_worstcase.v ../rtl/data_mem.v ../rtl/control_unit.v ../rtl/mmu.v ../rtl/cpu_core.v cpu_core_fpga_top.v; synth_ecp5 -top cpu_core_fpga_top -flatten; stat"
```

Last confirmed result (2026-08-10, PRE registered-fetch redesign):
~10,587 cells (6968 LUT4, 1088 TRELLIS_DPR16X4, 2219 muxes, 165 CCU2C,
137 FFs). Not yet re-measured against the current `SYNC_READ=1` core -
worth doing before citing a current worst-case number, since the
fetch-stage redesign changed real logic (pc_r/squash_r), not just the
memory's own mapping.

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

**CAVEAT (2026-08-14): the 946 TRELLIS_COMB/40 FF/83.42MHz numbers
below are STALE and not reliably reproducible even on the PRE-redesign
RTL** - a same-toolchain re-check found they depend on a
memory-mapping fallback (`using FF mapping for memory...`) that
doesn't reproduce consistently. Do not cite them as a stable baseline
without re-measuring.

**Post registered-fetch-redesign `synth_ecp5` result (2026-08-14,
confirmed - this run's own conclusion, not carried over)**: the
combinational-read ROM's `using FF mapping` fallback is CONFIRMED
GONE - `instr_mem` now maps to **2 real DP16KD block RAMs**, exactly
the honest, correctly-inferred result this redesign was for:
- **7,491 LUT4, 179 CCU2C, 1,344 L6MUX21, 2,577 PFUMX, 1,088
  TRELLIS_DPR16X4 (register banks - unchanged), 170 TRELLIS_FF**
- **2 DP16KD block RAMs** (instr_mem's real 1024x32 ROM, finally
  mapped correctly instead of exploding into flip-flops)
- `Found and reported 0 problems.`

A full `nextpnr-ecp5` place-and-route re-run (for a fresh Fmax number)
was attempted this session but could not be completed locally after
several attempts, each killed by an external session-management
interruption partway through placement (not a design/timing failure -
placement was progressing normally each time, into the simulated-
annealing refinement stage). Re-run the command above (ideally via a
long-lived environment like GitHub Actions, following this project's
established pattern for multi-minute EDA jobs) to get a current Fmax
figure before citing one.

This is genuine physical synthesis on a real target device family -
not a generic/no-device area estimate. See
[[project_axisa_synthesis_check]] in project memory for the full
investigation, including the registered-fetch redesign that produced
this result.
