@echo off
setlocal
:: Указываем путь к папке w64devkit
set "PATH=%~dp0w64devkit\bin;%PATH%"

echo Compiling boot...
.\tools\nasm.exe -f bin src\boot\boot.asm -o build\boot.bin
if %errorlevel% neq 0 goto :error

echo Compiling kernel entry...
.\tools\nasm.exe -f elf32 src\kernel\kernel_entry.asm -o build\kernel_entry.o
if %errorlevel% neq 0 goto :error

echo Compiling IDT...
.\tools\nasm.exe -f elf32 src\kernel\idt.asm -o build\idt.o
if %errorlevel% neq 0 goto :error

echo Compiling Kernel (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/kernel.c -o build/kernel.o
if %errorlevel% neq 0 goto :error

echo Compiling Screen (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/screen.c -o build/screen.o
if %errorlevel% neq 0 goto :error

echo Compiling FAT12 driver (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/fs/fat12.c -o build/fat12.o
if %errorlevel% neq 0 goto :error

echo Compiling Paging (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/paging.c -o build/paging.o
if %errorlevel% neq 0 goto :error

echo Compiling TSS (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/tss.c -o build/tss.o
if %errorlevel% neq 0 goto :error

echo Compiling Heap allocator (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/heap.c -o build/heap.o
if %errorlevel% neq 0 goto :error

echo Compiling Tasking (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/tasking.c -o build/tasking.o
if %errorlevel% neq 0 goto :error

echo Compiling Self-test (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/selftest.c -o build/selftest.o
if %errorlevel% neq 0 goto :error

echo Compiling VFS (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/vfs.c -o build/vfs.o
if %errorlevel% neq 0 goto :error

echo Compiling IDE driver (C)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/drivers/ide.c -o build/ide.o
if %errorlevel% neq 0 goto :error

echo Compiling Syscalls...
.\tools\nasm.exe -f elf32 src\kernel\syscalls.asm -o build\syscalls.o
if %errorlevel% neq 0 goto :error

echo Compiling Usermode (ring3 entry)...
.\tools\nasm.exe -f elf32 src\kernel\usermode.asm -o build\usermode.o
if %errorlevel% neq 0 goto :error

echo Linking to PE...
:: Линкуем в формат, который он понимает (i386pe)
ld -T kernel.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\kernel_entry.o build\idt.o build\kernel.o build\screen.o build\fat12.o build\paging.o build\tss.o build\heap.o build\tasking.o build\selftest.o build\vfs.o build\ide.o build\syscalls.o build\usermode.o -o build\kernel.exe
if %errorlevel% neq 0 goto :error

echo Stripping to Binary...
:: Вырезаем чистое содержимое из EXE в бинарный файл.
:: -R .reloc убирает ненужную для плоского бинарника секцию релокаций
:: (и паддинг перед ней) - без неё kernel.bin на ~3.2 КБ меньше.
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

echo Compiling user program (hello.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\hello.c -o build\hello.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\hello.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\hello.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\hello.exe build\hello.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\hello.bin fs\HELLO.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (exitdemo.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\exitdemo.c -o build\exitdemo.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\exitdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\exitdemo.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\exitdemo.exe build\exitdemo.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\exitdemo.bin fs\EXIT.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (crashdemo.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\crashdemo.c -o build\crashdemo.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\crashdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\crashdemo.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\crashdemo.exe build\crashdemo.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\crashdemo.bin fs\CRASH.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (echo.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\echo.c -o build\echo.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\echo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\echo.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\echo.exe build\echo.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\echo.bin fs\ECHO.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (cat.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\cat.c -o build\cat.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\cat.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\cat.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\cat.exe build\cat.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\cat.bin fs\CAT.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (sh.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\sh.c -o build\sh.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\sh.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\sh.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\sh.exe build\sh.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\sh.bin fs\SH.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (uptime.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\uptime.c -o build\uptime.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\uptime.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\uptime.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\uptime.exe build\uptime.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\uptime.bin fs\UPTIME.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (sleep_test.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\sleep_test.c -o build\sleep_test.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\sleep_test.o build\libaxiom\syscalls.o build\libaxiom\stdio.o -o build\sleep_test.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\sleep_test.exe build\sleep_test.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\sleep_test.bin fs\SLEEP.BIN
if %errorlevel% neq 0 goto :error

echo Building FAT12 RAM-disk image from fs/...
python tools\make_fat12.py
if %errorlevel% neq 0 goto :error

echo Creating image...
copy /b build\boot.bin + build\kernel.bin build\os-image.bin
echo Padding image to 1.44MB...
powershell -Command "$file = 'build\os-image.bin'; $size = (Get-Item $file).Length; $padding = 1474560 - $size; if ($padding -gt 0) { $stream = [System.IO.File]::OpenWrite($file); $stream.Seek($size, 'Begin'); $stream.Write((New-Object byte[] $padding), 0, $padding); $stream.Close() }"

echo Writing FAT12 filesystem into build/disk.img (first 64KB, LBA 0-127)...
powershell -Command "$disk = 'build\disk.img'; $fat = [System.IO.File]::ReadAllBytes('build\fat12.bin'); $stream = [System.IO.File]::Open($disk, 'OpenOrCreate', 'Write'); $stream.Write($fat, 0, $fat.Length); if ($stream.Length -lt 10485760) { $stream.SetLength(10485760) }; $stream.Close()"

echo Success!
pause
exit /b 0

:error
echo ERROR! Something went wrong.
pause
exit /b 1