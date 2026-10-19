param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') { throw 'This mutating fixture requires an isolated Windows CI runner.' }
Import-Module (Join-Path $PSScriptRoot 'ProxyDiagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProxyWriterTrace.psm1') -Force
$null = [IO.Directory]::CreateDirectory($OutputDirectory)
$metadata = Get-WinEvent -ListProvider 'Microsoft-Windows-Kernel-Registry'
$schemas = @($metadata.Events | Where-Object { $_.Id -in @(1, 2, 5, 6) } | ForEach-Object { [ordered]@{ id = $_.Id; opcode = [string]$_.Opcode; template = $_.Template } })
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'provider-schemas.json'), (ConvertTo-Json -InputObject $schemas -Depth 10), (New-Object Text.UTF8Encoding($false)))
$baseline = Get-FwProxySnapshot
$fingerprint = Get-FwConfigurationFingerprint $baseline
$path = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path, $true)
if ($null -eq $key) { throw 'Fixture proxy registry key missing.' }
$exists = $key.GetValueNames() -contains 'ProxyEnable'
$original = $key.GetValue('ProxyEnable')
$kind = if ($exists) { $key.GetValueKind('ProxyEnable') } else { $null }
$trace = $null
$child = $null
$evidence = $null
try {
    $trace = Start-FwProxyWriterTrace (Join-Path $OutputDirectory 'private') 8
    Start-Sleep -Milliseconds 700
    $payload = '$k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Internet Settings",$true); try {$k.SetValue("ProxyEnable",1,[Microsoft.Win32.RegistryValueKind]::DWord); Start-Sleep -Seconds 2; $k.SetValue("ProxyEnable",0,[Microsoft.Win32.RegistryValueKind]::DWord); Start-Sleep -Seconds 1} finally {$k.Dispose()}'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $exe = Join-Path $PSHOME 'powershell.exe'
    $child = Start-Process -FilePath $exe -ArgumentList @('-NoLogo', '-NoProfile', '-EncodedCommand', $encoded) -PassThru -WindowStyle Hidden
    $seen = @()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $snapshot = Get-FwProxySnapshot
        $seen += [ordered]@{ atUtc = $snapshot.atUtc; proxyEnable = $snapshot.registry.CurrentUser.ProxyEnable.value }
        Start-Sleep -Milliseconds 200
    } while ($clock.Elapsed.TotalSeconds -lt 5)
    if (-not $child.WaitForExit(5000) -or $child.ExitCode -ne 0) { throw 'Writer fixture did not finish successfully.' }
    $evidence = Complete-FwProxyWriterTrace $trace
    $trace = $null
    $evidence.fixturePid = $child.Id
    $evidence.stateSamples = $seen
    $matching = @($evidence.writers | Where-Object { $_.processId -eq $child.Id -and $_.valueName -eq 'ProxyEnable' -and $_.nativeStatus -in @('0', '0x0', '0x00000000') })
    $evidence.fixtureWriterDetected = $matching.Count -ge 2
    $evidence.fixtureProcessNameResolved = @($matching | Where-Object { $_.processName -ieq 'powershell.exe' }).Count -ge 2
    $evidence.onAndOffObserved = @($seen | Where-Object { $_.proxyEnable -eq 1 }).Count -gt 0 -and @($seen | Where-Object { $_.proxyEnable -eq 0 }).Count -gt 0
    if (-not $evidence.fixtureWriterDetected -or -not $evidence.fixtureProcessNameResolved -or -not $evidence.onAndOffObserved) { throw 'Native writer attribution or state transition detection failed.' }
    if (Test-Path -LiteralPath (Join-Path $OutputDirectory 'private/registry.etl')) { throw 'Unencrypted trace remained after successful capture.' }
} finally {
    if ($null -ne $trace) {
        try { $stop = Stop-FwProxyWriterTrace $trace; if ($stop.stillRunning) { throw 'Trace still active.' } } catch { Write-Warning 'Fixture trace cleanup failed.' }
    }
    if ($null -ne $child) {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
        $child.Dispose()
    }
    if ($exists) { $key.SetValue('ProxyEnable', $original, $kind) } else { $key.DeleteValue('ProxyEnable', $false) }
    $key.Dispose()
    $after = Get-FwProxySnapshot
    $restored = $fingerprint -ceq (Get-FwConfigurationFingerprint $after)
    if ($null -ne $evidence) {
        $evidence.originalConfigurationRestored = $restored
        [IO.File]::WriteAllText((Join-Path $OutputDirectory 'writer-attribution.json'), (ConvertTo-Json -InputObject $evidence -Depth 18), (New-Object Text.UTF8Encoding($false)))
    }
    if (-not $restored) { throw 'Fixture failed to restore original registry/WinINet configuration.' }
}
$bounded = Start-FwProxyWriterTrace (Join-Path $OutputDirectory 'bounded-private') 5
try {
    Start-Sleep -Seconds 22
    $automaticallyStopped = -not (Test-FwProxyTraceRunning $bounded)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'bounded-session.json'), (ConvertTo-Json -InputObject @{ passed = $automaticallyStopped; maximumSeconds = 20; noAuditPolicyChanged = $true; noCustomerComputerUsed = $true }), (New-Object Text.UTF8Encoding($false)))
    if (-not $automaticallyStopped) { throw 'Trace duration limit was not enforced by Windows.' }
} finally { $null = Stop-FwProxyWriterTrace $bounded }
Write-Host 'PASS: Native registry writer, process identity, on/off timing, restoration and bounded trace lifetime.'
