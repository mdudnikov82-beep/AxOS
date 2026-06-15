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

echo Compiling user program (hello.c)...
.\tools\nasm.exe -f elf32 src\user\start.asm -o build\user_start.o
if %errorlevel% neq 0 goto :error

gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -c src\user\hello.c -o build\hello.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\user_start.o build\hello.o -o build\hello.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\hello.exe build\hello.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\hello.bin fs\HELLO.BIN
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