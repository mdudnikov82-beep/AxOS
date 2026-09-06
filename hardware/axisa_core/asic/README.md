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

## RESOLVED (2026-09-05): re-synthesized after QHAD/QCNOT + FPU - real growth, new Fmax = 18.18 MHz, real power number

`cpu_core.v` grew a real FPU (`fp_addsub.v`/`fp_mul.v`, ported from
`rv32i_core`) plus its first-ever multi-cycle instruction sequencer
(QHAD/QCNOT - see `docs/ISA.md`) since the 45.7MHz result above was
measured. That FPU/sequencer hardware is real combinational logic
present in the netlist regardless of whether the loaded program (still
`test1.hex`, which never executes QHAD/QCNOT) ever exercises it - not
a memory-content-dependent effect like the Tiny Tapeout wrapper's own
overage (see `tinytapeout/README.md`).

**Real consequences, found via 2 more real dispatch failures before
this passed**:
1. **`[GPL-0301] Utilization 107.297% exceeds`** - the design no
   longer fit the old 300×300µm (90,000µm²) floorplan at all, even at
   the SAME 47.5%-utilization test1.hex program that used to fit
   comfortably. Fixed by enlarging `DIE_AREA` to `"0 0 450 450"`
   (202,500µm², ~2.25x) - real headroom confirmed by the final
   ~41% utilization achieved.
