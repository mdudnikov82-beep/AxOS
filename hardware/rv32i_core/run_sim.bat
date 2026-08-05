@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "IVERILOG=C:\iverilog\bin\iverilog.exe"
set "VVP=C:\iverilog\bin\vvp.exe"
set "GCC_PREFIX=C:\axos_build\riscv-gcc\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-"
set "GCC=%GCC_PREFIX%gcc.exe"
set "OBJCOPY=%GCC_PREFIX%objcopy.exe"

echo ===== Per-module testbenches =====

echo [1] alu...
"%IVERILOG%" -o out_tb_alu.vvp rtl\alu.v tb\tb_alu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_alu.vvp | findstr /C:"ALL ALU TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_alu & "%VVP%" out_tb_alu.vvp & goto :error)
echo   OK

echo [2] regfile...
"%IVERILOG%" -o out_tb_regfile.vvp rtl\regfile.v tb\tb_regfile.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_regfile.vvp | findstr /C:"ALL REGFILE TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_regfile & "%VVP%" out_tb_regfile.vvp & goto :error)
echo   OK

echo [3] imm_gen...
"%IVERILOG%" -o out_tb_imm.vvp rtl\imm_gen.v tb\tb_imm_gen.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_imm.vvp | findstr /C:"ALL IMM_GEN TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_imm_gen & "%VVP%" out_tb_imm.vvp & goto :error)
echo   OK

echo [4] control_unit...
"%IVERILOG%" -o out_tb_control.vvp rtl\control_unit.v tb\tb_control_unit.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_control.vvp | findstr /C:"ALL CONTROL_UNIT TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_control_unit & "%VVP%" out_tb_control.vvp & goto :error)
echo   OK

echo [5] data_mem...
"%IVERILOG%" -o out_tb_datamem.vvp rtl\data_mem.v tb\tb_data_mem.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_datamem.vvp | findstr /C:"ALL DATA_MEM TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_data_mem & "%VVP%" out_tb_datamem.vvp & goto :error)
echo   OK

echo [6] forward_unit...
"%IVERILOG%" -o out_tb_forward.vvp rtl\forward_unit.v tb\tb_forward_unit.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_forward.vvp | findstr /C:"ALL FORWARD_UNIT TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_forward_unit & "%VVP%" out_tb_forward.vvp & goto :error)
echo   OK

echo [7] hazard_unit...
"%IVERILOG%" -o out_tb_hazard.vvp rtl\hazard_unit.v tb\tb_hazard_unit.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_hazard.vvp | findstr /C:"ALL HAZARD_UNIT TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_hazard_unit & "%VVP%" out_tb_hazard.vvp & goto :error)
echo   OK

echo [8] shared_bus...
"%IVERILOG%" -o out_tb_sbus.vvp rtl\data_mem.v rtl\shared_bus.v tb\tb_shared_bus.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_sbus.vvp | findstr /C:"ALL SHARED_BUS TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_shared_bus & "%VVP%" out_tb_sbus.vvp & goto :error)
echo   OK

echo [9] fp_addsub...
"%IVERILOG%" -o out_tb_fpaddsub.vvp rtl\fp_addsub.v tb\tb_fp_addsub.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_fpaddsub.vvp | findstr /C:"ALL FP_ADDSUB TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_fp_addsub & "%VVP%" out_tb_fpaddsub.vvp & goto :error)
echo   OK

echo [10] fp_mul...
"%IVERILOG%" -o out_tb_fpmul.vvp rtl\fp_mul.v tb\tb_fp_mul.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_fpmul.vvp | findstr /C:"ALL FP_MUL TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_fp_mul & "%VVP%" out_tb_fpmul.vvp & goto :error)
echo   OK

echo [11] fp_forward_unit...
"%IVERILOG%" -o out_tb_fpfwd.vvp rtl\fp_forward_unit.v tb\tb_fp_forward_unit.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_fpfwd.vvp | findstr /C:"ALL FP_FORWARD_UNIT TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_fp_forward_unit & "%VVP%" out_tb_fpfwd.vvp & goto :error)
echo   OK

echo [12] fp_div (multi-cycle)...
"%IVERILOG%" -o out_tb_fpdiv.vvp rtl\fp_div.v tb\tb_fp_div.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_fpdiv.vvp | findstr /C:"ALL FP_DIV TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_fp_div & "%VVP%" out_tb_fpdiv.vvp & goto :error)
echo   OK

