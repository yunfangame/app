param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][int]$ExpectedMajor
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required' }
if ($PSVersionTable.PSVersion.Major -ne $ExpectedMajor) { throw 'PowerShell runtime differs from the requested test' }
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = (Get-Process -Id $PID).Path
$utf8 = New-Object Text.UTF8Encoding($true)
[void](New-Item -ItemType Directory -Force -Path $EvidenceDirectory)
$checks = New-Object 'Collections.Generic.List[object]'
$sourceFiles = @(
    'tooling/windows/Collect-Startup-Diagnostics.cmd',
    'tooling/windows/collect_startup_diagnostics.ps1',
    'tooling/windows/startup_diagnostics_native.cs',
    'tooling/windows/startup-diagnostics-readme.txt',
    'tooling/windows/window_recovery/Recover-FengWo-Window.cmd',
    'tooling/windows/window_recovery/recover_window.ps1',
    'tooling/windows/window_recovery/window_recovery_native.cs',
    'tooling/windows/window_recovery/readme.txt',
    '.ci/window-scoped/test_readonly_tools.ps1'
)
$sourceHashes = [ordered]@{}
foreach ($relative in $sourceFiles) {
    $path = Join-Path $repository $relative
    $sourceHashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'source.json'), (
    [ordered]@{ commit = $env:GITHUB_SHA; runtime = $PSVersionTable.PSVersion.ToString(); no_launch = $true; inspect_only = $true; source_hashes = $sourceHashes } |
    ConvertTo-Json -Depth 6
), $utf8)

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-ReadOnlyTool {
    param([string]$Name, [string]$ScriptPath, [string[]]$ToolArguments)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $engine
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ToolArguments
    $info.Arguments = (@($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        Assert-Condition ($process.Start()) 'Owned diagnostic process could not start'
        $processHandle = $process.Handle
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(180000)) {
            try { $process.Kill() } catch { }
            throw 'Owned diagnostic process exceeded its three minute limit'
        }
        Assert-Condition ($stdout.Wait(5000) -and $stderr.Wait(5000)) 'Diagnostic streams did not drain'
        [IO.File]::WriteAllText((Join-Path $EvidenceDirectory ($Name + '-stdout.txt')), $stdout.Result, $utf8)
        [IO.File]::WriteAllText((Join-Path $EvidenceDirectory ($Name + '-stderr.txt')), $stderr.Result, $utf8)
        Assert-Condition ($null -ne $process.ExitCode -and $process.ExitCode -eq 0) ('Diagnostic process failed: ' + $Name)
    } finally {
        $process.Dispose()
    }
}

function Assert-ArchiveMatches {
    param([string]$ArchivePath, [string]$ReportPath, [string]$EntryName)
    Assert-Condition (Test-Path -LiteralPath $ArchivePath -PathType Leaf) 'Diagnostic archive was not preserved'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entries = @($archive.Entries | Where-Object { [IO.Path]::GetFileName($_.FullName) -eq $EntryName })
        Assert-Condition ($entries.Count -eq 1) 'Archive report entry is missing or ambiguous'
        $stream = $entries[0].Open()
        $reader = New-Object IO.StreamReader($stream)
        try {
            Assert-Condition ($reader.ReadToEnd() -eq [IO.File]::ReadAllText($ReportPath)) 'Archive report differs from the complete report'
        } finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    } finally {
        $archive.Dispose()
    }
}

