param(
    [Parameter(Mandatory = $true)][int]$ExpectedMajor,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
[void](New-Item -ItemType Directory -Force -Path $EvidenceDirectory)
$work = Join-Path $env:RUNNER_TEMP ('窗口恢复 中文 空格 ' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $work)
$toolDirectory = Join-Path $PSScriptRoot 'tool'
$scriptPath = Join-Path $toolDirectory 'recover_window.ps1'
$engine = (Get-Process -Id $PID).Path
$ownedProcesses = New-Object 'Collections.Generic.Dictionary[int,string]'
$checks = New-Object 'Collections.Generic.List[object]'
$failures = New-Object 'Collections.Generic.List[string]'

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Stop-OwnedFixtures {
    foreach ($processId in @($ownedProcesses.Keys)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        try {
            if ($process.Path -eq $ownedProcesses[$processId]) {
                Stop-Process -Id $processId -Force
                [void]$process.WaitForExit(5000)
            }
        } catch { }
    }
    $ownedProcesses.Clear()
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
        Stop-OwnedFixtures
    }
}

function Start-Fixture {
    param([string]$Name = 'FengWo', [string]$ClassName = 'FLUTTER_RUNNER_WIN32_WINDOW', [string]$State = 'offscreen')
    $path = Join-Path $work ($Name + '.exe')
    $readyPath = Join-Path $work ([Guid]::NewGuid().ToString('N') + '.json')
    $arguments = '"' + $ClassName + '" "' + $State + '" "' + $readyPath + '"'
    $process = Start-Process -FilePath $path -ArgumentList $arguments -PassThru
    $ownedProcesses.Add($process.Id, $path)
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $readyPath)) {
        $process.Refresh()
        if ($process.HasExited) { throw "Synthetic fixture exited with $($process.ExitCode)" }
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Synthetic fixture did not report its window handle' }
        Start-Sleep -Milliseconds 100
    }
    $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
    Assert-Condition ($ready.pid -eq $process.Id) 'Fixture reported a different process id'
    return [pscustomobject]@{ Process = $process; Handle = [long]$ready.handle; Before = [SyntheticRecoveryFixture.Program]::Describe([long]$ready.handle) }
}