echo [13] fp_sqrt (multi-cycle)...
"%IVERILOG%" -o out_tb_fpsqrt.vvp rtl\fp_sqrt.v tb\tb_fp_sqrt.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_fpsqrt.vvp | findstr /C:"ALL FP_SQRT TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_fp_sqrt & "%VVP%" out_tb_fpsqrt.vvp & goto :error)
echo   OK

echo [14] router (NoC mesh building block)...
"%IVERILOG%" -o out_tb_router.vvp rtl\router.v tb\tb_router.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_router.vvp | findstr /C:"ALL ROUTER TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_router & "%VVP%" out_tb_router.vvp & goto :error)
echo   OK

echo [15] NoC link (core adapter + router + router + memory adapter, single X-axis hop)...
"%IVERILOG%" -o out_tb_noclink.vvp rtl\router.v rtl\data_mem.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v tb\tb_noc_link.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_noclink.vvp | findstr /C:"ALL NOC LINK TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_noc_link & "%VVP%" out_tb_noclink.vvp & goto :error)
echo   OK

echo [15b] NoC link, dedicated W-axis (Ana/Kata) hop - NOT reused from the X-axis case...
"%IVERILOG%" -o out_tb_noclink_w.vvp rtl\router.v rtl\data_mem.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v tb\tb_noc_link_w.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_noclink_w.vvp | findstr /C:"ALL NOC LINK-W TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_noc_link_w & "%VVP%" out_tb_noclink_w.vvp & goto :error)
echo   OK

echo.
echo ===== Full core: hand-assembled program (asm_test1.py) =====
python sw\asm_test1.py sw\test1.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_tb_cpu1.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu1.vvp +EXPECT_TOHOST=42 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: hand-assembled program & "%VVP%" out_tb_cpu1.vvp +EXPECT_TOHOST=42 & goto :error)
echo   OK (tohost=42)

echo.
echo ===== Full core: real compiled C program (test_basic.c) =====
"%GCC%" -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -O2 -T sw\link.ld -o sw\test_basic.elf sw\start.S sw\test_basic.c
if %errorlevel% neq 0 goto :error
"%OBJCOPY%" -O binary --only-section=.text --only-section=.rodata sw\test_basic.elf sw\test_basic.bin
if %errorlevel% neq 0 goto :error
python sw\bin2hex.py sw\test_basic.bin sw\test_basic.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -DINSTR_HEX=\"sw/test_basic.hex\" -o out_tb_cpu2.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu2.vvp +EXPECT_TOHOST=110 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: compiled C program & "%VVP%" out_tb_cpu2.vvp +EXPECT_TOHOST=110 & goto :error)
echo   OK (tohost=110)

echo.
echo ===== Pipelined core (cpu_core_pipelined.v) =====

echo Cross-check 1: hand-assembled program (must match single-cycle: 42)
"%IVERILOG%" -o out_tb_pipe1.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe1.vvp +EXPECT_TOHOST=42 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined, hand-assembled program & "%VVP%" out_tb_pipe1.vvp +EXPECT_TOHOST=42 & goto :error)
echo   OK (tohost=42, matches single-cycle)

echo Cross-check 2: real compiled C program (must match single-cycle: 110)
"%IVERILOG%" -DINSTR_HEX=\"sw/test_basic.hex\" -o out_tb_pipe2.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe2.vvp +EXPECT_TOHOST=110 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined, compiled C program & "%VVP%" out_tb_pipe2.vvp +EXPECT_TOHOST=110 & goto :error)
echo   OK (tohost=110, matches single-cycle)

echo Hazard stress test (forwarding + load-use stall + branch flush together)
python sw\asm_hazard_test.py sw\hazard_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -DINSTR_HEX=\"sw/hazard_test.hex\" -o out_tb_pipe3.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe3.vvp +EXPECT_TOHOST=119 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined, hazard stress test & "%VVP%" out_tb_pipe3.vvp +EXPECT_TOHOST=119 & goto :error)
echo   OK (tohost=119)

