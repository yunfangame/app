param(
    [string]$InstallDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('discover', 'stop', 'finalize', 'uninstall')][string]$Operation,
    [string]$OwnershipEvidencePath,
    [string]$DiscoveryOutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-FengWoInstallPath {
    param([string]$Path)
    if ($Path -notmatch '^[A-Za-z]:[\\/]') { throw 'A local absolute installation path is required' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if ($full.Length -le 3) { throw 'A dedicated installation directory is required' }
    return $full
}

function Test-FengWoSamePath {
    param([string]$First, [string]$Second)
    try { return [StringComparer]::OrdinalIgnoreCase.Equals((ConvertTo-FengWoInstallPath $First), (ConvertTo-FengWoInstallPath $Second)) } catch { return $false }
}

function Assert-FengWoPlainPath {
    param([string]$Path)
    $entry = [IO.DirectoryInfo]::new((ConvertTo-FengWoInstallPath $Path))
    while ($entry) {
        if ($entry.Exists -and ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Redirected installation paths are not supported' }
        $entry = $entry.Parent
    }
}

function Test-FengWoApplicationFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $false }
    if ([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) { return $false }
    $metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    return $metadata.ProductName -ceq '蜂窝加速器' -and $metadata.CompanyName -cin @('FengWo', 'com.follow')
}

function Get-FengWoInstallIdentity {
    param([string]$Directory)
    Assert-FengWoPlainPath $Directory
    $application = Join-Path $Directory 'FengWo.exe'
    $legacyApplication = Join-Path $Directory 'FlClash.exe'
    $owned = Test-FengWoApplicationFile $application
    $legacyOwned = Test-FengWoApplicationFile $legacyApplication
    $foreign = ([IO.File]::Exists($application) -and -not $owned) -or ([IO.File]::Exists($legacyApplication) -and -not $legacyOwned)
    return [ordered]@{ owned = ($owned -or $legacyOwned); legacy_application = $legacyOwned; foreign_application = $foreign }
}

function Test-FengWoLegacyDisplayName {
    param([string]$Name)
    return $Name -cmatch '^蜂窝加速器(?:\s+(?:(?:version|版本)\s*)?v?\d+(?:\.\d+){1,3}(?:\+\d+)?)?\s*$'
}

function Get-FengWoLegacyRegistrations {
    param([string]$Directory)
    $records = [Collections.Generic.List[object]]::new()
    foreach ($hive in @('LocalMachine', 'CurrentUser')) {
        foreach ($view in @('Registry64', 'Registry32')) {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hive, [Microsoft.Win32.RegistryView]::$view)
            try {
                $key = $base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\728B3532-C74B-4870-9068-BE70FE12A3E6_is1')
                if (-not $key) { continue }
                try {
                    $displayName = [string]$key.GetValue('DisplayName')
                    $location = [string]$key.GetValue('InstallLocation')
                    if (-not $location) { $location = [string]$key.GetValue('Inno Setup: App Path') }
                    if ((Test-FengWoLegacyDisplayName $displayName) -and (-not $Directory -or (Test-FengWoSamePath $location $Directory))) {
                        $records.Add([ordered]@{ hive = $hive; view = $view; display_name = $displayName; location = $location })
                    }
                } finally { $key.Dispose() }
            } finally { $base.Dispose() }
        }
    }
    return $records.ToArray()
}

function Find-FengWoLegacyInstallDirectory {
    foreach ($record in @(Get-FengWoLegacyRegistrations)) {
        try {
            $directoryPath = ConvertTo-FengWoInstallPath $record.location
            $identity = Get-FengWoInstallIdentity $directoryPath
            if ($identity.owned -and -not $identity.foreign_application) { return $directoryPath }
        } catch { continue }
    }
    return $null
}

function Get-FengWoServiceExecutable {
    param([string]$Command)
    $value = $Command.Trim()
    if ($value.StartsWith('"')) {
        if ($value -notmatch '^"([^"\r\n]+)"$') { return $null }
        $value = $Matches[1]
    } elseif ($value -notmatch '(?i)\.exe$' -or $value.Contains('"')) { return $null }
    try { return ConvertTo-FengWoInstallPath $value } catch { return $null }
}

function Get-FengWoOwnedService {
    param([string]$Name, [string]$Directory, [bool]$LegacyAllowed)
    if ($Name -cnotin @('FengWoHelperService', 'FlClashHelperService')) { throw 'Unexpected service identity' }
    if ($Name -ceq 'FlClashHelperService' -and -not $LegacyAllowed) { return $null }
    $service = Get-CimInstance Win32_Service -Filter ("Name='" + $Name + "'")
    if (-not $service) { return $null }
    $expected = Join-Path $Directory ($Name + '.exe')
    $actual = Get-FengWoServiceExecutable ([string]$service.PathName)
    if (-not $actual -or -not (Test-FengWoSamePath $actual $expected)) { return $null }
    return $service
}

