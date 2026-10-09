function Get-FwDiscoveryProperty {
    param($Value, [string]$Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) { return $Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-FwLocalFullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1f]' -or $Path.StartsWith('\\') -or $Path.StartsWith('//')) { return $null }
    if ([IO.Path]::DirectorySeparatorChar -eq '\' -and $Path -notmatch '^[A-Za-z]:[\\/]') { return $null }
    try {
        if (-not [IO.Path]::IsPathRooted($Path)) { return $null }
        return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    } catch { return $null }
}

function Test-FwLocalEntry {
    param([string]$Path, [bool]$Directory = $false)
    $full = Get-FwLocalFullPath $Path
    if (-not $full) { return $false }
    try {
        $attributes = [IO.File]::GetAttributes($full)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        return ((($attributes -band [IO.FileAttributes]::Directory) -ne 0) -eq $Directory)
    } catch { return $false }
}

function Test-FwContainedDirectory {
    param([string]$Root, [string]$Path)
    $base = Get-FwLocalFullPath $Root
    $current = Get-FwLocalFullPath $Path
    if (-not $base -or -not $current) { return $false }
    if (-not $current.Equals($base, [StringComparison]::OrdinalIgnoreCase) -and -not $current.StartsWith(($base + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    while ($current) {
        if (-not (Test-FwLocalEntry $current $true)) { return $false }
        if ($current.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $false
}

function Get-FwBoundedFile {
    param([string]$Root, [string]$RelativePath, [long]$MaxBytes = 16777216)
    $base = Get-FwLocalFullPath $Root
    if (-not $base -or -not (Test-FwLocalEntry $base $true)) { return $null }
    try {
        $full = [IO.Path]::GetFullPath((Join-Path $base $RelativePath))
        $prefix = $base + [IO.Path]::DirectorySeparatorChar
        if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $null }
        if (-not (Test-FwContainedDirectory $base ([IO.Path]::GetDirectoryName($full)))) { return $null }
        if (-not (Test-FwLocalEntry $full)) { return $null }
        $file = New-Object IO.FileInfo($full)
        if ($file.Length -gt $MaxBytes) { return $null }
        return $file
    } catch { return $null }
}

function Read-FwBoundedText {
    param([IO.FileInfo]$File, [long]$MaxBytes = 16777216)
    if ($null -eq $File) { return $null }
    $stream = $null
    try {
        if (-not (Test-FwLocalEntry $File.FullName)) { return $null }
        $File.Refresh()
        $beforeLength = $File.Length
        $beforeWrite = $File.LastWriteTimeUtc.Ticks
        $stream = New-Object IO.FileStream($File.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if ($stream.Length -gt $MaxBytes) { return $null }
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { return $null }
            $offset += $read
        }
        $File.Refresh()
        if ($File.Length -ne $beforeLength -or $File.LastWriteTimeUtc.Ticks -ne $beforeWrite -or $stream.Length -ne $beforeLength) { return $null }
        $encoding = New-Object Text.UTF8Encoding($false, $true)
        return $encoding.GetString($bytes).TrimStart([char]0xfeff)
    } catch { return $null }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Get-FwRunningClientRecords {
    foreach ($process in @(Get-Process -Name FengWo, fengwoacc -ErrorAction SilentlyContinue | Select-Object -First 128)) {
        try {
            if ($process.Path) { [pscustomobject]@{ Path=$process.Path; ProcessId=$process.Id; Source='process' } }
        } catch {}
    }
}

function Get-FwRegistryClientRecords {
    foreach ($base in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path -LiteralPath $base -ErrorAction SilentlyContinue)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Select-Object -First 1024)) {
            $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $display = [string](Get-FwDiscoveryProperty $entry 'DisplayName')
            if ($display -notmatch 'FengWo|fengwoacc|蜂窝' -or $display -match 'FlClash') { continue }
            $location = [string](Get-FwDiscoveryProperty $entry 'InstallLocation')
            if ($location) {
                foreach ($name in @('FengWo.exe', 'fengwoacc.exe')) { [pscustomobject]@{ Path=(Join-Path $location $name); ProcessId=0; Source='registry' } }
            }
            $icon = ([string](Get-FwDiscoveryProperty $entry 'DisplayIcon') -replace ',\s*-?\d+\s*$', '').Trim().Trim('"')
            if ($icon) { [pscustomobject]@{ Path=$icon; ProcessId=0; Source='registry' } }
        }
    }
}

function Get-FwShortcutClientRecords {
    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop
        $visited = @{}
        $queue = New-Object 'System.Collections.Generic.Queue[object]'
        foreach ($name in @('Desktop', 'CommonDesktopDirectory', 'Programs', 'CommonPrograms')) {
            $base = [Environment]::GetFolderPath($name)
            if ($base) { $queue.Enqueue([pscustomobject]@{ Path=$base; Depth=0 }) }
        }
        $scanned = 0
        while ($queue.Count -gt 0 -and $visited.Count -lt 256 -and $scanned -lt 4096) {
            $directory = $queue.Dequeue()
            $full = Get-FwLocalFullPath $directory.Path
            if (-not $full -or $visited.ContainsKey($full) -or -not (Test-FwLocalEntry $full $true)) { continue }
            $visited[$full] = $true
            foreach ($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue | Select-Object -First (4096 - $scanned))) {
                $scanned++
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($item.PSIsContainer) {
                    if ($directory.Depth -lt 3) { $queue.Enqueue([pscustomobject]@{ Path=$item.FullName; Depth=($directory.Depth + 1) }) }
                    continue
                }
                if ($item.Extension -ne '.lnk' -or $item.Name -notmatch 'FengWo|fengwoacc|蜂窝' -or $item.Name -match 'FlClash') { continue }
                $shortcut = $null
                try {
                    $shortcut = $shell.CreateShortcut($item.FullName)
                    if ($shortcut.TargetPath) { [pscustomobject]@{ Path=$shortcut.TargetPath; ProcessId=0; Source='shortcut' } }
                } catch {}
                finally { if ($null -ne $shortcut -and [Runtime.InteropServices.Marshal]::IsComObject($shortcut)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) } }
            }
        }
    } catch {}
    finally { if ($null -ne $shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } }
}

