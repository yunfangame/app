[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'WINDOWS_POWERSHELL51_REQUIRED' }
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Collect-Client.ps1') -LibraryOnly -NonInteractive
$script:Passed=0
function Assert-Collector([bool]$Value,[string]$Reason) { if (-not $Value) { throw $Reason };$script:Passed++;Write-Host ('PASS '+$Reason) }
$reportBases=@($root,[IO.Path]::GetTempPath(),[Environment]::GetFolderPath('Desktop')) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
$existing=@{}
foreach ($base in $reportBases) { foreach ($file in @(Get-ChildItem -LiteralPath $base -Filter 'FengWo-Client-Timeout-Report-*' -ErrorAction SilentlyContinue)) { $existing[$file.FullName]=$true } }
$created=@()
try {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $reply=Invoke-BoundedProcess (Join-Path $PSHOME 'powershell.exe') @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'Collect-Client.ps1'),'-NonInteractive','-AllowNonWindows','-MaxSeconds','60','-ObserveSeconds','1') 20000
    $watch.Stop()
    Assert-Collector (-not $reply.TimedOut -and $reply.ExitCode -eq 0) 'Actual no-client Collector terminates cleanly within bounded 20 seconds'
    foreach ($base in $reportBases) { $created+=@(Get-ChildItem -LiteralPath $base -Filter 'FengWo-Client-Timeout-Report-*' -ErrorAction SilentlyContinue | Where-Object { -not $existing.ContainsKey($_.FullName) }) }
    $zips=@($created | Where-Object { -not $_.PSIsContainer -and $_.Extension -eq '.zip' })
    Assert-Collector ($zips.Count -eq 1) 'Actual no-client Collector creates exactly one partial ZIP'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($zips[0].FullName)
    try { $entries=@($archive.Entries | ForEach-Object { $_.FullName });$reportEntry=$archive.GetEntry('report.json');$reader=New-Object IO.StreamReader($reportEntry.Open());try { $reportText=$reader.ReadToEnd() } finally { $reader.Dispose() } }
    finally { $archive.Dispose() }
    Assert-Collector (($entries -contains '检测报告.html') -and ($entries -contains 'summary.txt') -and ($entries -contains 'report.json') -and ($entries -contains 'results.jsonl')) 'Partial ZIP includes HTML text JSON and JSONL evidence'
    $report=$reportText | ConvertFrom-Json
    Assert-Collector ($report.Completion -eq 'partial' -or $report.completion -eq 'partial') 'Partial report explicitly states incomplete collection'
    Assert-Collector ($reportText.Contains('CLIENT_NOT_FOUND')) 'Missing installation is reported as CLIENT_NOT_FOUND rather than unhandled exception'
    $metadata=@{ElapsedMs=$watch.ElapsedMilliseconds;ExitCode=$reply.ExitCode;TimedOut=$reply.TimedOut;ExpectedReason='CLIENT_NOT_FOUND';ZipEntries=$entries}
    if ($env:RUNNER_TEMP) {
        $reportRoot=Join-Path $env:RUNNER_TEMP 'fwdiag-powershell51';[void][IO.Directory]::CreateDirectory($reportRoot)
        [IO.File]::WriteAllText((Join-Path $reportRoot 'collector-no-client-metadata.json'),($metadata | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath $zips[0].FullName -Destination (Join-Path $reportRoot 'collector-no-client-report.zip')
    }
} finally {
    foreach ($entry in $created) { Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ('RESULT passed='+$script:Passed+' failed=0')
