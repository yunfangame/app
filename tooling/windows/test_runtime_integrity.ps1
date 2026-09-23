param(
    [Parameter(Mandatory = $true)][string]$ProbePath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-IsolatedProbe([string]$Executable, [string]$WorkingDirectory) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $info.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Probe process did not start' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Probe exceeded 20 seconds'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ([string]::IsNullOrWhiteSpace($stdout)) {
            throw "Probe had no JSON result (exit $($process.ExitCode)): $stderr"
        }
        $payload = $stdout | ConvertFrom-Json
        return [pscustomobject]@{
            exitCode = $process.ExitCode
            payload = $payload
        }
    } finally {
        $process.Dispose()
    }
}

function Set-TestIntegrity([string]$Directory, [string]$Level) {
    $result = & "$env:SystemRoot\System32\icacls.exe" $Directory '/setintegritylevel' "(OI)(CI)$Level" '/T' '/L' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not set isolated test integrity: $result" }
}

$resolvedProbe = (Resolve-Path -LiteralPath $ProbePath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('FengWo-Integrity-' + [guid]::NewGuid().ToString('N'))
$report = [ordered]@{
    status = 'running'
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    probeSha256 = (Get-FileHash -LiteralPath $resolvedProbe -Algorithm SHA256).Hash.ToLowerInvariant()
    cases = @()
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $isolatedProbe = Join-Path $testRoot 'FengWoIntegrityProbe.exe'
    Copy-Item -LiteralPath $resolvedProbe -Destination $isolatedProbe
    Set-TestIntegrity $testRoot 'M'
    $medium = Invoke-IsolatedProbe $isolatedProbe $testRoot
    if ($medium.exitCode -ne 0 -or $medium.payload.status -ne 'allowed' -or
        $medium.payload.integrity_rid -lt 8192 -or -not $medium.payload.startup_would_continue) {
        throw "Medium process was not permitted: $($medium | ConvertTo-Json -Depth 8 -Compress)"
    }
    $report.cases += [ordered]@{ name = 'medium-startup-allowed'; result = $medium }

    Set-TestIntegrity $testRoot 'L'
    $low = Invoke-IsolatedProbe $isolatedProbe $testRoot
    if ($low.exitCode -ne 23 -or $low.payload.status -ne 'blocked' -or
        $low.payload.diagnostic_code -ne 'WIN-INTEGRITY-LOW' -or
        $low.payload.integrity_rid -ne 4096 -or $low.payload.startup_would_continue -or
        $low.payload.executable_path -ne $isolatedProbe) {
        throw "Low process did not stop with accurate context: $($low | ConvertTo-Json -Depth 8 -Compress)"
    }
    $report.cases += [ordered]@{ name = 'low-startup-blocked'; result = $low }

    Set-TestIntegrity $testRoot 'M'
    $repaired = Invoke-IsolatedProbe $isolatedProbe $testRoot
    if ($repaired.exitCode -ne 0 -or $repaired.payload.status -ne 'allowed' -or
        $repaired.payload.integrity_rid -lt 8192 -or -not $repaired.payload.startup_would_continue) {
        throw "Repaired process was not permitted: $($repaired | ConvertTo-Json -Depth 8 -Compress)"
    }
    $report.cases += [ordered]@{ name = 'repaired-startup-allowed'; result = $repaired }
    if ((Get-FileHash -LiteralPath $isolatedProbe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.probeSha256) {
        throw 'Integrity-label repair changed executable contents'
    }
    $report.status = 'passed'
} catch {
    $report.status = 'failed'
    $report['error'] = $_.Exception.Message
    throw
} finally {
    $report['finishedAt'] = (Get-Date).ToUniversalTime().ToString('o')
    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
