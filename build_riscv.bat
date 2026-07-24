@echo off
setlocal

set "RISCV_PREFIX=C:\axos_build\riscv-gcc\xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-"
set "CC=%RISCV_PREFIX%gcc.exe"
set "LD=%RISCV_PREFIX%ld.exe"
set "OBJCOPY=%RISCV_PREFIX%objcopy.exe"
set "QEMU=C:\Program Files\qemu\qemu-system-riscv64.exe"

rem riscv64IMAC not riscv64GC: our C code is soft-float (UFLAGS' -mabi=lp64,
rem no F/D extensions) - the "gc" target defaults to hard-float (lp64d) and
rem the linker refuses to mix float ABIs in one binary ("can't link
rem double-float modules with soft-float modules").
set "RUSTC=%USERPROFILE%\.cargo\bin\rustc.exe"
set "RUST_TARGET=riscv64imac-unknown-none-elf"

set "SRC=src\arch\riscv64"
set "USRC=src\user\rv64"
set "OUT=rv64build\out"

if not exist "%CC%" (
    echo ERROR: RISC-V GCC not found: %CC%
    goto :error
)

if not exist %OUT% mkdir %OUT%

set "KFLAGS=-march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany -ffreestanding -fstack-protector-strong -Os -Wall -I%SRC%"
rem -fno-tree-loop-distribute-patterns: tag144_t (18 bytes, src/user/rv64/malloc.h)
rem is too big for GCC to always inline in a loop at -Os, so without this flag it
rem silently lowers array-fill loops like __mte_fill()'s "__mte_tag[i] = tag;" into
rem calls to memcpy() - undefined in this -nostdlib freestanding build (caught only
rem on a clean CI runner; a local rebuild left a STALE mtetest_rv64.elf in place
rem instead of failing loudly, since this script doesn't halt on a link error).
set "UFLAGS=-march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany -ffreestanding -fno-stack-protector -fno-tree-loop-distribute-patterns -Os -nostdlib -I%USRC%"

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

echo [5d2] virtio_keyboard.c...
"%CC%" %KFLAGS% -c %SRC%\virtio_keyboard.c -o %OUT%\virtio_keyboard.o
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
    %OUT%\virtio_keyboard.o ^
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

echo [U56] httpget.c...
"%CC%" %UFLAGS% -c %USRC%\httpget.c -o %OUT%\uhttpget.o
if %errorlevel% neq 0 goto :error

echo [U57] Linking httpget...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\httpget_rv64.elf %OUT%\ucrt0.o %OUT%\uhttpget.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\httpget_rv64.elf) do echo   httpget_rv64.elf: %%~zF bytes

echo [U57b] dnscachet.c...
"%CC%" %UFLAGS% -c %USRC%\dnscachet.c -o %OUT%\udnscachet.o
if %errorlevel% neq 0 goto :error

echo [U57c] Linking dnscachet...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\dnscachet_rv64.elf %OUT%\ucrt0.o %OUT%\udnscachet.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\dnscachet_rv64.elf) do echo   dnscachet_rv64.elf: %%~zF bytes

echo [U58] tcptest.c...
"%CC%" %UFLAGS% -c %USRC%\tcptest.c -o %OUT%\utcptest.o
if %errorlevel% neq 0 goto :error

echo [U59] Linking tcptest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\tcptest_rv64.elf %OUT%\ucrt0.o %OUT%\utcptest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\tcptest_rv64.elf) do echo   tcptest_rv64.elf: %%~zF bytes

echo [U60] tcpserve.c...
"%CC%" %UFLAGS% -c %USRC%\tcpserve.c -o %OUT%\utcpserve.o
if %errorlevel% neq 0 goto :error

echo [U61] Linking tcpserve...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\tcpserve_rv64.elf %OUT%\ucrt0.o %OUT%\utcpserve.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\tcpserve_rv64.elf) do echo   tcpserve_rv64.elf: %%~zF bytes

