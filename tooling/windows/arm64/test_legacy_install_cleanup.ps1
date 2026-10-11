param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

. (Join-Path $PSScriptRoot 'common.ps1')
$environment = Assert-FwArmRunner
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'The harness requires PowerShell 7; the product script is tested with Windows PowerShell 5.1' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'The isolated SCM fixture requires administrator privileges' }
} finally { $identity.Dispose() }
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
$application = Join-Path $bundle 'FengWo.exe'
$metadata = (Get-Item -LiteralPath $application).VersionInfo
if ($metadata.CompanyName -cne 'FengWo' -or $metadata.ProductName -cne '蜂窝加速器' -or -not (Get-FwPeIdentity $application).arm64) { throw 'The test requires the real native FengWo application identity' }
$repositorySource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../windows/packaging/exe/fengwo_install_cleanup.ps1'))
$source = Join-Path $bundle 'prerequisites/fengwo_install_cleanup.ps1'
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $repositorySource -Algorithm SHA256).Hash) { throw 'The packaged cleanup script differs from the frozen product source' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$root = Join-Path $env:RUNNER_TEMP ('fengwo-legacy-cleanup-' + [Guid]::NewGuid().ToString('N'))
$registryPath = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\728B3532-C74B-4870-9068-BE70FE12A3E6_is1'
$powershell51 = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
if (-not [IO.File]::Exists($powershell51)) { throw 'The native Windows PowerShell executable was not found' }
$checks = [Collections.Generic.List[object]]::new()
$cleanupErrors = [Collections.Generic.List[string]]::new()
$failure = $null
$created = $false
$caseRegistryCreated = $false
$caseProtocolsCreated = [Collections.Generic.List[string]]::new()
$caseAutoLaunchCreated = $false
$caseAutoLaunchCommands = [Collections.Generic.List[string]]::new()
$caseAutoLaunchApprovals = [Collections.Generic.List[string]]::new()
$autoLaunchPaths = @('Software\Microsoft\Windows\CurrentVersion\Run', 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32')
$enabledApproval = [byte[]](2, 0, 0, 0, 11, 22, 33, 44, 55, 66, 77, 88)
$disabledApproval = [byte[]](3, 0, 0, 0, 88, 77, 66, 55, 44, 33, 22, 11)
$serviceCreated = $false
$serviceProcess = $null
$serviceCommand = $null
$counter = $null

function Open-LegacyRegistry([string]$Hive = 'LocalMachine', [string]$View = 'Registry64') {
    return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$Hive, [Microsoft.Win32.RegistryView]::$View)
}

function Read-LegacyRegistryTree([string]$Path, [string]$Hive = 'LocalMachine', [string]$View = 'Registry64') {
    $base = Open-LegacyRegistry $Hive $View
    try {
        $key = $base.OpenSubKey($Path)
        if (-not $key) { return $null }
        try {
            $values = @()
            foreach ($name in @($key.GetValueNames() | Sort-Object)) {
                $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($value -is [byte[]]) { $value = [Convert]::ToBase64String($value) }
                $values += [ordered]@{ name = $name; kind = $key.GetValueKind($name).ToString(); value = $value }
            }
            $children = @()
            foreach ($name in @($key.GetSubKeyNames() | Sort-Object)) { $children += [ordered]@{ name = $name; tree = (Read-LegacyRegistryTree ($Path + '\' + $name) $Hive $View) } }
            return [ordered]@{ values = $values; children = $children }
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function ConvertTo-LegacyArguments([string[]]$Arguments) {
    return (@($Arguments | ForEach-Object { '"' + ([regex]::Replace(([regex]::Replace($_, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"' }) -join ' ')
}

function Invoke-LegacyChild([string]$File, [string[]]$Arguments, [string]$Stage, [bool]$ExpectFailure = $false, [int]$TimeoutSeconds = 60) {
    $process = Start-Process -FilePath $File -ArgumentList (ConvertTo-LegacyArguments $Arguments) -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory ($Stage + '-stdout.txt')) -RedirectStandardError (Join-Path $EvidenceDirectory ($Stage + '-stderr.txt'))
    try {
        $handle = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); [void]$process.WaitForExit(5000); throw ('The exact owned child exceeded its deadline: ' + $Stage) }
        if (($ExpectFailure -and $process.ExitCode -eq 0) -or (-not $ExpectFailure -and $process.ExitCode -ne 0)) { throw ('Unexpected child exit code: ' + $Stage + ' (' + $process.ExitCode + ')') }
        return $process.ExitCode
    } finally { $process.Dispose() }
}

function Invoke-RealLegacyCleanup([string]$Directory, [string]$Operation, [string]$EvidencePath, [string]$Stage, [bool]$ExpectFailure = $false) {
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $source, '-Operation', $Operation)
    if ($Operation -ceq 'discover') { $arguments += @('-DiscoveryOutputPath', $EvidencePath) } else { $arguments += @('-InstallDirectory', $Directory, '-OwnershipEvidencePath', $EvidencePath) }
    [void](Invoke-LegacyChild $powershell51 $arguments $Stage $ExpectFailure)
}

function Write-LegacyRegistration([string]$DisplayName, [string]$Location) {
    $base = Open-LegacyRegistry
    try {
        $key = $base.CreateSubKey($registryPath)
        $script:caseRegistryCreated = $true
        try {
            $key.SetValue('DisplayName', $DisplayName)
            $key.SetValue('DisplayVersion', '0.8.97')
            $key.SetValue('InstallLocation', $Location)
            $key.SetValue('Inno Setup: App Path', $Location)
            $key.SetValue('UninstallString', ('"' + (Join-Path $Location 'unins000.exe') + '"'))
            $key.SetValue('SentinelBinary', [byte[]](0, 1, 255, 42), [Microsoft.Win32.RegistryValueKind]::Binary)
            $key.SetValue('SentinelDword', 42, [Microsoft.Win32.RegistryValueKind]::DWord)
            $key.SetValue('SentinelQword', [long]1099511627776, [Microsoft.Win32.RegistryValueKind]::QWord)
            $key.SetValue('SentinelExpand', '%TEMP%\FlClash', [Microsoft.Win32.RegistryValueKind]::ExpandString)
            $key.SetValue('SentinelMulti', [string[]]('first', 'second'), [Microsoft.Win32.RegistryValueKind]::MultiString)
        } finally { $key.Dispose() }
        $child = $base.CreateSubKey($registryPath + '\sentinel-child')
        try { $child.SetValue('', 'FOREIGN_SYNTHETIC_REGISTRY') } finally { $child.Dispose() }
    } finally { $base.Dispose() }
}

function Write-LegacyProtocol([string]$Scheme, [string]$Executable) {
    if ($Scheme -cnotin @('clash', 'clashmeta', 'flclash', 'fengwo')) { throw 'Unexpected synthetic protocol identity' }
    $base = Open-LegacyRegistry 'CurrentUser'
    try {
        $key = $base.CreateSubKey('Software\Classes\' + $Scheme)
        if (-not $script:caseProtocolsCreated.Contains($Scheme)) { $script:caseProtocolsCreated.Add($Scheme) }
        try {
            $key.SetValue('', 'Synthetic protocol ' + $Scheme)
            $key.SetValue('URL Protocol', '')
            $key.SetValue('FengWoSyntheticFixture', 'FENGWO_SYNTHETIC_URI_FIXTURE')
        } finally { $key.Dispose() }
        $command = $base.CreateSubKey('Software\Classes\' + $Scheme + '\shell\open\command')
        try { $command.SetValue('', ('"' + $Executable + '" "%1"')) } finally { $command.Dispose() }
    } finally { $base.Dispose() }
}

function Assert-LegacyProtocolUnchanged([string]$Scheme, [object]$Before, [string]$Stage) {
    $after = Read-LegacyRegistryTree ('Software\Classes\' + $Scheme) 'CurrentUser'
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-uri-' + $Scheme + '.json')) $after
    if (($Before | ConvertTo-Json -Depth 30 -Compress) -cne ($after | ConvertTo-Json -Depth 30 -Compress)) { throw ('The protected protocol registration changed: ' + $Stage + '/' + $Scheme) }
}

function Read-LegacyAutoLaunchValue([string]$Path, [string]$Name, [string]$View) {
    $base = Open-LegacyRegistry 'CurrentUser' $View
    try {
        $key = $base.OpenSubKey($Path)
        if (-not $key) { return $null }
        try {
            if ($key.GetValueNames() -notcontains $Name) { return $null }
            $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($value -is [byte[]]) { $value = [Convert]::ToBase64String($value) }
            return [ordered]@{ value = $value; kind = $key.GetValueKind($Name).ToString() }
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}

function Get-LegacyAutoLaunchSnapshot {
    $values = @()
    foreach ($view in @('Registry64', 'Registry32')) {
        foreach ($path in $script:autoLaunchPaths) {
            foreach ($name in @('FengWo', 'FlClash')) { $values += [ordered]@{ view = $view; path = $path; name = $name; state = (Read-LegacyAutoLaunchValue $path $name $view) } }
        }
    }
    return $values
}

function Write-LegacyAutoLaunch([string]$Name, [string]$Executable, [byte[]]$Approved) {
    if ($Name -cnotin @('FengWo', 'FlClash')) { throw 'Unexpected synthetic auto-launch identity' }
    $command = '"' + $Executable + '"'
    if (-not $script:caseAutoLaunchCommands.Contains($command)) { $script:caseAutoLaunchCommands.Add($command) }
    $approval = [Convert]::ToBase64String($Approved)
    if (-not $script:caseAutoLaunchApprovals.Contains($approval)) { $script:caseAutoLaunchApprovals.Add($approval) }
    $script:caseAutoLaunchCreated = $true
    foreach ($view in @('Registry64', 'Registry32')) {
        $base = Open-LegacyRegistry 'CurrentUser' $view
        try {
            $run = $base.CreateSubKey($script:autoLaunchPaths[0])
            try { $run.SetValue($Name, $command, [Microsoft.Win32.RegistryValueKind]::String) } finally { $run.Dispose() }
            foreach ($path in $script:autoLaunchPaths[1..2]) {
                $key = $base.CreateSubKey($path)
                try { $key.SetValue($Name, $Approved, [Microsoft.Win32.RegistryValueKind]::Binary) } finally { $key.Dispose() }
            }
        } finally { $base.Dispose() }
    }
}

function Assert-LegacyAutoLaunchMigrated([string]$Directory, [byte[]]$Approved, [string]$Stage) {
    $after = Get-LegacyAutoLaunchSnapshot
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-auto-launch.json')) $after
    $command = '"' + (Join-Path $Directory 'FengWo.exe') + '"'
    $approval = [Convert]::ToBase64String($Approved)
    foreach ($entry in $after) {
        if ($entry.name -ceq 'FlClash') { if ($null -ne $entry.state) { throw 'An owned old auto-launch value survived migration' }; continue }
        $expected = if ($entry.path -ceq $script:autoLaunchPaths[0]) { $command } else { $approval }
        $kind = if ($entry.path -ceq $script:autoLaunchPaths[0]) { 'String' } else { 'Binary' }
        if (-not $entry.state -or $entry.state.value -cne $expected -or $entry.state.kind -cne $kind) { throw 'Owned auto-launch migration did not preserve its exact command and enable state' }
    }
}

function Assert-LegacyAutoLaunchUnchanged([object]$Before, [string]$Stage, [string]$Name = '') {
    $after = Get-LegacyAutoLaunchSnapshot
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-auto-launch.json')) $after
    $first = @($Before | Where-Object { -not $Name -or $_.name -ceq $Name })
    $second = @($after | Where-Object { -not $Name -or $_.name -ceq $Name })
    if (($first | ConvertTo-Json -Depth 10 -Compress) -cne ($second | ConvertTo-Json -Depth 10 -Compress)) { throw 'A protected auto-launch command or enable state changed' }
}

function Remove-LegacyAutoLaunchFixtures {
    if (-not $script:caseAutoLaunchCreated) { return }
    foreach ($view in @('Registry64', 'Registry32')) {
        $base = Open-LegacyRegistry 'CurrentUser' $view
        try {
            foreach ($path in $script:autoLaunchPaths) {
                $key = $base.OpenSubKey($path, $true)
                if (-not $key) { continue }
                try {
                    foreach ($name in @('FengWo', 'FlClash')) {
                        if ($key.GetValueNames() -notcontains $name) { continue }
                        $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                        $owned = if ($path -ceq $script:autoLaunchPaths[0]) { $value -is [string] -and $script:caseAutoLaunchCommands.Contains($value) } else { $value -is [byte[]] -and $script:caseAutoLaunchApprovals.Contains([Convert]::ToBase64String($value)) }
                        if (-not $owned) { throw 'The synthetic auto-launch owner changed; refusing fixture cleanup' }
                        $key.DeleteValue($name, $false)
                    }
                } finally { $key.Dispose() }
            }
        } finally { $base.Dispose() }
    }
    $script:caseAutoLaunchCreated = $false
    $script:caseAutoLaunchCommands.Clear()
    $script:caseAutoLaunchApprovals.Clear()
}

function Start-LegacyService([string]$Directory, [string]$Case) {
    if (Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'") { throw 'An existing service prevents this SCM fixture stage' }
    $executable = Join-Path $Directory 'FlClashHelperService.exe'
    Copy-Item -LiteralPath $script:fixtureExecutable -Destination $executable
    $script:serviceCommand = '"' + $executable + '"'
    $script:counter = Join-Path $Directory 'foreign-stop-count.txt'
    $ready = Join-Path $Directory 'foreign-service-ready.txt'
    [void](Invoke-LegacyChild 'sc.exe' @('create', 'FlClashHelperService', 'binPath=', $script:serviceCommand, 'start=', 'demand') ($Case + '-create-service'))
    $script:serviceCreated = $true
    $registered = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
    if (-not $registered -or $registered.PathName -cne $script:serviceCommand) { throw 'The newly created SCM fixture path did not verify' }
    [void](Invoke-LegacyChild 'sc.exe' @('start', 'FlClashHelperService') ($Case + '-start-service'))
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $fixtureReady = $false
    do {
        $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
        if ($service -and $service.State -ceq 'Running' -and $service.ProcessId -gt 0 -and [IO.File]::Exists($ready)) {
            try { $readyText = [IO.File]::ReadAllText($ready) } catch [IO.IOException] { $readyText = $null }
            $fixtureReady = $readyText -ceq ([string]$service.ProcessId)
            if ($fixtureReady) { break }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $fixtureReady) { throw 'The native no-argument SCM fixture failed to start' }
    $script:serviceProcess = [Diagnostics.Process]::GetProcessById($service.ProcessId)
    $handle = $script:serviceProcess.Handle
    Assert-FwArmProcess $service.ProcessId
    if ($service.PathName -cne $script:serviceCommand -or [IO.File]::ReadAllText($script:counter) -cne '0') { throw 'The service fixture initial ownership did not verify' }
}

function Get-LegacyServiceSnapshot {
    $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
    if (-not $service -or $service.State -cne 'Running' -or $service.ProcessId -ne $script:serviceProcess.Id -or $script:serviceProcess.HasExited) { throw 'The external native service did not remain alive' }
    if ([IO.File]::ReadAllText($script:counter) -cne '0') { throw 'The product sent STOP to the external native service' }
    return [ordered]@{ name = $service.Name; pid = $service.ProcessId; path = $service.PathName; state = $service.State; start_mode = $service.StartMode; account = $service.StartName; registry = (Read-LegacyRegistryTree 'SYSTEM\CurrentControlSet\Services\FlClashHelperService'); stop_count = 0 }
}

function Assert-LegacyRegistryUnchanged([object]$Before, [string]$Stage) {
    $after = Read-LegacyRegistryTree $registryPath
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-registry.json')) $after
    if (($Before | ConvertTo-Json -Depth 30 -Compress) -cne ($after | ConvertTo-Json -Depth 30 -Compress)) { throw ('The original FlClash uninstall registration changed: ' + $Stage) }
}

function Remove-LegacyCase([string]$Case) {
    Remove-LegacyAutoLaunchFixtures
    if ($script:serviceCreated) {
        $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
        if ($service) {
            if ($service.PathName -cne $script:serviceCommand) { throw 'The SCM fixture path changed; refusing cleanup of another service owner' }
            if ($service.State -cne 'Stopped') { [void](Invoke-LegacyChild 'sc.exe' @('stop', 'FlClashHelperService') ($Case + '-cleanup-stop')) }
            $controller = [ServiceProcess.ServiceController]::new('FlClashHelperService')
            try { $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(10)) } finally { $controller.Dispose() }
            [void](Invoke-LegacyChild 'sc.exe' @('delete', 'FlClashHelperService') ($Case + '-cleanup-delete'))
        }
        $script:serviceCreated = $false
    }
    if ($script:serviceProcess) {
        try { if (-not $script:serviceProcess.HasExited) { $script:serviceProcess.Kill(); if (-not $script:serviceProcess.WaitForExit(5000)) { throw 'The exact owned SCM fixture PID did not exit' } } } finally { $script:serviceProcess.Dispose(); $script:serviceProcess = $null }
    }
    if ($script:caseRegistryCreated) {
        $base = Open-LegacyRegistry
        try { $base.DeleteSubKeyTree($registryPath, $false) } finally { $base.Dispose() }
        $script:caseRegistryCreated = $false
    }
    $base = Open-LegacyRegistry 'CurrentUser'
    try {
        foreach ($scheme in $script:caseProtocolsCreated.ToArray()) {
            $name = 'Software\Classes\' + $scheme
            $key = $base.OpenSubKey($name)
            if (-not $key) { continue }
            try { $owned = $key.GetValue('FengWoSyntheticFixture') -ceq 'FENGWO_SYNTHETIC_URI_FIXTURE' } finally { $key.Dispose() }
            if (-not $owned) { throw 'The synthetic protocol owner changed; refusing fixture cleanup' }
            $base.DeleteSubKeyTree($name, $false)
        }
        $script:caseProtocolsCreated.Clear()
    } finally { $base.Dispose() }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        if (-not (Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'")) { return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'The owned service fixture registration was not fully removed'
}

try {
    if (Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'") { throw 'A pre-existing FlClash service prevents isolation' }
    foreach ($hive in @('LocalMachine', 'CurrentUser')) {
        foreach ($view in @('Registry64', 'Registry32')) {
            $base = Open-LegacyRegistry $hive $view
            try {
                foreach ($name in @($registryPath, ($registryPath.Replace('728B3532-', '{728B3532-').Replace('_is1', '}_is1')))) {
                    $key = $base.OpenSubKey($name)
                    if ($key) { $key.Dispose(); throw 'A pre-existing original uninstall GUID prevents isolation' }
                }
            } finally { $base.Dispose() }
        }
    }
    foreach ($view in @('Registry64', 'Registry32')) {
        $base = Open-LegacyRegistry 'CurrentUser' $view
        try {
            foreach ($scheme in @('clash', 'clashmeta', 'flclash', 'fengwo')) {
                $key = $base.OpenSubKey('Software\Classes\' + $scheme)
                if ($key) { $key.Dispose(); throw 'A pre-existing protocol registration prevents isolation' }
            }
        } finally { $base.Dispose() }
    }
    foreach ($entry in @(Get-LegacyAutoLaunchSnapshot)) {
        if ($null -ne $entry.state) { throw 'A pre-existing FengWo or FlClash auto-launch value prevents isolation' }
    }
    [void][IO.Directory]::CreateDirectory($root)
    $created = $true
    [void](Invoke-LegacyChild $powershell51 @('-NoProfile', '-NonInteractive', '-Command', '$PSVersionTable.PSVersion.ToString()') 'powershell51-version')
    $version = [IO.File]::ReadAllText((Join-Path $EvidenceDirectory 'powershell51-version-stdout.txt')).Trim()
    if ($version -notmatch '^5\.1\.') { throw ('The product was not tested with real Windows PowerShell 5.1: ' + $version) }
    $fixtureBuild = Join-Path $root 'fixture-build'
    if (-not $env:FENGWO_ARM64_CMAKE_GENERATOR) { throw 'The native ARM64 CMake generator is required' }
    [void](Invoke-LegacyChild 'cmake' @('-S', (Join-Path $PSScriptRoot 'flclash_fixture'), '-B', $fixtureBuild, '-G', $env:FENGWO_ARM64_CMAKE_GENERATOR, '-A', 'ARM64') 'fixture-configure' $false 120)
    [void](Invoke-LegacyChild 'cmake' @('--build', $fixtureBuild, '--config', 'Release') 'fixture-build' $false 120)
    $fixtureExecutable = Join-Path $fixtureBuild 'Release/flclash_fixture.exe'
    if (-not (Get-FwPeIdentity $fixtureExecutable).arm64) { throw 'The SCM fixture is not a native ARM64 executable' }
    foreach ($case in @('owned-service-foreign-guid', 'external-service', 'unowned-directory', 'owned-legacy-guid')) {
        $caseDirectory = Join-Path $root $case
        $honey = Join-Path $caseDirectory 'FengWo'
        $foreign = Join-Path $caseDirectory 'FlClash'
        [void][IO.Directory]::CreateDirectory($honey)
        [void][IO.Directory]::CreateDirectory($foreign)
        if ($case -cne 'unowned-directory') { Copy-Item -LiteralPath $application -Destination (Join-Path $honey 'FengWo.exe') }
        $ownedGuid = $case -ceq 'owned-legacy-guid'
        Write-LegacyRegistration $(if ($ownedGuid) { '蜂窝加速器 1.0.8' } else { 'FlClash 0.8.97' }) $(if ($ownedGuid) { $honey } else { $foreign })
        $before = Read-LegacyRegistryTree $registryPath
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($case + '-registry-before.json')) $before
        $foreignProtocolBefore = $null
        $currentProtocolBefore = $null
        if ($ownedGuid) {
            Copy-Item -LiteralPath $application -Destination (Join-Path $honey 'FlClash.exe')
            Copy-Item -LiteralPath $fixtureExecutable -Destination (Join-Path $foreign 'FlClash.exe')
            Write-LegacyProtocol 'clash' (Join-Path $honey 'FengWo.exe')
            Write-LegacyProtocol 'clashmeta' (Join-Path $honey 'FlClash.exe')
            Write-LegacyProtocol 'flclash' (Join-Path $foreign 'FlClash.exe')
            Write-LegacyProtocol 'fengwo' (Join-Path $honey 'FengWo.exe')
            $foreignProtocolBefore = Read-LegacyRegistryTree 'Software\Classes\flclash' 'CurrentUser'
            $currentProtocolBefore = Read-LegacyRegistryTree 'Software\Classes\fengwo' 'CurrentUser'
            Save-FwArmEvidence (Join-Path $EvidenceDirectory ($case + '-foreign-uri-before.json')) $foreignProtocolBefore
            $caseAutoLaunchCommands.Add('"' + (Join-Path $honey 'FengWo.exe') + '"')
            Write-LegacyAutoLaunch 'FlClash' (Join-Path $honey 'FlClash.exe') $enabledApproval
        }
        Start-LegacyService $(if ($case -cin @('owned-service-foreign-guid', 'owned-legacy-guid')) { $honey } else { $foreign }) $case
        try {
            $evidence = Join-Path $EvidenceDirectory ($case + '-ownership.json')
            if ($ownedGuid) {
                $discovery = Join-Path $EvidenceDirectory 'owned-legacy-guid-discovery.txt'
                Invoke-RealLegacyCleanup '' 'discover' $discovery ($case + '-discover')
                if (-not [StringComparer]::OrdinalIgnoreCase.Equals([IO.File]::ReadAllText($discovery), $honey)) { throw 'Legacy discovery did not return the exact trusted Honey directory' }
            }
            $externalBefore = $null
            if ($case -cin @('external-service', 'unowned-directory')) { $externalBefore = Get-LegacyServiceSnapshot }
            Invoke-RealLegacyCleanup $honey 'stop' $evidence ($case + '-stop')
            $ownership = Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json
            if ($case -ceq 'owned-service-foreign-guid') {
                if (-not $ownership.owned_before_install -or -not $ownership.legacy_service_owned_before_install -or @($ownership.legacy_registrations).Count -ne 0) { throw 'GUID-free Honey service ownership was not captured' }
            }
            if ($case -cin @('owned-service-foreign-guid', 'owned-legacy-guid')) {
                $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
                if (-not $service -or $service.State -cne 'Stopped' -or [IO.File]::ReadAllText($counter) -cne '1' -or -not $serviceProcess.WaitForExit(5000)) { throw 'The owned legacy service did not stop exactly once' }
            } else {
                if ($ownership.legacy_service_owned_before_install) { throw 'An external SCM service was incorrectly adopted' }
                if (($externalBefore | ConvertTo-Json -Depth 30 -Compress) -cne ((Get-LegacyServiceSnapshot) | ConvertTo-Json -Depth 30 -Compress)) { throw 'Stop changed the external service' }
            }
            if (-not $ownedGuid) { Assert-LegacyRegistryUnchanged $before ($case + '-after-stop') }
            Invoke-RealLegacyCleanup $honey 'finalize' $evidence ($case + '-finalize') ($case -ceq 'unowned-directory')
            if ($case -cin @('owned-service-foreign-guid', 'owned-legacy-guid')) {
                if (Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'") { throw 'Finalize did not remove the owned legacy SCM registration' }
                if ([IO.File]::ReadAllText($counter) -cne '1') { throw 'Finalize sent an extra STOP to the owned service' }
            } else {
                $after = Get-LegacyServiceSnapshot
                Save-FwArmEvidence (Join-Path $EvidenceDirectory ($case + '-service-after.json')) $after
                if (($externalBefore | ConvertTo-Json -Depth 30 -Compress) -cne ($after | ConvertTo-Json -Depth 30 -Compress)) { throw 'Finalize changed the external service' }
            }
            if ($ownedGuid) {
                Assert-LegacyAutoLaunchMigrated $honey $enabledApproval ($case + '-enabled-migration')
                if ($null -ne (Read-LegacyRegistryTree $registryPath)) { throw 'Finalize left the trusted owned legacy GUID' }
                foreach ($scheme in @('clash', 'clashmeta')) {
                    if ($null -ne (Read-LegacyRegistryTree ('Software\Classes\' + $scheme) 'CurrentUser')) { throw 'Finalize left an owned old Honey URI registration' }
                }
                Assert-LegacyProtocolUnchanged 'flclash' $foreignProtocolBefore ($case + '-after-finalize')
                Assert-LegacyProtocolUnchanged 'fengwo' $currentProtocolBefore ($case + '-after-finalize')
                Write-LegacyProtocol 'clash' (Join-Path $honey 'FengWo.exe')
                Write-LegacyProtocol 'clashmeta' (Join-Path $honey 'FlClash.exe')
                Invoke-RealLegacyCleanup $honey 'uninstall' $evidence ($case + '-uninstall-uri')
                foreach ($scheme in @('clash', 'clashmeta', 'fengwo')) {
                    if ($null -ne (Read-LegacyRegistryTree ('Software\Classes\' + $scheme) 'CurrentUser')) { throw 'Uninstall left a proven Honey URI registration' }
                }
                Assert-LegacyProtocolUnchanged 'flclash' $foreignProtocolBefore ($case + '-after-uninstall')
                foreach ($entry in @(Get-LegacyAutoLaunchSnapshot)) {
                    if ($null -ne $entry.state) { throw 'Uninstall left a proven Honey auto-launch value' }
                }
                Write-LegacyAutoLaunch 'FlClash' (Join-Path $honey 'FlClash.exe') $disabledApproval
                Invoke-RealLegacyCleanup $honey 'finalize' $evidence ($case + '-disabled-migration')
                Assert-LegacyAutoLaunchMigrated $honey $disabledApproval ($case + '-disabled-migration')
                Copy-Item -LiteralPath $fixtureExecutable -Destination (Join-Path $foreign 'FengWo.exe')
                Write-LegacyAutoLaunch 'FengWo' (Join-Path $foreign 'FengWo.exe') $disabledApproval
                Write-LegacyAutoLaunch 'FlClash' (Join-Path $honey 'FlClash.exe') $enabledApproval
                $foreignTargetBefore = Get-LegacyAutoLaunchSnapshot
                Invoke-RealLegacyCleanup $honey 'finalize' $evidence ($case + '-foreign-autolaunch-target')
                Assert-LegacyAutoLaunchUnchanged $foreignTargetBefore ($case + '-foreign-autolaunch-target')
                Invoke-RealLegacyCleanup $honey 'uninstall' $evidence ($case + '-foreign-autolaunch-target-uninstall')
                Assert-LegacyAutoLaunchUnchanged $foreignTargetBefore ($case + '-foreign-autolaunch-target-uninstall') 'FengWo'
                foreach ($entry in @(Get-LegacyAutoLaunchSnapshot)) { if ($entry.name -ceq 'FlClash' -and $null -ne $entry.state) { throw 'Uninstall left the owned old auto-launch value beside a foreign new target' } }
                Remove-LegacyAutoLaunchFixtures
                Write-LegacyAutoLaunch 'FlClash' (Join-Path $foreign 'FlClash.exe') $enabledApproval
                Write-LegacyAutoLaunch 'FengWo' (Join-Path $honey 'FengWo.exe') $disabledApproval
                $foreignOriginalBefore = Get-LegacyAutoLaunchSnapshot
                Invoke-RealLegacyCleanup $honey 'finalize' $evidence ($case + '-foreign-original-autolaunch')
                Assert-LegacyAutoLaunchUnchanged $foreignOriginalBefore ($case + '-foreign-original-autolaunch')
                Invoke-RealLegacyCleanup $honey 'uninstall' $evidence ($case + '-foreign-original-autolaunch-uninstall')
                Assert-LegacyAutoLaunchUnchanged $foreignOriginalBefore ($case + '-foreign-original-autolaunch-uninstall') 'FlClash'
                foreach ($entry in @(Get-LegacyAutoLaunchSnapshot)) { if ($entry.name -ceq 'FengWo' -and $null -ne $entry.state) { throw 'Uninstall left the owned new auto-launch value beside the original FlClash target' } }
                Remove-LegacyAutoLaunchFixtures
                Copy-Item -LiteralPath $fixtureExecutable -Destination (Join-Path $honey 'FlClash.exe') -Force
                Write-LegacyProtocol 'clashmeta' (Join-Path $honey 'FlClash.exe')
                $wrongBrandBefore = Read-LegacyRegistryTree 'Software\Classes\clashmeta' 'CurrentUser'
                Write-LegacyAutoLaunch 'FlClash' (Join-Path $honey 'FlClash.exe') $disabledApproval
                $wrongAutoLaunchBefore = Get-LegacyAutoLaunchSnapshot
                Invoke-RealLegacyCleanup $honey 'finalize' $evidence ($case + '-foreign-brand-finalize') $true
                Assert-LegacyProtocolUnchanged 'clashmeta' $wrongBrandBefore ($case + '-foreign-brand')
                Assert-LegacyProtocolUnchanged 'flclash' $foreignProtocolBefore ($case + '-foreign-brand')
                Assert-LegacyAutoLaunchUnchanged $wrongAutoLaunchBefore ($case + '-foreign-brand')
                Invoke-RealLegacyCleanup $honey 'uninstall' $evidence ($case + '-foreign-brand-uninstall') $true
                Assert-LegacyAutoLaunchUnchanged $wrongAutoLaunchBefore ($case + '-foreign-brand-uninstall')
            } else { Assert-LegacyRegistryUnchanged $before ($case + '-after-finalize') }
            $checks.Add([ordered]@{ name = $case; passed = $true; powershell = $version; stopped = ($case -cin @('owned-service-foreign-guid', 'owned-legacy-guid')); foreign_guid_preserved = (-not $ownedGuid); owned_guid_removed = $ownedGuid; owned_old_uri_removed = $ownedGuid; foreign_uri_preserved = $ownedGuid; same_path_foreign_brand_uri_preserved = $ownedGuid; owned_uri_uninstall_verified = $ownedGuid; owned_enabled_auto_launch_migrated = $ownedGuid; owned_disabled_auto_launch_migrated = $ownedGuid; foreign_auto_launch_target_preserved = $ownedGuid; foreign_original_auto_launch_preserved = $ownedGuid; same_path_foreign_brand_auto_launch_preserved = $ownedGuid; owned_auto_launch_uninstall_verified = $ownedGuid; native_fixture = $true })
        } finally { Remove-LegacyCase $case }
    }
} catch { $failure = $_.Exception.Message } finally {
    try { if ($created) { Remove-LegacyCase 'final' } } catch { $cleanupErrors.Add($_.Exception.Message) }
    if ($created) { try { Remove-Item -LiteralPath $root -Recurse -Force } catch { $cleanupErrors.Add($_.Exception.Message) } }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'legacy-cleanup-verification.json') ([ordered]@{ passed = (-not $failure -and $cleanupErrors.Count -eq 0 -and $checks.Count -eq 4); failure = $failure; cleanup_failures = @($cleanupErrors.ToArray()); checks = @($checks.ToArray()); environment = $environment; product_cleanup_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant(); fixture_source_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'flclash_fixture/flclash_fixture.cpp') -Algorithm SHA256).Hash.ToLowerInvariant(); synthetic_files_only = $true; application_started = $false; system_proxy_or_tun_started = $false })
}
if ($failure) { throw $failure }
if ($cleanupErrors.Count) { throw ($cleanupErrors -join '; ') }
if ($checks.Count -ne 4) { throw 'Not all four real PowerShell 5.1 cleanup cases were verified' }
