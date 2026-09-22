@echo off
setlocal
if "%~1"=="" (
    if exist "%~dp0tls_targets.json" (
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_tls_diagnostics.ps1" -TargetsFile "%~dp0tls_targets.json"
    ) else (
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_tls_diagnostics.ps1"
    )
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_tls_diagnostics.ps1" -TargetsFile "%~1"
)
if errorlevel 1 echo Collection failed. Please send a screenshot of this window to support.
pause
endlocal
