Set-StrictMode -Version 2.0

function Invoke-FwLogman {
    param([string[]]$Arguments)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $env:SystemRoot 'System32\logman.exe'
    $start.Arguments = ($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); $process.WaitForExit(); throw 'Owned logman command timed out.' }
        $null = $stdout.Wait(1000)
        $null = $stderr.Wait(1000)
        return $process.ExitCode
    } finally { $process.Dispose() }
}

function New-FwPrivateDirectory {
    param([string]$Path)
    $null = [IO.Directory]::CreateDirectory($Path)
    if (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Private directory cannot be a reparse point.' }
    $security = New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true, $false)
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    foreach ($sid in @($current, $system)) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $security.AddAccessRule($rule)
    }
    [IO.Directory]::SetAccessControl($Path, $security)
}

function Start-FwProxyWriterTrace {
    param([string]$PrivateDirectory, [ValidateRange(5, 180)][int]$Seconds = 45)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator consent is required for registry writer tracing.' }
    New-FwPrivateDirectory $PrivateDirectory
    $session = 'FengWoProxy-' + [Guid]::NewGuid().ToString('N')
    $etl = Join-Path $PrivateDirectory 'registry.etl'
    $providers = Join-Path $PrivateDirectory 'providers.txt'
    $content = '"Microsoft-Windows-Kernel-Registry" 0x3300 5' + "`r`n" + '"Microsoft-Windows-Kernel-Process" 0x10 5' + "`r`n"
    [IO.File]::WriteAllText($providers, $content, [Text.Encoding]::ASCII)
    $duration = [TimeSpan]::FromSeconds($Seconds + 15).ToString('hh\:mm\:ss')
    $exit = Invoke-FwLogman @('create', 'trace', $session, '-pf', $providers, '-o', $etl, '-f', 'bincirc', '-max', '32', '-nb', '16', '64', '-bs', '64', '-rf', $duration, '-ets')
    if ($exit -ne 0) { throw ('Registry trace start failed; exit=' + $exit) }
    return [ordered]@{ session = $session; etl = $etl; privateDirectory = $PrivateDirectory; startedUtc = [DateTime]::UtcNow.ToString('o'); currentUserSid = $identity.User.Value; maximumSeconds = $Seconds + 15 }
}

function Stop-FwProxyWriterTrace {
    param($Trace)
    if ($Trace.session -notmatch '^FengWoProxy-[a-f0-9]{32}$') { throw 'Unexpected trace session.' }
    $stopExit = Invoke-FwLogman @('stop', $Trace.session, '-ets')
    return [ordered]@{ stopExit = $stopExit; stillRunning = Test-FwProxyTraceRunning $Trace }
}

function Test-FwProxyTraceRunning {
    param($Trace)
    if ($Trace.session -notmatch '^FengWoProxy-[a-f0-9]{32}$') { throw 'Unexpected trace session.' }
    return (Invoke-FwLogman @('query', $Trace.session, '-ets')) -eq 0
}

function Get-FwEventData {
    param($Record)
    $xml = New-Object Xml.XmlDocument
    $xml.XmlResolver = $null
    $xml.LoadXml($Record.ToXml())
    $fields = @{}
    foreach ($node in $xml.SelectNodes("//*[local-name()='EventData']/*[local-name()='Data']")) {
        $fields[$node.GetAttribute('Name')] = $node.InnerText
    }
    return $fields
}

function Get-FwSafeProcessName {
    param([string]$Value)
    $name = [IO.Path]::GetFileName($Value)
    if ($name -match '^[a-zA-Z0-9_. -]{1,100}$') { return $name }
    return 'unresolved_or_redacted'
}