function Get-FwKnownClientRecords {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        foreach ($relative in @('FengWo\FengWo.exe', 'FengWo\fengwoacc.exe', 'Programs\FengWo\FengWo.exe', 'Programs\FengWo\fengwoacc.exe')) {
            [pscustomobject]@{ Path=(Join-Path $base $relative); ProcessId=0; Source='known_location' }
        }
    }
}

function Get-FwClientVersion {
    param([string]$Path)
    try { return [Diagnostics.FileVersionInfo]::GetVersionInfo($Path) } catch { return $null }
}

function ConvertTo-FwDirectoryComponent {
    param([string]$Value)
    if (-not $Value) { return '' }
    $result = ($Value -replace '[<>:"/\\|?*]', '_').TrimEnd().TrimEnd('.')
    if ($result.Length -gt 255) { $result = $result.Substring(0, 255) }
    if ($result -eq '.' -or $result -eq '..' -or $result -match '[\x00-\x1f]') { return '' }
    return $result
}

function Get-FwClientDataDirectories {
    param([string]$CompanyName, [string]$ProductName, [string]$ExePath)
    $company = ConvertTo-FwDirectoryComponent $CompanyName
    $product = ConvertTo-FwDirectoryComponent $ProductName
    if (-not $product) { $product = [IO.Path]::GetFileNameWithoutExtension($ExePath) }
    $seen = @{}
    foreach ($base in @($env:APPDATA, [Environment]::GetFolderPath('ApplicationData'), $env:LOCALAPPDATA, [Environment]::GetFolderPath('LocalApplicationData'))) {
        if (-not (Get-FwLocalFullPath $base)) { continue }
        $relative = $product
        if ($company) { $relative = Join-Path $company $product }
        foreach ($child in @($relative, (Join-Path 'com.follow' '蜂窝加速器'))) {
            $path = Get-FwLocalFullPath (Join-Path $base $child)
            if ($path -and -not $seen.ContainsKey($path)) { $seen[$path]=$true; $path }
        }
    }
}