function Invoke-Recovery {
    param([string]$Name, [switch]$InspectOnly, [string]$CmdPath)
    $output = Join-Path $EvidenceDirectory $Name
    [void](New-Item -ItemType Directory -Force -Path $output)
    $console = Join-Path $output 'console.txt'
    $stderr = Join-Path $output 'stderr.txt'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    if ([string]::IsNullOrWhiteSpace($CmdPath)) {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-NonInteractive', '-OutputDirectory', $output)
        if ($InspectOnly) { $arguments += '-InspectOnly' }
        $quoted = @($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $process = Start-Process -FilePath $engine -ArgumentList $quoted -PassThru -RedirectStandardOutput $console -RedirectStandardError $stderr
    } else {
        $command = '""' + $CmdPath + '" -NonInteractive -OutputDirectory "' + $output + '""'
        $process = Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /s /c ' + $command) -PassThru -RedirectStandardOutput $console -RedirectStandardError $stderr
    }
    try {
        $nativeHandle = $process.Handle
        if (-not $process.WaitForExit(60000)) {
            try { $process.Kill() } catch { }
            throw 'Recovery tool exceeded the 60 second test limit'
        }
        $exitCode = $process.ExitCode
        Assert-Condition ($null -ne $exitCode) 'Process exit code was unavailable'
    } finally {
        $watch.Stop()
        $process.Dispose()
    }
    $reportPath = Join-Path $output 'window-report.json'
    Assert-Condition (Test-Path -LiteralPath $reportPath -PathType Leaf) 'Recovery JSON report was not preserved'
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Assert-Condition ($report.SchemaVersion -eq 1) 'Unexpected recovery report schema'
    $archive = $output + '.zip'
    Assert-Condition (Test-Path -LiteralPath $archive -PathType Leaf) 'Recovery ZIP report was not preserved'
    $expanded = Join-Path $work ('expanded-' + $Name)
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    $archived = @(Get-ChildItem -LiteralPath $expanded -Recurse -Filter 'window-report.json' -File)
    Assert-Condition ($archived.Count -eq 1) 'Recovery ZIP contains no final report'
    Assert-Condition ((Get-FileHash -LiteralPath $archived[0].FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash) 'Recovery ZIP report differs from the final JSON'
    $checks.Add([ordered]@{ name = "$Name-report"; status = $report.Status; exit_code = $exitCode; elapsed_seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 2); archive_matches = $true })
    Assert-Condition ($exitCode -eq 0) 'Recovery tool returned a nonzero exit code'
    return $report
}

function Assert-Unchanged {
    param([object]$Before, [object]$After)
    foreach ($field in @('Handle', 'ProcessId', 'ClassName', 'Visible', 'Minimized', 'Hung', 'DwmCloaked', 'Left', 'Top', 'Right', 'Bottom')) {
        Assert-Condition ($Before.$field -eq $After.$field) "Non-target window changed $field"
    }
}

function Assert-Recovered {
    param([object]$Fixture, [object]$Report)
    $Fixture.Process.Refresh()
    Assert-Condition (-not $Fixture.Process.HasExited) 'Recovery tool terminated the application process'
    $after = [SyntheticRecoveryFixture.Program]::Describe($Fixture.Handle)
    $workArea = [SyntheticRecoveryFixture.Program]::PrimaryWorkArea()
    Assert-Condition ($after.Visible -and -not $after.Minimized -and -not $after.Hung -and $after.DwmCloaked -eq $false) 'Recovered window is not responsive, visible and uncloaked'
    Assert-Condition ($after.Left -ge $workArea.Left -and $after.Top -ge $workArea.Top -and $after.Right -le $workArea.Right -and $after.Bottom -le $workArea.Bottom) 'Recovered window is outside the primary work area'
    Assert-Condition ($Report.Status -eq 'window_on_primary') 'Recovery tool did not confirm primary-screen recovery'
    Assert-Condition (@($Report.Verification | Where-Object { $_.ProcessId -eq $Fixture.Process.Id -and $_.ResponsiveUncloakedWindowOnPrimary }).Count -eq 1) 'Recovery report did not verify the fixture window'
    $checks.Add([ordered]@{ name = 'independent-window-state'; pid_unchanged = $true; class_name = $after.ClassName; before = $Fixture.Before; after = $after; primary_work_area = $workArea })
}

Test-Scenario 'runtime-parser-and-native-compilation' {
    Assert-Condition ($PSVersionTable.PSVersion.Major -eq $ExpectedMajor) 'Wrong PowerShell runtime'
    if ($ExpectedMajor -eq 5) { Assert-Condition ($PSVersionTable.PSVersion.Minor -eq 1) 'Expected Windows PowerShell 5.1' }
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    Assert-Condition ($errors.Count -eq 0) ($errors | Out-String)
    Add-Type -Path (Join-Path $toolDirectory 'window_recovery_native.cs')
    $capture = [FengWoWindowRecovery.NativeProbe]::Capture()
    Assert-Condition ($capture.CurrentProcessId -eq $PID) 'Native capture reports a different current process'
    Assert-Condition (@($capture.Monitors | Where-Object { $_.Primary }).Count -eq 1) 'Native capture did not identify one primary monitor'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    $fixtureSource = Join-Path $PSScriptRoot 'fixture_windows.cs'
    & $compiler /nologo /target:winexe /platform:x64 ("/out:" + (Join-Path $work 'FengWo.exe')) $fixtureSource
    Assert-Condition ($LASTEXITCODE -eq 0) 'Synthetic fixture compiler failed'
    Copy-Item -LiteralPath (Join-Path $work 'FengWo.exe') -Destination (Join-Path $work 'OtherClient.exe')
    Add-Type -Path $fixtureSource
}

foreach ($state in @('offscreen', 'hidden', 'minimized')) {
    Test-Scenario ("recover-$state-window") {
        $fixture = Start-Fixture -State $state
        if ($state -eq 'hidden') { Assert-Condition (-not $fixture.Before.Visible) 'Fixture was not hidden' }
        if ($state -eq 'minimized') { Assert-Condition ($fixture.Before.Minimized) 'Fixture was not minimized' }
        if ($state -eq 'offscreen') { Assert-Condition ($fixture.Before.Left -gt [SyntheticRecoveryFixture.Program]::PrimaryWorkArea().Right) 'Fixture was not offscreen' }
        $report = Invoke-Recovery -Name $state
        Assert-Recovered $fixture $report
    }
}

Test-Scenario 'different-process-name-is-unchanged' {
    $fixture = Start-Fixture -Name 'OtherClient'
    $report = Invoke-Recovery -Name 'different-process'
    Assert-Condition ($report.Status -eq 'no_matching_window') 'Nonmatching executable was selected for recovery'
    $fixture.Process.Refresh()
    Assert-Condition (-not $fixture.Process.HasExited) 'Nonmatching process was terminated'
    Assert-Unchanged $fixture.Before ([SyntheticRecoveryFixture.Program]::Describe($fixture.Handle))
}

Test-Scenario 'different-window-class-is-unchanged' {
    $fixture = Start-Fixture -ClassName 'SYNTHETIC_UNMATCHED_WINDOW_CLASS' -State 'hidden'
    $report = Invoke-Recovery -Name 'different-class'
    Assert-Condition ($report.Status -eq 'no_matching_window') 'Nonmatching window class was selected for recovery'
    $fixture.Process.Refresh()
    Assert-Condition (-not $fixture.Process.HasExited) 'Nonmatching process was terminated'
    Assert-Unchanged $fixture.Before ([SyntheticRecoveryFixture.Program]::Describe($fixture.Handle))
}

Test-Scenario 'no-target-preserves-report' {
    $report = Invoke-Recovery -Name 'no-target'
    Assert-Condition ($report.Status -eq 'no_matching_window') 'No-target run reported a window recovery'
}

Test-Scenario 'cmd-entrypoint-chinese-space-path' {
    $copiedTool = Join-Path $work '工具 中文 空格'
    [void](New-Item -ItemType Directory -Force -Path $copiedTool)
    Get-ChildItem -LiteralPath $toolDirectory -File | Copy-Item -Destination $copiedTool
    $fixture = Start-Fixture -State 'offscreen'
    $report = Invoke-Recovery -Name 'cmd-entrypoint' -CmdPath (Join-Path $copiedTool 'Recover-FengWo-Window.cmd')
    Assert-Recovered $fixture $report
}

[ordered]@{ runtime = $PSVersionTable.PSVersion.ToString(); expected_major = $ExpectedMajor; source_sha = $env:GITHUB_SHA; synthetic_data_only = $true; checks = @($checks.ToArray()); failures = @($failures.ToArray()); passed = $failures.Count -eq 0 } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'verification.json') -Encoding UTF8
if ($failures.Count -gt 0) { throw ($failures -join "`n") }