echo.
echo ===== Mini-SoC: 36 P-cores + 35 E-cores (soc_top.v, 4D 2x3x6x2 NoC mesh) =====
echo p0=hazard_test.hex(119) p1-p35=test1.hex(42) e0=test_basic.hex(110) e1-e34=test1.hex(42), all concurrent
"%IVERILOG%" -o out_soc.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v rtl\cpu_core_pipelined.v rtl\router.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v rtl\soc_top.v tb\tb_soc.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_soc.vvp | findstr /C:"PASS: all 71 cores matched" >nul
if %errorlevel% neq 0 (echo FAILED: mini-SoC & "%VVP%" out_soc.vvp & goto :error)
echo   OK (p0=119, p1-p35=42, e0=110, e1-e34=42, all 71 concurrent)

echo.
echo ===== NoC: cross-core communication through the 4D mesh, real W-axis hop (soc_top.v) =====
echo e0 (producer, at grid position (1,0,0,1), W=1, 5 hops from memory) writes a payload+flag to shared mem, p0 (consumer, at (0,0,0,0), W=0, 3 hops from memory) polls and reads it back - through several real router hops each way including a genuine Ana/Kata (W-axis) crossing since memory sits at W=0 and e0 sits at W=1, not just X/Y/Z routing; p1-p35/e1-e34 run independently alongside
python sw\asm_shared_producer.py sw\shared_producer.hex
if %errorlevel% neq 0 goto :error
python sw\asm_shared_consumer.py sw\shared_consumer.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_shared_soc.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v rtl\cpu_core_pipelined.v rtl\router.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v rtl\soc_top.v tb\tb_shared_soc.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_shared_soc.vvp | findstr /C:"PASS: cross-core communication verified" >nul
if %errorlevel% neq 0 (echo FAILED: NoC cross-core test & "%VVP%" out_shared_soc.vvp & goto :error)
echo   OK (p0=127, e0=77, p1-p35/e1-e34=42, cross-core communication verified through a real W-axis hop)

echo.
echo ===== Minimal RV32F: FLW/FSW + FADD.S/FSUB.S/FMUL.S (E-core only) =====
python sw\asm_fp_test.py sw\fp_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_tb_cpufp.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu_fp.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufp.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: RV32F integration test & "%VVP%" out_tb_cpufp.vvp & goto :error)
echo   OK (tohost=1082130432 = 0x40800000 = 4.0)

echo.
echo ===== Minimal RV32F on the pipelined P-core (cpu_core_pipelined.v) =====
echo Cross-check: same program as the E-core, must match its result exactly
"%IVERILOG%" -o out_tb_cpufppipe1.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_fp_pipe.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufppipe1.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined RV32F cross-check & "%VVP%" out_tb_cpufppipe1.vvp & goto :error)
echo   OK (tohost=1082130432 = 0x40800000 = 4.0, matches single-cycle)

echo FP hazard stress test (load-use stall + EX/MEM forward + store-data forward together)
python sw\asm_fp_pipe_test.py sw\fp_pipe_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -DINSTR_HEX=\"sw/fp_pipe_test.hex\" -o out_tb_cpufppipe2.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_fp_pipe.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufppipe2.vvp +EXPECT_TOHOST=1094713344 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined RV32F hazard stress test & "%VVP%" out_tb_cpufppipe2.vvp +EXPECT_TOHOST=1094713344 & goto :error)
echo   OK (tohost=1094713344 = 0x41400000 = 12.0)

echo.
echo ===== FDIV.S: multi-cycle restoring division (E-core only) =====
python sw\asm_fp_div_test.py sw\fp_div_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_tb_cpufpdiv.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu_fp_div.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufpdiv.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: FDIV.S integration test & "%VVP%" out_tb_cpufpdiv.vvp & goto :error)
echo   OK (tohost=1080033280 = 0x40600000 = 3.5)

echo.
echo ===== FDIV.S ported to the pipelined P-core (cpu_core_pipelined.v) =====
echo Cross-check: same program as the E-core, no bus contention (GRANT_DENY_CYCLES=0), must match its result exactly
"%IVERILOG%" -DINSTR_HEX=\"sw/fp_div_test.hex\" -o out_tb_cpufpdivpipe1.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_fp_div_pipe.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufpdivpipe1.vvp +GRANT_DENY_CYCLES=0 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined FDIV.S cross-check & "%VVP%" out_tb_cpufpdivpipe1.vvp +GRANT_DENY_CYCLES=0 & goto :error)
echo   OK (tohost=1080033280 = 0x40600000 = 3.5, matches single-cycle)

