@echo off
setlocal
cd /d "%~dp0.."

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AX-BOOTSTRAP.ps1"

if errorlevel 1 (
  echo.
  echo AX Execution Bridge bootstrap FAILED.
  pause
  exit /b 1
)

echo.
echo AX Execution Bridge bootstrap completed.
echo Keep this PC online. AX can continue through the configured self-hosted runner.
pause
