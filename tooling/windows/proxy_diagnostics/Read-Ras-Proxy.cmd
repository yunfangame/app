@echo off
setlocal
set "FW_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "FW_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%FW_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Read-RasProxy.ps1"
set "FW_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %FW_EXIT%
