@echo off
setlocal
set "FW_WINDOW_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "FW_WINDOW_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%FW_WINDOW_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0recover_window.ps1" %*
set "FW_WINDOW_EXIT=%ERRORLEVEL%"
if /i not "%~1"=="-NonInteractive" pause
exit /b %FW_WINDOW_EXIT%
