@echo off
setlocal

set "RISCV_PREFIX=C:\axos_build\riscv-gcc\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-"
set "CC=%RISCV_PREFIX%gcc.exe"
set "LD=%RISCV_PREFIX%ld.exe"
set "OBJCOPY=%RISCV_PREFIX%objcopy.exe"
set "QEMU=C:\Program Files\qemu\qemu-system-riscv64.exe"

set "SRC=src\arch\riscv64"
set "USRC=src\user\rv64"
set "OUT=rv64build\out"

if not exist "%CC%" (
    echo ERROR: RISC-V GCC not found: %CC%
    goto :error
)

if not exist %OUT% mkdir %OUT%

set "KFLAGS=-march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany -ffreestanding -fstack-protector-strong -Os -Wall -I%SRC%"
set "UFLAGS=-march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany -ffreestanding -fno-stack-protector -Os -nostdlib -I%USRC%"

echo ===== Kernel =====

echo [1] entry.S...
"%CC%" %KFLAGS% -c %SRC%\boot\entry.S -o %OUT%\entry.o
if %errorlevel% neq 0 goto :error

echo [2] paging.c...
"%CC%" %KFLAGS% -c %SRC%\paging.c -o %OUT%\paging.o
if %errorlevel% neq 0 goto :error

echo [3] pmem.c...
"%CC%" %KFLAGS% -c %SRC%\pmem.c -o %OUT%\pmem.o
if %errorlevel% neq 0 goto :error

echo [4] heap.c...
"%CC%" %KFLAGS% -c %SRC%\heap.c -o %OUT%\heap.o
if %errorlevel% neq 0 goto :error

echo [5] virtio_blk.c...
"%CC%" %KFLAGS% -c %SRC%\virtio_blk.c -o %OUT%\virtio_blk.o
if %errorlevel% neq 0 goto :error

echo [5b] virtio_gpu.c...
"%CC%" %KFLAGS% -c %SRC%\virtio_gpu.c -o %OUT%\virtio_gpu.o
if %errorlevel% neq 0 goto :error

echo [5c] console.c...
"%CC%" %KFLAGS% -c %SRC%\console.c -o %OUT%\console.o
if %errorlevel% neq 0 goto :error

echo [5d] virtio_input.c...
"%CC%" %KFLAGS% -c %SRC%\virtio_input.c -o %OUT%\virtio_input.o
if %errorlevel% neq 0 goto :error

echo [5e] virtio_net.c...
"%CC%" %KFLAGS% -c %SRC%\virtio_net.c -o %OUT%\virtio_net.o
if %errorlevel% neq 0 goto :error

echo [6] fat12.c...
"%CC%" %KFLAGS% -c %SRC%\fat12.c -o %OUT%\fat12.o
if %errorlevel% neq 0 goto :error

echo [6b] vfs.c...
"%CC%" %KFLAGS% -c %SRC%\vfs.c -o %OUT%\vfs.o
if %errorlevel% neq 0 goto :error

echo [7] syscall.c...
"%CC%" %KFLAGS% -c %SRC%\syscall.c -o %OUT%\syscall.o
if %errorlevel% neq 0 goto :error

echo [8] proc.c...
"%CC%" %KFLAGS% -c %SRC%\proc.c -o %OUT%\proc.o
if %errorlevel% neq 0 goto :error

echo [9] elf_loader.c...
"%CC%" %KFLAGS% -c %SRC%\elf_loader.c -o %OUT%\elf_loader.o
if %errorlevel% neq 0 goto :error

echo [10] kernel_main.c...
"%CC%" %KFLAGS% -c %SRC%\kernel_main.c -o %OUT%\kernel_main.o
if %errorlevel% neq 0 goto :error

echo [10b] stack_chk.c...
"%CC%" %KFLAGS% -c %SRC%\stack_chk.c -o %OUT%\stack_chk.o
if %errorlevel% neq 0 goto :error