function Stop-FengWoOwnedService {
    param([string]$Name, [string]$Directory, [bool]$LegacyAllowed)
    $service = Get-FengWoOwnedService $Name $Directory $LegacyAllowed
    if (-not $service) { return }
    $controller = [ServiceProcess.ServiceController]::new($Name)
    try {
        $controller.Refresh()
        if ($controller.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped) {
            if ($controller.Status -ne [ServiceProcess.ServiceControllerStatus]::StopPending) { $controller.Stop() }
            $controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(15))
        }
    } finally { $controller.Dispose() }
}

function Remove-FengWoOwnedService {
    param([string]$Name, [string]$Directory, [bool]$LegacyAllowed)
    Stop-FengWoOwnedService $Name $Directory $LegacyAllowed
    $service = Get-FengWoOwnedService $Name $Directory $LegacyAllowed
    if (-not $service) { return }
    $result = Invoke-CimMethod -InputObject $service -MethodName Delete
    if ($result.ReturnValue -ne 0) { throw ('Owned service removal failed: ' + $Name + ' (' + $result.ReturnValue + ')') }
}

function Stop-FengWoOwnedProcesses {
    param([string]$Directory, [string[]]$Names)
    foreach ($name in $Names) {
        $expected = Join-Path $Directory ($name + '.exe')
        foreach ($candidate in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            try {
                try { $actual = $candidate.MainModule.FileName } catch { continue }
                if (-not (Test-FengWoSamePath $actual $expected)) { continue }
                $processHandle = $candidate.Handle
                if ($candidate.HasExited) { continue }
                if ($name -cin @('FengWo', 'FlClash') -and $candidate.CloseMainWindow()) { [void]$candidate.WaitForExit(3000) }
                if (-not $candidate.HasExited) { $candidate.Kill() }
                if (-not $candidate.WaitForExit(5000)) { throw ('Owned process did not exit: ' + $name) }
            } finally { $candidate.Dispose() }
        }
    }
}

function Remove-FengWoLegacyRegistrations {
    param([string]$Directory, [object[]]$Records)
    foreach ($record in $Records) {
        if ($record.hive -cnotin @('LocalMachine', 'CurrentUser') -or $record.view -cnotin @('Registry64', 'Registry32')) { throw 'Invalid legacy ownership evidence' }
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$($record.hive), [Microsoft.Win32.RegistryView]::$($record.view))
        try {
            $name = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\728B3532-C74B-4870-9068-BE70FE12A3E6_is1'
            $key = $base.OpenSubKey($name)
            if (-not $key) { continue }
            try {
                $displayName = [string]$key.GetValue('DisplayName')
                $location = [string]$key.GetValue('InstallLocation')
                if (-not $location) { $location = [string]$key.GetValue('Inno Setup: App Path') }
                $owned = $displayName -ceq $record.display_name -and (Test-FengWoLegacyDisplayName $displayName) -and (Test-FengWoSamePath $location $Directory) -and (Test-FengWoSamePath $location $record.location)
            } finally { $key.Dispose() }
            if ($owned) { $base.DeleteSubKeyTree($name, $false) }
        } finally { $base.Dispose() }
    }
}

function Test-FengWoProtocolCommandOwned {
    param([string]$Command, [string]$Directory, [bool]$AllowLegacyApplication)
    if ($Command -notmatch '^"([^"\r\n]+)"(?:\s|$)') { return $false }
    $executable = $Matches[1]
    $names = @('FengWo.exe')
    if ($AllowLegacyApplication) { $names += 'FlClash.exe' }
    foreach ($name in $names) {
        $expected = Join-Path $Directory $name
        if ((Test-FengWoSamePath $executable $expected) -and (Test-FengWoApplicationFile $expected)) { return $true }
    }
    return $false
}

function Remove-FengWoOwnedProtocols {
    param([string]$Directory, [string[]]$Schemes, [bool]$AllowLegacyApplication)
    foreach ($scheme in $Schemes) {
        if ($scheme -cnotin @('fengwo', 'clash', 'clashmeta', 'flclash')) { throw 'Unexpected protocol identity' }
    }
    foreach ($view in @('Registry64', 'Registry32')) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::$view)
        try {
            foreach ($scheme in $Schemes) {
                $name = 'Software\Classes\' + $scheme
                $key = $base.OpenSubKey($name + '\shell\open\command')
                if (-not $key) { continue }
                try { $command = [string]$key.GetValue('') } finally { $key.Dispose() }
                if (Test-FengWoProtocolCommandOwned $command $Directory $AllowLegacyApplication) { $base.DeleteSubKeyTree($name, $false) }
            }
        } finally { $base.Dispose() }
    }
}