function Find-FengWoClients {
    $clients = @{}
    $records = @(Get-FwRunningClientRecords) + @(Get-FwRegistryClientRecords) + @(Get-FwShortcutClientRecords) + @(Get-FwKnownClientRecords)
    foreach ($record in $records) {
        $path = Get-FwLocalFullPath ([string](Get-FwDiscoveryProperty $record 'Path'))
        if (-not $path -or [IO.Path]::GetFileName($path) -notmatch '^(FengWo|fengwoacc)\.exe$' -or -not (Test-FwLocalEntry $path)) { continue }
        if (-not $clients.ContainsKey($path)) {
            $version = Get-FwClientVersion $path
            $product = [string](Get-FwDiscoveryProperty $version 'ProductName')
            $original = [string](Get-FwDiscoveryProperty $version 'OriginalFilename')
            if ($product -match 'FlClash' -or $original -match '^FlClash\.exe$') { continue }
            if ($product -and $product -notmatch 'FengWo|fengwoacc|蜂窝') { continue }
            $company = [string](Get-FwDiscoveryProperty $version 'CompanyName')
            $clients[$path] = [pscustomobject]@{
                ExePath=$path; Running=$false; ProcessIds=@(); DiscoverySources=@()
                ProductName=$product; CompanyName=$company
                FileVersion=[string](Get-FwDiscoveryProperty $version 'FileVersion')
                BrandVerified=($product -match 'FengWo|fengwoacc|蜂窝')
                DataDirectories=@(Get-FwClientDataDirectories $company $product $path)
            }
        }
        $client = $clients[$path]
        $processId = 0
        if ([int]::TryParse([string](Get-FwDiscoveryProperty $record 'ProcessId'), [ref]$processId) -and $processId -gt 0) {
            $client.Running = $true
            if ($client.ProcessIds -notcontains $processId) { $client.ProcessIds += $processId }
        }
        $source = [string](Get-FwDiscoveryProperty $record 'Source')
        if ($source -in @('process', 'registry', 'shortcut', 'known_location') -and $client.DiscoverySources -notcontains $source) { $client.DiscoverySources += $source }
    }
    $clients.Values | Sort-Object @{Expression={ if ($_.Running -and $_.BrandVerified) { 0 } elseif ($_.Running) { 1 } elseif ($_.BrandVerified) { 2 } else { 3 } }}, ExePath
}

function ConvertTo-FwSafeTestUrl {
    param($Value)
    if ($Value -isnot [string] -or $Value.Length -gt 2048 -or $Value -match '[\x00-\x20\\]') { return $null }
    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https') -or $uri.UserInfo -or -not $uri.Host -or $uri.Fragment) { return $null }
    return $uri.AbsoluteUri
}

function ConvertTo-FwSafeLogCode {
    param($Value, [string]$Kind)
    if ($Value -isnot [string] -or $Value.Length -gt 80 -or $Value -match '(?i)password|passwd|secret|token|authorization|subscribe|@|[/\\:]|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}|[0-9a-f]{24}') { return $null }
    if ($Kind -eq 'event') {
        if ($Value -match '^(app|startup|core|connection|configuration|config|setup|preferences|profile|subscription|network|api|auth|session|login|logout|proxy|system|window|windows|macos|tun|helper|diagnostic|delay|update|navigation|home|lifecycle|dns|route|service|mode|xboard)([._][a-z][a-z0-9_]{0,35}){1,5}$') { return $Value }
        return $null
    }
    if ($Kind -eq 'error_type') {
        if ($Value -match '^[A-Za-z][A-Za-z0-9_]{0,55}(Exception|Error|Failure)$') { return $Value }
        return $null
    }
    if ($Value -match '^[A-Za-z][A-Za-z0-9_-]{0,63}$' -or $Value -match '^-?[0-9]{1,9}$') { return $Value }
    return $null
}

function Get-FwFingerprint {
    param([string]$Value, [int]$Length = 12)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value.Trim().ToLowerInvariant()))
        return ([BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()).Substring(0, $Length)
    } finally { $sha.Dispose() }
}

function ConvertTo-FwSafeInteger {
    param($Value, [long]$Maximum = 2147483647, [long]$Minimum = 0)
    if ($null -eq $Value -or $Value -is [bool]) { return $null }
    $number = 0L
    if ([long]::TryParse([string]$Value, [ref]$number) -and $number -ge $Minimum -and $number -le $Maximum) { return $number }
    return $null
}

function ConvertTo-FwSafeReference {
    param($Value, [string]$Kind)
    if ($Value -isnot [string]) { return $null }
    if ($Kind -eq 'attempt_id') {
        if ($Value -match '^[a-z0-9]{5,32}_[0-9]{1,8}$') { return $Value.ToLowerInvariant() }
        return $null
    }
    if ($Value -match '^[a-fA-F0-9]{12}$') { return $Value.ToLowerInvariant() }
    return $null
}

