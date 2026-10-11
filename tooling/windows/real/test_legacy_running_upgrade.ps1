param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][string]$Generator,
    [Parameter(Mandatory = $true)][string]$ExpectedInstallerSha256,
    [Parameter(Mandatory = $true)][long]$ExpectedInstallerBytes
)

. (Join-Path $PSScriptRoot '../arm64/common.ps1')
$environment = Assert-FwNativeRunner -Architecture x64
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'The isolated upgrade fixture requires administrator privileges' }
} finally { $identity.Dispose() }
$installer = Get-Item -LiteralPath $InstallerPath
if ($installer.Length -ne $ExpectedInstallerBytes -or (Get-FileHash $installer.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedInstallerSha256) { throw 'The upgrade installer differed from the verified candidate' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$legacyDirectory = Join-Path $env:ProgramFiles 'FlClash'
$payloadDirectory = Join-Path $env:RUNNER_TEMP ('fengwo-upgrade-payload-' + [Guid]::NewGuid().ToString('N'))
$scratch = Join-Path $env:RUNNER_TEMP ('fengwo-upgrade-fixture-' + [Guid]::NewGuid().ToString('N'))
$powershell51 = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$oldRegistry = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\728B3532-C74B-4870-9068-BE70FE12A3E6_is1'
$newRegistry = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\0B31AA8F-C520-4E03-ACF1-FBE8B4EBA461_is1'
$checks = [Collections.Generic.List[object]]::new()
$cleanupErrors = [Collections.Generic.List[string]]::new()
$failure = $null
$directoryCreated = $false
$oldRegistryCreated = $false
$serviceCreated = $false
$baselineInstalled = $false
$upgraded = $false
$gui = $null
$core = $null
$serviceProcess = $null
$pipe = $null

function ConvertTo-UpgradeArguments([string[]]$Arguments) {
    return (@($Arguments | ForEach-Object { '"' + ([regex]::Replace(([regex]::Replace($_, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"' }) -join ' ')
}

function Invoke-UpgradeChild([string]$File, [string[]]$Arguments, [string]$Stage, [int]$TimeoutSeconds = 120) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $File -ArgumentList (ConvertTo-UpgradeArguments $Arguments) -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory ($Stage + '-stdout.txt')) -RedirectStandardError (Join-Path $EvidenceDirectory ($Stage + '-stderr.txt'))
    try {
        $handle = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); [void]$process.WaitForExit(5000); throw ('The owned upgrade child exceeded its deadline: ' + $Stage) }
        $result = [ordered]@{ stage = $Stage; exit_code = $process.ExitCode; elapsed_ms = $watch.ElapsedMilliseconds }
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-result.json')) $result
        return $result
    } finally { $process.Dispose() }
}

function Assert-UpgradeChild([object]$Result) {
    if ($Result.exit_code -ne 0) { throw ('The upgrade stage failed: ' + $Result.stage + ' (' + $Result.exit_code + ')') }
}

function Get-UpgradeState([string]$Stage) {
    $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
    $processes = @(Get-Process -Name FlClash, FlClashCore, FlClashHelperService -ErrorAction SilentlyContinue | ForEach-Object { [ordered]@{ name = $_.ProcessName; pid = $_.Id; path = $_.MainModule.FileName } })
    $state = [ordered]@{ stage = $Stage; service = $(if ($service) { [ordered]@{ name = $service.Name; state = $service.State; pid = $service.ProcessId; path = $service.PathName; accepts_stop = $service.AcceptStop } } else { $null }); processes = $processes }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-state.json')) $state
    return $state
}

function Start-UpgradeComponents([string]$Stage) {
    foreach ($name in @('foreign-stop-count.txt', 'foreign-service-ready.txt', 'gui-ready.txt')) {
        $path = Join-Path $legacyDirectory $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
    }
    Assert-UpgradeChild (Invoke-UpgradeChild 'sc.exe' @('start', 'FlClashHelperService') ($Stage + '-service-start'))
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
        $ready = Join-Path $legacyDirectory 'foreign-service-ready.txt'
        $readyText = $null
        if (Test-Path -LiteralPath $ready -PathType Leaf) { try { $readyText = [IO.File]::ReadAllText($ready) } catch [IO.IOException] {} }
        if ($service -and $service.State -ceq 'Running' -and $service.ProcessId -gt 0 -and $readyText -ceq [string]$service.ProcessId) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $service -or $service.State -cne 'Running' -or $readyText -cne [string]$service.ProcessId) { throw 'The owned legacy SCM fixture did not start' }
    $script:serviceProcess = [Diagnostics.Process]::GetProcessById($service.ProcessId)
    $handle = $script:serviceProcess.Handle
    Assert-FwNativeProcess -ProcessId $service.ProcessId -Architecture x64
    $script:gui = Start-Process -FilePath (Join-Path $legacyDirectory 'FlClash.exe') -ArgumentList (ConvertTo-UpgradeArguments @('idle', (Join-Path $legacyDirectory 'gui-ready.txt'))) -PassThru
    $handle = $script:gui.Handle
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath (Join-Path $legacyDirectory 'gui-ready.txt') -PathType Leaf) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if ($script:gui.HasExited -or -not (Test-Path -LiteralPath (Join-Path $legacyDirectory 'gui-ready.txt') -PathType Leaf)) { throw 'The owned legacy GUI fixture did not start' }
    $script:pipe = [FengWoRealWindowsTests.CorePipe]::new('FlClash')
    $script:core = Start-Process -FilePath (Join-Path $legacyDirectory 'FlClashCore.exe') -ArgumentList $script:pipe.Address -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory ($Stage + '-core-stdout.txt')) -RedirectStandardError (Join-Path $EvidenceDirectory ($Stage + '-core-stderr.txt'))
    $handle = $script:core.Handle
    [void]$script:pipe.Accept($script:core.Id, 10000)
    $request = @{ id = ('upgrade-' + $Stage); method = 'getIsInit'; arguments = $null }
    $script:pipe.Send(($request | ConvertTo-Json -Compress))
    $response = $script:pipe.Receive(10000) | ConvertFrom-Json -AsHashtable
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-core-handshake.json')) ([ordered]@{ request = $request; response = $response })
    if ($response['id'] -cne $request.id -or ($response.Contains('error') -and $null -ne $response['error']) -or -not $response.Contains('result') -or $response['result'] -isnot [bool] -or $response['result']) { throw 'The real owned Core RPC handshake did not verify' }
    $state = Get-UpgradeState ($Stage + '-running')
    if (@($state.processes).Count -ne 3) { throw 'All three exact owned legacy processes must be running' }
    foreach ($entry in $state.processes) { if (-not [StringComparer]::OrdinalIgnoreCase.Equals([IO.Path]::GetDirectoryName($entry.path), $legacyDirectory)) { throw 'A running legacy process belongs to another installation' } }
}

function Assert-UpgradeComponentsStopped([string]$Stage, [bool]$ExpectRemoved = $false) {
    $state = Get-UpgradeState $Stage
    if (@($state.processes).Count -ne 0) { throw 'The exact legacy processes survived the product cleanup' }
    if ($ExpectRemoved) { if ($null -ne $state.service) { throw 'The upgrade left the owned legacy SCM registration' } } elseif (-not $state.service -or $state.service.state -cne 'Stopped') { throw 'The product did not stop the owned legacy service' }
    foreach ($process in @($script:gui, $script:core, $script:serviceProcess)) {
        if ($process -and -not $process.WaitForExit(5000)) { throw 'An exact owned legacy PID survived cleanup' }
        if ($process) { $process.Dispose() }
    }
    $script:gui = $null
    $script:core = $null
    $script:serviceProcess = $null
    if ($script:pipe) { $script:pipe.Dispose(); $script:pipe = $null }
}

try {
    if (Test-Path -LiteralPath $legacyDirectory) { throw 'A pre-existing Program Files FlClash directory prevents isolation' }
    if (Get-Process -Name FlClash, FlClashCore, FlClashHelperService, FengWo, FengWoCore, FengWoHelperService -ErrorAction SilentlyContinue) { throw 'Existing client processes prevent isolation' }
    if (Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService' OR Name='FengWoHelperService'") { throw 'An existing client service prevents isolation' }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try { foreach ($path in @($oldRegistry, $newRegistry)) { $key = $base.OpenSubKey($path); if ($key) { $key.Dispose(); throw 'An existing product installation prevents isolation' } } } finally { $base.Dispose() }
    [void][IO.Directory]::CreateDirectory($scratch)
    Assert-UpgradeChild (Invoke-UpgradeChild $powershell51 @('-NoProfile', '-NonInteractive', '-Command', '$PSVersionTable.PSVersion.ToString()') 'powershell51-version')
    if ([IO.File]::ReadAllText((Join-Path $EvidenceDirectory 'powershell51-version-stdout.txt')).Trim() -notmatch '^5\.1\.') { throw 'Real native Windows PowerShell 5.1 is required' }
    Assert-UpgradeChild (Invoke-UpgradeChild $installer.FullName @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR=' + $payloadDirectory), '/TASKS=', ('/LOG=' + (Join-Path $EvidenceDirectory 'payload-installation.log'))) 'payload-install')
    $baselineInstalled = $true
    $source = Join-Path $payloadDirectory 'fengwo_install_cleanup.ps1'
    $repositorySource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../windows/packaging/exe/fengwo_install_cleanup.ps1'))
    if ((Get-FileHash $source -Algorithm SHA256).Hash -cne (Get-FileHash $repositorySource -Algorithm SHA256).Hash) { throw 'The actual packaged cleanup script differed from candidate source' }
    $fixtureSource = Join-Path $PSScriptRoot '../arm64/flclash_fixture/flclash_fixture.cpp'
    Copy-Item -LiteralPath $fixtureSource -Destination (Join-Path $scratch 'fixture.cpp')
    [IO.File]::WriteAllText((Join-Path $scratch 'CMakeLists.txt'), @'
cmake_minimum_required(VERSION 3.15)
project(fengwo_legacy_upgrade_fixture LANGUAGES CXX RC)
add_executable(legacy_fixture fixture.cpp brand.rc)
set_property(TARGET legacy_fixture PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_compile_features(legacy_fixture PRIVATE cxx_std_17)
target_compile_definitions(legacy_fixture PRIVATE UNICODE _UNICODE)
target_compile_options(legacy_fixture PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/W4> $<$<COMPILE_LANGUAGE:CXX>:/WX>)
target_link_libraries(legacy_fixture PRIVATE advapi32 user32)
'@, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $scratch 'brand.rc'), @'
#include <windows.h>
1 VERSIONINFO
FILEVERSION 1,0,8,0
PRODUCTVERSION 1,0,8,0
FILEFLAGSMASK 0x3fL
FILEFLAGS 0x0L
FILEOS VOS_NT_WINDOWS32
FILETYPE VFT_APP
FILESUBTYPE 0x0L
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904e4"
    BEGIN
      VALUE "CompanyName", "com.follow\0"
      VALUE "ProductName", "蜂窝加速器\0"
      VALUE "FileDescription", "FengWo synthetic legacy upgrade fixture\0"
      VALUE "FileVersion", "1.0.8\0"
      VALUE "InternalName", "FlClash\0"
      VALUE "OriginalFilename", "FlClash.exe\0"
      VALUE "ProductVersion", "1.0.8\0"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x0409, 1252
  END
END
'@, [Text.UnicodeEncoding]::new($false, $true))
    Assert-UpgradeChild (Invoke-UpgradeChild 'cmake' @('-S', $scratch, '-B', (Join-Path $scratch 'build'), '-G', $Generator, '-A', 'x64') 'fixture-configure')
    Assert-UpgradeChild (Invoke-UpgradeChild 'cmake' @('--build', (Join-Path $scratch 'build'), '--config', 'Release') 'fixture-build')
    [void][IO.Directory]::CreateDirectory($legacyDirectory)
    $directoryCreated = $true
    foreach ($name in @('FlClash.exe', 'FlClashHelperService.exe')) { Copy-Item -LiteralPath (Join-Path $scratch 'build/Release/legacy_fixture.exe') -Destination (Join-Path $legacyDirectory $name) }
    Copy-Item -LiteralPath (Join-Path $payloadDirectory 'FengWoCore.exe') -Destination (Join-Path $legacyDirectory 'FlClashCore.exe')
    $metadata = (Get-Item -LiteralPath (Join-Path $legacyDirectory 'FlClash.exe')).VersionInfo
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'legacy-product-metadata.json') ([ordered]@{ company = $metadata.CompanyName; product = $metadata.ProductName; file_version = $metadata.FileVersion; product_version = $metadata.ProductVersion; internal_name = $metadata.InternalName; language = $metadata.Language })
    Copy-Item -LiteralPath (Join-Path $scratch 'brand.rc') -Destination (Join-Path $EvidenceDirectory 'synthetic-brand.rc')
    Copy-Item -LiteralPath (Join-Path $scratch 'build/Release/legacy_fixture.exe') -Destination (Join-Path $EvidenceDirectory 'synthetic-legacy-fixture.exe')
    if ($metadata.CompanyName -cne 'com.follow' -or $metadata.ProductName -cne '蜂窝加速器') { throw 'The real old product metadata did not verify' }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $base.CreateSubKey($oldRegistry)
        $oldRegistryCreated = $true
        try { $key.SetValue('DisplayName', '蜂窝加速器 1.0.8'); $key.SetValue('DisplayVersion', '1.0.8'); $key.SetValue('InstallLocation', $legacyDirectory); $key.SetValue('Inno Setup: App Path', $legacyDirectory) } finally { $key.Dispose() }
    } finally { $base.Dispose() }
    $serviceCommand = '"' + (Join-Path $legacyDirectory 'FlClashHelperService.exe') + '"'
    Assert-UpgradeChild (Invoke-UpgradeChild 'sc.exe' @('create', 'FlClashHelperService', 'binPath=', $serviceCommand, 'start=', 'demand') 'legacy-service-create')
    $serviceCreated = $true
    Add-Type -Path (Join-Path $PSScriptRoot 'core_windows_fixture.cs')
    Start-UpgradeComponents 'direct-stop'
    $ownership = Join-Path $EvidenceDirectory 'direct-stop-ownership.json'
    $result = Invoke-UpgradeChild $powershell51 @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $source, '-InstallDirectory', $legacyDirectory, '-Operation', 'stop', '-OwnershipEvidencePath', $ownership) 'direct-stop'
    [void](Get-UpgradeState 'direct-stop-result')
    Assert-UpgradeChild $result
    Assert-UpgradeComponentsStopped 'direct-stop-stopped'
    $owned = Get-Content -LiteralPath $ownership -Raw | ConvertFrom-Json
    if (-not $owned.owned_before_install -or -not $owned.legacy_application -or -not $owned.legacy_service_owned_before_install) { throw 'The running old application and service were not adopted by strict ownership' }
    $checks.Add([ordered]@{ name = 'running-legacy-direct-ps51-stop'; passed = $true; exact_old_metadata = $true; real_core_pipe_pid_verified = $true; result = $result })
    $result = Invoke-UpgradeChild $powershell51 @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $source, '-InstallDirectory', $legacyDirectory, '-Operation', 'stop', '-OwnershipEvidencePath', (Join-Path $EvidenceDirectory 'already-stopped-ownership.json')) 'already-stopped'
    Assert-UpgradeChild $result
    $checks.Add([ordered]@{ name = 'already-stopped-idempotent-ps51-stop'; passed = $true; result = $result })
    Start-UpgradeComponents 'actual-upgrade'
    $result = Invoke-UpgradeChild $installer.FullName @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR=' + $legacyDirectory), '/TASKS=', ('/LOG=' + (Join-Path $EvidenceDirectory 'actual-upgrade-installation.log'))) 'actual-upgrade'
    [void](Get-UpgradeState 'actual-upgrade-result')
    Assert-UpgradeChild $result
    $upgraded = $true
    Assert-UpgradeComponentsStopped 'actual-upgrade-stopped' $true
    foreach ($name in @('FengWo.exe', 'FengWoCore.exe', 'FengWoHelperService.exe')) { if ((Get-FileHash (Join-Path $legacyDirectory $name) -Algorithm SHA256).Hash -cne (Get-FileHash (Join-Path $payloadDirectory $name) -Algorithm SHA256).Hash) { throw ('The upgrade installed a different product component: ' + $name) } }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try { $key = $base.OpenSubKey($oldRegistry); if ($key) { $key.Dispose(); throw 'The trusted old uninstall GUID survived the upgrade' }; $key = $base.OpenSubKey($newRegistry); if (-not $key) { throw 'The new product registration is missing' }; try { if (-not [StringComparer]::OrdinalIgnoreCase.Equals([string]$key.GetValue('Inno Setup: App Path'), $legacyDirectory)) { throw 'The new installation registration points at the wrong directory' } } finally { $key.Dispose() } } finally { $base.Dispose() }
    $checks.Add([ordered]@{ name = 'running-legacy-full-installer-upgrade'; passed = $true; old_service_removed = $true; new_components_exact = $true; result = $result })
} catch {
    $failure = $_.Exception.Message
    try { [void](Get-UpgradeState 'failure') } catch { $cleanupErrors.Add('Failure state could not be read: ' + $_.Exception.Message) }
} finally {
    foreach ($process in @($gui, $core, $serviceProcess)) {
        if ($process) { try { if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) } } catch { $cleanupErrors.Add($_.Exception.Message) } finally { $process.Dispose() } }
    }
    if ($pipe) { try { $pipe.Dispose() } catch { $cleanupErrors.Add($_.Exception.Message) } }
    if ($serviceCreated) {
        try {
            $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
            if ($service) { if ($service.PathName -cne $serviceCommand) { throw 'The legacy SCM owner changed; refusing cleanup' }; Assert-UpgradeChild (Invoke-UpgradeChild 'sc.exe' @('delete', 'FlClashHelperService') 'final-service-delete') }
        } catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    if ($baselineInstalled) {
        $uninstaller = Join-Path $(if ($upgraded) { $legacyDirectory } else { $payloadDirectory }) 'unins000.exe'
        try { if (Test-Path -LiteralPath $uninstaller -PathType Leaf) { Assert-UpgradeChild (Invoke-UpgradeChild $uninstaller @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG=' + (Join-Path $EvidenceDirectory 'final-uninstallation.log'))) 'final-uninstall') } } catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    if ($oldRegistryCreated) { try { $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64); try { $base.DeleteSubKeyTree($oldRegistry, $false) } finally { $base.Dispose() } } catch { $cleanupErrors.Add($_.Exception.Message) } }
    foreach ($path in @($scratch, $payloadDirectory)) { try { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force } } catch { $cleanupErrors.Add($_.Exception.Message) } }
    if ($directoryCreated) { try { Remove-Item -LiteralPath $legacyDirectory -Recurse -Force } catch { $cleanupErrors.Add($_.Exception.Message) } }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'upgrade-verification.json') ([ordered]@{ passed = (-not $failure -and $cleanupErrors.Count -eq 0 -and $checks.Count -eq 3); failure = $failure; cleanup_failures = @($cleanupErrors.ToArray()); checks = @($checks.ToArray()); installer_sha256 = $ExpectedInstallerSha256; installer_bytes = $ExpectedInstallerBytes; environment = $environment; legacy_directory = $legacyDirectory; legacy_application = 'synthetic native GUI with com.follow product metadata'; legacy_core = 'actual packaged Core under its legacy executable name'; legacy_service = 'actual SCM native synthetic service'; customer_data_uploaded = $false; system_proxy_or_tun_started = $false })
}
if ($failure) { throw $failure }
if ($cleanupErrors.Count) { throw ($cleanupErrors -join '; ') }
if ($checks.Count -ne 3) { throw 'All three running legacy upgrade stages are required' }
