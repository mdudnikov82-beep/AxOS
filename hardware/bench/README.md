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

Caveats, honestly:
- Cycles are not time. The RV32I cores do a whole multiply or add in one
  cycle, so their clock is probably slower than AxISA's. The pipelined
  core now has its own sky130 flow (`hardware/rv32i_core/asic`,
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