function ConvertTo-FwTimestamp {
    param($Value)
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { return $null }
        return ([DateTimeOffset]$Value).ToUniversalTime()
    }
    if ($Value -isnot [string] -or $Value.Length -gt 48 -or $Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$') { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $parsed.ToUniversalTime() }
    return $null
}

function Get-FwSafeLogFields {
    param($Fields, [switch]$ListenerOnly)
    $safe = [ordered]@{}
    $codes = @('error_code', 'error_type', 'diagnostic_code', 'code', 'stage', 'status', 'phase', 'operation', 'reason', 'tls_reason', 'subscription_v2_code', 'failure', 'mode', 'protocol', 'listener', 'owner', 'outcome', 'last_error_type', 'cause_type')
    $numbers = @('port', 'mixed_port', 'socks_port', 'duration_ms', 'elapsed_ms', 'attempt', 'attempts', 'retry_count', 'http_status', 'exit_code', 'os_error_code', 'last_os_error_code', 'win32_error', 'command_exit_code', 'command_spawn_error_code', 'ras_failure_count', 'candidate_count', 'node_count', 'content_bytes', 'revision', 'generation', 'session_revision')
    $booleans = @('success', 'timed_out', 'cancelled', 'enabled', 'tcp_ready', 'udp_ready', 'allow_lan', 'readback_enabled', 'fallback_used', 'running', 'running_requested', 'system_proxy_requested', 'tun_requested', 'has_profile', 'initialize', 'stale_request', 'force', 'core_stopped', 'secure_subscription')
    if ($ListenerOnly) {
        $codes = @('stage', 'listener', 'protocol', 'reason', 'status', 'error_type')
        $numbers = @('port', 'os_error_code', 'elapsed_ms', 'attempts')
        $booleans = @('tcp_ready', 'udp_ready', 'allow_lan', 'success', 'ready')
    }
    foreach ($key in $codes) {
        $kind = $key
        if ($key -in @('last_error_type', 'cause_type')) { $kind = 'error_type' }
        $value = ConvertTo-FwSafeLogCode (Get-FwDiscoveryProperty $Fields $key) $kind
        if ($null -ne $value) { $safe[$key] = $value }
    }
    foreach ($key in $numbers) {
        $maximum = 2147483647L
        $minimum = 0L
        if ($key -in @('os_error_code', 'last_os_error_code', 'win32_error', 'command_spawn_error_code')) { $maximum = 4294967295L }
        if ($key -in @('exit_code', 'command_exit_code')) { $minimum = -2147483648L; $maximum = 4294967295L }
        if ($key -eq 'content_bytes') { $maximum = 9007199254740991L }
        if ($key -match 'port$') { $maximum = 65535L }
        $number = ConvertTo-FwSafeInteger (Get-FwDiscoveryProperty $Fields $key) $maximum $minimum
        if ($null -ne $number) { $safe[$key] = $number }
    }
    foreach ($key in $booleans) {
        $value = Get-FwDiscoveryProperty $Fields $key
        if ($value -is [bool]) { $safe[$key] = $value }
    }
    if (-not $ListenerOnly) {
        foreach ($key in @('endpoint_ref', 'next_endpoint_ref', 'request_ref', 'account_ref', 'selected_node_ref', 'selected_group_ref', 'attempt_id')) {
            $value = ConvertTo-FwSafeReference (Get-FwDiscoveryProperty $Fields $key) $key
            if ($null -ne $value) { $safe[$key] = $value }
        }
        $details = Get-FwDiscoveryProperty $Fields 'details'
        if ($null -ne $details -and ($details -is [Collections.IDictionary] -or $details -is [pscustomobject])) {
            $nested = Get-FwSafeLogFields $details -ListenerOnly
            if ($nested.Count -gt 0) { $safe['details'] = [pscustomobject]$nested }
        }
    }
    return $safe
}

