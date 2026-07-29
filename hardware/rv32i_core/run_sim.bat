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
echo ===== ALL SIMULATIONS PASSED =====
exit /b 0

:error
echo.
echo ===== SIMULATION FAILED =====
exit /b 1
