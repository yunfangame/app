param(
    [ValidateRange(1, 30)]
    [int]$Days = 1,
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This collector requires Windows.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = [Environment]::GetFolderPath('Desktop')
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = [IO.Path]::GetTempPath()
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 6)
$folder = Join-Path $OutputDirectory "FengWo-Windows-Diagnostics-$stamp-$suffix"
$null = New-Item -ItemType Directory -Path $folder
$since = (Get-Date).AddDays(-$Days)
$collectionErrors = [Collections.Generic.List[string]]::new()

function Invoke-CollectionStep {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        Write-Host "Collected: $Name"
    } catch {
        $collectionErrors.Add("${Name}: $($_.Exception.Message)")
        Write-Host "Unavailable: $Name"
    }
}

function Write-Events {
    param([string]$LogName, [int[]]$Ids = @(), [string]$Prefix, [switch]$ClientOnly, [int]$Limit = 500)
    $filter = @{ LogName = $LogName; StartTime = $since }
    if ($Ids.Count -gt 0) { $filter.Id = $Ids }
    $queryArguments = @{ FilterHashtable = $filter; ErrorAction = 'Stop' }
    if ($Limit -gt 0) { $queryArguments.MaxEvents = $Limit }
    try {
        $events = @(Get-WinEvent @queryArguments)
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
            throw
        }
        $events = @()
    }
    if ($ClientOnly) {
        $events = @($events | Where-Object {
            $_.ToXml() -match '(?i)FlClash|FengWo|fengwoacc'
        })
    }
    $xml = @('<Events>') + @($events | ForEach-Object { $_.ToXml() }) + @('</Events>')
    $xml | Set-Content -LiteralPath (Join-Path $folder "$Prefix.xml") -Encoding UTF8
    if ($events.Count -eq 0) {
        'No matching events in the selected time range.' |
            Set-Content -LiteralPath (Join-Path $folder "$Prefix.txt") -Encoding UTF8
    } else {
        $events | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
            Format-List | Out-String -Width 240 |
            Set-Content -LiteralPath (Join-Path $folder "$Prefix.txt") -Encoding UTF8
    }
}

Invoke-CollectionStep 'Windows version' {
    $version = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [ordered]@{
        CollectorVersion = 2
        CollectedAt = (Get-Date).ToString('o')
        TimeZone = [TimeZoneInfo]::Local.Id
        Since = $since.ToString('o')
        ProductName = $version.ProductName
        DisplayVersion = $version.DisplayVersion
        CurrentBuild = $version.CurrentBuild
        UBR = $version.UBR
        Architecture = $env:PROCESSOR_ARCHITECTURE
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'windows-version.json') -Encoding UTF8
}

Invoke-CollectionStep 'Shutdown and system errors' {
    Write-Events -LogName 'System' -Ids @(41, 1001, 1074, 6006, 6008, 18, 19, 46) -Prefix 'system-events'
}

Invoke-CollectionStep 'Client crashes and hangs' {
    Write-Events -LogName 'Application' -Ids @(1000, 1001, 1002) -Prefix 'client-events' -ClientOnly
}

Invoke-CollectionStep 'Complete system event timeline' {
    Write-Events -LogName 'System' -Prefix 'system-full' -Limit 0
}

Invoke-CollectionStep 'Application and service failures' {
    Write-Events -LogName 'Application' -Ids @(1000, 1001, 1002, 1026) -Prefix 'application-failures' -Limit 0
}

Invoke-CollectionStep 'System event log configuration' {
    Get-WinEvent -ListLog 'System' |
        Select-Object IsEnabled, LogMode, RecordCount, MaximumSizeInBytes, LogFilePath, IsLogFull |
        ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $folder 'event-log-settings.json') -Encoding UTF8
}

Invoke-CollectionStep 'Crash dump settings' {
    Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' |
        Select-Object CrashDumpEnabled, AutoReboot, LogEvent, DumpFile, MinidumpDir, DedicatedDumpFile, AlwaysKeepMemoryDump |
        ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $folder 'dump-settings.json') -Encoding UTF8
}

Invoke-CollectionStep 'Page file state' {
    $pageFiles = @(Get-CimInstance -ClassName Win32_PageFileUsage -OperationTimeoutSec 15 |
        Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)
    ConvertTo-Json -InputObject $pageFiles -Depth 3 |
        Set-Content -LiteralPath (Join-Path $folder 'page-files.json') -Encoding UTF8
}

Invoke-CollectionStep 'Boot time' {
    Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 15 |
        Select-Object Caption, Version, LastBootUpTime |
        ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $folder 'boot-time.json') -Encoding UTF8
}

Invoke-CollectionStep 'Loaded system drivers' {
    $systemDrivers = @(Get-CimInstance -ClassName Win32_SystemDriver -Filter "State='Running'" -OperationTimeoutSec 15 |
        Select-Object Name, DisplayName, State, StartMode, ServiceType, PathName)
    ConvertTo-Json -InputObject $systemDrivers -Depth 3 |
        Set-Content -LiteralPath (Join-Path $folder 'system-drivers.json') -Encoding UTF8
}

Invoke-CollectionStep 'Network drivers' {
    $drivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -Filter "DeviceClass='NET'" -OperationTimeoutSec 15 |
        Select-Object DeviceName, Manufacturer, DriverVersion, DriverDate, InfName, IsSigned)
    ConvertTo-Json -InputObject $drivers -Depth 3 |
        Set-Content -LiteralPath (Join-Path $folder 'network-drivers.json') -Encoding UTF8
}

Invoke-CollectionStep 'Crash dump file list' {
    $dumpFiles = @()
    $miniDumpDirectory = Join-Path $env:SystemRoot 'Minidump'
    if (Test-Path -LiteralPath $miniDumpDirectory) {
        $dumpFiles += @(Get-ChildItem -LiteralPath $miniDumpDirectory -Filter '*.dmp' -File |
            Where-Object { $_.LastWriteTime -ge $since } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 10)
    }
    $memoryDump = Join-Path $env:SystemRoot 'MEMORY.DMP'
    if (Test-Path -LiteralPath $memoryDump) {
        $dumpFiles += Get-Item -LiteralPath $memoryDump
    }
    $dumpList = @($dumpFiles | Select-Object Name, Length, LastWriteTime)
    ConvertTo-Json -InputObject $dumpList -Depth 3 |
        Set-Content -LiteralPath (Join-Path $folder 'dump-files.json') -Encoding UTF8
}

if ($collectionErrors.Count -gt 0) {
    $collectionErrors | Set-Content -LiteralPath (Join-Path $folder 'collection-errors.txt') -Encoding UTF8
}

$archive = "$folder.zip"
Compress-Archive -LiteralPath $folder -DestinationPath $archive -CompressionLevel Optimal
Write-Host ''
Write-Host 'Finished. Send this ZIP file to support:'
Write-Host $archive
Write-Host 'No proxy, driver, network or power settings were changed.'