function Read-FwDiagnosticFile {
    param([IO.FileInfo]$File, [ValidateRange(1,5000)][int]$Limit = 1000)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $stats = [ordered]@{ Readable=$false; InvalidRows=0; ValidRows=0; TailTruncated=$false; TailOmittedLines=0 }
    $text = Read-FwBoundedText $File 4194304
    if ($null -eq $text) { return [pscustomobject]@{ Rows=@(); Stats=[pscustomobject]$stats } }
    $stats.Readable = $true
    $allLines = @($text -split '\r?\n' | Where-Object { $_.Length -gt 0 })
    $stats.TailTruncated = $allLines.Count -gt $Limit
    $stats.TailOmittedLines = [Math]::Max(0, ($allLines.Count - $Limit))
    foreach ($line in @($allLines | Select-Object -Last $Limit)) {
        if ($line.Length -gt 32768) { $stats.InvalidRows++; continue }
        try { $row = $line | ConvertFrom-Json -ErrorAction Stop } catch { $stats.InvalidRows++; continue }
        $event = ConvertTo-FwSafeLogCode (Get-FwDiscoveryProperty $row 'event') 'event'
        $time = ConvertTo-FwTimestamp (Get-FwDiscoveryProperty $row 'timestamp')
        if (-not $event -or $null -eq $time) { $stats.InvalidRows++; continue }
        $fields = [pscustomobject](Get-FwSafeLogFields (Get-FwDiscoveryProperty $row 'fields'))
        $sequence = ConvertTo-FwSafeInteger (Get-FwDiscoveryProperty $row 'sequence')
        $rawSession = Get-FwDiscoveryProperty $row 'session'
        $sessionRef = $null
        if ($rawSession -is [string] -and $rawSession.Length -le 256 -and $rawSession -notmatch '[\x00-\x1f]') { $sessionRef = Get-FwFingerprint $rawSession }
        $timestamp = $time.ToUniversalTime().ToString('o')
        $identity = $timestamp + '|' + $event + '|' + ($fields | ConvertTo-Json -Depth 8 -Compress)
        if ($sessionRef -and $null -ne $sequence) { $identity = $sessionRef + '|' + $sequence + '|' + $event }
        $rows.Add([pscustomobject]@{ timestamp=$timestamp; event=$event; event_id=(Get-FwFingerprint $identity 24); session_ref=$sessionRef; sequence=$sequence; fields=$fields })
        $stats.ValidRows++
    }
    return [pscustomobject]@{ Rows=@($rows.ToArray()); Stats=[pscustomobject]$stats }
}

function Get-FwSafeLogRows {
    param([IO.FileInfo]$File, [ValidateRange(1,5000)][int]$Limit = 1000)
    $snapshot = Read-FwDiagnosticFile $File $Limit
    return $snapshot.Rows
}

function Get-FwDiagnosticTimeline {
    param([Parameter(Mandatory=$true)][string]$Root, [ValidateRange(1,5000)][int]$Limit = 1000)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $stats = [ordered]@{ FilesFound=0; FilesRead=0; ReadFailed=0; ValidRows=0; RetainedRows=0; DuplicateRows=0; InvalidRows=0; DroppedRows=0; TailOmittedLines=0; CountUnknown=$false; Truncated=$false; FreshestTimestamp=$null; Source='client_structured_diagnostic_files' }
    foreach ($name in @('events.jsonl.2', 'events.jsonl.1', 'events.jsonl')) {
        $file = Get-FwBoundedFile $Root (Join-Path 'diagnostics' $name) 4194304
        if ($null -eq $file) { continue }
        $stats.FilesFound++
        $snapshot = Read-FwDiagnosticFile $file $Limit
        if (-not $snapshot.Stats.Readable) { $stats.ReadFailed++; continue }
        $stats.FilesRead++
        $stats.InvalidRows += $snapshot.Stats.InvalidRows
        $stats.ValidRows += $snapshot.Stats.ValidRows
        $stats.TailOmittedLines += $snapshot.Stats.TailOmittedLines
        if ($snapshot.Stats.TailTruncated) { $stats.Truncated = $true }
        foreach ($row in $snapshot.Rows) { $rows.Add($row) }
    }
    $unique = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($row in @($rows.ToArray() | Sort-Object timestamp, session_ref, sequence)) {
        if ($seen.ContainsKey($row.event_id)) { $stats.DuplicateRows++; continue }
        $seen[$row.event_id] = $true
        $unique.Add($row)
    }
    $stats.DroppedRows = [Math]::Max(0, ($unique.Count - $Limit))
    $stats.CountUnknown = $stats.TailOmittedLines -gt 0 -or $stats.ReadFailed -gt 0
    if ($unique.Count -gt $Limit) { $stats.Truncated = $true }
    $retained = @($unique.ToArray() | Select-Object -Last $Limit)
    $stats.RetainedRows = $retained.Count
    if ($retained.Count -gt 0) { $stats.FreshestTimestamp = $retained[-1].timestamp }
    return [pscustomobject]@{ Rows=$retained; Stats=[pscustomobject]$stats }
}