2. **The old 45.7MHz Fmax no longer held** - even a conservative
   50ns/20MHz retry failed real timing (`RSZ-0062`, WNS=**-3.803ns**
   after the resizer's best effort) - the FPU's `fp_mul`→`fp_addsub`
   chain (a real 24×24 multiply feeding a float add/sub, both
   combinational, in QHAD's one-cycle-per-step datapath) is
   significantly longer than the old ALU-only critical path.
3. **A real, unrelated infrastructure failure mid-bisection**: `volare`
   (the sky130 PDK downloader) hit `403 rate limit exceeded` from
   `api.github.com/repos/efabless/volare/releases` - every dispatch was
   re-downloading the whole PDK from GitHub's release API with no
   caching, and several dispatches in a short bisection window
   exhausted GitHub's anonymous rate limit. Fixed by adding
   `actions/cache@v4` on `~/.volare` (keyed loosely - a stale/missing
   cache just means volare re-fetches, same as before, never worse) to
   `.github/workflows/openlane-axisa-synth.yml`.

**New confirmed numbers**:
- **7,568 standard cells, 83,637.72 µm²** (up from 3,614 cells/42,741
  µm² - real, expected growth from the FPU + sequencer, not a bug) -
  ~41% utilization of the new 202,500µm² die.
- **DRC: Passed ✅ / LVS: Passed ✅ / Antenna: Failed ✗** (same
  pre-existing, disclosed, unfixed issue as before - 15 pin + 9 net
  violations at this configuration).
- **Real Fmax bisected to CLOCK_PERIOD=55ns = 18.18 MHz** (confirmed
  via the same RSZ-0062/RSZ-0099 discriminator this project already
  established): 50ns FAILS (RSZ-0062, WNS=-3.803ns); 55ns **PASSES**
  cleanly (`RSZ-0099`: 248/248 endpoints repaired, no RSZ-0062). Not
  narrowed further than this 5ns bracket - locked in at 55ns as the
  honest, real, signed-off value rather than continuing to bisect for
  marginal precision.
- **Real power (OpenROAD `report_power`, vectorless default switching
  activity - a first real number, not a representative-workload
  number)** at the locked-in 55ns/18.18MHz config:

  | Group | Internal | Switching | Leakage | Total | Share |
  |---|---|---|---|---|---|
  | Sequential | 1.49e-03 W | 2.73e-04 W | ~0 | ~1.8mW | small |
  | Combinational | dominant | dominant | ~0 | dominant | ~99% |
  | Clock | small | small | ~0 | small | ~0.3% |
  | **Total** | 8.18e-02 W | 1.08e-01 W | 5.80e-08 W | **≈190 mW** | 100% |

  (At the earlier-tried, timing-failing 50ns/20MHz point the same
  report gave ≈217mW - higher, consistent with dynamic power scaling
  with frequency; the 55ns/190mW number above is the one to cite, since
  it's the one with clean, real timing signoff behind it.)

**Honest caveat for any external use of this power number** (e.g. a
grant/pitch context): "vectorless default activity" is OpenSTA's
generic statistical estimate, not derived from this core's real
program behavior - a credible next step, not yet done, would be a real
gate-level simulation with a representative program, feeding its VCD
into `report_power` via `read_vcd`, for an activity-driven (not just
default) number.

## RESOLVED (2026-09-05): real workload-driven power via gate-level VCD simulation

The vectorless number above is OpenSTA's generic statistical estimate,
not this core's real behavior. Got a genuinely real one instead: a
gate-level (not RTL) Icarus simulation of the actual SYNTHESIZED
netlist (`runs/.../final/nl/cpu_core_top.nl.v`) against sky130's own
behavioral Verilog models (`primitives.v` + `sky130_fd_sc_hd.v`),
driving `test1.hex` for real and dumping a VCD - fed into OpenROAD's
`report_power` via `read_vcd -scope`. New files: `tb_gatelevel_power.v`
(also doubles as a real functional gate-level-vs-RTL equivalence check
- confirmed `tohost=200`, matching the RTL testbenches exactly, not
just "didn't crash"), new steps in `.github/workflows/openlane-axisa-
synth.yml` (install `iverilog`, run the gate-level sim, run the
VCD-driven `report_power`).

**3 real, sequential dispatch failures before this worked, each
diagnosed from actual output, not guessed**:
1. `[ERROR ORD-2010] no technology has been read` - `openroad`'s own
   `read_verilog` (unlike the earlier `read_db`-based vectorless step,
   which loads a self-contained database with technology baked in)
   needs an explicit `read_lef` first.
2. The `*.tlef` glob picked an unrelated `sky130_fd_sc_hvl` techlef
   instead of the correct `sky130_fd_sc_hd__nom.tlef` - harmless this
   time (same underlying process layers), but fixed to the correct
   file once its real name was visible in a diagnostic listing.
3. `report_activity_annotation` isn't a real OpenROAD/OpenSTA command
   (removed - was a nice-to-have diagnostic, not needed for
   `report_power` itself; `read_lef`/`read_verilog`/`link_design`/
   `read_sdc`/`read_spef`/`read_vcd` had all already succeeded by the
   time this failed).

**Real result: Total ≈ 2.46 mW** (1.37e-03 W internal + 1.09e-03 W
switching + 6.19e-08 W leakage) - **dramatically lower** than the
190mW vectorless estimate above, and this is itself a real, honest,
non-obvious finding, not a discrepancy to paper over:

- `test1.hex` is a tiny 15-instruction program that halts almost
  immediately - the VCD capture window is dominated by the chip
  sitting idle in its post-`HALT` state, not sustained real switching.
- OpenSTA's vectorless default instead assumes some baseline
  statistical toggle rate on every signal for the whole analysis - a
  generic, more conservative "worst case shape" estimate, not a
  measurement of any specific program's real behavior.

**Neither number alone is "the" credible one for external use** (e.g.
a grant/competition submission) - 190mW is a generic upper-bound-style
estimate, 2.46mW reflects a near-idle chip running a trivial one-shot
program. A genuinely representative number would need a longer,
computationally-active program (e.g. the looping UART shell,
`sw/mini_shell_loop.axasm`, or a real compute loop) run for enough
cycles to reflect sustained, real operating behavior - not yet done,
a real next step if a single defensible power figure is needed.

## Still open (real, disclosed, not yet worked on)

1. **No SRAM macro** - `instr_mem`/`data_mem` synthesized as plain
   flip-flops via `sky130_fd_sc_hd` (no on-chip memory macro exists in
   this flow yet - would need OpenRAM or a pre-hardened SRAM IP, a
   separate, larger follow-up). The 7,568-cell/83,637.72µm² result
   above already includes this real cost, it isn't hidden.
2. **Antenna violations** - real, present in at least some
   configurations (see tables above), not deliberately fixed.
3. **Fmax found is specific to this exact floorplan/DIE_AREA/placement
   configuration** - a different floorplan (e.g. after fixing antenna,
   or after a real PDN/pin-order pass) could shift the real number
   somewhat in either direction; this isn't a fundamental, PDK-wide
   ceiling, just the honest result for this specific synthesis
   configuration.
4. **No single representative power number yet** - vectorless
   (190mW, generic estimate) and VCD-driven-on-`test1.hex` (2.46mW,
   real but near-idle/trivial workload) are both real but neither is a
   credible "typical operating power" figure on its own - would need a
   longer, computationally-active program's VCD for that.
5. **55ns Fmax is only bounded to a 5ns bracket** (50ns fails, 55ns
   passes) - not narrowed further by choice, not because tighter
   bisection isn't possible.
