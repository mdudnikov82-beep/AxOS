@echo off
echo AxOS simple build

rem Check NASM (try PATH, then tools\nasm.exe)
set "NASM_CMD="
where nasm >nul 2>&1 && set "NASM_CMD=nasm"
if not defined NASM_CMD if exist "%~dp0tools\nasm.exe" set "NASM_CMD=%~dp0tools\nasm.exe"
if not defined NASM_CMD (
  echo [ERROR] NASM not found in PATH or tools\nasm.exe
  goto :end
)
echo Using NASM: %NASM_CMD%

rem Check GCC
where gcc >nul 2>&1
if errorlevel 1 (
  echo [ERROR] GCC not found in PATH
  goto :end
)

rem Check Node
where node >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Node.js not found in PATH
  goto :end
)

if not exist build mkdir build

echo.
echo === Assemble bootloader ===
"%NASM_CMD%" -f bin src\boot\boot.asm -o build\boot.bin || goto :end
"%NASM_CMD%" -f bin src\boot\boot_kernel.asm -o build\boot_kernel.bin || goto :end

echo.
echo === Build kernel (C + ASM) ===
gcc -m32 -ffreestanding -c src\kernel\kernel.c -o build\kernel.o || goto :end
"%NASM_CMD%" -f elf32 src\kernel\kernel_start.asm -o build\kernel_start.o || goto :end

if exist src\kernel\linker.ld (
  set LINKER=src\kernel\linker.ld
) else (
  if exist linker.ld (
    set LINKER=linker.ld
  ) else (
    set LINKER=linker.ld
  )
)

echo.
echo === Linking ===
ld -T %LINKER% -m elf_i386 -o build\kernel.elf build\kernel_start.o build\kernel.o || goto :end

echo.
echo === Objcopy to raw binary ===
objcopy -O binary build\kernel.elf build\kernel.bin || goto :end

echo.
echo === Copy to Unknown and package ===
if not exist Unknown mkdir Unknown
copy /Y build\boot.bin Unknown\boot.bin >nul
copy /Y build\kernel.bin Unknown\kernel.bin >nul

node Unknown\packager.js || goto :end

echo.
echo === Build finished ===
goto :finish

:end
echo.
echo Build failed.

:finish
exit /b 0
