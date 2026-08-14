@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "IVERILOG=C:\iverilog\bin\iverilog.exe"
set "VVP=C:\iverilog\bin\vvp.exe"

echo ===== AxISA milestone 1: ALUR/ALUI/BRANCH/HALT, 4 register banks =====
python sw\asm_test1.py sw\test1.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_tb_cpu.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_cpu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu.vvp | findstr /C:"ALL AXISA MILESTONE-1 TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_cpu & "%VVP%" out_tb_cpu.vvp & goto :error)
echo   OK (tohost=200, r3=12, g3=7, b3=30 - all 4 register banks verified independently)

echo.
echo ===== AxISA milestone 2: GLUON/BARYON/MESON/LOAD/STORE/JAL =====
python sw\asm_test2.py sw\test2.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_tb_cpu2.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_cpu2.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_tb_cpu2.vvp | findstr /C:"ALL AXISA MILESTONE-2 TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_cpu2 & "%VVP%" out_tb_cpu2.vvp & goto :error)
echo   OK (tohost=324 - chained BARYON+MESON+GLUON+LOAD/STORE+JAL result; r3=3 - GLUON same-bank 2R+1W, direct peek)

echo.
echo ===== AxISA demo: "particle collider" (real .axasm source, sw\axasm.py) =====
python sw\axasm.py sw\demo_collider.axasm sw\collider.hex
if %errorlevel% neq 0 goto :error

"%IVERILOG%" -o out_collider.vvp "-DINSTR_HEX=\"sw/collider.hex\"" rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_run.v
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
"%IVERILOG%" -o out_nocsingle.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v rtl\shared_mem_backing.v rtl\router.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v tb\tb_noc_single.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_nocsingle.vvp | findstr /C:"ALL AXISA NOC SINGLE-CORE TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_noc_single & "%VVP%" out_nocsingle.vvp & goto :error)
echo   OK (tohost=99 - real STORE then LOAD round trip through the NoC)

echo.
echo ===== Mini-SoC: AxISA multi-core mesh (3D 8x8x16, 1023 cores + 1 memory) =====
echo NOTE: this section alone takes several minutes to compile (over 1000 core instances) - by far the slowest step in this suite
python sw\axasm.py sw\shared_producer.axasm sw\shared_producer.hex
if %errorlevel% neq 0 goto :error
python sw\axasm.py sw\shared_consumer.axasm sw\shared_consumer.hex
if %errorlevel% neq 0 goto :error
echo c0 (consumer, busy-waits, 13 hops from memory) reads c1's (producer, 12 hops) payload through the arbitrated NoC - real X+Y+Z routing, not just X/Y - only correct (127) if it genuinely observed the other core's write; c2-c1022 run independently (test1.hex) alongside
"%IVERILOG%" -o out_soc.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v rtl\shared_mem_backing.v rtl\router.v rtl\noc_core_adapter.v rtl\noc_mem_adapter.v rtl\soc_top.v tb\tb_soc.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_soc.vvp | findstr /C:"PASS: cross-core communication verified" >nul
if %errorlevel% neq 0 (echo FAILED: AxISA mini-SoC & "%VVP%" out_soc.vvp & goto :error)
echo   OK (c0=127, c1=77, c2-c1022=200, all 1023 concurrent, cross-core communication verified through real Z-axis routing)

echo.
echo ===== AxISA mini-kernel: UART console + one-command shell (real .axasm source) =====
python sw\axasm.py sw\mini_shell.axasm sw\mini_shell.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_shell.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_uart_shell.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_shell.vvp | findstr /C:"ALL AXISA UART SHELL TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_uart_shell & "%VVP%" out_shell.vvp & goto :error)
echo   OK ("hi" recognized - prompt+echo+"OK" byte-exact through the simulated console)

"%IVERILOG%" -o out_shell_nomatch.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_uart_shell_nomatch.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_shell_nomatch.vvp | findstr /C:"ALL AXISA UART SHELL NOMATCH TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_uart_shell_nomatch & "%VVP%" out_shell_nomatch.vvp & goto :error)
echo   OK ("xy" correctly NOT recognized - prompt+echo+"?" byte-exact)

echo.
echo ===== AxISA traps 1/3: illegal-instruction (entry+EPC+CAUSE+RFT) =====
python sw\axasm.py sw\trap_illegal.axasm sw\trap_illegal.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_trap1.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_trap_illegal.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_trap1.vvp | findstr /C:"ALL AXISA TRAP-ILLEGAL TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_trap_illegal & "%VVP%" out_trap1.vvp & goto :error)
echo   OK (tohost=88, R/G/B/N survived the round trip, CAUSE/EPC captured correctly)

echo.
echo ===== AxISA traps 2/3: SYSCALL + real user-mode transition + PRIV_VIOLATION =====
python sw\axasm.py sw\trap_syscall.axasm sw\trap_syscall.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_trap2.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_trap_syscall.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_trap2.vvp | findstr /C:"ALL AXISA TRAP-SYSCALL TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_trap_syscall & "%VVP%" out_trap2.vvp & goto :error)
echo   OK (tohost=110, bootstrap into user mode, SYSCALL cause=1, PRIV_VIOLATION cause=3, both round trips verified)

echo.
echo ===== AxISA traps 3/3: external interrupt =====
python sw\axasm.py sw\trap_irq.axasm sw\trap_irq.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_trap3.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_trap_irq.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_trap3.vvp | findstr /C:"ALL AXISA TRAP-IRQ TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_trap_irq & "%VVP%" out_trap3.vvp & goto :error)
echo   OK (tohost=42, IRQ preempted a real spin loop, handler's EPC redirect honored exactly)

"%IVERILOG%" -o out_trap3b.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_trap_irq_squash.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_trap3b.vvp | findstr /C:"ALL AXISA TRAP-IRQ-SQUASH TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_trap_irq_squash & "%VVP%" out_trap3b.vvp & goto :error)
echo   OK (tohost=42, IRQ synced to land exactly on a post-branch squash cycle - EPC still =0x28, not a wrong-path bubble address)

python sw\axasm.py sw\trap_irq_stall.axasm sw\trap_irq_stall.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_trap4.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_trap_irq_stall.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_trap4.vvp | findstr /C:"ALL AXISA TRAP-IRQ-STALL TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_trap_irq_stall & "%VVP%" out_trap4.vvp & goto :error)
echo   OK (tohost=55, IRQ arriving mid-mem_stall correctly deferred until the STORE completed - EPC=0x28, not the store's own address)

echo.
echo ===== AxISA virtual memory: real translation + a recoverable page fault =====
python sw\axasm.py sw\mmu_test.axasm sw\mmu_test.hex
if %errorlevel% neq 0 goto :error
"%IVERILOG%" -o out_mmu.vvp rtl\alu.v rtl\regbank.v rtl\instr_mem.v rtl\data_mem.v rtl\control_unit.v rtl\cpu_core.v rtl\mmu.v tb\tb_mmu.v
if %errorlevel% neq 0 goto :error
"%VVP%" out_mmu.vvp | findstr /C:"ALL AXISA MMU TESTS PASSED" >nul
if %errorlevel% neq 0 (echo FAILED: tb_mmu & "%VVP%" out_mmu.vvp & goto :error)
echo   OK (tohost=342, translated STORE/LOAD round trip proven non-identity via a direct physical-memory peek, page fault CAUSE=4 correctly delivered and recovered via RFT)

echo.
echo ===== ALL SIMULATIONS PASSED =====
exit /b 0

:error
echo.
echo ===== SIMULATION FAILED =====
exit /b 1