function ConvertTo-FwWriterEvidence {
    param([object[]]$Records, [string]$CurrentUserSid, [hashtable]$LiveProcesses = @{})
    $objects = @{}
    $processes = @{}
    foreach ($key in $LiveProcesses.Keys) {
        $processes[[string]$key] = @($LiveProcesses[$key] | ForEach-Object { [ordered]@{ name = Get-FwSafeProcessName $_.name; observedUtc = $_.observedUtc; source = $_.source } })
    }
    $writers = New-Object 'Collections.Generic.List[object]'
    $counts = [ordered]@{ total = 0; registryWrites = 0; unresolvedProxyNamedWrites = 0; matchedProxyWrites = 0 }
    foreach ($record in @($Records | Sort-Object TimeCreated)) {
        $counts.total++
        if ($null -eq $record.TimeCreated) { continue }
        $data = Get-FwEventData $record
        $time = $record.TimeCreated.ToUniversalTime()
        if ($record.ProviderName -eq 'Microsoft-Windows-Kernel-Process') {
            $pidValue = $null
            foreach ($name in @('ProcessID', 'ProcessId')) { if ($data.ContainsKey($name)) { $pidValue = $data[$name]; break } }
            $image = $null
            foreach ($name in @('ImageName', 'ImageFileName')) { if ($data.ContainsKey($name)) { $image = $data[$name]; break } }
            if ($null -ne $pidValue -and $image) {
                $key = [string][uint32]$pidValue
                if (-not $processes.ContainsKey($key)) { $processes[$key] = @() }
                $processes[$key] += [ordered]@{ name = Get-FwSafeProcessName $image; observedUtc = $time; source = 'kernel_process_event' }
            }
            continue
        }
        if ($record.ProviderName -ne 'Microsoft-Windows-Kernel-Registry') { continue }
        $object = if ($data.ContainsKey('KeyObject')) { [string]$data.KeyObject } else { '' }
        $keyName = if ($data.ContainsKey('KeyName')) { [string]$data.KeyName } else { '' }
        if (-not $keyName -and $data.ContainsKey('RelativeName')) {
            $relative = [string]$data.RelativeName
            $base = if ($data.ContainsKey('BaseName')) { [string]$data.BaseName } else { '' }
            if (-not $base -and $data.ContainsKey('BaseObject') -and $objects.ContainsKey([string]$data.BaseObject)) { $base = $objects[[string]$data.BaseObject] }
            $keyName = if ($relative.StartsWith('\')) { $relative } elseif ($base) { $base.TrimEnd('\') + '\' + $relative } else { $relative }
        }
        if ($object -and $keyName) { $objects[$object] = $keyName }
        if (-not $keyName -and $object -and $objects.ContainsKey($object)) { $keyName = $objects[$object] }
        $opcode = [int]$record.Opcode
        if ($opcode -notin @(36, 37) -and [int]$record.Id -notin @(5, 6)) { continue }
        $counts.registryWrites++
        $valueName = if ($data.ContainsKey('ValueName')) { [string]$data.ValueName } else { '' }
        if ($valueName -notin @('ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL', 'AutoDetect', 'DefaultConnectionSettings', 'SavedLegacySettings')) { continue }
        if (-not $keyName) { $counts.unresolvedProxyNamedWrites++; continue }
        if ($keyName -notmatch '(?i)\\Software\\(?:WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Internet Settings(?:\\Connections)?$') { continue }
        if ($keyName -match '(?i)^\\REGISTRY\\USER\\' -and $keyName -notmatch ('(?i)^\\REGISTRY\\USER\\' + [regex]::Escape($CurrentUserSid) + '\\')) { continue }
        $writerId = [string]$record.ProcessId
        $identity = $null
        if ($processes.ContainsKey($writerId)) {
            $identity = @($processes[$writerId] | Where-Object { [DateTime]$_.observedUtc -le $time } | Sort-Object observedUtc -Descending | Select-Object -First 1)
        }
        $writerName = if ($null -ne $identity -and @($identity).Count -gt 0) { $identity[0].name } else { 'unresolved_or_exited' }
        $status = if ($data.ContainsKey('Status')) { [string]$data.Status } else { 'unknown' }
        $writers.Add([ordered]@{
            atUtc = $time.ToString('o'); processId = [int]$record.ProcessId; processName = $writerName
            operation = if ($opcode -eq 37 -or [int]$record.Id -eq 6) { 'DeleteValue' } else { 'SetValue' }
            valueName = $valueName; keyScope = if ($keyName -match '(?i)^\\REGISTRY\\MACHINE\\') { 'machine' } else { 'current_user' }
            connectionsSubkey = $keyName.EndsWith('\Connections', [StringComparison]::OrdinalIgnoreCase)
            nativeStatus = $status; valueContentCollected = $false; initiatorMayDifferFromRegistryWriter = $true
        })
        $counts.matchedProxyWrites++
    }
    return [ordered]@{ status = if ($writers.Count -gt 0) { 'proxy_registry_writers_captured' } else { 'writer_not_determined' }; counts = $counts; writers = @($writers.ToArray()); limitations = @('A write event is not proof that its new value disabled the proxy; correlate state samples.', 'A Windows broker/service can write on behalf of another process.', 'No event does not prove no writer: existing handles, schema differences or dropped events may prevent attribution.') }
}

function Complete-FwProxyWriterTrace {
    param($Trace, [hashtable]$LiveProcesses = @{})
    $stop = Stop-FwProxyWriterTrace $Trace
    if ($stop.stillRunning) { throw 'Owned trace did not stop.' }
    $records = @(Get-WinEvent -Path $Trace.etl -Oldest -ErrorAction Stop)
    $result = ConvertTo-FwWriterEvidence $records $Trace.currentUserSid $LiveProcesses
    $result.traceStopped = $true
    $result.maximumFileSizeMb = 32
    Add-Type -AssemblyName System.Security
    $raw = [IO.File]::ReadAllBytes($Trace.etl)
    $protected = [Security.Cryptography.ProtectedData]::Protect($raw, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes(($Trace.etl + '.dpapi'), $protected)
    [IO.File]::Delete($Trace.etl)
    return $result
}

Export-ModuleMember -Function New-FwPrivateDirectory, Start-FwProxyWriterTrace, Stop-FwProxyWriterTrace, Test-FwProxyTraceRunning, Get-FwEventData, ConvertTo-FwWriterEvidence, Complete-FwProxyWriterTrace
