@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "IVERILOG=C:\iverilog\bin\iverilog.exe"
set "VVP=C:\iverilog\bin\vvp.exe"

echo ===== AxISA milestone 1: ALUR/ALUI/BRANCH/HALT, 4 register banks =====
python sw\asm_test1.py sw\test1.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_tb_cpu.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\control_unit.v rtl\cpu_core.v tb\tb_cpu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu.vvp | findstr /C:"ALL AXISA MILESTONE-1 TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_cpu & "%VVP%" out_tb_cpu.vvp & goto :error)
echo   OK (tohost=200, r3=12, g3=7, b3=30 - all 4 register banks verified independently)

echo.
echo ===== ALL SIMULATIONS PASSED =====
exit /b 0

:error
echo.
echo ===== SIMULATION FAILED =====
exit /b 1
