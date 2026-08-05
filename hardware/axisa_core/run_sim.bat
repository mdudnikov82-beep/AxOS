@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "IVERILOG=C:\iverilog\bin\iverilog.exe"
set "VVP=C:\iverilog\bin\vvp.exe"

echo ===== AxISA milestone 1: ALUR/ALUI/BRANCH/HALT, 4 register banks =====
python sw\asm_test1.py sw\test1.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_tb_cpu.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v tb\tb_cpu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu.vvp | findstr /C:"ALL AXISA MILESTONE-1 TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_cpu & "%VVP%" out_tb_cpu.vvp & goto :error)
echo   OK (tohost=200, r3=12, g3=7, b3=30 - all 4 register banks verified independently)

echo.
echo ===== AxISA milestone 2: GLUON/BARYON/MESON/LOAD/STORE/JAL =====
python sw\asm_test2.py sw\test2.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_tb_cpu2.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v tb\tb_cpu2.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu2.vvp | findstr /C:"ALL AXISA MILESTONE-2 TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_cpu2 & "%VVP%" out_tb_cpu2.vvp & goto :error)
echo   OK (tohost=324 - chained BARYON+MESON+GLUON+LOAD/STORE+JAL result; r3=3 - GLUON same-bank 2R+1W, direct peek)

echo.
echo ===== AxISA demo: "particle collider" (real .axasm source, sw\axasm.py) =====
python sw\axasm.py sw\demo_collider.axasm sw\collider.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_collider.vvp "-DINSTR_HEX=\"sw/collider.hex\"" rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v tb\tb_run.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_collider.vvp +EXPECT_TOHOST=28 | findstr /C:"PASS: tohost matches expected value" >nul
if %errorlevel% neq 0 (echo FAILED: collider demo & "%VVP%" out_collider.vvp +EXPECT_TOHOST=28 & goto :error)
echo   OK (tohost=28 - real backward-branch loop, BARYON collisions, STORE/LOAD round-trip, all assembled from text)

echo.
echo ===== ALL SIMULATIONS PASSED =====
exit /b 0

:error
echo.
echo ===== SIMULATION FAILED =====
exit /b 1
