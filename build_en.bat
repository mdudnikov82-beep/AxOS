@echo off
setlocal enabledelayedexpansion

echo AxOS build (English)

rem --- Find NASM ---
set "NASM_CMD="
where nasm >nul 2>&1 && set "NASM_CMD=nasm"
if not defined NASM_CMD if exist "%~dp0tools\nasm.exe" set "NASM_CMD=%~dp0tools\nasm.exe"
if not defined NASM_CMD if defined ProgramFiles if exist "%ProgramFiles%\NASM\nasm.exe" set "NASM_CMD=%ProgramFiles%\NASM\nasm.exe"
if not defined NASM_CMD if exist "%ProgramFiles(x86)%\NASM\nasm.exe" set "NASM_CMD=%ProgramFiles(x86)%\NASM\nasm.exe"
if not defined NASM_CMD if exist "C:\w64devkit\bin\nasm.exe" set "NASM_CMD=C:\w64devkit\bin\nasm.exe"

if not defined NASM_CMD (
  echo [ERROR] NASM not found in PATH or in common locations (tools, Program Files, w64devkit).
  goto :end
) else (
  echo Using NASM: %NASM_CMD%
)

rem --- Check other tools ---
where gcc >nul 2>&1 || (echo [ERROR] GCC not found in PATH & goto :end)
where ld >nul 2>&1 || echo [WARN] ld not found in PATH — build may fail without linker
where objcopy >nul 2>&1 || echo [WARN] objcopy not found in PATH — binary conversion may fail
where node >nul 2>&1 || (echo [ERROR] Node.js not found in PATH & goto :end)

rem --- Prepare build dir ---
if not exist build mkdir build

echo.
echo === Assemble bootloader ===
"%NASM_CMD%" -f bin src\boot\boot.asm -o build\boot.bin
"%NASM_CMD%" -f bin src\boot\boot_kernel.asm -o build\boot_kernel.bin

echo.
echo === Build kernel (C + ASM) ===
gcc -m32 -ffreestanding -c src\kernel\kernel.c -o build\kernel.o
"%NASM_CMD%" -f elf32 src\kernel\kernel_start.asm -o build\kernel_start.o

rem --- Find linker script ---
set "LINKER=linker.ld"
if exist src\kernel\linker.ld set "LINKER=src\kernel\linker.ld"
if exist linker.ld set "LINKER=linker.ld"

echo.
echo === Linking ===
ld -T %LINKER% -m elf_i386 -o build\kernel.elf build\kernel_start.o build\kernel.o

echo.
echo === Objcopy to raw binary ===
objcopy -O binary build\kernel.elf build\kernel.bin

echo.
echo === Copy to Unknown and package ===
if not exist Unknown mkdir Unknown
copy /Y build\boot.bin Unknown\boot.bin >nul
copy /Y build\kernel.bin Unknown\kernel.bin >nul

node Unknown\packager.js

echo.
echo === Build finished ===
goto :finish

:end
echo.
echo Build aborted due to missing tools.
goto :finish

:finish
endlocal
exit /b 0
