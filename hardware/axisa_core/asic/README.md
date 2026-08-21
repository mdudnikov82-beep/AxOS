# AxISA ASIC synthesis (OpenLane2 / sky130)

Step 2 of the AxISA-to-ASIC roadmap ([[project_axisa_synthesis_check]]
in project memory has the full FPGA-side history this follows on
from). Step 1 (a bare OpenLane2 + sky130 smoke test on GitHub Actions,
`.github/workflows/openlane-smoke-test.yml`) already confirmed the
toolchain itself stands up cleanly with no local Docker/WSL needed.

This step pushes `cpu_core` (AxISA's real single-cycle core, same
module the FPGA flow already synthesizes) through OpenLane2's default
RTL-to-GDSII flow against the open SkyWater sky130 PDK - a completely
different target than the FPGA work (real standard cells + real
place/route/DRC/LVS signoff, no vendor block-RAM/LUT primitives at
all).

`config.json` is deliberately minimal (`DESIGN_NAME`, `VERILOG_FILES`,
`CLOCK_PORT`, `CLOCK_PERIOD` - the same 4 fields OpenLane's own
quickstart doc calls the bare minimum) - no PDN/pin-order/floorplan
tuning yet. `CLOCK_PERIOD` is set conservatively (50ns = 20MHz) for
this first attempt specifically to separate "does the flow complete
at all" from "what's the real achievable Fmax" - exactly the same
reasoning `nextpnr-ecp5 --freq` used on the FPGA side (an input
target to report slack against, not a hard requirement).

## Known open questions for this first attempt (not yet answered - see real results before assuming either way)

1. **`instr_mem.v`'s X-optimism collapse risk.** `INSTR_INIT_FILE` is
   left at its default (`""`, no program loaded) for this first pass -
   OpenLane's synthesis step is Yosys-based, so the SAME collapse this
   project already hit on the FPGA side (an empty ROM lets the
   optimizer prove most of the datapath "unreachable" and deletes it -
   see `instr_mem_worstcase.v`'s own header comment) could happen
   here too. Deliberately not pre-solved - the FPGA fix required a
   real loaded program via a wrapper module, and doing that here needs
   knowing how OpenLane's Yosys step resolves `$readmemh` paths (its
   own sandboxed run directory, not necessarily this design's own
   `src`-relative convention) - worth learning from a real error
   rather than guessing.
2. **No SRAM macro** - `instr_mem`/`data_mem` will synthesize as plain
   flip-flops via `sky130_fd_sc_hd`, not any kind of on-chip memory
   macro (sky130 has no direct standard-cell equivalent to ECP5's
   DP16KD - a real memory macro would need OpenRAM or a pre-hardened
   SRAM IP, a separate, later step). Expected to be a real area cost,
   not a bug - full instr_mem+data_mem flip-flop area is a known
   quantity to measure once the flow completes at all.
3. **`CLOCK_PERIOD`/floorplan sizing are first guesses** - real timing
   closure and utilization tuning is expected to take iteration once
   there's a first successful run to react to.
