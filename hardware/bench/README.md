# Fair fight: `U·ψ` on RV32I vs AxISA

One SU(3) matrix times one color vector — the core operation of lattice
QCD — on the project's two RV32I cores (`hardware/rv32i_core`, RV32F
subset: `FLW`/`FSW`/`FADD.S`/`FSUB.S`/`FMUL.S`, no FMA) and on AxISA's
`SU3MUL`. Same matrix, same vector, same binary32 rounding order, so all
three must produce the same bits — and they do: every core is checked
against AxISA's reference model (`tools/gen_su3mul_test.py`), not against
another core.

The RV32I program is fully unrolled straight-line code written by hand
(`gen_bench_su3mul.py`): no loop, no address arithmetic, and one add per
row fewer than `SU3MUL` does — every advantage goes to RV32I.

| core | instructions | cycles |
|---|---|---|
| RV32I single-cycle (`cpu_core.v`) | 96 + LW + ECALL | 125 |
| RV32I 5-stage pipeline (`cpu_core_pipelined.v`) | 96 + LW + ECALL | 107 |
| AxISA `SU3MUL`, v2.0 (one-cycle FPU) | **1** | 79 |
| AxISA `SU3MUL`, two-stage FPU, waiting after every step | **1** | 133 |
| AxISA `SU3MUL`, v2.3 pipelined terms | **1** | **52** |

What the fight showed: the one-instruction advantage was real (1 vs 96
instructions, 4 bytes vs 384 of code), but after the FPU was split into
two stages the sequencer was waiting after every multiply and add, and
lost on cycles. Pipelining the terms (a new one every 4 cycles, see
`docs/ISA.md` "Pipelined terms") put it ahead: 52 vs 107.

## In nanoseconds (sky130, 2026-10-30)

Both cores through the same OpenLane2 flow and config (runs 41055086346
AxISA at `b120284`, 41055081636 RV32I): 100 ns target, relative sizing,
40% utilization, 128-word instruction memory loaded through a port,
512-byte data memory.

How the clock period is read from a 100 ns run: the SDC gives the
outside world 20% of the clock on every port (input and output delay
20 ns, plus 0.25 ns uncertainty). A register-to-register path with slack
`s` needs `100 - s` ns; a path that starts or ends at a port needs
`(80 - s) / 0.8`, because the port's 20% shrinks with the clock too.
The period is the larger of the two, from the worst slack and the worst
register-to-register slack in OpenLane's `stapostpnr/summary.rpt`.

| | ss 100°C 1.60V | tt 25°C 1.80V | cell area | flip-flops |
|---|---|---|---|---|
| AxISA v2.3 | 48.12 ns, **20.8 MHz** (port) | 25.34 ns, 39.5 MHz (port) | 958,796 µm² | 13,619 |
| RV32I 5-stage | 50.67 ns, 19.7 MHz (reg) | 24.22 ns, 41.3 MHz (reg) | 724,114 µm² | 11,177 |

`U·ψ` = cycles x period:

| | ss | tt |
|---|---|---|
| AxISA, 52 cycles | **2.50 µs** | **1.32 µs** |
| RV32I, 107 cycles | 5.42 µs | 2.59 µs |
| AxISA faster by | **2.17x** | **1.97x** |

The two cores clock about the same: AxISA a little faster at ss, RV32I a
little faster at tt. RV32I's worst path is register to register (FP
forwarding into its one-cycle FPU, `ffu.mem_wb_rd -> ex_mem_fpu_result`).
AxISA's ends at the output ports: the whole integer instruction in one
cycle, from the start of the instruction (`squash_r`) through decode,
register read and the address adder to `uart_rx_ack`, `uart_tx_valid`,
`bus_req` and `bus_addr` (`asic/worst_paths.py`). AxISA needs half the
cycles. It is 1.32x the area, so per unit of area its lead is about
1.64x (ss) and 1.49x (tt). Both: DRC 0, LVS 0, no timing violations;
antenna violations 349 nets (AxISA) vs 100 (RV32I).

Correction (2026-11-24): this section first used `1 / (100 - slack)` for
every path. That is right for RV32I at ss and wrong for port paths,
which made AxISA look slower: 17.1 / 24.8 MHz instead of 20.8 / 39.5,
and a 1.78x / 1.40x lead instead of 2.17x / 1.97x. RV32I at tt moved
too, 36.5 -> 41.3 MHz, because its worst tt path is also a port path.