function Remove-FengWoOwnedProtocol {
    param([string]$Directory)
    Remove-FengWoOwnedProtocols $Directory @('fengwo') $false
}

function Remove-FengWoOwnedLegacyProtocols {
    param([string]$Directory)
    Remove-FengWoOwnedProtocols $Directory @('clash', 'clashmeta', 'flclash') $true
}

function Invoke-FengWoInstallCleanup {
    param([string]$Directory, [string]$Action, [string]$EvidencePath)
    $directoryPath = ConvertTo-FengWoInstallPath $Directory
    $identity = Get-FengWoInstallIdentity $directoryPath
    if ($identity.foreign_application) { throw 'The installation directory contains another application; choose a separate FengWo directory' }
    $records = @()
    if ($identity.owned) { $records = @(Get-FengWoLegacyRegistrations $directoryPath) }
    if ($Action -ceq 'stop') {
        if (-not $EvidencePath) { throw 'Installation ownership evidence path is required' }
        $legacyServiceOwned = $false
        if ($identity.owned) { $legacyServiceOwned = [bool](Get-FengWoOwnedService 'FlClashHelperService' $directoryPath $true) }
        $evidence = [ordered]@{ directory = $directoryPath; owned_before_install = $identity.owned; legacy_application = $identity.legacy_application; legacy_service_owned_before_install = $legacyServiceOwned; legacy_registrations = $records }
        [IO.File]::WriteAllText($EvidencePath, ($evidence | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        if (-not $identity.owned) { return }
        $apps = @('FengWo')
        if ($identity.legacy_application) { $apps += 'FlClash' }
        Stop-FengWoOwnedProcesses $directoryPath $apps
        Stop-FengWoOwnedService 'FengWoHelperService' $directoryPath $false
        Stop-FengWoOwnedService 'FlClashHelperService' $directoryPath $legacyServiceOwned
        $components = @('FengWoCore', 'FengWoHelperService')
        $components += @('FlClashCore', 'FlClashHelperService')
        Stop-FengWoOwnedProcesses $directoryPath $components
        return
    }
    if (-not $identity.owned) { throw 'The installed FengWo identity could not be verified' }
    if ($Action -ceq 'finalize') {
        if (-not $EvidencePath -or -not [IO.File]::Exists($EvidencePath)) { throw 'Installation ownership evidence is missing' }
        $evidence = [IO.File]::ReadAllText($EvidencePath) | ConvertFrom-Json
        if (-not (Test-FengWoSamePath $evidence.directory $directoryPath)) { throw 'Installation ownership evidence belongs to another path' }
        if ($evidence.owned_before_install -and $evidence.legacy_service_owned_before_install) {
            Remove-FengWoOwnedService 'FlClashHelperService' $directoryPath $true
        }
        if ($evidence.owned_before_install) { Remove-FengWoOwnedLegacyProtocols $directoryPath }
        if ($evidence.owned_before_install -and @($evidence.legacy_registrations).Count -gt 0) {
            Remove-FengWoLegacyRegistrations $directoryPath @($evidence.legacy_registrations)
        }
        return
    }
    if ($Action -ceq 'uninstall') {
        Stop-FengWoOwnedProcesses $directoryPath @('FengWo')
        Remove-FengWoOwnedService 'FengWoHelperService' $directoryPath $false
        Stop-FengWoOwnedProcesses $directoryPath @('FengWoCore', 'FengWoHelperService')
        Remove-FengWoOwnedProtocol $directoryPath
        Remove-FengWoOwnedLegacyProtocols $directoryPath
        return
    }
    throw 'Unsupported installation cleanup operation'
}

if ($MyInvocation.InvocationName -ne '.') {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Installation cleanup requires Windows' }
    if ($Operation -ceq 'discover') {
        if (-not $DiscoveryOutputPath) { throw 'Installation discovery output path is required' }
        $discoveredPath = Find-FengWoLegacyInstallDirectory
        [IO.File]::WriteAllText($DiscoveryOutputPath, [string]$discoveredPath, [Text.UTF8Encoding]::new($false))
    } else {
        Invoke-FengWoInstallCleanup $InstallDirectory $Operation $OwnershipEvidencePath
    }
}
