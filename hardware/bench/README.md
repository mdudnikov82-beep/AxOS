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
512-byte data memory. Fmax = 1 / (100 ns - worst setup slack).

| | ss 100°C 1.60V | tt 25°C 1.80V | cell area | flip-flops |
|---|---|---|---|---|
| AxISA v2.3 | 58.49 ns, 17.1 MHz | 40.27 ns, 24.8 MHz | 958,796 µm² | 13,619 |
| RV32I 5-stage | 50.67 ns, 19.7 MHz | 27.37 ns, 36.5 MHz | 724,114 µm² | 11,177 |

`U·ψ` = cycles x period:

| | ss | tt |
|---|---|---|
| AxISA, 52 cycles | **3.04 µs** | **2.09 µs** |
| RV32I, 107 cycles | 5.42 µs | 2.93 µs |
| AxISA faster by | **1.78x** | **1.40x** |

RV32I clocks faster (its worst path: FP forwarding into its one-cycle
FPU, `ffu.mem_wb_rd -> ex_mem_fpu_result`); AxISA needs half the cycles
(its worst path: the integer decode -> register file -> trap check ->
write path). AxISA is 1.32x the area, so per unit of area its lead is
about 1.35x (ss) and 1.06x (tt). Both: DRC 0, LVS 0, no timing
violations; antenna violations 349 nets (AxISA) vs 100 (RV32I).

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
the 2026-10-30 table: AxISA 1,183,250 µm², 17.8 / 25.7 MHz (ss / tt);
RV32I 954,269 µm², 20.7 / 36.6 MHz.

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
  cycle - and the 5-stage one still clocks faster than AxISA (above).
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