echo [11] Linking kernel...
"%LD%" -m elf64lriscv -T %SRC%\kernel.ld -o %OUT%\kernel.elf ^
    %OUT%\entry.o ^
    %OUT%\paging.o ^
    %OUT%\pmem.o ^
    %OUT%\heap.o ^
    %OUT%\virtio_blk.o ^
    %OUT%\virtio_gpu.o ^
    %OUT%\console.o ^
    %OUT%\virtio_input.o ^
    %OUT%\virtio_net.o ^
    %OUT%\fat12.o ^
    %OUT%\vfs.o ^
    %OUT%\syscall.o ^
    %OUT%\proc.o ^
    %OUT%\elf_loader.o ^
    %OUT%\kernel_main.o ^
    %OUT%\stack_chk.o
if %errorlevel% neq 0 goto :error

"%OBJCOPY%" -O binary %OUT%\kernel.elf %OUT%\kernel.bin
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\kernel.elf) do echo Kernel: %%~zF bytes

echo.
echo ===== User programs =====

echo [U1] crt0.S...
"%CC%" %UFLAGS% -c %USRC%\crt0.S -o %OUT%\ucrt0.o
if %errorlevel% neq 0 goto :error

echo [U2] hello.c...
"%CC%" %UFLAGS% -c %USRC%\hello.c -o %OUT%\uhello.o
if %errorlevel% neq 0 goto :error

echo [U3] Linking hello...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\hello_rv64.elf %OUT%\ucrt0.o %OUT%\uhello.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\hello_rv64.elf) do echo   hello_rv64.elf: %%~zF bytes

echo [U4] axsh.c...
"%CC%" %UFLAGS% -c %USRC%\axsh.c -o %OUT%\uaxsh.o
if %errorlevel% neq 0 goto :error

echo [U5] Linking axsh...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axsh_rv64.elf %OUT%\ucrt0.o %OUT%\uaxsh.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axsh_rv64.elf) do echo   axsh_rv64.elf:  %%~zF bytes

echo [U6] counter.c...
"%CC%" %UFLAGS% -c %USRC%\counter.c -o %OUT%\ucounter.o
if %errorlevel% neq 0 goto :error

echo [U7] Linking counter...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\counter_rv64.elf %OUT%\ucrt0.o %OUT%\ucounter.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\counter_rv64.elf) do echo   counter_rv64.elf: %%~zF bytes

echo [U8] uptime.c...
"%CC%" %UFLAGS% -c %USRC%\uptime.c -o %OUT%\uuptime.o
if %errorlevel% neq 0 goto :error

echo [U9] Linking uptime...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\uptime_rv64.elf %OUT%\ucrt0.o %OUT%\uuptime.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\uptime_rv64.elf) do echo   uptime_rv64.elf: %%~zF bytes

echo [U10] fdtest.c...
"%CC%" %UFLAGS% -c %USRC%\fdtest.c -o %OUT%\ufdtest.o
if %errorlevel% neq 0 goto :error

echo [U11] Linking fdtest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\fdtest_rv64.elf %OUT%\ucrt0.o %OUT%\ufdtest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\fdtest_rv64.elf) do echo   fdtest_rv64.elf: %%~zF bytes

echo [U12] sleeptest.c...
"%CC%" %UFLAGS% -c %USRC%\sleeptest.c -o %OUT%\usleeptest.o
if %errorlevel% neq 0 goto :error

echo [U13] Linking sleeptest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\sleeptest_rv64.elf %OUT%\ucrt0.o %OUT%\usleeptest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\sleeptest_rv64.elf) do echo   sleeptest_rv64.elf: %%~zF bytes

echo [U14] wxtest.c...
"%CC%" %UFLAGS% -c %USRC%\wxtest.c -o %OUT%\uwxtest.o
if %errorlevel% neq 0 goto :error

echo [U15] Linking wxtest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\wxtest_rv64.elf %OUT%\ucrt0.o %OUT%\uwxtest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\wxtest_rv64.elf) do echo   wxtest_rv64.elf: %%~zF bytes

