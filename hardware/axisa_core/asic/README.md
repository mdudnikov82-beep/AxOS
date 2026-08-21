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

## RESOLVED (2026-08-21): first successful AxISA ASIC synthesis - real numbers

Took 5 real dispatches of `.github/workflows/openlane-axisa-synth.yml`
to get here, each hitting a genuinely different, confirmed-from-actual-
log-output problem (not guessed in advance):

1. **`[PPL-0024]` - 157 I/O pins didn't fit the default floorplan.**
   `cpu_core`'s port list (mostly wide 32-bit buses - `tohost_value`,
   `bus_addr`, `bus_write_data`, `bus_read_data`) adds up to 157
   individual pins, and OpenLane's default utilization-driven
   floorplan sizing has no awareness of pin count, only cell area.
   OpenROAD's own error gave the exact number needed: "Increase the
   die perimeter from 324.96um to 533.80um."
2. **`FP_CORE_UTIL` alone did nothing** - the reported required
   perimeter didn't change at all after setting it, because cell area
   was still tiny relative to the fixed pin-count requirement.
3. **`DIE_AREA` alone made it WORSE** (perimeter shrank to 181.58um) -
   `FP_SIZING` defaults to `"relative"` (utilization-driven) and
   silently ignores `DIE_AREA` unless `FP_SIZING` is explicitly
   `"absolute"` - confirmed via OpenLane's own docs, which specifically
   recommend this combination for very small designs. Fixed by setting
   both `"FP_SIZING": "absolute"` and `"DIE_AREA": "0 0 300 300"`.
4. **`instr_mem.v`'s X-optimism collapse - confirmed, not just
   theorized.** With `INSTR_INIT_FILE=""` (no program loaded), Yosys
   proved the fetched instruction was a constant forever and deleted
   almost the entire clocked datapath - directly visible in OpenROAD's
   own log: `Net "clk" has 0 sinks. Skipping...`, `No clock nets have
   been found`, and a `45 critical disconnected pins found` error
   (every output whose driving logic had been optimized away). Same
   bug class already hit and fixed on the FPGA side. Fixed by adding
   `cpu_core_top.v` (a thin wrapper, mirrors
   `fpga/cpu_core_fpga_top_pnr.v`) loading a real program via
   `INSTR_INIT_FILE("../sw/test1.hex")` - **this exact relative path
   worked on the first try**, confirming OpenLane's Yosys step runs
   with a cwd one directory level below `asic/` (i.e. the design's own
   root), matching the same relative relationship as the FPGA flow's
   own convention.

**Confirmed result** (via
[run 32457079870](https://github.com/mdudnikov82-beep/AxOS/actions/runs/32457079870),
commit `0b82257`) - `Flow complete.`, a real, non-collapsed synthesis:
- **3,614 standard cells, 42,741 µm² cell area** inside the 300×300µm
  (90,000 µm²) die - **4,881 real nets** (compare to the collapsed
  attempt's near-zero net count - this is genuinely the whole CPU,
  not a pruned stub).
- **DRC: Passed ✅ / LVS: Passed ✅**
- **Antenna: Failed ✗** - a real, common ASIC signoff issue (long
  wires can act as unintended antennas during fabrication, risking
  gate-oxide damage) - not fixed in this default-config first pass,
  a real, disclosed follow-up (typically antenna diodes or wire-length
  rules), not swept under the rug.
- **Timing: setup MET cleanly** at the 50ns/20MHz target (`No setup
  violations found`) - 683 hold violations were found and
  automatically repaired by inserting 664 hold buffers (a completely
  normal, automatic OpenROAD step, not a design problem) - final
  timing is clean (TNS = 0).
- 41 disconnected pins remain, but the checker itself reports **0
  critical** - these are the legitimately-unconnected top-level
  primary inputs (`bus_grant`, `uart_rx_data_in`, `uart_rx_ready_in`,
  `irq_in`) a standalone core synthesis is expected to leave dangling.

## Still open (real, disclosed, not yet worked on)

1. **No SRAM macro** - `instr_mem`/`data_mem` synthesized as plain
   flip-flops via `sky130_fd_sc_hd` (no on-chip memory macro exists in
   this flow yet - would need OpenRAM or a pre-hardened SRAM IP, a
   separate, larger follow-up). The 3,614-cell/42,741µm² result above
   already includes this real cost, it isn't hidden.
2. **Antenna violations unresolved** (see above).
3. **`CLOCK_PERIOD`=50ns/20MHz was a deliberately conservative first
   guess** - setup timing had comfortable positive slack throughout
   placement (worst slack seen ~23-24ns), suggesting real headroom to
   push the clock period down significantly in a future iteration -
   not yet attempted.
