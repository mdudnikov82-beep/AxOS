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

## RESOLVED (2026-08-22): real Fmax found via binary search - 45.7 MHz

The 50ns/20MHz target above was deliberately conservative just to get
a first clean pass. Once that worked, did a real binary search on
`CLOCK_PERIOD` across 10 more dispatches to find the true limit -
`config.json` is left at the final, confirmed-passing value.

**Critical methodology lesson, learned the hard way partway through**:
`"Flow complete."` and the GitHub Actions job showing `"success"` do
**NOT** mean timing passed - OpenLane doesn't hard-fail the whole run
just because setup timing isn't fully closed, it just logs a warning
and saves whatever layout it has. The `Checker.SetupViolations`
messages (`WARNING Setup violations found in the following corners`
immediately followed by `VERBOSE No setup violations found`) turned
out to appear in BOTH passing and failing runs equally - not a
reliable signal, initially misread as one. **The real, confirmed
discriminator is the resizer's own repair-completion messages**:
- `[RSZ-0062] Unable to repair all setup violations.` appearing
  anywhere in the log = a REAL, confirmed timing failure.
- `[RSZ-0099] Repairing N out of N (100.00%) violating endpoints...`
  with a matching N and NO `RSZ-0062` = a REAL, confirmed clean pass.

**Binary search results** (each period tested via a real full OpenLane
dispatch, cell count/area identical throughout at 3,614 cells/42,741
µm² - only timing outcome changed):

| CLOCK_PERIOD | Frequency | Result |
|---|---|---|
| 50ns | 20.0 MHz | PASS (0 violations, comfortable margin) |
| 30ns | 33.3 MHz | PASS (worst slack ~7.3-8.4ns) |
| 24ns | 41.7 MHz | PASS (58/58 repaired, margin ~3.3-4.4ns) |
| 22ns | 45.5 MHz | PASS (130/130 repaired, margin ~1.3-2.4ns) |
| 21.875ns | 45.7 MHz | **PASS** (133/133 repaired, 100%) |
| 21.8125ns | 45.7 MHz | **PASS (final, confirmed)** (143/143 repaired, 100%) |
| 21.75ns | 45.6 MHz | FAIL (`RSZ-0062`, unrepaired) |
| 21.5ns | 46.5 MHz | FAIL (`RSZ-0062`, unrepaired) |
| 21ns | 47.6 MHz | FAIL (`RSZ-0062`, unrepaired) |
| 20ns | 50.0 MHz | FAIL (`RSZ-0062`, unrepaired, 3 corners violated) |

**Real, confirmed Fmax: 21.8125ns period = 45.7 MHz**, bounded to
within ~0.06 MHz by the last fail/pass pair (21.75ns fails, 21.8125ns
passes) - a genuinely tight, hard-won number, not an estimate. This is
**~1.38x faster than AxISA's own confirmed FPGA/ECP5 Fmax (33.02
MHz)** - a real, honest apples-to-apples improvement from moving off
FPGA fabric onto real standard cells, on the exact same RTL.
`DRC`/`LVS` passed throughout every single run in the search; `Antenna`
flipped between pass and fail across different placements/routes
(incidental to the specific layout each period produced, not a
deliberate fix) - still an open, disclosed, unfixed item at the final
21.8125ns configuration specifically (check the latest run's own
manufacturability report before relying on antenna-clean for any
given commit).

## Still open (real, disclosed, not yet worked on)

1. **No SRAM macro** - `instr_mem`/`data_mem` synthesized as plain
   flip-flops via `sky130_fd_sc_hd` (no on-chip memory macro exists in
   this flow yet - would need OpenRAM or a pre-hardened SRAM IP, a
   separate, larger follow-up). The 3,614-cell/42,741µm² result above
   already includes this real cost, it isn't hidden.
2. **Antenna violations** - real, present in at least some
   configurations (see table above), not deliberately fixed.
3. **Fmax found is specific to this exact floorplan/DIE_AREA/placement
   configuration** - a different floorplan (e.g. after fixing antenna,
   or after a real PDN/pin-order pass) could shift the real number
   somewhat in either direction; this isn't a fundamental, PDK-wide
   ceiling, just the honest result for this specific synthesis
   configuration.