echo [U16] sbrktest.c...
"%CC%" %UFLAGS% -c %USRC%\sbrktest.c -o %OUT%\usbrktest.o
if %errorlevel% neq 0 goto :error

echo [U17] Linking sbrktest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\sbrktest_rv64.elf %OUT%\ucrt0.o %OUT%\usbrktest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\sbrktest_rv64.elf) do echo   sbrktest_rv64.elf: %%~zF bytes

echo [U18] malloctest.c...
"%CC%" %UFLAGS% -c %USRC%\malloctest.c -o %OUT%\umalloctest.o
if %errorlevel% neq 0 goto :error

echo [U19] Linking malloctest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\malloctest_rv64.elf %OUT%\ucrt0.o %OUT%\umalloctest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\malloctest_rv64.elf) do echo   malloctest_rv64.elf: %%~zF bytes

echo [U20] mallocdf.c...
"%CC%" %UFLAGS% -c %USRC%\mallocdf.c -o %OUT%\umallocdf.o
if %errorlevel% neq 0 goto :error

echo [U21] Linking mallocdf...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\mallocdf_rv64.elf %OUT%\ucrt0.o %OUT%\umallocdf.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\mallocdf_rv64.elf) do echo   mallocdf_rv64.elf: %%~zF bytes

echo [U22] mtetest.c...
"%CC%" %UFLAGS% -c %USRC%\mtetest.c -o %OUT%\umtetest.o
if %errorlevel% neq 0 goto :error

echo [U23] Linking mtetest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\mtetest_rv64.elf %OUT%\ucrt0.o %OUT%\umtetest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\mtetest_rv64.elf) do echo   mtetest_rv64.elf: %%~zF bytes

echo [U24] mteoverfl.c...
"%CC%" %UFLAGS% -c %USRC%\mteoverfl.c -o %OUT%\umteoverfl.o
if %errorlevel% neq 0 goto :error

echo [U25] Linking mteoverfl...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\mteoverfl_rv64.elf %OUT%\ucrt0.o %OUT%\umteoverfl.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\mteoverfl_rv64.elf) do echo   mteoverfl_rv64.elf: %%~zF bytes

echo [U26] gfxdemo.c...
"%CC%" %UFLAGS% -c %USRC%\gfxdemo.c -o %OUT%\ugfxdemo.o
if %errorlevel% neq 0 goto :error

echo [U27] Linking gfxdemo...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\gfxdemo_rv64.elf %OUT%\ucrt0.o %OUT%\ugfxdemo.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\gfxdemo_rv64.elf) do echo   gfxdemo_rv64.elf: %%~zF bytes

echo [U28] gfxtext.c...
"%CC%" %UFLAGS% -c %USRC%\gfxtext.c -o %OUT%\ugfxtext.o
if %errorlevel% neq 0 goto :error

echo [U29] Linking gfxtext...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\gfxtext_rv64.elf %OUT%\ucrt0.o %OUT%\ugfxtext.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\gfxtext_rv64.elf) do echo   gfxtext_rv64.elf: %%~zF bytes

echo [U30] axterm.c...
"%CC%" %UFLAGS% -c %USRC%\axterm.c -o %OUT%\uaxterm.o
if %errorlevel% neq 0 goto :error

echo [U31] Linking axterm...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axterm_rv64.elf %OUT%\ucrt0.o %OUT%\uaxterm.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axterm_rv64.elf) do echo   axterm_rv64.elf: %%~zF bytes

echo [U32] axabout.c...
"%CC%" %UFLAGS% -c %USRC%\axabout.c -o %OUT%\uaxabout.o
if %errorlevel% neq 0 goto :error

echo [U33] Linking axabout...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axabout_rv64.elf %OUT%\ucrt0.o %OUT%\uaxabout.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axabout_rv64.elf) do echo   axabout_rv64.elf: %%~zF bytes

echo [U34] axpaint.c...
"%CC%" %UFLAGS% -c %USRC%\axpaint.c -o %OUT%\uaxpaint.o
if %errorlevel% neq 0 goto :error

