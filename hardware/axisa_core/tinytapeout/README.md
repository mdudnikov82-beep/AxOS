# AxISA Tiny Tapeout wrapper (OpenLane2 / sky130)

Next step of the AxISA-to-ASIC roadmap after the `asic/` flow (see
[[project_axisa_asic_openlane]] in project memory / `hardware/
axisa_core/asic/README.md` for that full history: 3,614 cells/42,741
µm², DRC+LVS pass, real Fmax=45.7MHz). Tiny Tapeout is a real,
accessible hobbyist ASIC shuttle program - but its top module must fit
a FIXED 24-pin `tt_um_*` interface (`ui_in[7:0]`, `uo_out[7:0]`,
`uio_in/out/oe[7:0]`, `ena`, `clk`, `rst_n`), vastly narrower than
`cpu_core`'s own 157-pin native port list.

**Scope of this step, deliberately limited**: design + simulate + run
a real OpenLane synthesis check on the wrapper. This does **not**
set up an actual Tiny Tapeout submission (no forking their template
repo, no `info.yaml`, no real shuttle/deadline commitment) - that is
an explicit, separate, later step, only to be done with direct
approval given it's a paid, irreversible action.

## Design

`tt_um_axisa_core.v` is a thin adapter (same "instantiate + adapt
pins, no added logic" style as `asic/cpu_core_top.v`) around the exact
same `cpu_core.v` the `asic/` flow already synthesizes, with a new
permanent program baked in: `sw/mini_shell_loop.axasm` - a looping
variant of the existing working UART shell demo (`sw/mini_shell.axasm`)
that re-prints its prompt and accepts another command forever instead
of halting after one exchange (there's no host to notice a `HALT`
signal and restart real silicon).

Pin mapping (24 pins, fully accounted for):

| TT pin | cpu_core signal | Notes |
|---|---|---|
| `clk` | `clk` | direct |
| `rst_n` | `reset` | `reset = ~rst_n` (active-low -> active-high), no synchronizer - matches this project's existing no-reset-sync-tree precedent everywhere in `rtl/` |
| `ena` | *(unused)* | tied off per TT convention |
| `ui_in[7:0]` | `uart_rx_data_in[7:0]` | the simulated "keyboard" byte |
| `uo_out[7:0]` | `uart_tx_data[7:0]` | the "console" byte |
| `uio[0]` out | `uart_tx_valid` | `uio_oe[0]=1` |
| `uio[1]` in | `uart_rx_ready_in` | `uio_oe[1]=0` |
| `uio[2]` out | `uart_rx_ack` | `uio_oe[2]=1` |
| `uio[3]` out | `halted` | `uio_oe[3]=1` - **reads 0 always** for this bitstream, since `HALT` is never reached by design; not a bug |
| `uio[7:4]` | reserved, unused | `uio_oe[7:4]=0` |

`irq_in` is tied `1'b0` internally (no pin spent) - provably dead for
this program, since `ie_r` can only be set via a privileged `MVSR`
write that `mini_shell_loop.axasm` never issues. The shared-bus/NoC
port is tied off internally (`bus_grant=0`) and not exposed to any
pin, since this program never touches an address at or above
`SHARED_MEM_BASE`. **Footgun if this wrapper is ever reused with a
different program**: one that does touch shared memory would stall
forever (`mem_stall` permanently true) - fine for
`mini_shell_loop.axasm`, not fine for an arbitrary future program
without revisiting the tie-off.

## Verification

1. `sw/mini_shell_loop.axasm` assembled via the existing
   `sw/axasm.py`, verified in Icarus Verilog (`tb/
   tb_tt_um_axisa_core.v`, driven/observed only through the tt_um pin
   interface - never `cpu_core`'s native ports) - see `run_sim.bat`'s
   "AxISA Tiny Tapeout wrapper" section.
2. `.github/workflows/openlane-axisa-tinytapeout-synth.yml` runs the
   real OpenLane2/sky130 flow against `config.json`
   (`DIE_AREA "0 0 320 200"` = 64,000 µm², a first estimate of Tiny
   Tapeout's commonly-cited ~2x2-tile budget - expected to need
   correction from a real OpenLane error, same as `asic/config.json`'s
   own `DIE_AREA` did on its first attempt).

Timing pass/fail must be read via the same reliable discriminator the
`asic/` flow already established: `[RSZ-0062] Unable to repair all
setup violations.` = real fail; `[RSZ-0099] Repairing N out of N
(100.00%)...` with no `RSZ-0062` = real pass. **`"Flow complete."` and
a green GitHub Actions job do NOT mean timing passed** - OpenLane logs
a warning and saves the layout regardless.

## Still open (real, disclosed, not yet run)

1. **Area headroom is unverified for this exact program.** `cpu_core`
   alone measured 42,741 µm² against `asic/`'s `test1.hex` - that
   leaves only ~33% of the assumed 64,000 µm² budget for the wrapper's
   glue plus whatever `mini_shell_loop.hex` itself costs. Since
   `instr_mem` is a pure ROM (no write port), Yosys's constant-folding
   is content-specific - the 42,741 µm² figure does not automatically
   transfer to a differently-sized program until a real synth run
   confirms it.
2. **The 64,000 µm² / "2x2 tile" figure is a first estimate**, not
   validated against any specific real Tiny Tapeout shuttle template's
   actual usable area after padframe/power-routing keepout.
3. **Fmax is unmeasured for this floorplan** - the `asic/` flow's
   45.7MHz is specific to its own 300x300µm floorplan; a TT-sized die
   could go either faster or slower, genuinely unknown until tested.
4. **The pre-existing unbounded command-buffer offset** (no bounds
   check on `N3`, inherited from `mini_shell.axasm`) is now live on an
   always-running device instead of a one-shot demo - low real-world
   risk with a human typist, not fixed here.
5. No actual Tiny Tapeout submission process (forking their template,
   `info.yaml`, a real shuttle) has been started - see Scope above.