echo [U62] httpsrv.c...
"%CC%" %UFLAGS% -c %USRC%\httpsrv.c -o %OUT%\uhttpsrv.o
if %errorlevel% neq 0 goto :error

echo [U63] Linking httpsrv...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\httpsrv_rv64.elf %OUT%\ucrt0.o %OUT%\uhttpsrv.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\httpsrv_rv64.elf) do echo   httpsrv_rv64.elf: %%~zF bytes

echo [U64] grep.c...
"%CC%" %UFLAGS% -c %USRC%\grep.c -o %OUT%\ugrep.o
if %errorlevel% neq 0 goto :error

echo [U65] Linking grep...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\grep_rv64.elf %OUT%\ucrt0.o %OUT%\ugrep.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\grep_rv64.elf) do echo   grep_rv64.elf: %%~zF bytes

echo [U66] forktest.c...
"%CC%" %UFLAGS% -c %USRC%\forktest.c -o %OUT%\uforktest.o
if %errorlevel% neq 0 goto :error

echo [U67] Linking forktest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\forktest_rv64.elf %OUT%\ucrt0.o %OUT%\uforktest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\forktest_rv64.elf) do echo   forktest_rv64.elf: %%~zF bytes

echo [U68] scdemo.c...
"%CC%" %UFLAGS% -c %USRC%\scdemo.c -o %OUT%\uscdemo.o
if %errorlevel% neq 0 goto :error

echo [U69] Linking scdemo...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\scdemo_rv64.elf %OUT%\ucrt0.o %OUT%\uscdemo.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\scdemo_rv64.elf) do echo   scdemo_rv64.elf: %%~zF bytes

echo [U70] cfi.c (NOT -finstrument-functions - would self-instrument)...
"%CC%" %UFLAGS% -fno-omit-frame-pointer -c %USRC%\cfi.c -o %OUT%\ucfi.o
if %errorlevel% neq 0 goto :error

echo [U71] cfidemo.c (WITH -finstrument-functions)...
REM -fno-optimize-sibling-calls is required: without it, -Os tail-calls
REM (jr, not call+ret) the exit-hook out of an instrumented function's
REM epilogue, which collapses that function's OWN stack frame before the
REM hook ever runs - the frame-walk then inspects the CALLER's frame
REM instead, silently checking the wrong thing. x86's cfidemo never hits
REM this because it builds at implicit -O0 (no -O flag), where GCC never
REM performs sibling-call optimization at all.
"%CC%" %UFLAGS% -fno-omit-frame-pointer -fno-optimize-sibling-calls -finstrument-functions -c %USRC%\cfidemo.c -o %OUT%\ucfidemo.o
if %errorlevel% neq 0 goto :error

echo [U72] Linking cfidemo...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\cfidemo_rv64.elf %OUT%\ucrt0.o %OUT%\ucfidemo.o %OUT%\ucfi.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\cfidemo_rv64.elf) do echo   cfidemo_rv64.elf: %%~zF bytes

echo [U73] mlstest.c...
"%CC%" %UFLAGS% -c %USRC%\mlstest.c -o %OUT%\umlstest.o
if %errorlevel% neq 0 goto :error

echo [U74] Linking mlstest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\mlstest_rv64.elf %OUT%\ucrt0.o %OUT%\umlstest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\mlstest_rv64.elf) do echo   mlstest_rv64.elf: %%~zF bytes

echo [U75] sectest.c (fork+seccomp+MLS integration probe)...
"%CC%" %UFLAGS% -c %USRC%\sectest.c -o %OUT%\usectest.o
if %errorlevel% neq 0 goto :error

echo [U76] Linking sectest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\sectest_rv64.elf %OUT%\ucrt0.o %OUT%\usectest.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\sectest_rv64.elf) do echo   sectest_rv64.elf: %%~zF bytes