echo [U35] Linking axpaint...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axpaint_rv64.elf %OUT%\ucrt0.o %OUT%\uaxpaint.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axpaint_rv64.elf) do echo   axpaint_rv64.elf: %%~zF bytes

echo [U36] axdesk.c...
"%CC%" %UFLAGS% -c %USRC%\axdesk.c -o %OUT%\uaxdesk.o
if %errorlevel% neq 0 goto :error

echo [U37] Linking axdesk...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axdesk_rv64.elf %OUT%\ucrt0.o %OUT%\uaxdesk.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axdesk_rv64.elf) do echo   axdesk_rv64.elf: %%~zF bytes

echo [U38] kptrtest.c...
"%CC%" %UFLAGS% -c %USRC%\kptrtest.c -o %OUT%\ukptrtest.o
if %errorlevel% neq 0 goto :error

echo [U39] Linking kptrtest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\kptrtest_rv64.elf %OUT%\ucrt0.o %OUT%\ukptrtest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\kptrtest_rv64.elf) do echo   kptrtest_rv64.elf: %%~zF bytes

echo [U40] spin.c (TEMP diagnostic)...
"%CC%" %UFLAGS% -c %USRC%\spin.c -o %OUT%\uspin.o
if %errorlevel% neq 0 goto :error

echo [U41] Linking spin...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\spin_rv64.elf %OUT%\ucrt0.o %OUT%\uspin.o
if %errorlevel% neq 0 goto :error

echo [U42] nettest.c...
"%CC%" %UFLAGS% -c %USRC%\nettest.c -o %OUT%\unettest.o
if %errorlevel% neq 0 goto :error

echo [U43] Linking nettest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\nettest_rv64.elf %OUT%\ucrt0.o %OUT%\unettest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\nettest_rv64.elf) do echo   nettest_rv64.elf: %%~zF bytes

echo [U44] arptest.c...
"%CC%" %UFLAGS% -c %USRC%\arptest.c -o %OUT%\uarptest.o
if %errorlevel% neq 0 goto :error

echo [U45] Linking arptest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\arptest_rv64.elf %OUT%\ucrt0.o %OUT%\uarptest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\arptest_rv64.elf) do echo   arptest_rv64.elf: %%~zF bytes

echo [U46] pingtest.c...
"%CC%" %UFLAGS% -c %USRC%\pingtest.c -o %OUT%\upingtest.o
if %errorlevel% neq 0 goto :error

echo [U47] Linking pingtest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\pingtest_rv64.elf %OUT%\ucrt0.o %OUT%\upingtest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\pingtest_rv64.elf) do echo   pingtest_rv64.elf: %%~zF bytes

echo [U48] arpserve.c...
"%CC%" %UFLAGS% -c %USRC%\arpserve.c -o %OUT%\uarpserve.o
if %errorlevel% neq 0 goto :error

echo [U49] Linking arpserve...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\arpserve_rv64.elf %OUT%\ucrt0.o %OUT%\uarpserve.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\arpserve_rv64.elf) do echo   arpserve_rv64.elf: %%~zF bytes

echo [U50] dnstest.c...
"%CC%" %UFLAGS% -c %USRC%\dnstest.c -o %OUT%\udnstest.o
if %errorlevel% neq 0 goto :error

echo [U51] Linking dnstest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\dnstest_rv64.elf %OUT%\ucrt0.o %OUT%\udnstest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\dnstest_rv64.elf) do echo   dnstest_rv64.elf: %%~zF bytes

echo [U52] icmpsrv.c...
"%CC%" %UFLAGS% -c %USRC%\icmpsrv.c -o %OUT%\uicmpsrv.o
if %errorlevel% neq 0 goto :error

echo [U53] Linking icmpsrv...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\icmpsrv_rv64.elf %OUT%\ucrt0.o %OUT%\uicmpsrv.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\icmpsrv_rv64.elf) do echo   icmpsrv_rv64.elf: %%~zF bytes

