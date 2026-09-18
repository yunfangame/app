@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_crash_diagnostics.ps1"
if errorlevel 1 echo Collection failed. Please send a screenshot of this window to support.
pause
