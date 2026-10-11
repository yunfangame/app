param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [string]$FixtureExecutable
)

. (Join-Path $PSScriptRoot 'common.ps1')
$environment = Assert-FwArmRunner
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'The isolated native fixture requires PowerShell 7' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'The isolated service fixture requires administrator privileges' }
} finally { $identity.Dispose() }
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$id = [Guid]::NewGuid().ToString('N')
$fixtureDirectory = Join-Path $env:RUNNER_TEMP ('flclash-coexistence-' + $id)
$installDirectory = Join-Path $fixtureDirectory 'FengWo'
$foreignDirectory = Join-Path $fixtureDirectory 'FlClash'
$appData = [Environment]::GetFolderPath('ApplicationData')
$localData = [Environment]::GetFolderPath('LocalApplicationData')
$foreignData = Join-Path $appData 'com.follow/FlClash'
$foreignCache = Join-Path $localData 'com.follow/FlClash'
$ownData = Join-Path $appData 'FengWo/蜂窝加速器'
$ownCache = Join-Path $localData 'FengWo/蜂窝加速器'
$oldId = '728B3532-C74B-4870-9068-BE70FE12A3E6'
$newId = '0B31AA8F-C520-4E03-ACF1-FBE8B4EBA461'
$uninstallRoot = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\'
$runKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
$approvedKeys = @('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32')
$createdKeys = [Collections.Generic.List[object]]::new()
$createdValues = [Collections.Generic.List[object]]::new()
$foreignProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
$ownProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
$checks = [Collections.Generic.List[object]]::new()
$cleanupErrors = [Collections.Generic.List[string]]::new()
$failure = $null
$serviceCreated = $false
$lock = $null
$listener = $null
$proxyListener = $null
$proxyGuard = $null
$proxyBaseline = $null
$proxyRestore = $null
$corePipe = $null
$coreSession = $null
$servicePath = Join-Path $foreignDirectory 'FlClashHelperService.exe'
$counterPath = Join-Path $fixtureDirectory 'foreign-stop-count.txt'
$foreignBaseline = $null
$profileCreated = $false
$cacheCreated = $false
$fixtureCreated = $false
$uninstallVerified = $false
$sharedRegistryBefore = @{}

function Open-RegistryBase([string]$Hive, [string]$View = 'Registry64') {
    return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$Hive, [Microsoft.Win32.RegistryView]::$View)
}

