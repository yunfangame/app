param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'Requires an isolated GitHub Actions Windows runner'
}
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$installDirectory = Join-Path $env:RUNNER_TEMP 'FengWo AutoStart Test'
$applicationPath = Join-Path $installDirectory 'FengWo.exe'
$runPath = 'Software\Microsoft\Windows\CurrentVersion\Run'
$approvedPath = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$names = @('FengWo', 'FlClash')
$keys = @{}
$original = @()
foreach ($path in @($runPath, $approvedPath)) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
    $keys[$path] = $key
    foreach ($name in $names) {
        $exists = $key.GetValueNames() -contains $name
        $original += @{path=$path; name=$name; exists=$exists; value=$(if($exists){$key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null}); kind=$(if($exists){$key.GetValueKind($name)}else{$null})}
    }
}
$results = [Collections.Generic.List[object]]::new()
$savedProfile = Join-Path $env:RUNNER_TEMP ('fengwo-before-autostart-' + [Guid]::NewGuid())
$profileDirectory = $null
$profilePrepared = $false
$foreignCommand = '"C:\Another Installation\FlClash.exe"'
$foreignApproved = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)

function Stop-TestApplication {
    foreach ($process in @(Get-Process FengWo, FlClashCore -ErrorAction SilentlyContinue)) {
        if ($process.Path -and $process.Path.StartsWith($installDirectory + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            if (-not $process.WaitForExit(5000)) { throw 'Autostart test process did not exit' }
        }
    }
}

function Invoke-BoundedProcess([string]$File, [string[]]$Arguments, [int]$Timeout = 120000) {
    $process = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru
    $handle = $process.Handle
    if (-not $process.WaitForExit($Timeout)) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        throw "Process timed out: $File"
    }
    if ($process.ExitCode -ne 0) { throw "Process failed ($($process.ExitCode)): $File" }
}

function Install-TestPackage {
    Invoke-BoundedProcess $InstallerPath @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $installDirectory + '"'), '/TASKS=')
}

function Assert-ForeignRegistration {
    if ($keys[$runPath].GetValue('FlClash') -cne $foreignCommand) { throw 'Modified a different FlClash installation' }
    $approved = [byte[]]$keys[$approvedPath].GetValue('FlClash')
    if (($approved -join ',') -cne ($foreignApproved -join ',')) { throw 'Modified another installation startup approval' }
}

function Invoke-NativeOperation([string]$Operation) {
    $env:FENGWO_AUTOSTART_TEST_EXECUTABLE = $applicationPath
    $env:FENGWO_AUTOSTART_TEST_OPERATION = $Operation
    $env:FENGWO_AUTOSTART_KEEP_STATE = '1'
    $env:FENGWO_AUTOSTART_NATIVE_REPORT = Join-Path $OutputDirectory ("native-$Operation.json")
    & flutter test tooling/windows_autostart_native_test.dart --no-pub --reporter expanded 2>&1 | Tee-Object (Join-Path $OutputDirectory ("native-$Operation.txt"))
    if ($LASTEXITCODE -ne 0) { throw "Windows native auto launch $Operation failed" }
}

