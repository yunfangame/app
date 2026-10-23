param(
    [ValidateRange(1, 65535)][int]$Port = 17980,
    [string[]]$ConnectionName = @(),
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Requires Windows PowerShell 5.1 or later on Windows.' }
Import-Module (Join-Path $PSScriptRoot 'ProxyDiagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'RasProxyEvidence.psm1') -Force
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:LOCALAPPDATA 'FengWoProxyDiagnostics' }
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runDirectory = Join-Path $OutputDirectory ('ras-' + $runId)
$null = [IO.Directory]::CreateDirectory($runDirectory)
$report = [ordered]@{
    toolVersion = 'ras-readonly-1'
    startedUtc = [DateTime]::UtcNow.ToString('o')
    windowsVersion = [Environment]::OSVersion.Version.ToString()
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    is64BitProcess = [Environment]::Is64BitProcess
    proxyValuesWritten = $false
    refreshPerformed = $false
    networkProbePerformed = $false
    evidence = $null
    fatalError = $null
}
$exitCode = 0
try {
    Write-Host 'FengWo RAS proxy read-only collection. Keep the client error visible.'
    Write-Host 'Use the SAME Windows account as the client. Administrator access is not required.'
    Write-Host 'No proxy values, PAC, DNS, routes, TUN, policies or installed apps will be changed.'
    $report.evidence = Get-FwRasProxyEvidence -Port $Port -ConnectionName $ConnectionName
} catch {
    $exitCode = 1
    $report.fatalError = [ordered]@{ type = $_.Exception.GetType().Name; hresult = $_.Exception.HResult }
} finally {
    $report.completedUtc = [DateTime]::UtcNow.ToString('o')
    $file = Join-Path $runDirectory ('FengWo-RAS-Proxy-Report-' + $runId + '.json')
    [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $report -Depth 24), (New-Object Text.UTF8Encoding($false)))
    Write-Host ('Send this JSON and the client exported log to support: ' + $file)
    Write-Host 'No logs are uploaded automatically. This report does not mean the fault is repaired.'
}
exit $exitCode