## In joules (sky130, 2026-11-23)

Energy of one `U·ψ` on the synthesized netlists (`gen_bench_energy.py`,
`energy_power.sh`). Two programs per core, both write their own data
first (a netlist has no memory to preload): A = setup + check + halt,
B = setup + `U·ψ` + check + halt. Each runs on the gate-level netlist
at the SDC's 100 ns clock; OpenROAD `report_power` (tt 25°C 1.80V) reads
that run's own VCD; E = power x cycles x 100 ns, and `U·ψ` = E(B) -
E(A), which cancels each ISA's own way of setting data up. Both
programs check a checksum, on RTL and on the netlist.

| | A | B | `U·ψ` = B - A |
|---|---|---|---|
| AxISA | 158 cycles, 13.6 mW, 214.9 nJ | 209 cycles, 13.6 mW, 284.2 nJ | 51 cycles, **69.4 nJ** |
| RV32I | 80 cycles, 11.7 mW, 93.6 nJ | 180 cycles, 12.1 mW, 217.8 nJ | 100 cycles, 124.2 nJ |

**AxISA uses 1.79x less energy per `U·ψ`.** Per cycle it costs more
(1.36 vs ~1.2 nJ: a bigger core, more flip-flops on the clock), but it
needs half the cycles. Dynamic energy per cycle hardly depends on the
clock rate, so the ratio holds at each core's own Fmax too.

Runs: RV32I 42507816103 (`9e0c67f`); AxISA synthesis 44914318764
(`8f9b8a3`), energy 45207002821 (`axisa-energy-from-run.yml`, on that
run's netlist). These use a 256-word instruction memory (the energy
programs do not fit in 128), so the area and clock differ a little from
the 2026-10-30 table: AxISA 1,183,250 µm², 22.1 / 42.4 MHz (ss / tt);
RV32I 954,269 µm², 20.7 / 42.6 MHz (same way of reading the clock).

Caveats, honestly:
- `report_power` prints 3 digits (13.6 mW), so each `U·ψ` figure is
  good to about ±2 nJ; the ratio to about ±0.06.
- Most of the power is the clock tree and flip-flops (no clock gating
  in either core), so energy follows cycles closely. With clock gating
  both numbers would drop and the ratio could change.
- In the gate-level runs the register-bank flip-flops are set to 0
  during reset (`gl_probe.py`'s `gl_init.v`): the cell models keep X
  through the programs' own `ANDI x, x, 0` clears, which work on
  silicon. This happens before the VCD starts and is the same for A and B.
- The gate-level run found a real bug on the way: AxISA's MTE tag memory
  was cleared by an `initial` block, which synthesis drops (fixed in
  `8f9b8a3`, reset now clears it).

## Caveats on cycles and time

- Cycles are not time. The RV32I cores do a whole multiply or add in one
  cycle, and the 5-stage one still clocks about as fast as AxISA (above).
  The pipelined core has its own sky130 flow (`hardware/rv32i_core/asic`,
  `.github/workflows/openlane-rv32i-synth.yml`, same config and memory
  sizes as AxISA's, program loaded through a port) to turn cycles into
  nanoseconds. (The data moved to low addresses to fit its 512-byte
  memory; that cost the 5-stage core one cycle, 106 -> 107.)
- AxISA's count excludes building `ψ` in registers (immediates — the
  confinement rule keeps memory data out of R/G/B); RV32I's includes its
  6 `FLW`s of `ψ`.

Run (from `hardware/bench`):

```
python gen_bench_su3mul.py
iverilog -o single.vvp ../rv32i_core/rtl/{alu,regfile,fp_regfile,imm_gen,control_unit,instr_mem,data_mem,fp_addsub,fp_mul,fp_div,mmu,fp_sqrt,cpu_core}.v tb_bench_rv32i_single.v && vvp single.vvp
iverilog -o pipe.vvp ../rv32i_core/rtl/{alu,regfile,fp_regfile,imm_gen,control_unit,instr_mem,data_mem,fp_addsub,fp_mul,fp_div,forward_unit,fp_forward_unit,hazard_unit,mmu,fp_sqrt,cpu_core_pipelined}.v tb_bench_rv32i_pipe.v && vvp pipe.vvp
```

AxISA's count is checked by `tb/tb_su3mul.v` (`python run_sim.py su3mul`
in `hardware/axisa_core`).