echo [U77] cfisectest.c (CFI+seccomp integration probe, WITH -finstrument-functions)...
"%CC%" %UFLAGS% -fno-omit-frame-pointer -fno-optimize-sibling-calls -finstrument-functions -c %USRC%\cfisectest.c -o %OUT%\ucfisectest.o
if %errorlevel% neq 0 goto :error

echo [U78] Linking cfisectest...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\cfisectest_rv64.elf %OUT%\ucrt0.o %OUT%\ucfisectest.o %OUT%\ucfi.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\cfisectest_rv64.elf) do echo   cfisectest_rv64.elf: %%~zF bytes

echo [U79] axfiles.c...
"%CC%" %UFLAGS% -c %USRC%\axfiles.c -o %OUT%\uaxfiles.o
if %errorlevel% neq 0 goto :error

echo [U80] Linking axfiles...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axfiles_rv64.elf %OUT%\ucrt0.o %OUT%\uaxfiles.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axfiles_rv64.elf) do echo   axfiles_rv64.elf: %%~zF bytes

echo [U81] ai.c...
"%CC%" %UFLAGS% -c %USRC%\ai.c -o %OUT%\uai.o
if %errorlevel% neq 0 goto :error

echo [U82] Linking ai...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\ai_rv64.elf %OUT%\ucrt0.o %OUT%\uai.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\ai_rv64.elf) do echo   ai_rv64.elf: %%~zF bytes

echo [U83] axcalc.c...
"%CC%" %UFLAGS% -c %USRC%\axcalc.c -o %OUT%\uaxcalc.o
if %errorlevel% neq 0 goto :error

echo [U84] Linking axcalc...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axcalc_rv64.elf %OUT%\ucrt0.o %OUT%\uaxcalc.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axcalc_rv64.elf) do echo   axcalc_rv64.elf: %%~zF bytes

echo [U85] axnotepad.c...
"%CC%" %UFLAGS% -c %USRC%\axnotepad.c -o %OUT%\uaxnotepad.o
if %errorlevel% neq 0 goto :error

echo [U86] Linking axnotepad...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axnotepad_rv64.elf %OUT%\ucrt0.o %OUT%\uaxnotepad.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axnotepad_rv64.elf) do echo   axnotepad_rv64.elf: %%~zF bytes

echo [U87] axsnake.c...
"%CC%" %UFLAGS% -c %USRC%\axsnake.c -o %OUT%\uaxsnake.o
if %errorlevel% neq 0 goto :error

echo [U88] Linking axsnake...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axsnake_rv64.elf %OUT%\ucrt0.o %OUT%\uaxsnake.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axsnake_rv64.elf) do echo   axsnake_rv64.elf: %%~zF bytes

echo [U89] axclock.c...
"%CC%" %UFLAGS% -c %USRC%\axclock.c -o %OUT%\uaxclock.o
if %errorlevel% neq 0 goto :error

echo [U90] Linking axclock...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axclock_rv64.elf %OUT%\ucrt0.o %OUT%\uaxclock.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axclock_rv64.elf) do echo   axclock_rv64.elf: %%~zF bytes

echo [U91] axtodo.c...
"%CC%" %UFLAGS% -c %USRC%\axtodo.c -o %OUT%\uaxtodo.o
if %errorlevel% neq 0 goto :error

echo [U92] Linking axtodo...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axtodo_rv64.elf %OUT%\ucrt0.o %OUT%\uaxtodo.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axtodo_rv64.elf) do echo   axtodo_rv64.elf: %%~zF bytes

echo [U93] axtaskmgr.c...
"%CC%" %UFLAGS% -c %USRC%\axtaskmgr.c -o %OUT%\uaxtaskmgr.o
if %errorlevel% neq 0 goto :error

echo [U94] Linking axtaskmgr...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axtaskmgr_rv64.elf %OUT%\ucrt0.o %OUT%\uaxtaskmgr.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axtaskmgr_rv64.elf) do echo   axtaskmgr_rv64.elf: %%~zF bytes

