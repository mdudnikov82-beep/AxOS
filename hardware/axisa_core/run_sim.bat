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
echo ===== NoC: link test (fake bus driver + router.v + noc_core_adapter.v + noc_mem_adapter.v) =====
echo router.v/noc_core_adapter.v/noc_mem_adapter.v ported byte-for-byte unmodified from rv32i_core - this proves the generic bus protocol works with AxISA's own fixed word-only mem_size/mem_unsigned convention
"%IVERILOG%" -o out_noclink.vvp rtl\router.v rtl\shared_mem_backing.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v tb\tb_noc_link.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_noclink.vvp | findstr /C:"ALL AXISA NOC LINK TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_noc_link & "%VVP%" out_noclink.vvp & goto :error)
echo   OK

echo.
echo ===== NoC: single REAL core through one hop to shared memory =====
echo First test to exercise cpu_core.v's own is_shared_access/mem_stall/write-enable-gating/effective_dmem_rdata logic, not just the adapter+router protocol
"%IVERILOG%" -o out_nocsingle.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\shared_mem_backing.v rtl\router.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v tb\tb_noc_single.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_nocsingle.vvp | findstr /C:"ALL AXISA NOC SINGLE-CORE TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_noc_single & "%VVP%" out_nocsingle.vvp & goto :error)
echo   OK (tohost=99 - real STORE then LOAD round trip through the NoC)

echo.
echo ===== Mini-SoC: AxISA multi-core mesh (3x3, 8 cores + 1 memory) =====
python sw\axasm.py sw\shared_producer.axasm sw\shared_producer.hex
if %errorlevel% neq 0 goto :error
python sw\axasm.py sw\shared_consumer.axasm sw\shared_consumer.hex
if %errorlevel% neq 0 goto :error
echo c0 (consumer, busy-waits) reads c1's (producer) payload through the arbitrated NoC - only correct (127) if it genuinely observed the other core's write; c2-c7 run independently (test1.hex) alongside
"%IVERILOG%" -o out_soc.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\shared_mem_backing.v rtl\router.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v rtl\soc_top.v tb\tb_soc.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_soc.vvp | findstr /C:"PASS: cross-core communication verified" >nul
if %errorlevel% neq 0 (echo FAILED: AxISA mini-SoC & "%VVP%" out_soc.vvp & goto :error)
echo   OK (c0=127, c1=77, c2-c7=200, all 8 concurrent, cross-core communication verified)

echo.
echo ===== ALL SIMULATIONS PASSED =====
exit /b 0

:error
echo.
echo ===== SIMULATION FAILED =====
exit /b 1
