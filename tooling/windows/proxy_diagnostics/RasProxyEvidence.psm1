Set-StrictMode -Version 2.0

function Get-FwBypassTokens {
    param([AllowNull()][string]$Value)
    return @(([string]$Value).Split(';') | ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_.Length -gt 0 } | Sort-Object -Unique)
}

function Compare-FwProxyViews {
    param($Reference, $Observed)
    if (-not $Reference.Success -or -not $Observed.Success -or
        $null -eq $Reference.Configuration -or $null -eq $Observed.Configuration) {
        return [ordered]@{ comparable = $false; reason = 'query_failed' }
    }
    $left = $Reference.Configuration
    $right = $Observed.Configuration
    $expected = @(Get-FwBypassTokens $left.Bypass)
    $actual = @(Get-FwBypassTokens $right.Bypass)
    $missing = @($expected | Where-Object { $actual -cnotcontains $_ })
    $extra = @($actual | Where-Object { $expected -cnotcontains $_ })
    return [ordered]@{
        comparable = $true
        flagsEqual = [uint32]$left.Flags -eq [uint32]$right.Flags
        serverEqual = [string]::Equals($left.Server, $right.Server, [StringComparison]::Ordinal)
        bypassRawEqual = [string]::Equals($left.Bypass, $right.Bypass, [StringComparison]::Ordinal)
        bypassTokenSetEqual = $missing.Count -eq 0 -and $extra.Count -eq 0
        referenceBypassRuleCount = $expected.Count
        observedBypassRuleCount = $actual.Count
        missingBypassRuleCount = $missing.Count
        additionalBypassRuleCount = $extra.Count
        pacEqual = [string]::Equals($left.Pac, $right.Pac, [StringComparison]::Ordinal)
        comparisonDoesNotAuthorizeIgnoringBypass = $true
    }
}

function ConvertTo-FwRasQuery {
    param($Query, [int]$Port)
    $public = [ordered]@{ success = [bool]$Query.Success; error = [int]$Query.Error; optionError = [int]$Query.OptionError }
    if ($Query.Success -and $null -ne $Query.Configuration) {
        $value = $Query.Configuration
        $public.flags = [uint32]$value.Flags
        $public.manualEnabled = ([uint32]$value.Flags -band 2) -ne 0
        $public.automaticEnabled = ([uint32]$value.Flags -band 12) -ne 0
        $public.fengwoEndpoint = [string]$value.Server -ceq ('127.0.0.1:' + $Port)
        $public.server = ConvertTo-FwPrivateReference $value.Server
        $public.bypass = ConvertTo-FwPrivateReference $value.Bypass
        $public.bypass.ruleCount = @(Get-FwBypassTokens $value.Bypass).Count
        $public.pac = ConvertTo-FwPrivateReference $value.Pac
    }
    return $public
}

function Get-FwSavedProxyConnections {
    $root = $null
    $key = $null
    try {
        $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Default)
        $key = $root.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections', $false)
        $names = if ($null -eq $key) { @() } else {
            @($key.GetValueNames() | Where-Object {
                $_ -and $_ -notin @('DefaultConnectionSettings', 'SavedLegacySettings') -and
                $key.GetValueKind($_) -eq [Microsoft.Win32.RegistryValueKind]::Binary
            })
        }
        return [ordered]@{ success = $true; names = @($names); error = 0 }
    } catch {
        return [ordered]@{ success = $false; names = @(); error = $_.Exception.HResult }
    } finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $root) { $root.Dispose() }
    }
}

function Get-FwRasProxyEvidence {
    param(
        [ValidateRange(1, 65535)][int]$Port = 17980,
        [string[]]$ConnectionName = @(),
        [scriptblock]$ReadNames = { Get-FwSavedProxyConnections },
        [scriptblock]$Query = {
            param($Name, $Ansi, $Ui)
            Initialize-FwProxyNative
            [FengWoProxyDiagnostics.Native]::QueryConnection($Name, $Ansi, $Ui)
        }
    )
    $discovery = & $ReadNames
    $candidates = @(@($discovery.names) + @($ConnectionName) |
        Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Unique)
    $names = @('') + @($candidates | Select-Object -First 64)
    $public = New-Object 'Collections.Generic.List[object]'
    $defaultQueries = $null
    foreach ($name in $names) {
        $queries = [ordered]@{}
        foreach ($variant in @('wideUi', 'ansiUi', 'wideFlags', 'ansiFlags')) {
            try {
                $queries[$variant] = & $Query $name ($variant.StartsWith('ansi')) ($variant.EndsWith('Ui'))
            } catch {
                $queries[$variant] = [pscustomobject]@{ Success = $false; Error = $_.Exception.HResult; OptionError = 0; Configuration = $null }
            }
        }
        if ($name -ceq '') { $defaultQueries = $queries }
        $safeQueries = [ordered]@{}
        foreach ($variant in $queries.Keys) { $safeQueries[$variant] = ConvertTo-FwRasQuery $queries[$variant] $Port }
        $relativeToDefault = [ordered]@{}
        foreach ($variant in $queries.Keys) { $relativeToDefault[$variant] = Compare-FwProxyViews $defaultQueries[$variant] $queries[$variant] }
        $public.Add([ordered]@{
            kind = if ($name -ceq '') { 'default' } else { 'saved_connection_candidate' }
            connection = ConvertTo-FwPrivateReference $name
            activityVerified = $false
            queries = $safeQueries
            comparisons = [ordered]@{
                wideAnsiUi = Compare-FwProxyViews $queries.wideUi $queries.ansiUi
                wideAnsiFlags = Compare-FwProxyViews $queries.wideFlags $queries.ansiFlags
                wideUiFlags = Compare-FwProxyViews $queries.wideUi $queries.wideFlags
                ansiUiFlags = Compare-FwProxyViews $queries.ansiUi $queries.ansiFlags
                relativeToDefault = $relativeToDefault
            }
        })
    }
    return [ordered]@{
        atUtc = [DateTime]::UtcNow.ToString('o')
        proxyValuesWritten = $false
        refreshPerformed = $false
        networkProbePerformed = $false
        discovery = [ordered]@{ success = $discovery.success; error = $discovery.error; candidateCount = $candidates.Count; truncated = $candidates.Count -gt 64 }
        connections = @($public.ToArray())
        limitations = @(
            'Saved names are candidates, not proof of an active RAS connection.'
            'Sequential API queries are not an atomic snapshot; a client may change settings between reads.'
            'WinINet queries may resynchronize cached settings; this is not passive writer attribution.'
            'The default connection is a comparison reference, not the requested client configuration.'
            'Equal normalized token sets are diagnostic only; no client verification is bypassed.'
            'This tool does not test connection, disconnection, TUN cleanup or connectivity.'
        )
    }
}

Export-ModuleMember -Function Get-FwBypassTokens, Compare-FwProxyViews, Get-FwRasProxyEvidence
