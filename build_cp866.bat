@echo off
setlocal enabledelayedexpansion

echo AxOS ¢?" ø?‘'??ø‘'ñ‘Øç‘?óø‘? ‘?+?‘?óø (Windows)

rem ?‘???ç‘?‘?ç? ?ç?+‘:??ñ?‘<ç ñ?‘?‘'‘?‘??ç?‘'‘<
where nasm >nul 2>&1
if %ERRORLEVEL%==0 (
  set NASM_CMD=nasm
) else if exist "%~dp0tools\nasm.exe" (
  set "NASM_CMD=%~dp0tools\nasm.exe"
  echo [WARN] NASM ?ç ?øü?ç? ? PATH ¢?" ñ‘?õ?>‘?ú‘?‘? %NASM_CMD%
) else (
  echo [ERROR] NASM ?ç ?øü?ç? ? PATH ñ tools\nasm.exe ?‘'‘?‘?‘'‘?‘'?‘?ç‘'
  goto :end
)

where gcc >nul 2>&1 || (echo [ERROR] GCC ?ç ?øü?ç? ? PATH & goto :end)
where ld >nul 2>&1 || (echo [WARN] ld ?ç ?øü?ç? ? PATH ¢?" õ?õ‘??+‘?ü‘'ç ñú w64devkit & rem õ‘????>ñ?)
where objcopy >nul 2>&1 || (echo [WARN] objcopy ?ç ?øü?ç? ? PATH ¢?" õ‘????>ñ? ñ õ?‘???‘'‘?ñ?)
where node >nul 2>&1 || (echo [ERROR] Node.js ?ç ?øü?ç? ? PATH & goto :end)

rem ö?ú?ø‘'? õøõó‘? ‘?+?‘?óñ
if not exist build mkdir build

echo.
echo === ?‘?‘?ç?+>ñ‘???ø?ñç úø?‘?‘?ú‘Øñóø ===
nasm -f bin src\boot\boot.asm -o build\boot.bin
%NASM_CMD% -f bin src\boot\boot.asm -o build\boot.bin
%NASM_CMD% -f bin src\boot\boot_kernel.asm -o build\boot_kernel.bin

echo.
echo === ö+?‘?óø ‘??‘?ø (C + ASM) ===
gcc -m32 -ffreestanding -c src\kernel\kernel.c -o build\kernel.o
nasm -f elf32 src\kernel\kernel_start.asm -o build\kernel_start.o
%NASM_CMD% -f elf32 src\kernel\kernel_start.asm -o build\kernel_start.o

rem ?‘%ç? linker.ld (ó?‘?ç?‘? ñ>ñ src/kernel)
if exist linker.ld (
  set LINKER=linker.ld
) else if exist src\kernel\linker.ld (
  set LINKER=src\kernel\linker.ld
) else (
  echo [WARN] linker.ld ?ç ?øü?ç?, >ñ?ó??óø ??ç‘' úø?ç‘?‘?ñ‘'‘?‘?‘? ‘? ?‘?ñ+ó?ü
  set LINKER=linker.ld
)

echo.
echo === >ñ?ó??óø ===
ld -T %LINKER% -m elf_i386 -o build\kernel.elf build\kernel_start.o build\kernel.o

echo.
echo === ????ç‘?‘'ø‘Åñ‘? ? +ñ?ø‘??ñó ===
objcopy -O binary build\kernel.elf build\kernel.bin

echo.
echo === ??õñ‘???ø?ñç +ñ?ø‘??ñó?? ? Unknown/ ñ ‘?õøó??óø ?+‘?øúø ===
if not exist Unknown mkdir Unknown
copy /Y build\boot.bin Unknown\boot.bin >nul
copy /Y build\kernel.bin Unknown\kernel.bin >nul

node Unknown\packager.js

echo.
echo === ö+?‘?óø úø?ç‘?‘?ç?ø ===
goto :finish

:end
echo.
echo ö+?‘?óø õ‘?ç‘??ø?ø ñú-úø ?‘?ñ+óñ. ?‘???ç‘?‘?‘'ç ‘?‘?‘'ø???ó‘? ñ?‘?‘'‘?‘??ç?‘'??.
goto :finish

:finish
endlocal
exit /b 0

