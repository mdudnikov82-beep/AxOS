@echo off
setlocal
:: ????????? ???? ? ????? w64devkit
set "PATH=C:\axos_build\w64devkit\bin;C:\Users\Maxim\AppData\Local\Programs\Python\Python312;%PATH%"

:: build/ - ? .gitignore, ?? ??????????; ?? ?????? ??????? (CI) ?? ???
:: ???, ? ?????? ?????? ? ??? (boot.bin ????) ???? ??????, ??? mkdir
:: build\libaxiom ?????? ? ??????? - ??? ???? ?????? nasm ?????? ?
:: unable to open output file ?? ????? ?????? ????.
if not exist build mkdir build

echo Compiling boot...
.\tools\nasm.exe -f bin src\boot\boot.asm -o build\boot.bin
if %errorlevel% neq 0 goto :error

:: Флаги компилятора для 64-бит ядра.
:: -mno-red-zone: обязательно для ядра — прерывания используют 128Б "red zone" ниже RSP,
::   что затирало бы локальные переменные GCC. В ядре это ВСЕГДА баг.
:: -fstack-protector-strong: канарейка локальных буферов (см. stack_chk.c) -
::   раньше стояла только у userspace (libaxiom), у самого ядра не было вообще.
set "KFLAGS=-m64 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -mno-red-zone -fstack-protector-strong"

echo Compiling kernel entry...
.\tools\nasm.exe -f elf64 src\kernel\kernel_entry.asm -o build\kernel_entry.o
if %errorlevel% neq 0 goto :error

echo Compiling IDT...
.\tools\nasm.exe -f elf64 src\kernel\idt.asm -o build\idt.o
if %errorlevel% neq 0 goto :error