function Read-RegistryTree([string]$Hive, [string]$Path, [string]$View = 'Registry64') {
    $base = Open-RegistryBase $Hive $View
    try {
        $key = $base.OpenSubKey($Path)
        if (-not $key) { return $null }
        try {
            $values = @()
            foreach ($name in @($key.GetValueNames() | Sort-Object)) {
                $kind = $key.GetValueKind($name).ToString()
                $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($value -is [byte[]]) { $value = [Convert]::ToBase64String($value) }
                $values += [ordered]@{ name = $name; kind = $kind; value = $value }
            }
            $children = @()
            foreach ($name in @($key.GetSubKeyNames() | Sort-Object)) { $children += [ordered]@{ name = $name; tree = (Read-RegistryTree $Hive ($Path + '\' + $name) $View) } }
            return [ordered]@{ values = $values; children = $children }
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Set-FixtureValue([string]$Hive, [string]$Path, [string]$Name, [object]$Value, [Microsoft.Win32.RegistryValueKind]$Kind = [Microsoft.Win32.RegistryValueKind]::String) {
    $base = Open-RegistryBase $Hive
    try {
        $key = $base.CreateSubKey($Path)
        try { $key.SetValue($Name, $Value, $Kind) } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Assert-NoRegistryValue([string]$Path, [string]$Name) {
    foreach ($view in @('Registry64', 'Registry32')) {
        $base = Open-RegistryBase 'CurrentUser' $view
        try {
            $key = $base.OpenSubKey($Path)
            if ($key) { try { if ($key.GetValueNames() -contains $Name) { throw ('A pre-existing registry value prevents isolation: ' + $Name) } } finally { $key.Dispose() } }
        } finally { $base.Dispose() }
    }
}

function ConvertTo-WindowsArguments([string[]]$Arguments) {
    return (@($Arguments | ForEach-Object { '"' + ([regex]::Replace(([regex]::Replace($_, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"' }) -join ' ')
}

function Invoke-BoundedProcess([string]$File, [string[]]$Arguments, [string]$Stage, [int]$TimeoutSeconds = 120) {
    $commandLine = ConvertTo-WindowsArguments $Arguments
    $process = Start-Process -FilePath $File -ArgumentList $commandLine -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory ($Stage + '-stdout.txt')) -RedirectStandardError (Join-Path $EvidenceDirectory ($Stage + '-stderr.txt'))
    try {
        $handle = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); [void]$process.WaitForExit(5000); throw ('Owned process exceeded its deadline: ' + $Stage) }
        if ($process.ExitCode -ne 0) { throw ($Stage + ' exited with ' + $process.ExitCode) }
    } finally { $process.Dispose() }
}

function Wait-FixtureReady([string]$Path, [int]$ExpectedPid = 0) {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        if ([IO.File]::Exists($Path)) {
            try { $text = [IO.File]::ReadAllText($Path) } catch [IO.IOException] { $text = $null }
            $readyProcessId = 0
            if ($text -cmatch '\A[0-9]+\z' -and [int]::TryParse($text, [ref]$readyProcessId) -and $readyProcessId -gt 0 -and (-not $ExpectedPid -or $readyProcessId -eq $ExpectedPid)) { return }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ('Fixture never became ready: ' + [IO.Path]::GetFileName($Path))
}

function Get-ForeignFileHash([string]$Path) {
    if ($Path -ine (Join-Path $foreignData 'FlClash.lock')) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, 1)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        if ($stream.Length -ne 1) { throw 'The isolated original lock fixture must contain exactly one byte' }
        $bytes = [byte[]]::new(1)
        if ($stream.Read($bytes, 0, 1) -ne 1) { throw 'The isolated original lock fixture byte could not be read' }
        return [Convert]::ToHexString($algorithm.ComputeHash($bytes)).ToLowerInvariant()
    } finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Get-ForeignSnapshot {
    $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
    $processes = @()
    foreach ($process in $foreignProcesses) {
        if ($process.HasExited) { throw ('The installer terminated a foreign fixture PID: ' + $process.Id) }
        $processes += [ordered]@{ pid = $process.Id; start_time = $process.StartTime.ToUniversalTime().ToString('o'); executable = $process.MainModule.FileName; native_window_count = [FengWoCoexistenceWindows]::Count($process.Id) }
    }
    $registry = @()
    foreach ($entry in $createdKeys) { $registry += [ordered]@{ hive = $entry.hive; path = $entry.path; tree = (Read-RegistryTree $entry.hive $entry.path) } }
    foreach ($path in @($runKey) + $approvedKeys) { $registry += [ordered]@{ hive = 'CurrentUser'; path = $path; tree = (Read-RegistryTree 'CurrentUser' $path) } }
    $files = @()
    foreach ($directory in @($foreignDirectory, $foreignData, $foreignCache)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Recurse -File | Sort-Object FullName)) {
            $files += [ordered]@{ path = $file.FullName; hash = (Get-ForeignFileHash $file.FullName); bytes = $file.Length }
        }
    }
    $connections = @(Get-NetTCPConnection -State Listen -LocalPort 47890 -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' -and $_.OwningProcess -eq $PID })
    if ($connections.Count -ne 1 -or -not $listener.Server.IsBound) { throw 'The foreign loopback listener is no longer owned and listening' }
    $proxyConnections = @(Get-NetTCPConnection -State Listen -LocalPort 7890 -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' -and $_.OwningProcess -eq $PID })
    if ($proxyConnections.Count -ne 1 -or -not $proxyListener.Server.IsBound) { throw 'The foreign same-port proxy listener is no longer owned and listening' }
    $systemProxy = $proxyGuard.Capture()
    if (-not [FengWoCoexistenceTests.ProxyFixture]::Same($proxyBaseline, $systemProxy)) { throw 'The application changed the foreign native WinINet or typed HKCU proxy state' }
    if (-not $service -or $service.State -ne 'Running' -or $service.ProcessId -le 0) { throw 'The foreign SCM fixture is no longer running' }
    if ([IO.File]::ReadAllText($counterPath) -cne '0') { throw 'The installer sent STOP to the foreign SCM fixture' }
    $probe = $null
    try {
        $probe = [IO.File]::Open((Join-Path $foreignData 'FlClash.lock'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        $probe.Lock(4096, 1)
        throw 'The original application lock is no longer held'
    } catch [IO.IOException] { } finally { if ($probe) { $probe.Dispose() } }
    return [ordered]@{ processes = $processes; service = [ordered]@{ name = $service.Name; state = $service.State; pid = $service.ProcessId; path = $service.PathName; start_mode = $service.StartMode; account = $service.StartName; registry = (Read-RegistryTree 'LocalMachine' 'SYSTEM\CurrentControlSet\Services\FlClashHelperService') }; stop_count = 0; registry = $registry; files = $files; loopback_port = 47890; loopback_owner_pid = $PID; same_port_proxy_listener = 7890; same_port_proxy_listener_owner_pid = $PID; system_proxy = $systemProxy; file_lock_held = $true }
}

function Assert-ForeignUnchanged([string]$Stage) {
    $snapshot = Get-ForeignSnapshot
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-foreign-snapshot.json')) $snapshot
    if (($snapshot | ConvertTo-Json -Depth 30 -Compress) -cne ($foreignBaseline | ConvertTo-Json -Depth 30 -Compress)) { throw ('Foreign resources changed during ' + $Stage) }
    $checks.Add([ordered]@{ name = $Stage; passed = $true; foreign_stop_count = 0; foreign_processes = @($foreignProcesses | ForEach-Object { $_.Id }) })
}

function Install-FengWo([string]$Stage) {
    Invoke-BoundedProcess $InstallerPath @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR=' + $installDirectory), '/TASKS=', ('/LOG=' + (Join-Path $EvidenceDirectory ($Stage + '-installer.log')))) $Stage
    $application = Join-Path $installDirectory 'FengWo.exe'
    $metadata = (Get-Item -LiteralPath $application).VersionInfo
    if ($metadata.CompanyName -cne 'FengWo' -or $metadata.ProductName -cne '蜂窝加速器' -or -not (Get-FwPeIdentity $application).arm64) { throw 'Installed native application identity is incorrect' }
    $registrations = @()
    foreach ($hive in @('LocalMachine', 'CurrentUser')) {
        foreach ($view in @('Registry64', 'Registry32')) {
            $base = Open-RegistryBase $hive $view
            try {
                $key = $base.OpenSubKey($uninstallRoot + $newId + '_is1')
                if ($key) { try { $registrations += [ordered]@{ hive = $hive; view = $view; location = [string]$key.GetValue('InstallLocation'); path = [string]$key.GetValue('Inno Setup: App Path') } } finally { $key.Dispose() } }
            } finally { $base.Dispose() }
        }
    }
    $matching = @($registrations | Where-Object { $_.location.TrimEnd('\') -ieq $installDirectory.TrimEnd('\') -or $_.path.TrimEnd('\') -ieq $installDirectory.TrimEnd('\') })
    if ($matching.Count -lt 1) { throw 'The isolated FengWo AppId was not registered to its owned directory' }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-installed-identity.json')) ([ordered]@{ company = $metadata.CompanyName; product = $metadata.ProductName; app_id = $newId; native_application = (Get-FwPeIdentity $application); registrations = $registrations })
}

function Start-FengWo([string]$Stage) {
    $eventsPath = Join-Path $ownData 'diagnostics/events.jsonl'
    if ([IO.File]::Exists($eventsPath)) { [IO.File]::Delete($eventsPath) }
    $process = Start-Process -FilePath (Join-Path $installDirectory 'FengWo.exe') -WorkingDirectory $installDirectory -PassThru
    $handle = $process.Handle
    $ownProcesses.Add($process)
    Assert-FwArmProcess $process.Id
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        if ($process.HasExited) { throw ($Stage + ' exited before startup.ready') }
        $events = @()
        if ([IO.File]::Exists($eventsPath)) { $events = @(Get-Content -LiteralPath $eventsPath | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } }) }
        if (@($events | Where-Object { $_.event -ceq 'startup.failed' }).Count) { throw ($Stage + ' recorded startup.failed') }
        if (@($events | Where-Object { $_.event -ceq 'startup.ready' }).Count) {
            Copy-Item -LiteralPath $eventsPath -Destination (Join-Path $EvidenceDirectory ($Stage + '-events.jsonl'))
            [void](Assert-FengWoWindowTitle $process.Id)
            if ($process.HasExited) { throw 'The application exited after its first frame' }
            return $process
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ($Stage + ' never recorded startup.ready in the isolated FengWo data directory')
}

function Stop-OwnedApplications {
    foreach ($process in $ownProcesses) {
        if (-not $process.HasExited) { $process.Kill(); if (-not $process.WaitForExit(5000)) { throw 'An owned test application did not exit' } }
    }
}

function Exit-FengWoGracefully([Diagnostics.Process]$Process, [IntPtr]$Window) {
    if ($Process.HasExited -or $Window -eq [IntPtr]::Zero -or [FengWoTitleTest]::FindMainWindow($Process.Id) -ne $Window) { throw 'The exact owned application window is not available for graceful exit' }
    $elapsed = [Diagnostics.Stopwatch]::StartNew()
    if (-not [FengWoCoexistenceWindows]::RequestClose($Window, $Process.Id)) { throw 'The owned window rejected WM_CLOSE' }
    $exited = $Process.WaitForExit(20000)
    $elapsed.Stop()
    $exitCode = if ($exited) { $Process.ExitCode } else { $null }
    $eventsPath = Join-Path $ownData 'diagnostics/events.jsonl'
    $events = @()
    if ([IO.File]::Exists($eventsPath)) {
        Copy-Item -LiteralPath $eventsPath -Destination (Join-Path $EvidenceDirectory 'graceful-exit-events.jsonl')
        $events = @(Get-Content -LiteralPath $eventsPath | ForEach-Object { try { $_ | ConvertFrom-Json -AsHashtable } catch { } })
    }
    $exitEvents = @($events | Where-Object { $_['event'] -ceq 'system_proxy.cleanup.completed' -and $_['fields']['reason'] -ceq 'exit' })
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'graceful-exit.json') ([ordered]@{ pid = $Process.Id; exited = $exited; exit_code = $exitCode; elapsed_ms = $elapsed.ElapsedMilliseconds; window = $Window.ToInt64(); wm_close = $true; forced_kill = $false; cleanup = $exitEvents })
    if (-not $exited -or $exitCode -ne 0) { throw 'The unconnected application did not exit normally after WM_CLOSE' }
    if ($exitEvents.Count -eq 0) { throw 'The normal exit did not record application system-proxy cleanup' }
}

function Invoke-HelperRequest([string]$Method, [string]$Path, [object]$Body = $null) {
    $arguments = @{ Uri = ('http://127.0.0.1:47906/' + $Path); Method = $Method; NoProxy = $true; TimeoutSec = 10 }
    if ($null -ne $Body) { $arguments.ContentType = 'application/json'; $arguments.Body = ($Body | ConvertTo-Json -Compress) }
    return Invoke-WebRequest @arguments
}

try {
    if (Get-Process -Name FlClash, FlClashCore, FlClashHelperService, FengWo, FengWoCore, FengWoHelperService -ErrorAction SilentlyContinue) { throw 'Existing client processes prevent an isolated coexistence test' }
    foreach ($name in @('FlClashHelperService', 'FengWoHelperService')) { if (Get-CimInstance Win32_Service -Filter ("Name='" + $name + "'")) { throw ('A pre-existing SCM service prevents isolation: ' + $name) } }
    foreach ($directory in @($foreignData, $foreignCache, $ownData, $ownCache)) { if (Test-Path -LiteralPath $directory) { throw ('Pre-existing application data prevents isolation: ' + $directory) } }
    foreach ($hive in @('LocalMachine', 'CurrentUser')) {
        foreach ($view in @('Registry64', 'Registry32')) {
            foreach ($appId in @($oldId, $newId)) {
                foreach ($keyName in @(($appId + '_is1'), ('{' + $appId + '}_is1'))) { if ($null -ne (Read-RegistryTree $hive ($uninstallRoot + $keyName) $view)) { throw 'A pre-existing application uninstall registration prevents isolation' } }
            }
        }
    }
    foreach ($scheme in @('clash', 'clashmeta', 'flclash', 'fengwo')) { foreach ($view in @('Registry64', 'Registry32')) { if ($null -ne (Read-RegistryTree 'CurrentUser' ('Software\Classes\' + $scheme) $view)) { throw ('A pre-existing URL association prevents isolation: ' + $scheme) } } }
    foreach ($path in @($runKey) + $approvedKeys) { Assert-NoRegistryValue $path 'FlClash'; Assert-NoRegistryValue $path 'FengWo'; $sharedRegistryBefore[$path] = Read-RegistryTree 'CurrentUser' $path }
    if (Get-NetTCPConnection -State Listen -LocalPort 47890, 47906, 7890 -ErrorAction SilentlyContinue) { throw 'A pre-existing Helper or synthetic proxy port prevents isolation' }
    [void][IO.Directory]::CreateDirectory($foreignDirectory)
    $fixtureCreated = $true
    if (-not $FixtureExecutable) {
        if (-not $env:FENGWO_ARM64_CMAKE_GENERATOR) { throw 'The ARM64 CMake generator must be provided by the build workflow' }
        $fixtureBuild = Join-Path $fixtureDirectory 'fixture-build'
        Invoke-BoundedProcess 'cmake' @('-S', (Join-Path $PSScriptRoot 'flclash_fixture'), '-B', $fixtureBuild, '-G', $env:FENGWO_ARM64_CMAKE_GENERATOR, '-A', 'ARM64') 'fixture-configure'
        Invoke-BoundedProcess 'cmake' @('--build', $fixtureBuild, '--config', 'Release') 'fixture-build'
        $FixtureExecutable = Join-Path $fixtureBuild 'Release/flclash_fixture.exe'
    }
    if (-not (Get-FwPeIdentity $FixtureExecutable).arm64) { throw 'The foreign fixture must be a native ARM64 executable' }
    foreach ($name in @('FlClash.exe', 'FlClashCore.exe', 'FlClashHelperService.exe')) { Copy-Item -LiteralPath $FixtureExecutable -Destination (Join-Path $foreignDirectory $name) }
    foreach ($name in @('FlClash', 'FlClashCore')) {
        $ready = Join-Path $fixtureDirectory ($name + '-ready.txt')
        $process = Start-Process -FilePath (Join-Path $foreignDirectory ($name + '.exe')) -ArgumentList @('idle', ('"' + $ready + '"')) -PassThru
        $handle = $process.Handle
        $foreignProcesses.Add($process)
        Wait-FixtureReady $ready $process.Id
        Assert-FwArmProcess $process.Id
    }
    $serviceReady = Join-Path $fixtureDirectory 'foreign-service-ready.txt'
    $serviceCommand = '"' + $servicePath + '" service "' + $counterPath + '" "' + $serviceReady + '"'
    Invoke-BoundedProcess 'sc.exe' @('create', 'FlClashHelperService', 'binPath=', $serviceCommand, 'start=', 'demand') 'foreign-service-create'
    $serviceCreated = $true
    Invoke-BoundedProcess 'sc.exe' @('start', 'FlClashHelperService') 'foreign-service-start'
    Wait-FixtureReady $serviceReady
    $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
    $serviceProcess = [Diagnostics.Process]::GetProcessById($service.ProcessId)
    $handle = $serviceProcess.Handle
    $foreignProcesses.Add($serviceProcess)
    Assert-FwArmProcess $serviceProcess.Id
    [void][IO.Directory]::CreateDirectory($foreignData)
    $profileCreated = $true
    [void][IO.Directory]::CreateDirectory($foreignCache)
    $cacheCreated = $true
    foreach ($directory in @($foreignData, $foreignCache)) { [IO.File]::WriteAllText((Join-Path $directory 'coexistence-marker.txt'), $id) }
    foreach ($name in @('shared_preferences.json', 'config.yaml', 'db.sqlite', 'flutter_secure_storage.dat')) { [IO.File]::WriteAllText((Join-Path $foreignData $name), ('FOREIGN_SYNTHETIC_' + $id)) }
    [void][IO.Directory]::CreateDirectory((Join-Path $foreignData 'profiles'))
    [IO.File]::WriteAllText((Join-Path $foreignData 'profiles/synthetic.yaml'), ('FOREIGN_SYNTHETIC_' + $id))
    [IO.File]::WriteAllText((Join-Path $foreignCache 'cache-sentinel.bin'), $id)
    $lock = [IO.File]::Open((Join-Path $foreignData 'FlClash.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    $lock.SetLength(1)
    $lock.Lock(4096, 1)
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 47890)
    $listener.Start()
    $proxyListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 7890)
    $proxyListener.Start()
    Add-Type -Path (Join-Path $PSScriptRoot 'coexistence_proxy_fixture.cs')
    $proxyGuard = [FengWoCoexistenceTests.ProxyFixture]::new()
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'system-proxy-original.json') $proxyGuard.Original
    $proxyBaseline = $proxyGuard.SetForeign(7890)
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'system-proxy-synthetic.json') $proxyBaseline
    [void][IO.Directory]::CreateDirectory($ownData)
    $testConfig = @{ appSettingProps = @{ minimizeOnExit = $false; autoRun = $false; autoCheckUpdate = $false }; networkProps = @{ systemProxy = $true }; patchClashConfig = @{ 'mixed-port' = 7890 }; themeProps = @{} } | ConvertTo-Json -Depth 8 -Compress
    [IO.File]::WriteAllText((Join-Path $ownData 'shared_preferences.json'), (@{ 'flutter.version' = 1; 'flutter.config' = $testConfig } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    foreach ($hive in @('LocalMachine', 'CurrentUser')) {
        $path = $uninstallRoot + $oldId + '_is1'
        $createdKeys.Add([ordered]@{ hive = $hive; path = $path })
        foreach ($name in @('DisplayName', 'DisplayVersion', 'InstallLocation', 'Inno Setup: App Path', 'UninstallString', 'CoexistenceSentinel')) {
            $value = switch ($name) { 'DisplayName' { 'FlClash' } 'DisplayVersion' { '0.8.97' } 'UninstallString' { '"' + (Join-Path $foreignDirectory 'unins000.exe') + '"' } 'CoexistenceSentinel' { $id } default { $foreignDirectory } }
            Set-FixtureValue $hive $path $name $value
        }
    }
    foreach ($scheme in @('clash', 'clashmeta', 'flclash')) {
        $path = 'Software\Classes\' + $scheme
        $createdKeys.Add([ordered]@{ hive = 'CurrentUser'; path = $path })
        Set-FixtureValue 'CurrentUser' $path '' ('URL:' + $scheme)
        Set-FixtureValue 'CurrentUser' $path 'URL Protocol' ''
        Set-FixtureValue 'CurrentUser' $path 'CoexistenceSentinel' $id
        Set-FixtureValue 'CurrentUser' ($path + '\shell\open\command') '' ('"' + (Join-Path $foreignDirectory 'FlClash.exe') + '" "%1"')
    }
    $createdValues.Add([ordered]@{ path = $runKey; name = 'FlClash' })
    Set-FixtureValue 'CurrentUser' $runKey 'FlClash' ('"' + (Join-Path $foreignDirectory 'FlClash.exe') + '"')
    foreach ($path in $approvedKeys) {
        $createdValues.Add([ordered]@{ path = $path; name = 'FlClash' })
        Set-FixtureValue 'CurrentUser' $path 'FlClash' ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) ([Microsoft.Win32.RegistryValueKind]::Binary)
    }
    . (Join-Path $PSScriptRoot '../../verify_windows_title.ps1')
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FengWoCoexistenceWindows {
    private delegate bool Callback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(Callback callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int GetClassNameW(IntPtr window, StringBuilder name, int capacity);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool PostMessageW(IntPtr window, uint message, IntPtr first, IntPtr second);
    public static bool RequestClose(IntPtr window, int processId) {
        uint owner;
        GetWindowThreadProcessId(window, out owner);
        return owner == processId && PostMessageW(window, 0x0010, IntPtr.Zero, IntPtr.Zero);
    }
    public static int Count(int processId) {
        int count = 0;
        EnumWindows((window, parameter) => {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner == processId) {
                StringBuilder name = new StringBuilder(256);
                GetClassNameW(window, name, name.Capacity);
                if (name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") count++;
            }
            return true;
        }, IntPtr.Zero);
        return count;
    }
}
'@
    $foreignBaseline = Get-ForeignSnapshot
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'foreign-baseline.json') $foreignBaseline
    Assert-ForeignUnchanged 'baseline'
    Install-FengWo 'initial-install'
    Assert-ForeignUnchanged 'initial-install'
    $application = Start-FengWo 'initial-startup'
    Assert-ForeignUnchanged 'initial-startup'
    $windowBefore = [FengWoTitleTest]::FindMainWindow($application.Id)
    if ([FengWoCoexistenceWindows]::Count($application.Id) -ne 1) { throw 'The first instance does not have exactly one owned native window' }
    $second = Start-Process -FilePath (Join-Path $installDirectory 'FengWo.exe') -WorkingDirectory $installDirectory -PassThru
    $handle = $second.Handle
    $ownProcesses.Add($second)
    if (-not $second.WaitForExit(10000) -or $second.ExitCode -ne 0 -or $application.HasExited -or [FengWoTitleTest]::FindMainWindow($application.Id) -ne $windowBefore) { throw 'A repeated launch did not preserve the original owned instance and window' }
    $sameExecutable = @(Get-CimInstance Win32_Process -Filter "Name='FengWo.exe'" | Where-Object { $_.ExecutablePath -ieq (Join-Path $installDirectory 'FengWo.exe') })
    if ($sameExecutable.Count -ne 1 -or $sameExecutable[0].ProcessId -ne $application.Id -or [FengWoCoexistenceWindows]::Count($application.Id) -ne 1) { throw 'A repeated launch created another owned client process' }
    Assert-ForeignUnchanged 'repeat-launch'
    Exit-FengWoGracefully $application $windowBefore
    Assert-ForeignUnchanged 'graceful-exit'
    Stop-OwnedApplications
    Invoke-BoundedProcess (Join-Path $installDirectory 'FengWoHelperService.exe') @('install') 'owned-helper-install' 30
    $manifest = Get-Content -LiteralPath (Join-Path $installDirectory 'manifest.json') -Raw | ConvertFrom-Json
    $ping = Invoke-HelperRequest 'GET' ('ping?coreSha256=' + $manifest.coreSha256)
    $helperPath = Join-Path $installDirectory 'FengWoHelperService.exe'
    if ($ping.Content.Trim() -ine $helperPath -or $ping.Headers['x-fengwo-helper-protocol'] -cne '6') { throw 'The isolated FengWo Helper path and protocol header did not verify' }
    $helper = Get-CimInstance Win32_Service -Filter "Name='FengWoHelperService'"
    if (-not $helper -or $helper.State -ne 'Running' -or $helper.PathName.Trim('"') -ine $helperPath) { throw 'The installed Helper SCM identity is incorrect' }
    Assert-FwArmProcess $helper.ProcessId
    Add-Type -Path (Join-Path $PSScriptRoot 'core_fixture.cs')
    $corePipe = [FengWoArm64Tests.CorePipe]::new()
    $coreSession = $corePipe.SessionId
    if ($corePipe.Address -cnotmatch '^\\\\\.\\pipe\\FengWoCore_[a-f0-9]{32}$') { throw 'The Core pipe namespace is incorrect' }
    $start = (Invoke-HelperRequest 'POST' 'start' @{ address = $corePipe.Address; sessionId = $coreSession }).Content | ConvertFrom-Json
    if ($start.sessionId -cne $coreSession -or $start.pid -le 0) { throw 'Helper did not return the owned Core lease' }
    [void]$corePipe.Accept($start.pid, 10000)
    Assert-FwArmProcess $start.pid
    $ownedCore = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $start.pid)
    if ($ownedCore.ExecutablePath -ine (Join-Path $installDirectory 'FengWoCore.exe')) { throw 'Helper started a Core outside its owned installation' }
    $rpcRequest = [ordered]@{ id = 'coexistence-initial-state'; method = 'getIsInit'; arguments = $null }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'owned-core-initial-state-request.json') $rpcRequest
    $corePipe.Send(($rpcRequest | ConvertTo-Json -Compress))
    $rpcDeadline = [DateTime]::UtcNow.AddSeconds(10)
    $rpcFrameIndex = 0
    do {
        $rawResponse = $corePipe.Receive([Math]::Max(1, [int]($rpcDeadline - [DateTime]::UtcNow).TotalMilliseconds))
        $rpcFrameIndex++
        [IO.File]::WriteAllText((Join-Path $EvidenceDirectory ('owned-core-initial-state-response-{0:000}.json' -f $rpcFrameIndex)), $rawResponse, [Text.UTF8Encoding]::new($false))
        $response = $rawResponse | ConvertFrom-Json -AsHashtable
        if ($response -isnot [Collections.IDictionary]) { throw 'The owned Core sent a non-object RPC response' }
    } while ($response['id'] -cne $rpcRequest['id'] -and [DateTime]::UtcNow -lt $rpcDeadline)
    if ($response['id'] -isnot [string] -or $response['id'] -cne $rpcRequest['id'] -or ($response.Contains('error') -and $null -ne $response['error']) -or -not $response.Contains('result') -or $response['result'] -isnot [bool] -or $response['result'] -ne $false) { throw 'The owned Core initial-state RPC did not return Boolean false without an error' }
    $stopped = (Invoke-HelperRequest 'POST' 'stop' @{ sessionId = $coreSession }).Content | ConvertFrom-Json
    if ($stopped.sessionId -cne $coreSession -or $stopped.stopped -ne $true) { throw 'Helper did not stop its owned Core' }
    $coreSession = $null
    $corePipe.Dispose()
    $corePipe = $null
    Assert-ForeignUnchanged 'owned-helper-and-pipe'
    Install-FengWo 'overwrite-install'
    Assert-ForeignUnchanged 'overwrite-install'
    [void](Start-FengWo 'overwrite-startup')
    Assert-ForeignUnchanged 'overwrite-startup'
    Invoke-BoundedProcess (Join-Path $installDirectory 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG=' + (Join-Path $EvidenceDirectory 'uninstall.log'))) 'uninstall'
    if (Get-CimInstance Win32_Service -Filter "Name='FengWoHelperService'") { throw 'Uninstall left the owned Helper SCM registration' }
    if (Test-Path -LiteralPath (Join-Path $installDirectory 'FengWo.exe')) { throw 'Uninstall left the owned application payload' }
    foreach ($hive in @('LocalMachine', 'CurrentUser')) { foreach ($view in @('Registry64', 'Registry32')) { if ($null -ne (Read-RegistryTree $hive ($uninstallRoot + $newId + '_is1') $view)) { throw 'Uninstall left the owned AppId registration' } } }
    if ($null -ne (Read-RegistryTree 'CurrentUser' 'Software\Classes\fengwo')) { throw 'Uninstall left the owned URL association' }
    Assert-ForeignUnchanged 'uninstall'
    $uninstallVerified = $true
} catch { $failure = $_.Exception.Message } finally {
    if ($coreSession) { try { [void](Invoke-HelperRequest 'POST' 'stop' @{ sessionId = $coreSession }) } catch { $cleanupErrors.Add($_.Exception.Message) } }
    if ($corePipe) { $corePipe.Dispose() }
    try { Stop-OwnedApplications } catch { $cleanupErrors.Add($_.Exception.Message) }
    foreach ($process in $ownProcesses) { $process.Dispose() }
    $uninstaller = Join-Path $installDirectory 'unins000.exe'
    if (-not $uninstallVerified -and [IO.File]::Exists($uninstaller)) {
        try { Invoke-BoundedProcess $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG=' + (Join-Path $EvidenceDirectory 'cleanup-uninstall.log'))) 'cleanup-uninstall' } catch {
            $cleanupErrors.Add($_.Exception.Message)
            $uninstallDiagnostic = [ordered]@{ uninstaller_failure = $_.Exception.Message; service = $null; application = $null; cleanup_script = $null; direct_cleanup_attempted = $false; direct_cleanup_failure = $null; diagnostic_failure = $null }
            try {
                $ownHelper = Get-CimInstance Win32_Service -Filter "Name='FengWoHelperService'"
                $helperPath = Join-Path $installDirectory 'FengWoHelperService.exe'
                $helperOwned = -not $ownHelper
                if ($ownHelper) {
                    $uninstallDiagnostic.service = [ordered]@{ name = $ownHelper.Name; state = $ownHelper.State; pid = $ownHelper.ProcessId; path = $ownHelper.PathName }
                    $helperCommand = ([string]$ownHelper.PathName).Trim()
                    if ($helperCommand -match '^"([^"\r\n]+)"$') { $helperCommand = $Matches[1] }
                    if ($helperCommand -notmatch '["\r\n]' -and [IO.Path]::IsPathRooted($helperCommand)) {
                        $helperOwned = [StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetFullPath($helperCommand), [IO.Path]::GetFullPath($helperPath))
                    }
                }
                $applicationPath = Join-Path $installDirectory 'FengWo.exe'
                $applicationOwned = $false
                if ([IO.File]::Exists($applicationPath)) {
                    $metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($applicationPath)
                    $applicationOwned = $metadata.CompanyName -ceq 'FengWo' -and $metadata.ProductName -ceq '蜂窝加速器' -and -not ([IO.File]::GetAttributes($applicationPath) -band [IO.FileAttributes]::ReparsePoint)
                    $uninstallDiagnostic.application = [ordered]@{ path = $applicationPath; company = $metadata.CompanyName; product = $metadata.ProductName; owned = $applicationOwned }
                }
                $cleanupScript = Join-Path $installDirectory 'fengwo_install_cleanup.ps1'
                $sourceScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../windows/packaging/exe/fengwo_install_cleanup.ps1'))
                $scriptOwned = $false
                if ([IO.File]::Exists($cleanupScript) -and [IO.File]::Exists($sourceScript)) {
                    $installedHash = (Get-FileHash -LiteralPath $cleanupScript -Algorithm SHA256).Hash.ToLowerInvariant()
                    $sourceHash = (Get-FileHash -LiteralPath $sourceScript -Algorithm SHA256).Hash.ToLowerInvariant()
                    $scriptOwned = $installedHash -ceq $sourceHash -and -not ([IO.File]::GetAttributes($cleanupScript) -band [IO.FileAttributes]::ReparsePoint)
                    $uninstallDiagnostic.cleanup_script = [ordered]@{ path = $cleanupScript; installed_sha256 = $installedHash; source_sha256 = $sourceHash; matches_source = $scriptOwned }
                }
                $plainPath = $true
                $pathEntry = [IO.DirectoryInfo]::new($installDirectory)
                while ($pathEntry) {
                    if ($pathEntry.Exists -and ($pathEntry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $plainPath = $false }
                    $pathEntry = $pathEntry.Parent
                }
                $uninstallDiagnostic.helper_path_owned = $helperOwned
                $uninstallDiagnostic.plain_install_path = $plainPath
                if ($applicationOwned -and $helperOwned -and $scriptOwned -and $plainPath) {
                    $powershell51 = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
                    if (-not [IO.File]::Exists($powershell51)) { throw 'The native Windows PowerShell diagnostic executable was not found' }
                    $uninstallDiagnostic.direct_cleanup_attempted = $true
                    try { Invoke-BoundedProcess $powershell51 @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $cleanupScript, '-InstallDirectory', $installDirectory, '-Operation', 'uninstall') 'cleanup-uninstall-direct' 60 } catch {
                        $uninstallDiagnostic.direct_cleanup_failure = $_.Exception.Message
                        $cleanupErrors.Add($_.Exception.Message)
                    }
                }
            } catch {
                $uninstallDiagnostic.diagnostic_failure = $_.Exception.Message
                $cleanupErrors.Add($_.Exception.Message)
            } finally {
                try { Save-FwArmEvidence (Join-Path $EvidenceDirectory 'cleanup-uninstall-diagnostic.json') $uninstallDiagnostic } catch { $cleanupErrors.Add($_.Exception.Message) }
            }
        }
    }
    if ($serviceCreated) {
        try {
            $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
            if ($service -and $service.PathName -cne $serviceCommand) { throw 'The foreign fixture service path changed; refusing cleanup of another owner' }
            if ($service) {
                if ($service.State -ne 'Stopped') { Invoke-BoundedProcess 'sc.exe' @('stop', 'FlClashHelperService') 'fixture-service-stop' 20 }
                $controller = [ServiceProcess.ServiceController]::new('FlClashHelperService')
                try { $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(10)) } finally { $controller.Dispose() }
                Invoke-BoundedProcess 'sc.exe' @('delete', 'FlClashHelperService') 'fixture-service-delete' 20
            }
        } catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    foreach ($process in $foreignProcesses) {
        try { if (-not $process.HasExited) { $process.Kill(); if (-not $process.WaitForExit(5000)) { throw 'An exact foreign fixture PID did not exit during cleanup' } } } catch { $cleanupErrors.Add($_.Exception.Message) } finally { $process.Dispose() }
    }
    if ($proxyGuard) {
        try {
            $proxyRestore = $proxyGuard.Restore()
            Save-FwArmEvidence (Join-Path $EvidenceDirectory 'system-proxy-restoration.json') $proxyRestore
            if (-not $proxyRestore.Passed) { throw ('Original system proxy restoration failed: ' + ($proxyRestore.Errors -join '; ')) }
        } catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    if ($proxyListener) { $proxyListener.Stop() }
    if ($listener) { $listener.Stop() }
    if ($lock) { $lock.Dispose() }
    foreach ($entry in $createdKeys) {
        $base = Open-RegistryBase $entry.hive
        try { $base.DeleteSubKeyTree($entry.path, $false) } catch { $cleanupErrors.Add($_.Exception.Message) } finally { $base.Dispose() }
    }
    foreach ($entry in $createdValues) {
        $base = Open-RegistryBase 'CurrentUser'
        try { $key = $base.OpenSubKey($entry.path, $true); if ($key) { try { $key.DeleteValue($entry.name, $false) } finally { $key.Dispose() } } } catch { $cleanupErrors.Add($_.Exception.Message) } finally { $base.Dispose() }
    }
    foreach ($path in $sharedRegistryBefore.Keys) {
        try {
            $restored = Read-RegistryTree 'CurrentUser' $path
            if ($null -eq $sharedRegistryBefore[$path] -and $null -ne $restored -and @($restored.values).Count -eq 0 -and @($restored.children).Count -eq 0) {
                $base = Open-RegistryBase 'CurrentUser'
                try { $base.DeleteSubKey($path, $false) } finally { $base.Dispose() }
                $restored = $null
            }
            if (($restored | ConvertTo-Json -Depth 30 -Compress) -cne ($sharedRegistryBefore[$path] | ConvertTo-Json -Depth 30 -Compress)) { throw 'Shared registry fields did not restore to their pre-fixture state' }
        } catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    foreach ($entry in @([ordered]@{ path = $foreignData; created = $profileCreated }, [ordered]@{ path = $foreignCache; created = $cacheCreated })) {
        if ($entry.created) { try { Remove-Item -LiteralPath $entry.path -Recurse -Force } catch { $cleanupErrors.Add($_.Exception.Message) } }
    }
    if ($fixtureCreated) { try { Remove-Item -LiteralPath $fixtureDirectory -Recurse -Force } catch { $cleanupErrors.Add($_.Exception.Message) } }
    foreach ($directory in @($ownData, $ownCache)) { if ($fixtureCreated -and (Test-Path -LiteralPath $directory)) { try { Remove-Item -LiteralPath $directory -Recurse -Force } catch { $cleanupErrors.Add($_.Exception.Message) } } }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'coexistence-verification.json') ([ordered]@{ passed = (-not $failure -and $cleanupErrors.Count -eq 0 -and $checks.Count -eq 9); failure = $failure; cleanup_failures = @($cleanupErrors.ToArray()); environment = $environment; checks = @($checks.ToArray()); original_app_id = $oldId; owned_app_id = $newId; synthetic_resources_only = $true; system_proxy_started_by_synthetic_fixture = ($null -ne $proxyBaseline); app_system_proxy_or_tun_started = $false; real_customer_account_tested = $false; proxy_restoration = $proxyRestore; owned_uninstall_verified = $uninstallVerified; original_service_stop_count_verified_before_fixture_cleanup = ($checks.Count -eq 9); fixture_source_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'flclash_fixture/flclash_fixture.cpp') -Algorithm SHA256).Hash.ToLowerInvariant(); proxy_fixture_source_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'coexistence_proxy_fixture.cs') -Algorithm SHA256).Hash.ToLowerInvariant() })
}
if ($failure) { throw $failure }
if ($cleanupErrors.Count) { throw ($cleanupErrors -join '; ') }
if ($checks.Count -ne 9) { throw 'Not every coexistence stage was verified' }
