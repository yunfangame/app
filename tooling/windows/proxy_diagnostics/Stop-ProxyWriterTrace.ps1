param(
    [Parameter(Mandatory = $true)][string]$Session,
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][int]$OwnerPid,
    [Parameter(Mandatory = $true)][long]$OwnerStartTicks,
    [ValidateRange(5, 195)][int]$MaximumSeconds = 60
)
$ErrorActionPreference = 'Stop'
if ($Session -notmatch '^FengWoProxy-[a-f0-9]{32}$') { throw 'Unexpected trace identity.' }
Import-Module (Join-Path $PSScriptRoot 'ProxyWriterTrace.psm1') -Force
$ready = Join-Path $Directory 'watchdog.ready'
$done = Join-Path $Directory 'watchdog.done'
$clock = [Diagnostics.Stopwatch]::StartNew()
[IO.File]::WriteAllText($ready, 'ready')
try {
    while ($clock.Elapsed.TotalSeconds -lt $MaximumSeconds) {
        if (Test-Path -LiteralPath $done) { exit 0 }
        $owner = Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue
        if ($null -eq $owner -or $owner.StartTime.ToUniversalTime().Ticks -ne $OwnerStartTicks) { break }
        Start-Sleep -Milliseconds 250
    }
} finally {
    $result = Stop-FwProxyWriterTrace @{ session = $Session }
    [IO.File]::WriteAllText((Join-Path $Directory 'watchdog-result.json'), (ConvertTo-Json -InputObject @{ stopped = (-not $result.stillRunning); elapsedSeconds = $clock.Elapsed.TotalSeconds }))
}