echo [U95] hello_rust.rs (first Rust program - see the file's own comment
echo       for why no new crt0/loader was needed: same ucrt0.o + user_rv64.ld
echo       as every C program, Rust just needs to export a `main` symbol)...
if not exist "%RUSTC%" (
    echo ERROR: rustc not found: %RUSTC% - install via https://rustup.rs, then: rustup target add %RUST_TARGET%
    goto :error
)
"%RUSTC%" --target %RUST_TARGET% --crate-type bin -C panic=abort -C opt-level=2 --emit=obj -o %OUT%\uhello_rust.o %USRC%\hello_rust.rs
if %errorlevel% neq 0 goto :error

echo [U96] Linking hello_rust...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\hello_rust_rv64.elf %OUT%\ucrt0.o %OUT%\uhello_rust.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\hello_rust_rv64.elf) do echo   hello_rust_rv64.elf: %%~zF bytes

echo [U97] rustpanel.rs (real Rust GUI panel: raw gfx_*/mouse_state
echo       syscalls only, no window.h/gfx_ui.h - see the file's own comment)...
"%RUSTC%" --target %RUST_TARGET% --crate-type bin -C panic=abort -C opt-level=2 --emit=obj -o %OUT%\urustpanel.o %USRC%\rustpanel.rs
if %errorlevel% neq 0 goto :error

echo [U98] Linking rustpanel...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\rustpanel_rv64.elf %OUT%\ucrt0.o %OUT%\urustpanel.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\rustpanel_rv64.elf) do echo   rustpanel_rv64.elf: %%~zF bytes

echo [U99] axchat.c...
"%CC%" %UFLAGS% -c %USRC%\axchat.c -o %OUT%\uaxchat.o
if %errorlevel% neq 0 goto :error

echo [U100] Linking axchat...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axchat_rv64.elf %OUT%\ucrt0.o %OUT%\uaxchat.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axchat_rv64.elf) do echo   axchat_rv64.elf: %%~zF bytes

echo [U101] axbrowser.c...
"%CC%" %UFLAGS% -c %USRC%\axbrowser.c -o %OUT%\uaxbrowser.o
if %errorlevel% neq 0 goto :error

echo [U102] Linking axbrowser...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axbrowser_rv64.elf %OUT%\ucrt0.o %OUT%\uaxbrowser.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axbrowser_rv64.elf) do echo   axbrowser_rv64.elf: %%~zF bytes

echo [U103] axtetris.c...
"%CC%" %UFLAGS% -c %USRC%\axtetris.c -o %OUT%\uaxtetris.o
if %errorlevel% neq 0 goto :error

echo [U104] Linking axtetris...
"%LD%" -m elf64lriscv -T %USRC%\user_rv64.ld -o %OUT%\axtetris_rv64.elf %OUT%\ucrt0.o %OUT%\uaxtetris.o
if %errorlevel% neq 0 goto :error

for %%F in (%OUT%\axtetris_rv64.elf) do echo   axtetris_rv64.elf: %%~zF bytes

echo.
echo ===== Disk image =====

