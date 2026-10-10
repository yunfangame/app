@echo off
setlocal
chcp 65001 >nul
set "FENGWO_DIAG_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "FENGWO_DIAG_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%FENGWO_DIAG_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_startup_diagnostics.ps1" %*
if errorlevel 1 echo Diagnostics could not start. Send a screenshot of this window to support.
pause
endlocal
