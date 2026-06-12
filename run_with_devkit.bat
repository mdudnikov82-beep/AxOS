@echo off
setlocal

rem Temporarily prepend w64devkit\bin to PATH and run build_simple.bat
set "DEVKIT=%~dp0w64devkit\bin"
if exist "%DEVKIT%\gcc.exe" (
  echo Using w64devkit at %DEVKIT%
  set "PATH=%DEVKIT%;%PATH%"
) else (
  echo [WARN] w64devkit not found at %DEVKIT% — ensure toolchain is installed or adjust path
)

call build_simple.bat

endlocal
exit /b %ERRORLEVEL%
