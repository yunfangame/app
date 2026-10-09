@echo off
setlocal
chcp 65001 >nul
title FengWo Client Timeout Diagnostics
if not exist "%~dp0ClientCoreSession.cs" (
  echo Please extract the complete ZIP before running.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-Client.ps1" -NonInteractive
pause
endlocal