echo Adversarial race: an unrelated OLDER shared-memory store stuck in EX/MEM (bus_grant denied) spans FDIV.S's entire computation, forcing its DONE cycle to land mid-mem_stall
python sw\asm_fp_div_pipe_race_test.py sw\fp_div_pipe_race_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_tb_cpufpdivpipe2.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_fp_div_pipe.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufpdivpipe2.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined FDIV.S mem_stall/fpu_div_stall race & "%VVP%" out_tb_cpufpdivpipe2.vvp & goto :error)
echo   OK (tohost=1080033280 = 0x40600000 = 3.5, survives the race)

echo.
echo ===== FSQRT.S: multi-cycle restoring square root (E-core only) =====
python sw\asm_fp_sqrt_test.py sw\fp_sqrt_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_tb_cpufpsqrt.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu_fp_sqrt.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufpsqrt.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: FSQRT.S integration test & "%VVP%" out_tb_cpufpsqrt.vvp & goto :error)
echo   OK (tohost=1068827891 = 0x3fb504f3 = sqrt(2.0))

echo.
echo ===== FSQRT.S ported to the pipelined P-core (cpu_core_pipelined.v) =====
python sw\asm_fp_sqrt_pipe_race_test.py sw\fp_sqrt_pipe_race_test.hex
if %errorlevel% neq 0 goto :error
echo Cross-check: same program as the E-core, no bus contention (GRANT_DENY_CYCLES=0), must match its result exactly
"%IVERILOG%" -o out_tb_cpufpsqrtpipe.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined_fp_sqrt.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpufpsqrtpipe.vvp +GRANT_DENY_CYCLES=0 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined FSQRT.S cross-check & "%VVP%" out_tb_cpufpsqrtpipe.vvp +GRANT_DENY_CYCLES=0 & goto :error)
echo   OK (tohost=1068827891 = 0x3fb504f3, matches single-cycle)

echo Adversarial race: an unrelated OLDER shared-memory store stuck in EX/MEM (bus_grant denied) spans FSQRT.S's entire computation, forcing its DONE cycle to land mid-mem_stall
"%VVP%" out_tb_cpufpsqrtpipe.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined FSQRT.S mem_stall/fpu_sqrt_stall race & "%VVP%" out_tb_cpufpsqrtpipe.vvp & goto :error)
echo   OK (tohost=1068827891 = 0x3fb504f3, survives the race)

echo.
echo ===== MMU (mmu.v): real virtual-to-physical translation =====
python sw\asm_mmu_test.py sw\mmu_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_tb_mmu.vvp rtl\mmu.v rtl\fp_sqrt.v tb\tb_mmu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_mmu.vvp | findstr /C:"ALL MMU TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: standalone mmu.v testbench & "%VVP%" out_tb_mmu.vvp & goto :error)
echo   OK (2-level walk, TLB hit, R/W permission faults, invalid-PTE faults, PPN-range fault)

echo E-core (cpu_core.v) + MMU: VA 0 translates to a different physical page, proven via a sentinel swap
"%IVERILOG%" -o out_tb_cpu_mmu.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu_mmu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu_mmu.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: E-core + MMU integration & "%VVP%" out_tb_cpu_mmu.vvp & goto :error)
echo   OK (tohost=1234, the untranslated-address sentinel 9999 was not read)

echo P-core (cpu_core_pipelined.v) + MMU: same program, must match the E-core exactly
"%IVERILOG%" -o out_tb_pipe_mmu.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined_mmu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe_mmu.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: P-core + MMU integration & "%VVP%" out_tb_pipe_mmu.vvp & goto :error)
echo   OK (tohost=1234, matches E-core)

echo Adversarial race: fdiv_capture must also gate on !mmu_stall, not just !mem_stall - mmu_stall is forced high for exactly FDIV.S's done cycle, proving the ready-buffer rescues the result instead of silently restarting the division
"%IVERILOG%" -o out_tb_pipe_mmu_race.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined_mmu_race.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe_mmu_race.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined FDIV.S mmu_stall/fpu_div_done race & "%VVP%" out_tb_pipe_mmu_race.vvp & goto :error)
echo   OK (tohost=1080033280 = 0x40600000 = 3.5, survives the forced mmu_stall/done race)