$failure = $null
try {
    foreach ($relative in @('tooling/windows/collect_startup_diagnostics.ps1', 'tooling/windows/window_recovery/recover_window.ps1')) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repository $relative), [ref]$tokens, [ref]$errors)
        Assert-Condition (@($errors).Count -eq 0) ('PowerShell parser rejected ' + $relative)
    }
    $checks.Add([ordered]@{ name = 'runtime-parser'; passed = $true })
    $beforeProcesses = @(Get-Process -Name FengWo, fengwoacc, FlClash -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $startupOutput = Join-Path $EvidenceDirectory 'startup-output'
    Invoke-ReadOnlyTool -Name 'startup' -ScriptPath (Join-Path $repository 'tooling/windows/collect_startup_diagnostics.ps1') -ToolArguments @('-NoLaunch', '-NonInteractive', '-ObserveSeconds', '5', '-Days', '1', '-OutputDirectory', $startupOutput)
    $reports = @(Get-ChildItem -LiteralPath $startupOutput -Recurse -Filter 'summary.json' -File)
    Assert-Condition ($reports.Count -eq 1) 'Startup collector did not preserve exactly one full report'
    $summary = Get-Content -LiteralPath $reports[0].FullName -Raw | ConvertFrom-Json
    Assert-Condition ($summary.nativeHelperAvailable -eq $true) 'Startup native helper did not compile'
    Assert-Condition ($summary.launch.status -eq 'skipped_by_request' -and $summary.launch.classification -eq 'launch_skipped' -and $null -eq $summary.launch.startedPid) 'NoLaunch did not retain an explicit skipped launch'
    Assert-Condition ($summary.completedAt -and @($summary.observations).Count -gt 0) 'Startup observation did not complete'
    $reportDirectory = $reports[0].DirectoryName
    foreach ($name in @('summary.txt', 'collection-errors.txt', 'system.json', 'installations.json', 'processes-before.json', 'processes-after.json', 'process-observation.json', 'events-application.json', 'events-code-integrity.json', 'events-applocker-exe.json', 'events-applocker-script.json', 'events-defender.json')) {
        Assert-Condition (Test-Path -LiteralPath (Join-Path $reportDirectory $name) -PathType Leaf) ('Startup report omitted ' + $name)
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $reportDirectory -Filter '*.json' -File)) {
        [void](Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json)
    }
    Assert-ArchiveMatches -ArchivePath ($reportDirectory + '.zip') -ReportPath $reports[0].FullName -EntryName 'summary.json'
    $checks.Add([ordered]@{ name = 'startup-no-launch-full-report'; passed = $true; classification = $summary.launch.classification; observations = @($summary.observations).Count; partial_items = @($summary.collectionErrors).Count })
    $recoveryOutput = Join-Path $EvidenceDirectory 'window-inspection'
    Invoke-ReadOnlyTool -Name 'window-inspection' -ScriptPath (Join-Path $repository 'tooling/windows/window_recovery/recover_window.ps1') -ToolArguments @('-InspectOnly', '-NonInteractive', '-OutputDirectory', $recoveryOutput)
    $windowReport = Join-Path $recoveryOutput 'window-report.json'
    Assert-Condition (Test-Path -LiteralPath $windowReport -PathType Leaf) 'Window inspection report was not preserved'
    $inspection = Get-Content -LiteralPath $windowReport -Raw | ConvertFrom-Json
    Assert-Condition ($inspection.InspectOnly -eq $true -and $inspection.Status -eq 'inspection_only' -and @($inspection.Attempts).Count -eq 0) 'InspectOnly attempted a repair or did not preserve its mode'
    Assert-Condition ($null -ne $inspection.Before -and $inspection.FinishedAt) 'Native window inspection did not complete'
    Assert-ArchiveMatches -ArchivePath ($recoveryOutput + '.zip') -ReportPath $windowReport -EntryName 'window-report.json'
    $checks.Add([ordered]@{ name = 'window-inspect-only-full-report'; passed = $true; attempts = @($inspection.Attempts).Count })
    $afterProcesses = @(Get-Process -Name FengWo, fengwoacc, FlClash -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $beforeIdentity = ($beforeProcesses | Sort-Object) -join ','
    $afterIdentity = ($afterProcesses | Sort-Object) -join ','
    Assert-Condition ($beforeIdentity -ceq $afterIdentity) 'Read-only diagnostics changed client process identities'
    $checks.Add([ordered]@{ name = 'client-process-identities-unchanged'; passed = $true })
} catch {
    $failure = $_.Exception.Message
} finally {
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'verification.json'), (
        [ordered]@{ passed = ($null -eq $failure); runtime = $PSVersionTable.PSVersion.ToString(); checks = @($checks.ToArray()); failure = $failure; no_client_launch = $true; no_window_repair = $true } |
        ConvertTo-Json -Depth 8
    ), $utf8)
}
if ($failure) { throw $failure }