function ConvertTo-FwEmailIdentity {
    param($Value)
    if ($Value -isnot [string] -or $Value.Length -gt 254 -or $Value -match '[\x00-\x20]') { return $null }
    $normalized = $Value.Trim().ToLowerInvariant()
    if ($normalized -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $null }
    return $normalized
}

function Get-FwCachedAccountSummary {
    param($Preferences)
    $summary = [ordered]@{ account_ref=$null; source='local_preferences_and_offline_cache'; is_cached_source=$true; server_freshness='UNVERIFIED_CACHE'; account_match='UNKNOWN_ACCOUNT_MATCH'; cache_found=$false; cache_parsed=$false; verified_at=$null; cache_age_seconds=$null; cache_time_valid=$false }
    $email = ConvertTo-FwEmailIdentity (Get-FwDiscoveryProperty $Preferences 'flutter.xboard.email')
    $sessionAccount = ConvertTo-FwEmailIdentity (Get-FwDiscoveryProperty $Preferences 'flutter.xboard.session_account')
    $current = $sessionAccount
    if (-not $current) { $current = $email }
    if ($email -and $sessionAccount -and $email -ne $sessionAccount) { $current = $null }
    if ($current) { $summary.account_ref = Get-FwFingerprint $current }
    $source = Get-FwDiscoveryProperty $Preferences 'flutter.xboard.offline_cache'
    $summary.cache_found = $source -is [string] -and -not [string]::IsNullOrWhiteSpace($source)
    if (-not $summary.cache_found -or $source.Length -gt 4194304) { return [pscustomobject]$summary }
    try { $cache = $source | ConvertFrom-Json -ErrorAction Stop } catch { return [pscustomobject]$summary }
    if ($cache -isnot [pscustomobject]) { return [pscustomobject]$summary }
    $subscription = Get-FwDiscoveryProperty $cache 'subscription'
    if ($subscription -isnot [pscustomobject]) { return [pscustomobject]$summary }
    $summary.cache_parsed = $true
    $cachedEmail = ConvertTo-FwEmailIdentity (Get-FwDiscoveryProperty $subscription 'email')
    if (-not $current -or -not $cachedEmail -or $cachedEmail -ne $current) { return [pscustomobject]$summary }
    $summary.account_match = 'MATCHED'
    $verifiedAt = ConvertTo-FwTimestamp (Get-FwDiscoveryProperty $cache 'verified_at')
    if ($null -ne $verifiedAt) {
        $summary.verified_at = $verifiedAt.ToUniversalTime().ToString('o')
        $age = [DateTimeOffset]::UtcNow.Subtract($verifiedAt.ToUniversalTime()).TotalSeconds
        if ($age -ge 0 -and $age -le 2147483647) { $summary.cache_age_seconds = [long][Math]::Floor($age); $summary.cache_time_valid = $true }
    }
    $expiryValue = Get-FwDiscoveryProperty $subscription 'expired_at'
    $expiryProperty = $subscription.PSObject.Properties['expired_at']
    if ($null -ne $expiryProperty -and $null -eq $expiryValue) {
        $summary.expires_at_epoch_seconds = $null
        $summary.expires_at_utc = $null
        $summary.cached_never_expires = $true
    } else {
        $expiry = ConvertTo-FwSafeInteger $expiryValue 253402300799L
        if ($null -ne $expiry) {
            $expiresAt = [DateTimeOffset]::FromUnixTimeSeconds($expiry)
            $summary.expires_at_epoch_seconds = $expiry
            $summary.expires_at_utc = $expiresAt.ToUniversalTime().ToString('o')
            $summary.cached_never_expires = $false
            $summary.cached_expired_at_collection_time = $expiresAt -le [DateTimeOffset]::UtcNow
        }
    }
    $upload = ConvertTo-FwSafeInteger (Get-FwDiscoveryProperty $subscription 'u') 9007199254740991L
    $download = ConvertTo-FwSafeInteger (Get-FwDiscoveryProperty $subscription 'd') 9007199254740991L
    $total = ConvertTo-FwSafeInteger (Get-FwDiscoveryProperty $subscription 'transfer_enable') 9007199254740991L
    if ($null -ne $upload -and $null -ne $download -and $null -ne $total -and $upload -le (9007199254740991L - $download)) {
        $used = $upload + $download
        $summary.upload_bytes = $upload
        $summary.download_bytes = $download
        $summary.used_bytes = $used
        $summary.total_bytes = $total
        $summary.remaining_bytes = [Math]::Max(0L, ($total - $used))
        $summary.cached_traffic_exhausted = $used -ge $total
    }
    return [pscustomobject]$summary
}

