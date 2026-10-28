@echo off
REM Thin wrapper - the real test list lives in run_sim.py (shared with CI:
REM .github/workflows/axisa-sim.yml). Default here is --all (fast tests +
REM a generated 1023-core 8x8x16 mesh - see MESH_DIMS in run_sim.py).
REM Pass e.g. "run_sim.bat qmeasure" to run a subset, or "--mesh" for mesh only.
cd /d "%~dp0"
if "%~1"=="" (python run_sim.py --all) else (python run_sim.py %*)
exit /b %errorlevel%
