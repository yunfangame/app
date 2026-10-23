param([string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'ProxyDiagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'RasProxyEvidence.psm1') -Force
$checks = New-Object 'Collections.Generic.List[object]'
function Assert-Check {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $checks.Add([ordered]@{ name = $Name; passed = $true })
    Write-Host ('PASS: ' + $Name)
}
function New-Query {
    param([string]$Bypass = '*.private-company.invalid;localhost', [uint32]$Flags = 3)
    return [pscustomobject]@{
        Success = $true; Error = 0; OptionError = 0
        Configuration = [pscustomobject]@{
            Flags = $Flags; Server = '127.0.0.1:17980'; Bypass = $Bypass
            Pac = 'https://private-user:private-password@private-company.invalid/pac?token=private-token'
        }
    }
}
$reference = New-Query
$reordered = New-Query ' LOCALHOST ;*.PRIVATE-company.invalid;;localhost;'
$comparison = Compare-FwProxyViews $reference $reordered
Assert-Check ($comparison.comparable -and -not $comparison.bypassRawEqual -and $comparison.bypassTokenSetEqual) 'Formatting-only bypass differences are distinguished without modifying client verification'
$missing = New-Query 'localhost'
$comparison = Compare-FwProxyViews $reference $missing
Assert-Check (-not $comparison.bypassTokenSetEqual -and $comparison.missingBypassRuleCount -eq 1 -and $comparison.additionalBypassRuleCount -eq 0) 'Missing bypass rules are not accepted as equivalent'
$extra = New-Query '*.private-company.invalid;localhost;<local>'
$comparison = Compare-FwProxyViews $reference $extra
Assert-Check (-not $comparison.bypassTokenSetEqual -and $comparison.additionalBypassRuleCount -eq 1) 'Added local bypass rule remains a meaningful difference'
$comparison = Compare-FwProxyViews $reference (New-Query '')
Assert-Check (-not $comparison.bypassTokenSetEqual -and $comparison.observedBypassRuleCount -eq 0) 'An empty list cannot hide lost exclusions'
$failed = [pscustomobject]@{ Success = $false; Error = 13; OptionError = 0; Configuration = $null }
Assert-Check (-not (Compare-FwProxyViews $reference $failed).comparable) 'Query failures cannot pass as equal settings'
$state = @{ calls = @() }
$query = {
    param($Name, $Ansi, $Ui)
    $state.calls += [ordered]@{ name = $Name; ansi = $Ansi; ui = $Ui }
    if ($Name -eq 'private-ras-name' -and $Ansi -and $Ui) { return $failed }
    if ($Name -eq 'private-ras-name') { return $missing }
    return $reference
}.GetNewClosure()
$discovery = { [ordered]@{ success = $true; error = 0; names = @('private-ras-name', 'private-ras-name') } }
$evidence = Get-FwRasProxyEvidence -ReadNames $discovery -Query $query
Assert-Check ($evidence.connections.Count -eq 2 -and $state.calls.Count -eq 8) 'Deduplicated default and named connections each query all four native variants'
Assert-Check (@($state.calls | Where-Object { $_.name -eq 'private-ras-name' }).Count -eq 4) 'The nonempty connection name is retained in every native query'
$ras = $evidence.connections[1]
Assert-Check (-not $ras.queries.ansiUi.success -and $ras.queries.ansiUi.error -eq 13 -and $ras.queries.wideUi.success) 'ANSI and Unicode results remain independent when one view fails'
Assert-Check ($ras.comparisons.relativeToDefault.wideUi.missingBypassRuleCount -eq 1 -and -not $ras.activityVerified) 'Saved RAS candidates are not mislabeled active and differences reference the default explicitly'
$serialized = ConvertTo-Json -InputObject $evidence -Depth 24
Assert-Check ($serialized -notmatch 'private-ras-name|private-company\.invalid|private-user|private-password|private-token|127\.0\.0\.1') 'Public evidence contains no connection names, domains, proxy addresses or credentials'
Assert-Check ($ras.queries.wideUi.fengwoEndpoint -and $ras.queries.wideUi.manualEnabled -and $ras.queries.wideUi.bypass.ruleCount -eq 1) 'Endpoint and rule-count evidence survive privacy filtering'
Assert-Check (-not $evidence.proxyValuesWritten -and -not $evidence.refreshPerformed -and -not $evidence.networkProbePerformed) 'Dedicated evidence collection does not claim proxy writes, refreshes or network probes'
$noNames = Get-FwRasProxyEvidence -ReadNames { [ordered]@{ success = $false; error = 5; names = @() } } -ConnectionName 'manual-private-name' -Query { param($Name, $Ansi, $Ui) New-Query }
Assert-Check (-not $noNames.discovery.success -and $noNames.connections.Count -eq 2) 'A failed saved-name discovery is reported and an explicit name can still be queried'
$tooMany = Get-FwRasProxyEvidence -ReadNames { [ordered]@{ success = $true; error = 0; names = @(1..100 | ForEach-Object { 'RAS-' + $_ }) } } -Query { param($Name, $Ansi, $Ui) New-Query }
Assert-Check ($tooMany.discovery.truncated -and $tooMany.connections.Count -eq 65 -and $tooMany.discovery.candidateCount -eq 100) 'Named-connection queries are bounded and truncation is explicit'
$exceptions = Get-FwRasProxyEvidence -ReadNames $discovery -Query { throw 'private-path-or-password' }
$text = ConvertTo-Json -InputObject $exceptions -Depth 24
Assert-Check ($exceptions.connections.Count -eq 2 -and -not $exceptions.connections[0].queries.wideUi.success -and $text -notmatch 'private-path-or-password') 'A native query exception is isolated without leaking its message or inventing a good state'
$tokens = $null
$errors = $null
foreach ($file in @('RasProxyEvidence.psm1', 'Read-RasProxy.ps1', 'Test-RasProxyEvidence.ps1')) {
    $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file), [ref]$tokens, [ref]$errors)
    Assert-Check ($null -eq $errors -or $errors.Count -eq 0) ('PowerShell parser accepts ' + $file)
}
$nativeSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ProxyNative.cs'))
Assert-Check ($nativeSource -match 'public static QueryResult QueryConnection\(string connection, bool ansi, bool ui\)' -and
    $nativeSource -match 'StringToHGlobalAnsi\(connection\)' -and $nativeSource -match 'StringToHGlobalUni\(connection\)' -and
    $nativeSource -match 'FreeHGlobal\(list.Connection\)') 'Native named queries use matching encodings and free the connection allocation'
Add-Type -Path (Join-Path $PSScriptRoot 'ProxyNative.cs') -IgnoreWarnings -WarningAction SilentlyContinue
Initialize-FwProxyNative
Assert-Check ($null -ne ('FengWoProxyDiagnostics.Native' -as [type])) 'Native C# source compiles locally without calling Windows libraries'
$readonlySource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'RasProxyEvidence.psm1')) + [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Read-RasProxy.ps1'))
Assert-Check ($readonlySource -notmatch '::Refresh\(|Invoke-FwRefreshRepair|::Probe\(|SetValue\(|InternetSetOption|Start-FwProxyWriterTrace|Start-Process') 'Dedicated entrypoint cannot invoke write, refresh, probing or elevation paths'
if ($OutputDirectory) {
    $null = [IO.Directory]::CreateDirectory($OutputDirectory)
    $summary = [ordered]@{
        passed = $true; checks = @($checks.ToArray()); powershell = $PSVersionTable.PSVersion.ToString()
        nativeWindowsQueriesExecuted = $false; customerFailureReproducedOnWindows = $false
        completedUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'ras-portable-tests.json'), (ConvertTo-Json -InputObject $summary -Depth 24), (New-Object Text.UTF8Encoding($false)))
}
