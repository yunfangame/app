param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') { throw 'Entrypoint acceptance requires isolated Windows CI.' }
Import-Module (Join-Path $PSScriptRoot 'ProxyDiagnostics.psm1') -Force
$null = [IO.Directory]::CreateDirectory($OutputDirectory)
$baseline = Get-FwProxySnapshot
$originalFingerprint = Get-FwConfigurationFingerprint $baseline
$results = @()
$global:FwProxyTestConsent = ''
function global:Read-Host { param([string]$Prompt) return $global:FwProxyTestConsent }
try {
    foreach ($mode in @('Collect', 'Watch', 'Trace', 'Repair')) {
        $global:FwProxyTestConsent = if ($mode -eq 'Trace') { 'TRACE' } elseif ($mode -eq 'Repair') { 'REFRESH' } else { '' }
        $output = Join-Path $OutputDirectory $mode
        & (Join-Path $PSScriptRoot 'Start-ProxyDiagnostics.ps1') -Mode $mode -SkipNetwork -ObserveSeconds 5 -OutputDirectory $output
        if ($LASTEXITCODE -ne 0) { throw ('Entrypoint failed: ' + $mode) }
        $files = @(Get-ChildItem -LiteralPath $output -Filter 'report.json' -Recurse -File)
        if ($files.Count -ne 1) { throw ('Exactly one report expected: ' + $mode) }
        $report = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        if ($null -ne $report.fatalError -or $report.proxyConfigurationWrittenByTool -or $report.tunOrRoutesModified) { throw ('Unsafe or incomplete report: ' + $mode) }
        if ($mode -in @('Watch', 'Trace')) {
            if ($report.observationSamples -lt 2 -or $report.monitorPerformedWininetQueries -or $report.monitorPerformedNetworkProbes) { throw ('Minimal monitoring contract failed: ' + $mode) }
        }
        if ($mode -eq 'Trace' -and -not $report.writerTrace.traceStopped) { throw 'Writer tracing did not stop.' }
        if ($mode -eq 'Repair' -and $report.repair.status -ne 'refresh_completed_configuration_preserved') { throw 'Native refresh repair did not preserve configuration.' }
        $zips = @(Get-ChildItem -LiteralPath $output -Filter '*.zip' -Recurse -File)
        if ($zips.Count -ne 1) { throw ('Exactly one public ZIP expected: ' + $mode) }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zips[0].FullName)
        try {
            $names = @($archive.Entries | ForEach-Object { $_.FullName })
            if ($names.Count -ne 2 -or @($names | Where-Object { $_ -notin @('report.json', 'events.jsonl') }).Count -gt 0) { throw 'Private material included in report ZIP.' }
        } finally { $archive.Dispose() }
        $after = Get-FwProxySnapshot
        if ((Get-FwConfigurationFingerprint $after) -cne $originalFingerprint) { throw ('Entrypoint changed original proxy/policy configuration: ' + $mode) }
        $results += [ordered]@{ mode = $mode; passed = $true; configurationPreserved = $true; privateMaterialsExcludedFromZip = $true }
    }
} finally {
    Remove-Item -LiteralPath 'Function:global:Read-Host' -ErrorAction SilentlyContinue
    Remove-Variable -Name FwProxyTestConsent -Scope Global -ErrorAction SilentlyContinue
}
$value = [ordered]@{ passed = $true; results = $results; allOriginalConfigurationPreserved = $true; actualCustomerTested = $false; completedUtc = [DateTime]::UtcNow.ToString('o') }
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'cli-modes.json'), (ConvertTo-Json -InputObject $value -Depth 16), (New-Object Text.UTF8Encoding($false)))
Write-Host 'PASS: All customer entrypoints and ZIP privacy checks.'
