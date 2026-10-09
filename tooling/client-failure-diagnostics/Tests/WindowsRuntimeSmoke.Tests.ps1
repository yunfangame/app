[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'WINDOWS_POWERSHELL51_REQUIRED' }
$root=Split-Path -Parent $PSScriptRoot
$script:Passed=0
function Assert-Runtime([bool]$Value,[string]$Reason) { if (-not $Value) { throw $Reason };$script:Passed++;Write-Host ('PASS '+$Reason) }
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1')) {
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw ('UTF8_BOM_REQUIRED '+$file.Name) }
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw ('POWERSHELL51_PARSE_FAILED '+$file.Name) }
}
Assert-Runtime $true 'All PowerShell files are UTF-8 BOM and parse under Desktop 5.1'
$codeFiles=@('ClientCoreSession.cs','NetworkProbe.cs','HttpProbe.cs' | ForEach-Object { Join-Path $root $_ })
Add-Type -Path $codeFiles -CompilerOptions '/langversion:5'
Assert-Runtime ((('FengWoDiagnosticCoreSession' -as [type]) -ne $null) -and (('FengWoNetworkProbe' -as [type]) -ne $null) -and (('FengWoHttpProbe' -as [type]) -ne $null)) 'All three C# helpers compile in C# 5 against Windows .NET Framework'
. (Join-Path $root 'Collect-Client.ps1') -LibraryOnly -NonInteractive
$parentProcess=[Diagnostics.Process]::GetCurrentProcess()
$parentPath=$parentProcess.MainModule.FileName
$parentId=$PID
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('fw-runtime-local-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$listener.Start()
$port=[int]$listener.LocalEndpoint.Port
try {
    $owned=Get-FwClientRuntimeSnapshot -Client ([pscustomobject]@{ExePath=$parentPath}) -Ports @($port) -TimeoutMs 10000
    Assert-Runtime ($owned.Status -eq 'COMPLETE' -and $owned.ListenerQueryStatus -eq 'COMPLETE') 'Native Windows runtime snapshot completes with real localhost listener'
    $ownerRows=@($owned.Listeners | Where-Object { $_.Port -eq $port -and $_.OwnerProcessId -eq $parentId })
    Assert-Runtime ($ownerRows.Count -eq 1) 'Listener belongs to exact original test process PID'
    Assert-Runtime ($ownerRows[0].OwnerRole -eq 'client' -and $ownerRows[0].OwnerVerified -eq $true -and $ownerRows[0].AddressClass -eq 'loopback') 'Owner path identity classifies current process without a FengWo process name'
    $temporaryClient=Join-Path $fixture 'FengWo.exe'
    Copy-Item -LiteralPath $parentPath -Destination $temporaryClient
    $other=Get-FwClientRuntimeSnapshot -Client ([pscustomobject]@{ExePath=$temporaryClient}) -Ports @($port) -TimeoutMs 10000
    $otherRows=@($other.Listeners | Where-Object { $_.Port -eq $port -and $_.OwnerProcessId -eq $parentId })
    Assert-Runtime ($other.Status -eq 'COMPLETE' -and $other.ListenerQueryStatus -eq 'COMPLETE' -and $otherRows.Count -eq 1) 'Alternate local installation snapshot still discovers original listener owner'
    Assert-Runtime ($otherRows[0].OwnerRole -eq 'other_installation_or_application' -and $otherRows[0].OwnerVerified -eq $true) 'Unlaunched copied executable cannot claim original listener'
    $safe=@{Owned=$owned;AlternateInstallation=$other} | ConvertTo-Json -Depth 10
    Assert-Runtime (-not $safe.Contains($parentPath) -and -not $safe.Contains($fixture)) 'Native snapshot evidence excludes executable and fixture paths'
    if ($env:RUNNER_TEMP) {
        $report=Join-Path $env:RUNNER_TEMP 'fwdiag-powershell51'
        [void][IO.Directory]::CreateDirectory($report)
        [IO.File]::WriteAllText((Join-Path $report 'native-runtime-snapshots.json'),$safe,(New-Object Text.UTF8Encoding($false)))
    }
} finally {
    $listener.Stop()
    $parentProcess.Dispose()
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('RESULT passed='+$script:Passed+' failed=0')
