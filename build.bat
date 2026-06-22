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
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/kernel.c -o build/kernel.o
if %errorlevel% neq 0 goto :error

echo Compiling Screen (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/screen.c -o build/screen.o
if %errorlevel% neq 0 goto :error

echo Compiling FAT12 driver (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/fs/fat12.c -o build/fat12.o
if %errorlevel% neq 0 goto :error

echo Compiling Paging (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/paging.c -o build/paging.o
if %errorlevel% neq 0 goto :error

echo Compiling TSS (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/tss.c -o build/tss.o
if %errorlevel% neq 0 goto :error

echo Compiling Heap allocator (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/heap.c -o build/heap.o
if %errorlevel% neq 0 goto :error

echo Compiling Tasking (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/tasking.c -o build/tasking.o
if %errorlevel% neq 0 goto :error

echo Compiling Self-test (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/selftest.c -o build/selftest.o
if %errorlevel% neq 0 goto :error

echo Compiling VFS (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/kernel/vfs.c -o build/vfs.o
if %errorlevel% neq 0 goto :error

echo Compiling IDE driver (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/drivers/ide.c -o build/ide.o
if %errorlevel% neq 0 goto :error

echo Compiling mouse driver (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/drivers/mouse.c -o build/mouse.o
if %errorlevel% neq 0 goto :error

echo Compiling speaker driver (C)...
gcc -m32 -Os -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/drivers -c src/drivers/speaker.c -o build/speaker.o
if %errorlevel% neq 0 goto :error

echo Compiling Syscalls...
.\tools\nasm.exe -f elf32 src\kernel\syscalls.asm -o build\syscalls.o
if %errorlevel% neq 0 goto :error

echo Compiling Usermode (ring3 entry)...
.\tools\nasm.exe -f elf32 src\kernel\usermode.asm -o build\usermode.o
if %errorlevel% neq 0 goto :error

echo Linking to PE...
:: Линкуем в формат, который он понимает (i386pe)
ld -T kernel.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\kernel_entry.o build\idt.o build\kernel.o build\screen.o build\fat12.o build\paging.o build\tss.o build\heap.o build\tasking.o build\selftest.o build\vfs.o build\ide.o build\mouse.o build\speaker.o build\syscalls.o build\usermode.o -o build\kernel.exe
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
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\libaxiom\src\malloc.c -o build\libaxiom\malloc.o
if %errorlevel% neq 0 goto :error

echo Compiling user program (hello.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\hello.c -o build\hello.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\hello.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\hello.exe
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
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\exitdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\exitdemo.exe
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
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\crashdemo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\crashdemo.exe
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
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\echo.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\echo.exe
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
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\cat.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\cat.exe
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
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\sh.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\sh.exe
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
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\uptime.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\uptime.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\uptime.exe build\uptime.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\uptime.bin fs\UPTIME.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (ls.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\ls.c -o build\ls.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\ls.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\ls.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\ls.exe build\ls.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\ls.bin fs\LS.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (sleep_test.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\sleep_test.c -o build\sleep_test.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\sleep_test.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\sleep_test.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\sleep_test.exe build\sleep_test.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\sleep_test.bin fs\SLEEP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (malloc_test.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\malloc_test.c -o build\malloc_test.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\malloc_test.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\malloc_test.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\malloc_test.exe build\malloc_test.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\malloc_test.bin fs\MALLOC.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (rm.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\rm.c -o build\rm.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\rm.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\rm.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\rm.exe build\rm.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\rm.bin fs\RM.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (mkdir.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\mkdir.c -o build\mkdir.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\mkdir.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\mkdir.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\mkdir.exe build\mkdir.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\mkdir.bin fs\MKDIR.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (ps.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\ps.c -o build\ps.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\ps.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\ps.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\ps.exe build\ps.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\ps.bin fs\PS.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (top.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\top.c -o build\top.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\top.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\top.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\top.exe build\top.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\top.bin fs\TOP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (grep.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\grep.c -o build\grep.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\grep.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\grep.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\grep.exe build\grep.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\grep.bin fs\GREP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (write.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\write.c -o build\write.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\write.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\write.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\write.exe build\write.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\write.bin fs\WRITE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (disktool.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\disktool.c -o build\disktool.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\disktool.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\disktool.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\disktool.exe build\disktool.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\disktool.bin fs\DISKTOOL.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (fdtest.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\fdtest.c -o build\fdtest.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\fdtest.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\fdtest.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\fdtest.exe build\fdtest.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\fdtest.bin fs\FDTEST.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (date.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\date.c -o build\date.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\date.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\date.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\date.exe build\date.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\date.bin fs\DATE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (reboot.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\reboot.c -o build\reboot.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\reboot.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\reboot.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\reboot.exe build\reboot.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\reboot.bin fs\REBOOT.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (mouse.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\mouse.c -o build\mouse_tool.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\mouse_tool.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\mouse_tool.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\mouse_tool.exe build\mouse_tool.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\mouse_tool.bin fs\MOUSE.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (beep.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\beep.c -o build\beep.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\beep.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\beep.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\beep.exe build\beep.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\beep.bin fs\BEEP.BIN
if %errorlevel% neq 0 goto :error

echo Compiling user program (clip.c)...
gcc -m32 -ffreestanding -mno-sse -mno-sse2 -mno-mmx -I src/libaxiom/include -c src\user\clip.c -o build\clip.o
if %errorlevel% neq 0 goto :error

echo Linking user program...
ld -T src\user\user.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\libaxiom\crt0.o build\clip.o build\libaxiom\syscalls.o build\libaxiom\stdio.o build\libaxiom\malloc.o -o build\clip.exe
if %errorlevel% neq 0 goto :error

echo Stripping user program to flat binary...
objcopy -O binary build\clip.exe build\clip.bin
if %errorlevel% neq 0 goto :error

echo Copying user program into fs/ for FAT12 image...
copy /b build\clip.bin fs\CLIP.BIN
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
::  Отдельный графический demo-образ (mode 13h) - не часть основной
::  ОС, отдельный boot.bin + отдельное мини-ядро. См. gfx_demo.c.
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

echo Linking graphics kernel...
ld -T kernel.ld -m i386pe --file-alignment 0x200 --section-alignment 0x200 build\kernel_gfx_entry.o build\idt_gfx.o build\gfx_demo.o build\mouse_gfx.o -o build\kernel_gfx.exe
if %errorlevel% neq 0 goto :error

echo Stripping graphics kernel to flat binary...
objcopy -O binary build\kernel_gfx.exe build\kernel_gfx.bin
if %errorlevel% neq 0 goto :error

echo Creating graphics demo image...
copy /b build\boot_gfx.bin + build\kernel_gfx.bin build\os-image-gfx.bin
if %errorlevel% neq 0 goto :error
echo Padding graphics image to 1.44MB...
powershell -Command "$file = 'build\os-image-gfx.bin'; $size = (Get-Item $file).Length; $padding = 1474560 - $size; if ($padding -gt 0) { $stream = [System.IO.File]::OpenWrite($file); $stream.Seek($size, 'Begin'); $stream.Write((New-Object byte[] $padding), 0, $padding); $stream.Close() }"

echo Success!
pause
exit /b 0

:error
echo ERROR! Something went wrong.
pause
exit /b 1