echo [U54] dhcptest.c...
"%CC%" %UFLAGS% -c %USRC%\dhcptest.c -o %OUT%\udhcptest.o
if %errorlevel% neq 0 goto :error

echo [U55] Linking dhcptest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\dhcptest_rv64.elf %OUT%\ucrt0.o %OUT%\udhcptest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\dhcptest_rv64.elf) do echo   dhcptest_rv64.elf: %%~zF bytes

echo.
echo ===== Disk image =====

if not exist rv64build\fs\rv64 mkdir rv64build\fs\rv64
copy /b %OUT%\hello_rv64.elf     rv64build\fs\rv64\HELLO.ELF
copy /b %OUT%\axsh_rv64.elf      rv64build\fs\rv64\AXSH.ELF
copy /b %OUT%\counter_rv64.elf   rv64build\fs\rv64\COUNTER.ELF
copy /b %OUT%\uptime_rv64.elf    rv64build\fs\rv64\UPTIME.ELF
copy /b %OUT%\fdtest_rv64.elf    rv64build\fs\rv64\FDTEST.ELF
copy /b %OUT%\sleeptest_rv64.elf rv64build\fs\rv64\SLEEPTST.ELF
copy /b %OUT%\wxtest_rv64.elf    rv64build\fs\rv64\WXTEST.ELF
copy /b %OUT%\sbrktest_rv64.elf  rv64build\fs\rv64\SBRKTEST.ELF
copy /b %OUT%\axterm_rv64.elf    rv64build\fs\rv64\AXTERM.ELF
copy /b %OUT%\axabout_rv64.elf   rv64build\fs\rv64\AXABOUT.ELF
copy /b %OUT%\malloctest_rv64.elf rv64build\fs\rv64\MALLOCTS.ELF
copy /b %OUT%\mallocdf_rv64.elf   rv64build\fs\rv64\MALLOCDF.ELF
copy /b %OUT%\mtetest_rv64.elf    rv64build\fs\rv64\MTETEST.ELF
copy /b %OUT%\mteoverfl_rv64.elf  rv64build\fs\rv64\MTEOVER.ELF
copy /b %OUT%\gfxdemo_rv64.elf    rv64build\fs\rv64\GFXDEMO.ELF
copy /b %OUT%\gfxtext_rv64.elf    rv64build\fs\rv64\GFXTEXT.ELF
copy /b %OUT%\axpaint_rv64.elf    rv64build\fs\rv64\AXPAINT.ELF
copy /b %OUT%\axdesk_rv64.elf     rv64build\fs\rv64\AXDESK.ELF
copy /b %OUT%\kptrtest_rv64.elf   rv64build\fs\rv64\KPTRTEST.ELF
copy /b %OUT%\spin_rv64.elf       rv64build\fs\rv64\SPIN.ELF
copy /b %OUT%\nettest_rv64.elf     rv64build\fs\rv64\NETTEST.ELF
copy /b %OUT%\arptest_rv64.elf     rv64build\fs\rv64\ARPTEST.ELF
copy /b %OUT%\pingtest_rv64.elf    rv64build\fs\rv64\PINGTEST.ELF
copy /b %OUT%\arpserve_rv64.elf    rv64build\fs\rv64\ARPSERVE.ELF
copy /b %OUT%\dnstest_rv64.elf     rv64build\fs\rv64\DNSTEST.ELF
copy /b %OUT%\icmpsrv_rv64.elf     rv64build\fs\rv64\ICMPSRV.ELF
copy /b %OUT%\dhcptest_rv64.elf    rv64build\fs\rv64\DHCPTEST.ELF
if %errorlevel% neq 0 goto :error

python tools\make_fat12_rv64.py
if %errorlevel% neq 0 goto :error

echo.
echo Build OK!
echo Kernel : %CD%\%OUT%\kernel.elf
echo Disk   : %CD%\rv64build\disk.img
echo.
echo Run:
echo   rv64build\run_qemu.bat
goto :eof

:error
echo.
echo BUILD FAILED (error %errorlevel%)
exit /b 1
