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

echo.
echo ===== Full core: hand-assembled program (asm_test1.py) =====
python sw\asm_test1.py sw\test1.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_tb_cpu1.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\cpu_core.v tb\tb_cpu.v
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

"%IVERILOG%" -DINSTR_HEX=\"sw/test_basic.hex\" -o out_tb_cpu2.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\cpu_core.v tb\tb_cpu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu2.vvp +EXPECT_TOHOST=110 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: compiled C program & "%VVP%" out_tb_cpu2.vvp +EXPECT_TOHOST=110 & goto :error)
echo   OK (tohost=110)

echo.
echo ===== Pipelined core (cpu_core_pipelined.v) =====

echo Cross-check 1: hand-assembled program (must match single-cycle: 42)
"%IVERILOG%" -o out_tb_pipe1.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe1.vvp +EXPECT_TOHOST=42 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined, hand-assembled program & "%VVP%" out_tb_pipe1.vvp +EXPECT_TOHOST=42 & goto :error)
echo   OK (tohost=42, matches single-cycle)

echo Cross-check 2: real compiled C program (must match single-cycle: 110)
"%IVERILOG%" -DINSTR_HEX=\"sw/test_basic.hex\" -o out_tb_pipe2.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe2.vvp +EXPECT_TOHOST=110 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined, compiled C program & "%VVP%" out_tb_pipe2.vvp +EXPECT_TOHOST=110 & goto :error)
echo   OK (tohost=110, matches single-cycle)

echo Hazard stress test (forwarding + load-use stall + branch flush together)
python sw\asm_hazard_test.py sw\hazard_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -DINSTR_HEX=\"sw/hazard_test.hex\" -o out_tb_pipe3.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\forward_unit.v rtl\hazard_unit.v rtl\cpu_core_pipelined.v tb\tb_cpu_pipelined.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_pipe3.vvp +EXPECT_TOHOST=119 | findstr /C:"PASS: tohost matches" >nul
if %errorlevel% neq 0 (echo FAILED: pipelined, hazard stress test & "%VVP%" out_tb_pipe3.vvp +EXPECT_TOHOST=119 & goto :error)
echo   OK (tohost=119)

echo.
echo ===== Mini-SoC: 1 P-core + 1 E-core (soc_top.v) =====
echo P-core runs hazard_test.hex (119), E-core runs test_basic.hex (110), at the same time
"%IVERILOG%" -o out_soc.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\forward_unit.v rtl\hazard_unit.v rtl\cpu_core.v rtl\cpu_core_pipelined.v rtl\shared_bus.v rtl\soc_top.v tb\tb_soc.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_soc.vvp | findstr /C:"PASS: both cores matched" >nul
if %errorlevel% neq 0 (echo FAILED: mini-SoC & "%VVP%" out_soc.vvp & goto :error)
echo   OK (P=119, E=110, both concurrent)

echo.
echo ===== Shared bus: cross-core communication (soc_top.v + shared_bus.v) =====
echo E-core (producer) writes a payload+flag to shared mem, P-core (consumer) polls and reads it back
python sw\asm_shared_producer.py sw\shared_producer.hex
if %errorlevel% neq 0 goto :error
python sw\asm_shared_consumer.py sw\shared_consumer.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_shared_soc.vvp rtl\alu.v rtl\regfile.v rtl\imm_gen.v rtl\control_unit.v rtl\instr_mem.v rtl\data_mem.v rtl\forward_unit.v rtl\hazard_unit.v rtl\cpu_core.v rtl\cpu_core_pipelined.v rtl\shared_bus.v rtl\soc_top.v tb\tb_shared_soc.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_shared_soc.vvp | findstr /C:"PASS: cross-core communication verified" >nul
if %errorlevel% neq 0 (echo FAILED: shared-bus cross-core test & "%VVP%" out_shared_soc.vvp & goto :error)
echo   OK (P=127, E=77, cross-core communication verified)

echo.
echo ===== ALL SIMULATIONS PASSED =====
exit /b 0

:error
echo.
echo ===== SIMULATION FAILED =====
exit /b 1