function Get-FengWoLocalContext {
    param([Parameter(Mandatory=$true)]$Client)
    $candidates = @()
    $seen = @{}
    foreach ($directory in @(Get-FwDiscoveryProperty $Client 'DataDirectories') | Select-Object -First 16) {
        $root = Get-FwLocalFullPath ([string]$directory)
        if (-not $root -or $seen.ContainsKey($root) -or -not (Test-FwLocalEntry $root $true)) { continue }
        $seen[$root] = $true
        $active = Get-FwBoundedFile $root 'config.yaml'
        $preferences = Get-FwBoundedFile $root 'shared_preferences.json'
        $loadedPreferences = $null
        $loadedConfig = $null
        $rawPreferences = Read-FwBoundedText $preferences
        if ($null -ne $rawPreferences) {
            try {
                $outer = $rawPreferences | ConvertFrom-Json -ErrorAction Stop
                if ($outer -is [pscustomobject]) { $loadedPreferences = $outer }
                $inner = Get-FwDiscoveryProperty $loadedPreferences 'flutter.config'
                if ($inner -is [string]) {
                    $parsed = $inner | ConvertFrom-Json -ErrorAction Stop
                    if ($parsed -is [pscustomobject]) { $loadedConfig = $parsed }
                }
            } catch {}
        }
        $score = 0
        if ($null -ne $active) { $score += 4 }
        $validPreferences = $null -ne $loadedConfig -or $null -ne (ConvertTo-FwEmailIdentity (Get-FwDiscoveryProperty $loadedPreferences 'flutter.xboard.email')) -or $null -ne (ConvertTo-FwEmailIdentity (Get-FwDiscoveryProperty $loadedPreferences 'flutter.xboard.session_account'))
        if ($validPreferences) { $score += 2 }
        $latestLog = $null
        foreach ($name in @('events.jsonl', 'events.jsonl.1', 'events.jsonl.2')) {
            $file = Get-FwBoundedFile $root (Join-Path 'diagnostics' $name) 4194304
            if ($null -ne $file -and ($null -eq $latestLog -or $file.LastWriteTimeUtc -gt $latestLog.LastWriteTimeUtc)) {
                $preview = Read-FwDiagnosticFile $file 50
                if ($preview.Rows.Count -gt 0) { $latestLog = $file }
            }
        }
        $freshness = [DateTime]::MinValue
        if ($validPreferences) { $freshness = $preferences.LastWriteTimeUtc }
        if ($null -ne $latestLog -and $latestLog.LastWriteTimeUtc -gt $freshness) { $freshness = $latestLog.LastWriteTimeUtc }
        $preferred = $validPreferences -or $null -ne $latestLog
        $candidates += [pscustomobject]@{ Root=$root; Active=$active; Preferences=$preferences; LoadedPreferences=$loadedPreferences; LoadedConfig=$loadedConfig; LatestLog=$latestLog; Preferred=$preferred; Freshness=$freshness; Score=$score; Order=$candidates.Count }
    }
    $selected = $candidates | Sort-Object @{Expression={ if ($_.Preferred) { 0 } elseif ($_.Score -gt 0) { 1 } else { 2 } }}, @{Expression={ $_.Freshness };Descending=$true}, Order | Select-Object -First 1
    $recognizedCandidates = @($candidates | Where-Object { $_.Score -gt 0 -or $null -ne $_.LatestLog }).Count
    $selection = [pscustomobject]@{ CandidateCount=$candidates.Count; RecognizedCandidateCount=$recognizedCandidates; Ambiguous=($recognizedCandidates -gt 1); CurrentDirectoryConfirmed=$false; Basis='freshest_valid_preferences_or_recognized_diagnostic_log_mtime'; Scope='known_client_data_directories_only' }
    $result = [ordered]@{
        DataDirectory=$null; ActiveConfigPath=$null; ActiveConfigModifiedUtc=$null
        ProfilePath=$null; ProfileModifiedUtc=$null; ProviderCachePaths=@()
        TestUrl=$null; Logs=@(); LogPath=$null
        LogSnapshot=[pscustomobject]@{ Rows=@(); Stats=[pscustomobject]@{ FilesFound=0; FilesRead=0; RetainedRows=0; Truncated=$false } }
        DataDirectorySelection=$selection
        Account=(Get-FwCachedAccountSummary $null)
        Prefs=[pscustomobject]@{ Found=$false; Parsed=$false; CurrentProfileId=$null; HasCustomTestUrl=$false; TestUrlStatus='missing' }
    }
    if ($null -eq $selected) { return [pscustomobject]$result }
    $result.DataDirectory = $selected.Root
    if ($null -ne $selected.Active) {
        $result.ActiveConfigPath = $selected.Active.FullName
        $result.ActiveConfigModifiedUtc = $selected.Active.LastWriteTimeUtc.ToString('o')
    }
    $summary = [ordered]@{ Found=($null -ne $selected.Preferences); Parsed=$false; CurrentProfileId=$null; HasCustomTestUrl=$false; TestUrlStatus='missing' }
    $config = $selected.LoadedConfig
    $summary.Parsed = $null -ne $config
    $result.Account = Get-FwCachedAccountSummary $selected.LoadedPreferences
    $profileId = [string](Get-FwDiscoveryProperty $config 'currentProfileId')
    $numericId = 0L
    if ($profileId -match '^\d{1,19}$' -and [long]::TryParse($profileId, [ref]$numericId) -and $numericId -ge 0) {
        $profileId = [string]$numericId
        $summary.CurrentProfileId = $numericId
        $profile = Get-FwBoundedFile $selected.Root (Join-Path 'profiles' ($profileId + '.yaml'))
        if ($null -ne $profile) { $result.ProfilePath=$profile.FullName; $result.ProfileModifiedUtc=$profile.LastWriteTimeUtc.ToString('o') }
        $providerRelative = Join-Path (Join-Path (Join-Path 'profiles' 'providers') $profileId) 'proxies'
        $providerDirectory = Join-Path $selected.Root $providerRelative
        if (Test-FwContainedDirectory $selected.Root $providerDirectory) {
            foreach ($entry in @(Get-ChildItem -LiteralPath $providerDirectory -File -ErrorAction SilentlyContinue | Select-Object -First 256)) {
                if ($entry.Name -notmatch '^[0-9a-f]{32}$') { continue }
                $file = Get-FwBoundedFile $selected.Root (Join-Path $providerRelative $entry.Name)
                if ($null -ne $file) { $result.ProviderCachePaths += $file.FullName }
                if ($result.ProviderCachePaths.Count -ge 20) { break }
            }
        }
    }
    $settings = Get-FwDiscoveryProperty $config 'appSettingProps'
    $testUrl = Get-FwDiscoveryProperty $settings 'testUrl'
    if ($null -ne $testUrl) {
        $summary.HasCustomTestUrl = $true
        $result.TestUrl = ConvertTo-FwSafeTestUrl $testUrl
        $summary.TestUrlStatus = if ($result.TestUrl) { 'valid' } else { 'rejected' }
    }
    $patch = Get-FwDiscoveryProperty $config 'patchClashConfig'
    $mode = [string](Get-FwDiscoveryProperty $patch 'mode')
    if ($mode -in @('rule', 'global', 'direct')) { $summary.Mode = $mode }
    foreach ($key in @('mixed-port', 'port', 'socks-port')) {
        $number = 0
        $rawPort = Get-FwDiscoveryProperty $patch $key
        if ($null -ne $rawPort -and [int]::TryParse([string]$rawPort, [ref]$number) -and $number -ge 0 -and $number -le 65535) { $summary[$key] = $number }
    }
    foreach ($field in @(
        @{Name='UnifiedDelay'; Value=(Get-FwDiscoveryProperty $patch 'unified-delay')},
        @{Name='TunEnabled'; Value=(Get-FwDiscoveryProperty (Get-FwDiscoveryProperty $patch 'tun') 'enable')},
        @{Name='SystemProxy'; Value=(Get-FwDiscoveryProperty (Get-FwDiscoveryProperty $config 'networkProps') 'systemProxy')},
        @{Name='OpenLogs'; Value=(Get-FwDiscoveryProperty $settings 'openLogs')}
    )) {
        if ($field.Value -is [bool]) { $summary[$field.Name] = $field.Value }
    }
    $result.Prefs = [pscustomobject]$summary
    $result.LogSnapshot = Get-FwDiagnosticTimeline -Root $selected.Root -Limit 1000
    $result.Logs = @($result.LogSnapshot.Rows)
    if ($null -ne $selected.LatestLog) { $result.LogPath = $selected.LatestLog.FullName }
    return [pscustomobject]$result
}
