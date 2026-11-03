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

Caveats, honestly:
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