try {
    foreach ($key in $keys.Values) {
        foreach ($name in $names) { $key.DeleteValue($name, $false) }
    }
    $keys[$runPath].SetValue('FlClash', $foreignCommand, [Microsoft.Win32.RegistryValueKind]::String)
    $keys[$approvedPath].SetValue('FlClash', $foreignApproved, [Microsoft.Win32.RegistryValueKind]::Binary)
    Install-TestPackage
    $application = Get-Item -LiteralPath $applicationPath
    if ($application.VersionInfo.CompanyName -cne 'com.follow' -or [string]::IsNullOrWhiteSpace($application.VersionInfo.ProductName)) { throw 'Unexpected application identity' }
    if ($keys[$runPath].GetValue('FengWo') -ne $null -or $keys[$approvedPath].GetValue('FengWo') -ne $null) { throw 'Fresh install enabled auto launch by default' }
    Assert-ForeignRegistration
    $results.Add(@{case='fresh-install-default-disabled'; passed=$true})
    $profileDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) (Join-Path $application.VersionInfo.CompanyName $application.VersionInfo.ProductName)
    if (Test-Path -LiteralPath $profileDirectory) { Move-Item -LiteralPath $profileDirectory -Destination $savedProfile }
    $profilePrepared = $true
    New-Item -ItemType Directory -Force $profileDirectory | Out-Null
    $preferences = @{
        'flutter.version'=1
        'flutter.xboard.auto_login'=$false
        'flutter.config'=(@{appSettingProps=@{locale='en'; autoLaunch=$true; autoRun=$false; silentLaunch=$false}} | ConvertTo-Json -Depth 8 -Compress)
    } | ConvertTo-Json -Depth 8 -Compress
    [IO.File]::WriteAllText((Join-Path $profileDirectory 'shared_preferences.json'), $preferences, [Text.UTF8Encoding]::new($false))
    Invoke-NativeOperation 'exercise'
    $expectedCommand = '"' + $applicationPath + '"'
    if ($keys[$runPath].GetValue('FengWo') -cne $expectedCommand) { throw 'Installed autostart command is not correctly quoted' }
    Assert-ForeignRegistration
    Install-TestPackage
    if ($keys[$runPath].GetValue('FengWo') -cne $expectedCommand) { throw 'Overwrite install discarded enabled autostart' }
    if (([byte[]]$keys[$approvedPath].GetValue('FengWo'))[0] -ne 2) { throw 'Overwrite install changed startup approval' }
    $results.Add(@{case='overwrite-preserves-enabled-autostart'; passed=$true})
    $disabled = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
    $keys[$approvedPath].SetValue('FengWo', $disabled, [Microsoft.Win32.RegistryValueKind]::Binary)
    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.Run($keys[$runPath].GetValue('FengWo'), 1, $false)
    $eventsPath = Join-Path $profileDirectory 'diagnostics/events.jsonl'
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    $ready = $false
    do {
        if (Test-Path -LiteralPath $eventsPath) {
            foreach ($line in Get-Content -LiteralPath $eventsPath) {
                try { if (($line | ConvertFrom-Json).event -eq 'startup.ready') { $ready=$true } } catch {}
            }
        }
        if ($ready) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'Registered command did not start the installed application' }
    $running = @(Get-Process FengWo -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $applicationPath })
    if ($running.Count -ne 1) { throw 'Registered command did not start exactly one installed FengWo process' }
    if ($keys[$runPath].GetValue('FengWo') -cne $expectedCommand) { throw 'Application startup discarded the disabled registration' }
    if (([byte[]]$keys[$approvedPath].GetValue('FengWo'))[0] -ne 3) { throw 'Application startup overrode Task Manager disabled state' }
    $results.Add(@{case='registered-command-launches-and-respects-system-disable'; passed=$true})
    Stop-TestApplication
    Invoke-NativeOperation 'disable'
    if ($keys[$runPath].GetValue('FengWo') -ne $null -or $keys[$approvedPath].GetValue('FengWo') -ne $null) { throw 'Disable left FengWo autostart registration' }
    Assert-ForeignRegistration
    $results.Add(@{case='disable-cleans-owned-registration'; passed=$true})
    Invoke-NativeOperation 'enable'
    Invoke-BoundedProcess (Join-Path $installDirectory 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    if ($keys[$runPath].GetValue('FengWo') -ne $null -or $keys[$approvedPath].GetValue('FengWo') -ne $null) { throw 'Uninstall left owned FengWo autostart registration' }
    Assert-ForeignRegistration
    $results.Add(@{case='uninstall-cleans-owned-and-preserves-foreign-registration'; passed=$true})
} finally {
    Stop-TestApplication
    $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'autostart-results.json') -Encoding utf8
    foreach ($item in $original) {
        $key = $keys[$item.path]
        if ($item.exists) { $key.SetValue($item.name, $item.value, $item.kind) } else { $key.DeleteValue($item.name, $false) }
    }
    foreach ($key in $keys.Values) { $key.Dispose() }
    if ($profilePrepared -and (Test-Path -LiteralPath $profileDirectory)) { Remove-Item -LiteralPath $profileDirectory -Recurse -Force }
    if (Test-Path -LiteralPath $savedProfile) { Move-Item -LiteralPath $savedProfile -Destination $profileDirectory }
    foreach ($name in @('FENGWO_AUTOSTART_TEST_EXECUTABLE', 'FENGWO_AUTOSTART_TEST_OPERATION', 'FENGWO_AUTOSTART_KEEP_STATE', 'FENGWO_AUTOSTART_NATIVE_REPORT')) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
}
