param(
    [Parameter(Mandatory = $true)]
    [string]$VerifiedPackageDirectory,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)]
    [int]$ExpectedMajor
)

$ErrorActionPreference = 'Stop'
[void](New-Item -ItemType Directory -Force -Path $EvidenceDirectory)
$checks = New-Object Collections.Generic.List[object]
$failures = New-Object Collections.Generic.List[string]
$scriptPath = Join-Path $PSScriptRoot '../../tooling/windows/collect_startup_diagnostics.ps1'
$scriptPath = [IO.Path]::GetFullPath($scriptPath)
$engine = (Get-Process -Id $PID).Path
$work = Join-Path $env:RUNNER_TEMP ('startup-fixtures-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $work)
$ownedProcesses = New-Object 'Collections.Generic.HashSet[int]'

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-EntryCount {
    param([object]$Value)
    return @($Value | Where-Object { $null -ne $_ }).Count
}

function Stop-FixtureProcesses {
    foreach ($processId in @($ownedProcesses)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        try {
            if ($process.Path.StartsWith($work, [StringComparison]::OrdinalIgnoreCase)) { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    $ownedProcesses.Clear()
}

function New-ApplicationDirectory {
    param([string]$Name, [string]$Kind)
    $directory = Join-Path $work (Join-Path '蜂窝 中文 空格' $Name)
    [void](New-Item -ItemType Directory -Force -Path $directory)
    Get-ChildItem -LiteralPath $script:verifiedApp.DirectoryName -Force | Copy-Item -Destination $directory -Recurse -Force
    if (-not [string]::IsNullOrWhiteSpace($Kind)) {
        Copy-Item -LiteralPath (Join-Path $work "compiled-fixtures/$Kind/FengWo.exe") -Destination (Join-Path $directory 'FengWo.exe') -Force
    }
    return $directory
}

function Invoke-CollectorScenario {
    param([string]$Name, [string]$AppPath, [switch]$NoLaunch, [string]$CollectorPath = $scriptPath, [string]$CmdPath)
    $outputDirectory = Join-Path $EvidenceDirectory $Name
    [void](New-Item -ItemType Directory -Force -Path $outputDirectory)
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $CollectorPath, '-AppPath', $AppPath, '-OutputDirectory', $outputDirectory, '-ObserveSeconds', '5', '-NonInteractive')
    if ($NoLaunch) { $arguments += '-NoLaunch' }
    $beforeIds = @(Get-Process | ForEach-Object { $_.Id })
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ([string]::IsNullOrWhiteSpace($CmdPath)) {
            & $engine @arguments *> (Join-Path $outputDirectory 'collector-console.txt')
        } else {
            $command = '""' + $CmdPath + '" -AppPath "' + $AppPath + '" -OutputDirectory "' + $outputDirectory + '" -ObserveSeconds 5 -NonInteractive'
            if ($NoLaunch) { $command += ' -NoLaunch' }
            $command += ' <nul"'
            & $env:ComSpec /d /s /c $command *> (Join-Path $outputDirectory 'collector-console.txt')
        }
        $collectorExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        foreach ($process in @(Get-Process -Name 'FengWo', 'FlClashCore', 'FlClashHelperService' -ErrorAction SilentlyContinue)) {
            try {
                if ($beforeIds -notcontains $process.Id -and $process.Path.StartsWith($work, [StringComparison]::OrdinalIgnoreCase)) { [void]$ownedProcesses.Add($process.Id) }
            } catch { }
        }
    }
    $reports = @(Get-ChildItem -LiteralPath $outputDirectory -Recurse -Filter 'summary.json' -File)
    Assert-Condition ($reports.Count -eq 1) "$Name did not preserve one JSON report"
    $report = Get-Content -LiteralPath $reports[0].FullName -Raw | ConvertFrom-Json
    Assert-Condition ($report.collectorVersion -eq 1) "$Name has the wrong report format"
    Assert-Condition (Test-Path -LiteralPath (Join-Path $reports[0].DirectoryName 'summary.txt') -PathType Leaf) "$Name did not preserve a text report"
    $archives = @(Get-ChildItem -LiteralPath $outputDirectory -Filter '*.zip' -File)
    Assert-Condition ($archives.Count -eq 1) "$Name did not preserve a ZIP report"
    $expanded = Join-Path $work (Join-Path 'expanded-report' $Name)
    Expand-Archive -LiteralPath $archives[0].FullName -DestinationPath $expanded
    $archivedJson = @(Get-ChildItem -LiteralPath $expanded -Recurse -Filter 'summary.json' -File)
    $archivedText = @(Get-ChildItem -LiteralPath $expanded -Recurse -Filter 'summary.txt' -File)
    Assert-Condition ($archivedJson.Count -eq 1 -and $archivedText.Count -eq 1) "$Name ZIP is missing the final report"
    Assert-Condition ((Get-FileHash -LiteralPath $archivedJson[0].FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $reports[0].FullName -Algorithm SHA256).Hash) "$Name ZIP contains a stale JSON report"
    if ($report.launch.startedPid) { [void]$ownedProcesses.Add([int]$report.launch.startedPid) }
    $checks.Add([ordered]@{ name = "$Name-report"; collector_exit_code = $collectorExitCode; launch_status = $report.launch.status; classification = $report.launch.classification; started_pid = $report.launch.startedPid; observed_count = (Get-EntryCount $report.observations); collection_error_count = (Get-EntryCount $report.collectionErrors); zip_preserved = $true })
    return $report
}

function Test-Scenario {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $checks.Add([ordered]@{ name = $Name; passed = $true })
        Write-Host "PASS: $Name"
    } catch {
        $failures.Add("$Name : $($_.Exception.Message)")
        $checks.Add([ordered]@{ name = $Name; passed = $false; error = $_.Exception.Message })
        Write-Host "FAIL: $Name : $($_.Exception.Message)"
    } finally {
        Stop-FixtureProcesses
    }
}

Test-Scenario 'runtime-and-parser' {
    Assert-Condition ($PSVersionTable.PSVersion.Major -eq $ExpectedMajor) 'Wrong PowerShell major version'
    if ($ExpectedMajor -eq 5) { Assert-Condition ($PSVersionTable.PSVersion.Minor -eq 1) 'Expected Windows PowerShell 5.1' }
    $tokens = $null
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    Assert-Condition ($parseErrors.Count -eq 0) ($parseErrors | Out-String)
}

Test-Scenario 'verified-package-and-fixtures' {
    $hashFile = Join-Path $VerifiedPackageDirectory 'SHA256SUMS'
    Assert-Condition (Test-Path -LiteralPath $hashFile -PathType Leaf) 'Verified package has no SHA256SUMS'
    $verifiedCount = 0
    foreach ($line in @(Get-Content -LiteralPath $hashFile)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        Assert-Condition ($line -match '^([a-fA-F0-9]{64})\s+\*?(.+)$') 'Invalid package checksum record'
        $expectedHash = $Matches[1].ToLowerInvariant()
        $fileName = $Matches[2]
        Assert-Condition ([IO.Path]::GetFileName($fileName) -eq $fileName) 'Checksum file contains an unexpected path'
        $file = Join-Path $VerifiedPackageDirectory $fileName
        Assert-Condition (Test-Path -LiteralPath $file -PathType Leaf) 'Checksum target is absent'
        Assert-Condition ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $expectedHash) 'Verified package checksum mismatch'
        $verifiedCount++
    }
    Assert-Condition ($verifiedCount -gt 0) 'Package checksum list is empty'
    $installers = @(Get-ChildItem -LiteralPath $VerifiedPackageDirectory -Filter '*windows*.exe' -File)
    Assert-Condition ($installers.Count -eq 1) 'Expected one previously verified application installer'
    $bundle = Join-Path $work '验证 安装'
    $installArguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $bundle + '"'), ('/LOG="' + (Join-Path $EvidenceDirectory 'verified-installer.log') + '"'))
    $install = Start-Process -FilePath $installers[0].FullName -ArgumentList $installArguments -Wait -PassThru
    Assert-Condition ($install.ExitCode -eq 0) 'Verified application installer did not complete successfully'
    $app = @(Get-ChildItem -LiteralPath $bundle -Recurse -Filter 'FengWo.exe' -File)
    Assert-Condition ($app.Count -eq 1) 'Expected one FengWo executable in verified installation'
    $script:verifiedApp = $app[0]
    & (Join-Path $PSScriptRoot 'prepare_startup_fixtures.ps1') -OutputDirectory (Join-Path $work 'compiled-fixtures')
    $checks.Add([ordered]@{ name = 'package-provenance'; source_run = 37580333614; source_sha = 'd721e5b73bea9d8e0a627c6898cb72ec624b3a16'; exe_sha256 = (Get-FileHash -LiteralPath $app[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant(); product_version = $app[0].VersionInfo.ProductVersion })
}

Test-Scenario 'native-api-contract' {
    Add-Type -Path (Join-Path ([IO.Path]::GetDirectoryName($scriptPath)) 'startup_diagnostics_native.cs')
    $metadata = [FengWoStartupDiagnostics.NativeProbe]::ReadPe($script:verifiedApp.FullName)
    Assert-Condition ($metadata.Valid -and $metadata.Architecture -eq 'x64' -and $metadata.Machine -eq 34404 -and -not $metadata.IsDll) 'Native PE metadata does not match the verified application'
    Assert-Condition (@($metadata.Imports).Count -gt 0) 'Native PE metadata has no imported DLLs'
    $badPe = Join-Path $work 'invalid-pe.bin'
    [IO.File]::WriteAllBytes($badPe, [byte[]]@(0, 1, 2, 3))
    $invalidMetadata = [FengWoStartupDiagnostics.NativeProbe]::ReadPe($badPe)
    Assert-Condition (-not $invalidMetadata.Valid -and @($invalidMetadata.Errors).Count -gt 0) 'Native PE probe accepted an invalid PE file'
    $fixture = Start-Process -FilePath (Join-Path $work 'compiled-fixtures/window/FengWo.exe') -PassThru
    [void]$ownedProcesses.Add($fixture.Id)
    Start-Sleep -Seconds 1
    $windows = @([FengWoStartupDiagnostics.NativeProbe]::SnapshotWindows($fixture.Id))
    Assert-Condition (@($windows | Where-Object { $_.Visible -and $_.Title -eq '蜂窝加速器 Fixture' -and $_.Rect.Width -gt 0 -and $_.Rect.Height -gt 0 }).Count -gt 0) 'Native window snapshot did not find the visible fixture window'
    $integrity = [FengWoStartupDiagnostics.NativeProbe]::GetIntegrityLevel($PID)
    Assert-Condition ($integrity -in @('untrusted', 'low', 'medium', 'medium-plus', 'high', 'system', 'protected')) 'Native integrity probe could not read its own process token'
    $checks.Add([ordered]@{ name = 'native-evidence'; architecture = $metadata.Architecture; import_count = @($metadata.Imports).Count; window_count = $windows.Count; current_integrity = $integrity })
}

Test-Scenario 'normal-window-chinese-and-space-path' {
    $directory = New-ApplicationDirectory -Name '正常 启动' -Kind 'window'
    $report = Invoke-CollectorScenario -Name 'normal-window' -AppPath (Join-Path $directory 'FengWo.exe')
    Assert-Condition ($report.launch.startedPid -gt 0) 'Window fixture was not launched'
    Assert-Condition ((Get-EntryCount $report.observations) -gt 0) 'Window fixture was not sampled'
    Assert-Condition ($report.nativeHelperAvailable -and $report.launch.classification -eq 'process_running_window_visible') 'Collector did not classify the visible window correctly'
}

Test-Scenario 'abnormal-process-exit' {
    $directory = New-ApplicationDirectory -Name '异常 退出' -Kind 'exit'
    $report = Invoke-CollectorScenario -Name 'abnormal-exit' -AppPath (Join-Path $directory 'FengWo.exe')
    Assert-Condition ($report.launch.exitCode -eq 23) 'Collector did not preserve the fixture exit code 23'
    Assert-Condition ($report.launch.classification -eq 'exited_nonzero') 'Collector did not classify the abnormal process exit correctly'
}

Test-Scenario 'missing-dll-process-exit-code' {
    $directory = New-ApplicationDirectory -Name 'DLL 缺失 退出码' -Kind 'dllmissing'
    $report = Invoke-CollectorScenario -Name 'missing-dll-exit-code' -AppPath (Join-Path $directory 'FengWo.exe')
    Assert-Condition ($report.launch.exitCode -eq -1073741515 -and $report.launch.exitCodeHex -ieq '0xC0000135') 'Collector did not preserve the signed and hexadecimal missing DLL exit code'
}

Test-Scenario 'bad-image-process-exit-code' {
    $directory = New-ApplicationDirectory -Name '映像 错误 退出码' -Kind 'badimage'
    $report = Invoke-CollectorScenario -Name 'bad-image-exit-code' -AppPath (Join-Path $directory 'FengWo.exe')
    Assert-Condition ($report.launch.exitCode -eq -1073741701 -and $report.launch.exitCodeHex -ieq '0xC000007B') 'Collector did not preserve the signed and hexadecimal bad image exit code'
}

Test-Scenario 'running-process-without-window' {
    $directory = New-ApplicationDirectory -Name '无窗 运行' -Kind 'headless'
    $report = Invoke-CollectorScenario -Name 'headless-process' -AppPath (Join-Path $directory 'FengWo.exe')
    Assert-Condition ($report.launch.startedPid -gt 0) 'Headless fixture was not launched'
    Assert-Condition ((Get-EntryCount $report.observations) -gt 0) 'Headless fixture was not sampled'
    Assert-Condition ($report.launch.classification -eq 'process_running_no_visible_window') 'Collector did not classify the running headless process correctly'
}

Test-Scenario 'existing-process-without-window' {
    $directory = New-ApplicationDirectory -Name '既有 无窗' -Kind 'headless'
    $appPath = Join-Path $directory 'FengWo.exe'
    $started = Start-Process -FilePath $appPath -PassThru
    [void]$ownedProcesses.Add($started.Id)
    Start-Sleep -Seconds 1
    $report = Invoke-CollectorScenario -Name 'existing-headless-process' -AppPath $appPath -NoLaunch
    $started.Refresh()
    Assert-Condition (-not $started.HasExited) 'Collector killed a process it did not launch'
    Assert-Condition (-not $report.launch.startedPid) 'NoLaunch unexpectedly created a new process'
    Assert-Condition ((Get-EntryCount $report.observations) -gt 0) 'Collector did not sample the existing process'
    Assert-Condition ($report.launch.classification -eq 'launch_skipped') 'Collector did not preserve the explicit NoLaunch request'
    Assert-Condition (@($report.afterProcesses | Where-Object { $_.pid -eq $started.Id }).Count -eq 1) 'The existing fixture is absent from the final process snapshot'
}

Test-Scenario 'missing-executable-preserves-report' {
    $report = Invoke-CollectorScenario -Name 'missing-executable' -AppPath (Join-Path $work '不存在 的目录/FengWo.exe')
    Assert-Condition (-not $report.launch.startedPid) 'Missing executable unexpectedly started a process'
    Assert-Condition ((Get-EntryCount $report.findings) -gt 0) 'Missing executable produced no diagnostic finding'
    Assert-Condition ($report.launch.classification -eq 'executable_not_found') 'Collector did not classify the missing executable correctly'
}

Test-Scenario 'missing-runtime-file-preserves-report' {
    $directory = New-ApplicationDirectory -Name '缺失 运行库' -Kind ''
    Remove-Item -LiteralPath (Join-Path $directory 'flutter_windows.dll') -Force
    $report = Invoke-CollectorScenario -Name 'missing-runtime-file' -AppPath (Join-Path $directory 'FengWo.exe') -NoLaunch
    $serialized = $report | ConvertTo-Json -Depth 30
    Assert-Condition ($serialized -match 'flutter_windows\.dll') 'Missing Flutter runtime was absent from the report'
    Assert-Condition ((Get-EntryCount $report.findings) -gt 0) 'Missing Flutter runtime produced no diagnostic finding'
}

Test-Scenario 'native-helper-failure-preserves-partial-report' {
    $collectorDirectory = Join-Path $work '独立 脚本'
    [void](New-Item -ItemType Directory -Force -Path $collectorDirectory)
    $copiedCollector = Join-Path $collectorDirectory 'collect_startup_diagnostics.ps1'
    Copy-Item -LiteralPath $scriptPath -Destination $copiedCollector
    $directory = New-ApplicationDirectory -Name '部分 采集' -Kind 'window'
    $report = Invoke-CollectorScenario -Name 'partial-native-helper-failure' -AppPath (Join-Path $directory 'FengWo.exe') -NoLaunch -CollectorPath $copiedCollector
    Assert-Condition ((Get-EntryCount $report.collectionErrors) -gt 0) 'Missing native helper produced no collection error'
}

Test-Scenario 'cmd-entrypoint-from-chinese-and-space-path' {
    $collectorDirectory = Join-Path $work '双击 中文 空格'
    [void](New-Item -ItemType Directory -Force -Path $collectorDirectory)
    foreach ($fileName in @('collect_startup_diagnostics.ps1', 'startup_diagnostics_native.cs', 'Collect-Startup-Diagnostics.cmd')) {
        Copy-Item -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($scriptPath)) $fileName) -Destination (Join-Path $collectorDirectory $fileName)
    }
    $report = Invoke-CollectorScenario -Name 'cmd-entrypoint' -AppPath (Join-Path $work 'CMD 不存在/FengWo.exe') -CmdPath (Join-Path $collectorDirectory 'Collect-Startup-Diagnostics.cmd')
    Assert-Condition (-not $report.launch.startedPid) 'CMD missing executable unexpectedly started a process'
}

Test-Scenario 'real-verified-application-startup' {
    $directory = New-ApplicationDirectory -Name '真实 蜂窝客户端' -Kind ''
    $report = Invoke-CollectorScenario -Name 'real-application' -AppPath (Join-Path $directory 'FengWo.exe')
    Assert-Condition ($report.launch.startedPid -gt 0) 'The verified client was not launched'
    Assert-Condition ((Get-EntryCount $report.observations) -gt 0) 'The verified client was not sampled'
}

$summary = [ordered]@{
    runtime = $PSVersionTable.PSVersion.ToString()
    expected_major = $ExpectedMajor
    source_sha = $env:GITHUB_SHA
    checks = @($checks.ToArray())
    failures = @($failures.ToArray())
    all_passed = $failures.Count -eq 0
}
$summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'verification.json') -Encoding UTF8
if ($failures.Count -gt 0) { throw ($failures -join "`n") }