echo Compiling Kernel (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/kernel.c -o build/kernel.o
if %errorlevel% neq 0 goto :error

echo Compiling Screen (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/screen.c -o build/screen.o
if %errorlevel% neq 0 goto :error

echo Compiling FAT12 driver (C)...
gcc %KFLAGS% -I src/drivers -c src/fs/fat12.c -o build/fat12.o
if %errorlevel% neq 0 goto :error

echo Compiling Paging (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/paging.c -o build/paging.o
if %errorlevel% neq 0 goto :error

echo Compiling TSS (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/tss.c -o build/tss.o
if %errorlevel% neq 0 goto :error

echo Compiling Heap allocator (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/heap.c -o build/heap.o
if %errorlevel% neq 0 goto :error

echo Compiling Tasking (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/tasking.c -o build/tasking.o
if %errorlevel% neq 0 goto :error

echo Compiling Self-test (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/selftest.c -o build/selftest.o
if %errorlevel% neq 0 goto :error

echo Compiling ELF loader (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/elf.c -o build/elf.o
if %errorlevel% neq 0 goto :error

echo Compiling VFS (C)...
gcc %KFLAGS% -I src/drivers -c src/kernel/vfs.c -o build/vfs.o
if %errorlevel% neq 0 goto :error

echo Compiling IDE driver (C)...
gcc %KFLAGS% -I src/drivers -c src/drivers/ide.c -o build/ide.o
if %errorlevel% neq 0 goto :error

echo Compiling mouse driver (C)...
gcc %KFLAGS% -I src/drivers -c src/drivers/mouse.c -o build/mouse.o
if %errorlevel% neq 0 goto :error

echo Compiling speaker driver (C)...
gcc %KFLAGS% -I src/drivers -c src/drivers/speaker.c -o build/speaker.o
if %errorlevel% neq 0 goto :error

echo Compiling PCI driver (C)...
gcc %KFLAGS% -I src/drivers -c src/drivers/pci.c -o build/pci.o
if %errorlevel% neq 0 goto :error

echo Compiling DMA pool (fixed identity-mapped physical memory for drivers)...
gcc %KFLAGS% -I src/drivers -c src/drivers/dma_pool.c -o build/dma_pool.o
if %errorlevel% neq 0 goto :error

echo Compiling virtio-net driver (C)...
gcc %KFLAGS% -I src/drivers -c src/drivers/virtio_net.c -o build/virtio_net.o
if %errorlevel% neq 0 goto :error

echo Compiling KCFI (Forward-edge CFI for syscall_table)...
gcc %KFLAGS% -I src/kernel -c src/kernel/kcfi.c -o build/kcfi.o
if %errorlevel% neq 0 goto :error

echo Compiling stack canary (kernel -fstack-protector-strong support)...
gcc %KFLAGS% -I src/kernel -c src/kernel/stack_chk.c -o build/stack_chk.o
if %errorlevel% neq 0 goto :error

echo Compiling Syscalls...
.\tools\nasm.exe -f elf64 src\kernel\syscalls.asm -o build\syscalls.o
if %errorlevel% neq 0 goto :error

echo Compiling Usermode (ring3 entry)...
.\tools\nasm.exe -f elf64 src\kernel\usermode.asm -o build\usermode.o
if %errorlevel% neq 0 goto :error

echo Linking to PE (64-bit)...
ld -T kernel.ld -m i386pep --file-alignment 0x200 --section-alignment 0x200 build\kernel_entry.o build\idt.o build\kernel.o build\screen.o build\fat12.o build\paging.o build\kcfi.o build\stack_chk.o build\tss.o build\heap.o build\tasking.o build\selftest.o build\elf.o build\vfs.o build\ide.o build\mouse.o build\speaker.o build\pci.o build\dma_pool.o build\virtio_net.o build\syscalls.o build\usermode.o -o build\kernel.exe
if %errorlevel% neq 0 goto :error

echo Stripping to Binary...
:: ???????? ?????? ?????????? ?? EXE ? ???????? ????.
:: -R .reloc ??????? ???????? ??? ???????? ????????? ?????? ?????????
:: (? ??????? ????? ???) - ??? ??? kernel.bin ?? ~3.2 ?? ??????.
objcopy -O binary -R .reloc build\kernel.exe build\kernel.bin
if %errorlevel% neq 0 goto :error

echo Building libaxiom...
if not exist build\libaxiom mkdir build\libaxiom
.\tools\nasm.exe -f elf32 src\libaxiom\src\crt0.asm -o build\libaxiom\crt0.o
if %errorlevel% neq 0 goto :error
.\tools\nasm.exe -f elf32 src\libaxiom\src\syscalls.asm -o build\libaxiom\syscalls.o
if %errorlevel% neq 0 goto :error
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\libaxiom\src\stdio.c -o build\libaxiom\stdio.o
if %errorlevel% neq 0 goto :error
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\libaxiom\src\malloc.c -o build\libaxiom\malloc.o
if %errorlevel% neq 0 goto :error
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\libaxiom\src\stack_chk.c -o build\libaxiom\stack_chk.o
if %errorlevel% neq 0 goto :error
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\libaxiom\src\cfi.c -o build\libaxiom\cfi.o
if %errorlevel% neq 0 goto :error

echo Compiling user program (hello.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\hello.c -o build\hello.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\hello.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\hello.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\hello.exe build\hello.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\hello.bin build\hello.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\hello.elf fs\HELLO.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (exitdemo.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\exitdemo.c -o build\exitdemo.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\exitdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\exitdemo.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\exitdemo.exe build\exitdemo.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\exitdemo.bin build\exitdemo.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\exitdemo.elf fs\EXIT.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (crashdemo.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\crashdemo.c -o build\crashdemo.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\crashdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\crashdemo.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\crashdemo.exe build\crashdemo.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\crashdemo.bin build\crashdemo.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\crashdemo.elf fs\CRASH.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (echo.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\echo.c -o build\echo.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\echo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\echo.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\echo.exe build\echo.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\echo.bin build\echo.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\echo.elf fs\ECHO.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (cat.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\cat.c -o build\cat.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\cat.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\cat.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\cat.exe build\cat.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\cat.bin build\cat.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\cat.elf fs\CAT.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (sh.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\sh.c -o build\sh.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\sh.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\sh.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\sh.exe build\sh.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\sh.bin build\sh.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\sh.elf fs\SH.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (uptime.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\uptime.c -o build\uptime.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\uptime.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\uptime.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\uptime.exe build\uptime.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\uptime.bin build\uptime.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\uptime.elf fs\UPTIME.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (ls.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\ls.c -o build\ls.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\ls.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\ls.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\ls.exe build\ls.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\ls.bin build\ls.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\ls.elf fs\LS.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (sleep_test.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\sleep_test.c -o build\sleep_test.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\sleep_test.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\sleep_test.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\sleep_test.exe build\sleep_test.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\sleep_test.bin build\sleep_test.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\sleep_test.elf fs\SLEEP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (malloc_test.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\malloc_test.c -o build\malloc_test.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\malloc_test.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\malloc_test.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\malloc_test.exe build\malloc_test.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\malloc_test.bin build\malloc_test.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\malloc_test.elf fs\MALLOC.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (rm.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\rm.c -o build\rm.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\rm.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\rm.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\rm.exe build\rm.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\rm.bin build\rm.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\rm.elf fs\RM.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (mkdir.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\mkdir.c -o build\mkdir.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\mkdir.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\mkdir.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\mkdir.exe build\mkdir.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\mkdir.bin build\mkdir.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\mkdir.elf fs\MKDIR.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (ps.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\ps.c -o build\ps.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\ps.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\ps.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\ps.exe build\ps.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\ps.bin build\ps.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\ps.elf fs\PS.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (top.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\top.c -o build\top.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\top.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\top.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\top.exe build\top.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\top.bin build\top.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\top.elf fs\TOP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (grep.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\grep.c -o build\grep.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\grep.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\grep.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\grep.exe build\grep.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\grep.bin build\grep.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\grep.elf fs\GREP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (write.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\write.c -o build\write.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\write.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\write.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\write.exe build\write.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\write.bin build\write.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\write.elf fs\WRITE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (disktool.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\disktool.c -o build\disktool.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\disktool.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\disktool.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\disktool.exe build\disktool.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\disktool.bin build\disktool.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\disktool.elf fs\DISKTOOL.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (lspci.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\lspci.c -o build\lspci.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\lspci.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\lspci.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\lspci.exe build\lspci.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\lspci.bin build\lspci.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\lspci.elf fs\LSPCI.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (nettest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\nettest.c -o build\nettest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\nettest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\nettest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\nettest.exe build\nettest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\nettest.bin build\nettest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\nettest.elf fs\NETTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (arptest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\arptest.c -o build\arptest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\arptest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\arptest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\arptest.exe build\arptest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\arptest.bin build\arptest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\arptest.elf fs\ARPTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (pingtest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\pingtest.c -o build\pingtest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\pingtest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\pingtest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\pingtest.exe build\pingtest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\pingtest.bin build\pingtest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\pingtest.elf fs\PINGTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (dnstest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\dnstest.c -o build\dnstest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\dnstest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\dnstest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\dnstest.exe build\dnstest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\dnstest.bin build\dnstest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\dnstest.elf fs\DNSTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (dhcptest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\dhcptest.c -o build\dhcptest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\dhcptest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\dhcptest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\dhcptest.exe build\dhcptest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\dhcptest.bin build\dhcptest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\dhcptest.elf fs\DHCPTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (tcptest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\tcptest.c -o build\tcptest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\tcptest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\tcptest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\tcptest.exe build\tcptest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\tcptest.bin build\tcptest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\tcptest.elf fs\TCPTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (tcpserve.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\tcpserve.c -o build\tcpserve.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\tcpserve.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\tcpserve.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\tcpserve.exe build\tcpserve.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\tcpserve.bin build\tcpserve.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\tcpserve.elf fs\TCPSERVE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (httpget.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\httpget.c -o build\httpget.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\httpget.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\httpget.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\httpget.exe build\httpget.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\httpget.bin build\httpget.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\httpget.elf fs\HTTPGET.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (dnscachet.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\dnscachet.c -o build\dnscachet.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\dnscachet.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\dnscachet.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\dnscachet.exe build\dnscachet.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\dnscachet.bin build\dnscachet.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\dnscachet.elf fs\DNSCACHE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (httpsrv.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\httpsrv.c -o build\httpsrv.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\httpsrv.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\httpsrv.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\httpsrv.exe build\httpsrv.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\httpsrv.bin build\httpsrv.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\httpsrv.elf fs\HTTPSRV.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (memtest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\memtest.c -o build\memtest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\memtest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\memtest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\memtest.exe build\memtest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\memtest.bin build\memtest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\memtest.elf fs\MEMTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (fdtest.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\fdtest.c -o build\fdtest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\fdtest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\fdtest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\fdtest.exe build\fdtest.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\fdtest.bin build\fdtest.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\fdtest.elf fs\FDTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (date.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\date.c -o build\date.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\date.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\date.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\date.exe build\date.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\date.bin build\date.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\date.elf fs\DATE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (reboot.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\reboot.c -o build\reboot.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\reboot.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\reboot.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\reboot.exe build\reboot.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\reboot.bin build\reboot.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\reboot.elf fs\REBOOT.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (mouse.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\mouse.c -o build\mouse_tool.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\mouse_tool.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\mouse_tool.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\mouse_tool.exe build\mouse_tool.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\mouse_tool.bin build\mouse_tool.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\mouse_tool.elf fs\MOUSE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (beep.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\beep.c -o build\beep.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\beep.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\beep.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\beep.exe build\beep.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\beep.bin build\beep.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\beep.elf fs\BEEP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (clip.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\clip.c -o build\clip.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\clip.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\clip.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\clip.exe build\clip.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\clip.bin build\clip.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\clip.elf fs\CLIP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (ai.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\ai.c -o build\ai.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\ai.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\ai.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\ai.exe build\ai.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\ai.bin build\ai.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\ai.elf fs\AI.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (cfidemo.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\cfidemo.c -o build\cfidemo.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\cfidemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\cfidemo.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\cfidemo.exe build\cfidemo.bin
if %errorlevel% neq 0 goto :error

echo Wrapping flat binary in minimal ELF32...
python tools\make_elf.py build\cfidemo.bin build\cfidemo.elf
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\cfidemo.elf fs\CFI.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (wxdemo.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\wxdemo.c -o build\wxdemo.o
if %errorlevel% neq 0 goto :error

ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\wxdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\wxdemo.exe
if %errorlevel% neq 0 goto :error

objcopy -O binary build\wxdemo.exe build\wxdemo.bin
if %errorlevel% neq 0 goto :error

python tools\make_elf.py build\wxdemo.bin build\wxdemo.elf
if %errorlevel% neq 0 goto :error

copy /b build\wxdemo.elf fs\WXDEMO.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (scdemo.c)...
gcc -m32 -ffreestanding -fstack-protector -finstrument-functions -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\scdemo.c -o build\scdemo.o
if %errorlevel% neq 0 goto :error

ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\scdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\scdemo.exe
if %errorlevel% neq 0 goto :error

objcopy -O binary build\scdemo.exe build\scdemo.bin
if %errorlevel% neq 0 goto :error

python tools\make_elf.py build\scdemo.bin build\scdemo.elf
if %errorlevel% neq 0 goto :error

copy /b build\scdemo.elf fs\SCDEMO.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (rv32i.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\rv32i.c -o build\rv32i.o
if %errorlevel% neq 0 goto :error

ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 --allow-multiple-definition build\libaxiom\crt0.o build\rv32i.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\rv32i.exe
if %errorlevel% neq 0 goto :error

objcopy -O binary build\rv32i.exe build\rv32i.bin
if %errorlevel% neq 0 goto :error

python tools\make_elf.py build\rv32i.bin build\rv32i.elf
if %errorlevel% neq 0 goto :error

copy /b build\rv32i.elf fs\RV32I.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (rv32i_full.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\rv32i_full.c -o build\rv32i_full.o
if %errorlevel% neq 0 goto :error

ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 --allow-multiple-definition build\libaxiom\crt0.o build\rv32i_full.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o build\libaxiom\stack_chk.o build\libaxiom\cfi.o -o build\rv32i_full.exe
if %errorlevel% neq 0 goto :error

objcopy -O binary build\rv32i_full.exe build\rv32i_full.bin
if %errorlevel% neq 0 goto :error

python tools\make_elf.py build\rv32i_full.bin build\rv32i_full.elf
if %errorlevel% neq 0 goto :error

copy /b build\rv32i_full.elf fs\RVMTE.BIN
if %errorlevel% neq 0 goto :error

echo Building FAT12 RAM-disk image from fs/...
python tools\make_fat12.py
if %errorlevel% neq 0 goto :error

echo Creating image...
copy /b build\boot.bin + build\kernel.bin build\os-image.bin
echo Padding image to 1.44MB...
powershell -Command "$file = 'build\os-image.bin'; $size = (Get-Item $file).Length; $padding = 1474560 - $size; if ($padding -gt 0) { $stream = [System.IO.File]::OpenWrite($file); $stream.Seek($size, 'Begin'); $stream.Write((New-Object byte[] $padding), 0, $padding); $stream.Close() }"

echo Writing FAT12 filesystem into build/disk.img (first 256KB, LBA 0-511)...
powershell -Command "$disk = 'build\disk.img'; $fat = [System.IO.File]::ReadAllBytes('build\fat12.bin'); $stream = [System.IO.File]::Open($disk, 'OpenOrCreate', 'Write'); $stream.Write($fat, 0, $fat.Length); if ($stream.Length -lt 10485760) { $stream.SetLength(10485760) }; $stream.Close()"

:: =================================================================
::  ????????? ??????????? demo-????? (mode 13h) - ?? ????? ????????
::  ??, ????????? boot.bin + ????????? ????-????. ??. gfx_demo.c.
:: =================================================================
echo Assembling graphics bootloader (boot_gfx.asm)...
.\tools\nasm.exe -f bin src\boot\boot_gfx.asm -o build\boot_gfx.bin
if %errorlevel% neq 0 goto :error

echo Assembling graphics kernel entry...
.\tools\nasm.exe -f elf32 src\kernel\kernel_gfx_entry.asm -o build\kernel_gfx_entry.o
if %errorlevel% neq 0 goto :error

echo Assembling graphics IDT (mouse IRQ12 only)...
.\tools\nasm.exe -f elf32 src\kernel\idt_gfx.asm -o build\idt_gfx.o
if %errorlevel% neq 0 goto :error

echo Compiling graphics demo (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src\kernel\gfx_demo.c -o build\gfx_demo.o
if %errorlevel% neq 0 goto :error

echo Compiling mouse driver for graphics demo (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src\drivers\mouse.c -o build\mouse_gfx.o
if %errorlevel% neq 0 goto :error

echo Linking graphics kernel (32-бит, отдельный kernel_gfx.ld)...
ld -T kernel_gfx.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\kernel_gfx_entry.o build\idt_gfx.o build\gfx_demo.o build\mouse_gfx.o -o build\kernel_gfx.exe
if %errorlevel% neq 0 goto :error

echo Stripping graphics kernel to flat binary...
objcopy -O binary build\kernel_gfx.exe build\kernel_gfx.bin
if %errorlevel% neq 0 goto :error

echo Creating graphics demo image...
copy /b build\boot_gfx.bin + build\kernel_gfx.bin build\os-image-gfx.bin
if %errorlevel% neq 0 goto :error
echo Padding graphics image to 1.44MB...
powershell -Command "$file = 'build\os-image-gfx.bin'; $size = (Get-Item $file).Length; $padding = 1474560 - $size; if ($padding -gt 0) { $stream = [System.IO.File]::OpenWrite($file); $stream.Seek($size, 'Begin'); $stream.Write((New-Object byte[] $padding), 0, $padding); $stream.Close() }"

:: =================================================================
::  Graphical Shell (os-image-shell.bin) — replaces gfx_demo with
::  a proper desktop: icons, terminal, about screen, mouse + kbd.
:: =================================================================
echo.
echo ===== Graphical Shell =====

echo Assembling shell bootloader (boot_shell.asm - VBE 800x600x32)...
.\tools\nasm.exe -f bin src\boot\boot_shell.asm -o build\boot_shell.bin
if %errorlevel% neq 0 goto :error

echo Assembling shell IDT (keyboard IRQ1 + mouse IRQ12)...
.\tools\nasm.exe -f elf32 src\kernel\idt_shell.asm -o build\idt_shell.o
if %errorlevel% neq 0 goto :error

echo Generating embedded icon data (BMP -^> C array)...
python tools\bmp_to_c.py build\icons_data.h src\kernel\term.bmp term_bmp src\kernel\about.bmp about_bmp
if %errorlevel% neq 0 goto :error

echo Compiling graphical shell (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -I build -c src\kernel\gfx_shell.c -o build\gfx_shell.o
if %errorlevel% neq 0 goto :error

echo Compiling mouse driver for shell...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src\drivers\mouse.c -o build\mouse_shell.o
if %errorlevel% neq 0 goto :error

echo Linking graphical shell kernel...
ld -T kernel_gfx.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\kernel_gfx_entry.o build\idt_shell.o build\gfx_shell.o build\mouse_shell.o -o build\kernel_shell.exe
if %errorlevel% neq 0 goto :error

echo Stripping to flat binary...
objcopy -O binary build\kernel_shell.exe build\kernel_shell.bin
if %errorlevel% neq 0 goto :error

echo Creating shell image...
copy /b build\boot_shell.bin + build\kernel_shell.bin build\os-image-shell.bin
if %errorlevel% neq 0 goto :error
echo Padding shell image to 1.44MB...
powershell -Command "$file = 'build\os-image-shell.bin'; $size = (Get-Item $file).Length; $padding = 1474560 - $size; if ($padding -gt 0) { $stream = [System.IO.File]::OpenWrite($file); $stream.Seek($size, 'Begin'); $stream.Write((New-Object byte[] $padding), 0, $padding); $stream.Close() }"

echo Success!
exit /b 0

:error
echo ERROR! Something went wrong.
exit /b 1