echo Regression: a STORE that misses the TLB on first touch used to also corrupt physical page 0 (dmem_write wasn't gated by !mmu_stall) - both cores
python sw\asm_mmu_store_miss_test.py sw\mmu_store_miss_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_tb_cpu_mmu_sm.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu_mmu_store_miss.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu_mmu_sm.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: E-core store/TLB-miss corruption regression & "%VVP%" out_tb_cpu_mmu_sm.vvp & goto :error)
echo   OK (E-core: page 0 unchanged, tohost=0xabcde000)
"%IVERILOG%" -o out_tb_pipe_mmu_sm.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined_mmu_store_miss.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe_mmu_sm.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: P-core store/TLB-miss corruption regression & "%VVP%" out_tb_pipe_mmu_sm.vvp & goto :error)
echo   OK (P-core: page 0 unchanged, matches E-core)

echo.
echo ===== TLB invalidation (SFENCE.VMA) =====
python sw\asm_sfence_test.py sw\sfence_test.hex
if %errorlevel% neq 0 goto :error
python sw\asm_sfence_test.py sw\sfence_test_neg.hex --no-sfence
if %errorlevel% neq 0 goto :error

echo E-core: legitimately self-modifies its own page table then SFENCE.VMA + re-reads - proves the stale TLB entry is genuinely discarded
"%IVERILOG%" -o out_tb_cpu_sfence.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu_sfence.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu_sfence.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: E-core SFENCE.VMA & "%VVP%" out_tb_cpu_sfence.vvp & goto :error)
echo   OK (tohost=2222, invalidation worked)
echo Negative control: same program with SFENCE.VMA physically removed - MUST incorrectly return the stale sentinel, proving the positive result above wasn't a coincidence
"%IVERILOG%" -DINSTR_HEX=\"sw/sfence_test_neg.hex\" -o out_tb_cpu_sfence_neg.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_regfile.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\cpu_core.v tb\tb_cpu_sfence.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu_sfence_neg.vvp +EXPECT_TOHOST=1111 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: E-core SFENCE.VMA negative control & "%VVP%" out_tb_cpu_sfence_neg.vvp +EXPECT_TOHOST=1111 & goto :error)
echo   OK (tohost=1111, stale entry served without SFENCE - confirms the test genuinely discriminates)

echo P-core: same program, must match the E-core exactly
"%IVERILOG%" -o out_tb_pipe_sfence.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined_sfence.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe_sfence.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: P-core SFENCE.VMA & "%VVP%" out_tb_pipe_sfence.vvp & goto :error)
echo   OK (tohost=2222, matches E-core)
"%IVERILOG%" -DINSTR_HEX=\"sw/sfence_test_neg.hex\" -o out_tb_pipe_sfence_neg.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined_sfence.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe_sfence_neg.vvp +EXPECT_TOHOST=1111 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: P-core SFENCE.VMA negative control & "%VVP%" out_tb_pipe_sfence_neg.vvp +EXPECT_TOHOST=1111 & goto :error)
echo   OK (tohost=1111, matches E-core negative control)

echo Adversarial race: SFENCE.VMA held at IF/ID behind an older instruction's in-flight TLB walk (mmu_stall) must NOT livelock - a naive raw/held tlb_flush pulse repeatedly wipes the walk's own freshly-filled entry and never lets the core halt
"%IVERILOG%" -o out_tb_pipe_sfence_race.vvp rtl\alu.v rtl\regfile.v rtl\fp_regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\fp_addsub.v rtl\fp_mul.v rtl\fp_div.v rtl\mmu.v rtl\fp_sqrt.v rtl\forward_unit.v rtl\fp_forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined_sfence_race.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe_sfence_race.vvp | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined SFENCE.VMA held-during-walk race & "%VVP%" out_tb_pipe_sfence_race.vvp & goto :error)
echo   OK (tohost=4242, no livelock)

echo.
echo ===== ALL SIMULATIONS PASSED =====
exit /b 0

:error
echo.
echo ===== SIMULATION FAILED =====
exit /b 1
