Set-StrictMode -Version 2.0
$script:PrivacySalt = [Guid]::NewGuid().ToString('N')

function Initialize-FwProxyNative {
    if (-not ('FengWoProxyDiagnostics.Native' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'ProxyNative.cs')
    }
}

function Get-FwPrivateTag {
    param([AllowNull()][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($script:PrivacySalt + ':' + $Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function ConvertTo-FwPrivateReference {
    param([AllowNull()][string]$Value)
    $text = [string]$Value
    return [ordered]@{ present = (-not [string]::IsNullOrEmpty($text)); length = $text.Length; tag = Get-FwPrivateTag $text }
}

function Get-FwRegistryValue {
    param([string]$Hive, [string]$View, [string]$Key, [string]$Name)
    $root = $null
    $opened = $null
    try {
        $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$Hive, [Microsoft.Win32.RegistryView]::$View)
        $opened = $root.OpenSubKey($Key, $false)
        if ($null -eq $opened -or $opened.GetValueNames() -notcontains $Name) {
            return [ordered]@{ exists = $false; kind = ''; value = $null; error = 0 }
        }
        $kind = $opened.GetValueKind($Name).ToString()
        $value = $opened.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return [ordered]@{ exists = $true; kind = $kind; value = $value; error = 0 }
    } catch {
        return [ordered]@{ exists = $false; kind = ''; value = $null; error = $_.Exception.HResult }
    } finally {
        if ($null -ne $opened) { $opened.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-FwProxySnapshot {
    param([switch]$RegistryOnly)
    if (-not $RegistryOnly) { Initialize-FwProxyNative }
    $registry = [ordered]@{}
    $policies = New-Object 'Collections.Generic.List[object]'
    $settings = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $policyKeys = @(
        @{ key = 'Software\Policies\Microsoft\Windows\CurrentVersion\Internet Settings'; names = @('ProxySettingsPerUser', 'ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL', 'AutoDetect') },
        @{ key = 'Software\Policies\Microsoft\Internet Explorer\Control Panel'; names = @('Proxy', 'Autoconfig') }
    )
    foreach ($hive in @('CurrentUser', 'LocalMachine')) {
        $registry[$hive] = [ordered]@{}
        foreach ($name in @('ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL', 'AutoDetect')) {
            $registry[$hive][$name] = Get-FwRegistryValue $hive 'Default' $settings $name
        }
        foreach ($view in @('Registry64', 'Registry32')) {
            if ($view -eq 'Registry64' -and -not [Environment]::Is64BitOperatingSystem) { continue }
            foreach ($entry in $policyKeys) {
                foreach ($name in $entry.names) {
                    $value = Get-FwRegistryValue $hive $view $entry.key $name
                    $policies.Add([ordered]@{ hive = $hive; view = $view; key = $entry.key; name = $name; data = $value })
                }
            }
        }
    }
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^(FengWo|FengWoCore|fengwoacc|FlClash|FlClashCore|Clash|ClashVerge|Clash for Windows|v2rayN|sing-box)$'
    } | ForEach-Object { [ordered]@{ name = $_.ProcessName; pid = $_.Id; session = $_.SessionId } })
    $queries = [ordered]@{}
    if ($RegistryOnly) {
        foreach ($name in @('wideUi', 'ansiUi', 'wideEffective', 'ansiEffective')) {
            $queries[$name] = [pscustomobject]@{ Success = $false; Error = 0; OptionError = 0; Configuration = $null }
        }
    } else {
        $queries.wideUi = [FengWoProxyDiagnostics.Native]::Query($false, $true)
        $queries.ansiUi = [FengWoProxyDiagnostics.Native]::Query($true, $true)
        $queries.wideEffective = [FengWoProxyDiagnostics.Native]::Query($false, $false)
        $queries.ansiEffective = [FengWoProxyDiagnostics.Native]::Query($true, $false)
    }
    return [ordered]@{
        atUtc = [DateTime]::UtcNow.ToString('o')
        collectionMode = if ($RegistryOnly) { 'registry_only_no_wininet_query' } else { 'full_wininet_and_registry' }
        queries = $queries
        registry = $registry
        policies = @($policies.ToArray())
        processes = $processes
    }
}

function Test-FwConfigurationEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    return [uint32]$Left.Flags -eq [uint32]$Right.Flags -and
        [string]::Equals($Left.Server, $Right.Server, [StringComparison]::Ordinal) -and
        [string]::Equals($Left.Bypass, $Right.Bypass, [StringComparison]::Ordinal) -and
        [string]::Equals($Left.Pac, $Right.Pac, [StringComparison]::Ordinal)
}

function Get-FwConfigurationFingerprint {
    param($Snapshot)
    $ui = [ordered]@{}
    foreach ($name in @('wideUi', 'ansiUi')) {
        $query = $Snapshot.queries[$name]
        $ui[$name] = [ordered]@{ success = $query.Success; error = $query.Error; configuration = $query.Configuration }
    }
    $value = [ordered]@{ ui = $ui; registry = $Snapshot.registry; policies = $Snapshot.policies }
    return Get-FwPrivateTag (ConvertTo-Json -InputObject $value -Depth 15 -Compress)
}

function Test-FwRegistryAgreement {
    param($Snapshot)
    $query = $Snapshot.queries.wideUi
    if (-not $query.Success) { return $false }
    $enabled = $Snapshot.registry.CurrentUser.ProxyEnable
    $server = $Snapshot.registry.CurrentUser.ProxyServer
    if ($enabled.error -ne 0 -or $server.error -ne 0) { return $false }
    if ($enabled.exists -and $enabled.kind -ne 'DWord') { return $false }
    if ($server.exists -and $server.kind -notin @('String', 'ExpandString')) { return $false }
    $manual = ([uint32]$query.Configuration.Flags -band 2) -ne 0
    $registryEnabled = $enabled.exists -and ([int]$enabled.value -ne 0)
    if ($manual -ne $registryEnabled) { return $false }
    return (-not $manual) -or [string]::Equals([string]$server.value, $query.Configuration.Server, [StringComparison]::Ordinal)
}

function Get-FwRepairGuard {
    param($Snapshot)
    if (@($Snapshot.policies | Where-Object { $_.data.error -ne 0 }).Count -gt 0) { return 'policy_unreadable' }
    if (@($Snapshot.policies | Where-Object { $_.data.exists }).Count -gt 0) { return 'managed_proxy_policy_present' }
    if (@($Snapshot.processes).Count -gt 0) { return 'close_proxy_clients_first' }
    if (-not $Snapshot.queries.wideUi.Success -or -not $Snapshot.queries.ansiUi.Success) { return 'wininet_ui_read_failed' }
    if (-not (Test-FwConfigurationEqual $Snapshot.queries.wideUi.Configuration $Snapshot.queries.ansiUi.Configuration)) { return 'wide_ansi_disagree' }
    if (-not (Test-FwRegistryAgreement $Snapshot)) { return 'wininet_registry_disagree' }
    return 'allowed'
}

function ConvertTo-FwPublicSnapshot {
    param($Snapshot, [int]$Port = 17980)
    $minimal = $Snapshot.Contains('collectionMode') -and $Snapshot.collectionMode -eq 'registry_only_no_wininet_query'
    $queries = [ordered]@{}
    foreach ($name in @('wideUi', 'ansiUi', 'wideEffective', 'ansiEffective')) {
        $query = $Snapshot.queries[$name]
        $configuration = $query.Configuration
        $public = [ordered]@{ success = $query.Success; error = $query.Error; optionError = $query.OptionError }
        if ($query.Success -and $null -ne $configuration) {
            $public.flags = $configuration.Flags
            $public.manualEnabled = ([uint32]$configuration.Flags -band 2) -ne 0
            $public.automaticEnabled = ([uint32]$configuration.Flags -band 12) -ne 0
            $public.server = ConvertTo-FwPrivateReference $configuration.Server
            $public.server.fengwoLoopbackEndpoint = ($configuration.Server -ceq ('127.0.0.1:' + $Port))
            $public.bypass = ConvertTo-FwPrivateReference $configuration.Bypass
            $public.pac = ConvertTo-FwPrivateReference $configuration.Pac
        }
        $queries[$name] = $public
    }
    $registry = [ordered]@{}
    foreach ($hive in $Snapshot.registry.Keys) {
        $registry[$hive] = [ordered]@{}
        foreach ($name in $Snapshot.registry[$hive].Keys) {
            $entry = $Snapshot.registry[$hive][$name]
            $value = [ordered]@{ exists = $entry.exists; kind = $entry.kind; error = $entry.error }
            if ($entry.kind -eq 'DWord') { $value.numericValue = $entry.value }
            elseif ($entry.exists) { $value.reference = ConvertTo-FwPrivateReference ([string]$entry.value) }
            $registry[$hive][$name] = $value
        }
    }
    $policies = @($Snapshot.policies | ForEach-Object {
        $entry = [ordered]@{ hive = $_.hive; view = $_.view; key = $_.key; name = $_.name; exists = $_.data.exists; kind = $_.data.kind; error = $_.data.error }
        if ($_.data.kind -eq 'DWord') { $entry.numericValue = $_.data.value }
        elseif ($_.data.exists) { $entry.reference = ConvertTo-FwPrivateReference ([string]$_.data.value) }
        $entry
    })
    return [ordered]@{
        atUtc = $Snapshot.atUtc; queries = $queries; registry = $registry; policies = $policies
        collectionMode = if ($minimal) { 'registry_only_no_wininet_query' } else { 'full_wininet_and_registry' }
        processes = @($Snapshot.processes); registryAgreement = if ($minimal) { $null } else { Test-FwRegistryAgreement $Snapshot }
        wideAnsiAgreement = if ($minimal) { $null } else { Test-FwConfigurationEqual $Snapshot.queries.wideUi.Configuration $Snapshot.queries.ansiUi.Configuration }
        repairGuard = if ($minimal) { 'not_attempted_minimal_monitor' } else { Get-FwRepairGuard $Snapshot }; fingerprint = Get-FwConfigurationFingerprint $Snapshot
    }
}

function Save-FwEncryptedBackup {
    param($Snapshot, [string]$Path)
    Add-Type -AssemblyName System.Security
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Snapshot -Depth 20 -Compress))
    $protected = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    [IO.File]::WriteAllBytes($Path, $protected)
}

function Invoke-FwRefreshRepair {
    param(
        [bool]$Consent,
        [scriptblock]$ReadSnapshot = { Get-FwProxySnapshot },
        [scriptblock]$Refresh = { param($Option) [FengWoProxyDiagnostics.Native]::Refresh($Option) },
        [Parameter(Mandatory = $true)][scriptblock]$Backup
    )
    $result = [ordered]@{ status = 'consent_required'; options = @(); configurationWritten = $false; proxyConnectionVerified = $false; backupCreated = $false }
    if (-not $Consent) { return $result }
    $baseline = & $ReadSnapshot
    $guard = Get-FwRepairGuard $baseline
    if ($guard -ne 'allowed') { $result.status = $guard; return $result }
    & $Backup $baseline | Out-Null
    $result.backupCreated = $true
    $fresh = & $ReadSnapshot
    if ((Get-FwConfigurationFingerprint $baseline) -cne (Get-FwConfigurationFingerprint $fresh) -or (Get-FwRepairGuard $fresh) -ne 'allowed') {
        $result.status = 'state_changed_before_refresh'
        return $result
    }
    foreach ($option in @(95, 39, 37)) {
        $value = & $Refresh $option
        $result.options += [ordered]@{ option = $option; success = $value.Success; error = $value.Error }
        if (-not $value.Success) { $result.status = 'refresh_failed'; return $result }
    }
    $after = & $ReadSnapshot
    $result.configurationPreserved = (Get-FwConfigurationFingerprint $baseline) -ceq (Get-FwConfigurationFingerprint $after)
    $result.status = if ($result.configurationPreserved) { 'refresh_completed_configuration_preserved' } else { 'state_changed_no_overwrite_attempted' }
    return $result
}

function Get-FwPhaseAssessment {
    param([ValidateSet('before', 'connected', 'disconnected', 'exited')][string]$Phase, $Snapshot, $Baseline, [int]$Port = 17980)
    $query = $Snapshot.queries.wideUi
    $coherent = $query.Success -and $Snapshot.queries.ansiUi.Success -and
        (Test-FwConfigurationEqual $query.Configuration $Snapshot.queries.ansiUi.Configuration) -and
        (Test-FwRegistryAgreement $Snapshot)
    $manual = $coherent -and (([uint32]$query.Configuration.Flags -band 2) -ne 0)
    $ours = $manual -and $query.Configuration.Server -ceq ('127.0.0.1:' + $Port)
    $automatic = $coherent -and (([uint32]$query.Configuration.Flags -band 12) -ne 0)
    $restored = $null -ne $Baseline -and (Get-FwConfigurationFingerprint $Snapshot) -ceq (Get-FwConfigurationFingerprint $Baseline)
    $clientExited = @($Snapshot.processes | Where-Object { $_.name -match '^(FengWo|fengwoacc)$' }).Count -eq 0
    $passed = switch ($Phase) {
        'connected' { $coherent -and $ours -and -not $automatic }
        'disconnected' { $coherent -and -not $ours -and $restored }
        'exited' { $coherent -and -not $ours -and $restored -and $clientExited }
        default { $coherent -and -not $ours }
    }
    return [ordered]@{
        phase = $Phase; passed = [bool]$passed; coherent = [bool]$coherent; fengwoManualProxyActive = [bool]$ours
        automaticProxyEnabled = [bool]$automatic; originalConfigurationRestored = [bool]$restored
        clientExited = $clientExited; tunCleanupVerified = $false; noExplicitProxyDoesNotBypassTun = $true
    }
}

function Get-FwEnvironmentEvidence {
    $adapters = @()
    $errors = @()
    try {
        $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | ForEach-Object {
            [ordered]@{
                tag = Get-FwPrivateTag ($_.Name + ':' + $_.InterfaceDescription)
                interfaceIndex = $_.ifIndex; status = [string]$_.Status
                physical = [bool]$_.HardwareInterface
                tunCandidate = ($_.Name + ' ' + $_.InterfaceDescription) -match '(?i)wintun|\btun\b|mihomo|clash|fengwo|wireguard|tap-windows'
                mediaType = [string]$_.MediaType
            }
        })
    } catch { $errors += 'adapter_collection_unavailable' }
    $browsers = @()
    foreach ($hive in @('CurrentUser', 'LocalMachine')) {
        foreach ($browser in @('Google\Chrome', 'Microsoft\Edge')) {
            foreach ($name in @('ProxyMode', 'ProxyServer', 'ProxyPacUrl', 'ProxySettings')) {
                $value = Get-FwRegistryValue $hive 'Default' ('Software\Policies\' + $browser) $name
                $entry = [ordered]@{ hive = $hive; browser = $browser; name = $name; exists = $value.exists; error = $value.error }
                if ($name -eq 'ProxyMode' -and $value.value -in @('direct', 'auto_detect', 'pac_script', 'fixed_servers', 'system')) { $entry.mode = $value.value }
                elseif ($value.exists) { $entry.reference = ConvertTo-FwPrivateReference ([string]$value.value) }
                $browsers += $entry
            }
        }
    }
    $clientFiles = @()
    foreach ($process in @(Get-Process -Name FengWo, fengwoacc -ErrorAction SilentlyContinue)) {
        try {
            $path = $process.Path
            $file = Get-Item -LiteralPath $path -ErrorAction Stop
            $clientFiles += [ordered]@{ pid = $process.Id; name = $process.ProcessName; version = $file.VersionInfo.ProductVersion; exeSha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
        } catch { $errors += 'client_identity_unavailable' }
    }
    return [ordered]@{ adapters = $adapters; browserPolicies = $browsers; clientFiles = $clientFiles; errors = $errors; tunCandidatesAreNotProofOfTrafficRouting = $true }
}

Export-ModuleMember -Function Initialize-FwProxyNative, Get-FwPrivateTag, ConvertTo-FwPrivateReference, Get-FwProxySnapshot, Test-FwConfigurationEqual, Get-FwConfigurationFingerprint, Test-FwRegistryAgreement, Get-FwRepairGuard, ConvertTo-FwPublicSnapshot, Save-FwEncryptedBackup, Invoke-FwRefreshRepair, Get-FwPhaseAssessment, Get-FwEnvironmentEvidence