if not exist rv64build\fs\rv64 mkdir rv64build\fs\rv64
copy /b %OUT%\hello_rv64.elf     rv64build\fs\rv64\HELLO.ELF
copy /b %OUT%\axsh_rv64.elf      rv64build\fs\rv64\AXSH.ELF
copy /b %OUT%\ai_rv64.elf        rv64build\fs\rv64\AI.ELF
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
copy /b %OUT%\axfiles_rv64.elf    rv64build\fs\rv64\AXFILES.ELF
copy /b %OUT%\axcalc_rv64.elf     rv64build\fs\rv64\AXCALC.ELF
copy /b %OUT%\axnotepad_rv64.elf  rv64build\fs\rv64\AXNOTE.ELF
copy /b %OUT%\axsnake_rv64.elf    rv64build\fs\rv64\AXSNAKE.ELF
copy /b %OUT%\axclock_rv64.elf    rv64build\fs\rv64\AXCLOCK.ELF
copy /b %OUT%\axtodo_rv64.elf     rv64build\fs\rv64\AXTODO.ELF
copy /b %OUT%\axtaskmgr_rv64.elf  rv64build\fs\rv64\AXTASKM.ELF
copy /b %OUT%\hello_rust_rv64.elf rv64build\fs\rv64\RUSTHI.ELF
copy /b %OUT%\rustpanel_rv64.elf  rv64build\fs\rv64\RUSTPNL.ELF
copy /b %OUT%\axchat_rv64.elf     rv64build\fs\rv64\AXCHAT.ELF
copy /b %OUT%\axbrowser_rv64.elf  rv64build\fs\rv64\AXBROWSR.ELF
copy /b %OUT%\axtetris_rv64.elf   rv64build\fs\rv64\AXTETRIS.ELF
copy /b %OUT%\kptrtest_rv64.elf   rv64build\fs\rv64\KPTRTEST.ELF
copy /b %OUT%\spin_rv64.elf       rv64build\fs\rv64\SPIN.ELF
copy /b %OUT%\nettest_rv64.elf     rv64build\fs\rv64\NETTEST.ELF
copy /b %OUT%\arptest_rv64.elf     rv64build\fs\rv64\ARPTEST.ELF
copy /b %OUT%\pingtest_rv64.elf    rv64build\fs\rv64\PINGTEST.ELF
copy /b %OUT%\arpserve_rv64.elf    rv64build\fs\rv64\ARPSERVE.ELF
copy /b %OUT%\dnstest_rv64.elf     rv64build\fs\rv64\DNSTEST.ELF
copy /b %OUT%\icmpsrv_rv64.elf     rv64build\fs\rv64\ICMPSRV.ELF
copy /b %OUT%\dhcptest_rv64.elf    rv64build\fs\rv64\DHCPTEST.ELF
copy /b %OUT%\httpget_rv64.elf     rv64build\fs\rv64\HTTPGET.ELF
copy /b %OUT%\dnscachet_rv64.elf   rv64build\fs\rv64\DNSCACHE.ELF
copy /b %OUT%\tcptest_rv64.elf     rv64build\fs\rv64\TCPTEST.ELF
copy /b %OUT%\tcpserve_rv64.elf    rv64build\fs\rv64\TCPSERVE.ELF
copy /b %OUT%\httpsrv_rv64.elf     rv64build\fs\rv64\HTTPSRV.ELF
copy /b %OUT%\grep_rv64.elf        rv64build\fs\rv64\GREP.ELF
copy /b %OUT%\forktest_rv64.elf    rv64build\fs\rv64\FORKTEST.ELF
copy /b %OUT%\scdemo_rv64.elf      rv64build\fs\rv64\SCDEMO.ELF
copy /b %OUT%\cfidemo_rv64.elf     rv64build\fs\rv64\CFIDEMO.ELF
copy /b %OUT%\mlstest_rv64.elf     rv64build\fs\rv64\MLSTEST.ELF
copy /b %OUT%\sectest_rv64.elf     rv64build\fs\rv64\SECTEST.ELF
copy /b %OUT%\cfisectest_rv64.elf  rv64build\fs\rv64\CFISECTS.ELF
copy /b %USRC%\index.htm           rv64build\fs\rv64\INDEX.HTM
copy /b %USRC%\term.bmp            rv64build\fs\rv64\TERM.BMP
copy /b %USRC%\about.bmp           rv64build\fs\rv64\ABOUT.BMP
copy /b %USRC%\paint.bmp           rv64build\fs\rv64\PAINT.BMP
copy /b %USRC%\power.bmp           rv64build\fs\rv64\POWER.BMP
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
