[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'ClientDiscovery.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($module, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Discovery module syntax errors' }
$loadOutput = @(. $module)
if ($loadOutput.Count -ne 0) { throw 'Dot-source produced output' }
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:Passed = 0
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('fengwo-discovery-fixture-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)

function Assert-True([bool]$Value, [string]$Reason) { if (-not $Value) { throw $Reason } }
function Run-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:Passed++; Write-Host ('PASS ' + $Name) }
    catch { $script:Failures.Add($Name + ': ' + $_.Exception.Message); Write-Host ('FAIL ' + $Name) }
}
function Write-FixtureFile([string]$Relative, [string]$Text) {
    $path = Join-Path $fixture $Relative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Text, (New-Object Text.UTF8Encoding($false)))
    return $path
}
function Write-FixturePreferences($Config, [string]$Root='data') {
    $outer = @{ 'flutter.config'=($Config | ConvertTo-Json -Compress -Depth 20); 'flutter.version'=1; 'flutter.auth'='fixture-account-secret' }
    [void](Write-FixtureFile ($Root + '/shared_preferences.json') ($outer | ConvertTo-Json -Compress -Depth 20))
}
function Get-FixtureClient([string]$Root='data') {
    return [pscustomobject]@{ DataDirectories=@((Join-Path $fixture $Root)); ExePath=(Join-Path $fixture 'app/FengWo.exe') }
}
function New-FixtureLog([int]$Number) {
    return @{ timestamp='2026-10-08T12:00:00Z'; event='core.start_failed'; session='fixture-session-private'; sequence=$Number; fields=@{ error_code='CORE_START_FAILED'; error_type='TimeoutException'; stage='core_start'; status='failed'; port=7890; attempt=$Number; password='fixture-password-private'; url='https://user:pass@example.invalid/subscribe?token=fixture-token-private'; node='fixture-node-name'; payload=@{ account='fixture-account-private' } } }
}

try {
    Run-Case 'Module is UTF8 BOM and loads without side effects' {
        $bytes = [IO.File]::ReadAllBytes($module)
        Assert-True ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'UTF8 BOM missing'
        Assert-True ($loadOutput.Count -eq 0) 'Dot-source output is not empty'
    }
    Run-Case 'Active YAML and nested current profile are found without reading node credentials' {
        $active = Write-FixtureFile 'data/config.yaml' "proxies:`n  - name: fixture-account-private`n    server: private.example`n    password: fixture-password-private"
        $profile = Write-FixtureFile 'data/profiles/123.yaml' "proxies: []"
        Write-FixturePreferences @{ currentProfileId=123; appSettingProps=@{ testUrl='https://example.invalid/private-probe?probe=fixture-test-private'; openLogs=$true }; patchClashConfig=@{ mode='rule'; 'mixed-port'=7890; 'unified-delay'=$true; tun=@{ enable=$false }; secret='fixture-config-secret' }; networkProps=@{ systemProxy=$true }; davProps=@{ password='fixture-dav-password' } }
        $context = Get-FengWoLocalContext (Get-FixtureClient)
        Assert-True ($context.ActiveConfigPath -eq $active -and $context.ProfilePath -eq $profile) 'Current configuration paths incorrect'
        Assert-True ($context.TestUrl -eq 'https://example.invalid/private-probe?probe=fixture-test-private') 'Validated internal test URL lost'
        Assert-True ($context.Prefs.Parsed -and $context.Prefs.CurrentProfileId -eq 123 -and $context.Prefs.Mode -eq 'rule' -and $context.Prefs.SystemProxy) 'Safe preferences values missing'
        $safe = $context.Prefs | ConvertTo-Json -Compress -Depth 10
        Assert-True (-not $safe.Contains('fixture-') -and -not $safe.Contains('http') -and -not $safe.Contains('davProps')) 'Preferences summary leaked private data'
    }
    Run-Case 'Only current profile proxy caches are returned with a twenty file cap' {
        for ($index=0; $index -lt 25; $index++) { [void](Write-FixtureFile ('data/profiles/providers/123/proxies/' + $index.ToString('x32')) 'proxies: []') }
        [void](Write-FixtureFile 'data/profiles/providers/123/rules/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'payload: []')
        [void](Write-FixtureFile 'data/profiles/providers/456/proxies/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' 'proxies: []')
        [void](Write-FixtureFile 'data/profiles/providers/123/proxies/subscription-token.txt' 'private')
        $context = Get-FengWoLocalContext (Get-FixtureClient)
        Assert-True ($context.ProviderCachePaths.Count -eq 20) 'Provider file cap was not enforced'
        foreach ($path in $context.ProviderCachePaths) {
            Assert-True ($path.Contains((Join-Path '123' 'proxies')) -and [IO.Path]::GetFileName($path) -match '^[0-9a-f]{32}$') 'Unrelated provider file was returned'
        }
    }
    Run-Case 'Missing or traversal profile IDs do not enumerate historical profiles' {
        foreach ($id in @($null, '../456', '123/../../456', -1, '18446744073709551616')) {
            Write-FixturePreferences @{ currentProfileId=$id }
            $context = Get-FengWoLocalContext (Get-FixtureClient)
            Assert-True ($null -eq $context.ProfilePath -and $context.ProviderCachePaths.Count -eq 0) 'Invalid profile selected private historical files'
        }
        Write-FixturePreferences @{ currentProfileId=123 }
    }
    Run-Case 'Unsafe test URLs are rejected and never copied to preferences summary' {
        foreach ($url in @('file:///private/file','ftp://example.invalid/file','https://user:fixture-pass@example.invalid/probe','https://example.invalid/probe#fixture-secret',"https://example.invalid/`nheader",'https://example.invalid\fixture')) {
            Write-FixturePreferences @{ currentProfileId=123; appSettingProps=@{ testUrl=$url } }
            $context = Get-FengWoLocalContext (Get-FixtureClient)
            Assert-True ($null -eq $context.TestUrl -and $context.Prefs.TestUrlStatus -eq 'rejected') 'Unsafe test URL was accepted'
            Assert-True (-not ($context.Prefs | ConvertTo-Json -Compress).Contains('fixture')) 'Rejected URL leaked into summary'
        }
        foreach ($url in @('http://example.invalid/generate_204','https://[2001:db8::1]:8443/generate_204')) {
            Assert-True ($null -ne (ConvertTo-FwSafeTestUrl $url)) 'Valid HTTP URL rejected'
        }
    }
    Run-Case 'Malformed preferences preserve available active configuration' {
        [void](Write-FixtureFile 'data/shared_preferences.json' '{"flutter.config":"fixture-private-malformed')
        $context = Get-FengWoLocalContext (Get-FixtureClient)
        Assert-True ($context.ActiveConfigPath -and -not $context.Prefs.Parsed -and $null -eq $context.ProfilePath) 'Malformed preferences suppressed active config or fabricated profile'
        Assert-True (-not ($context.Prefs | ConvertTo-Json -Compress).Contains('fixture')) 'Raw parse failure leaked'
    }
    Run-Case 'Primary metadata data directory wins over a stale fallback configuration' {
        Write-FixturePreferences @{ currentProfileId=5 } 'primary'
        $profile = Write-FixtureFile 'primary/profiles/5.yaml' 'proxies: []'
        [void](Write-FixtureFile 'fallback/config.yaml' 'proxies: []')
        $client = [pscustomobject]@{ DataDirectories=@((Join-Path $fixture 'primary'), (Join-Path $fixture 'fallback')) }
        $context = Get-FengWoLocalContext $client
        Assert-True ($context.DataDirectory -eq (Join-Path $fixture 'primary') -and $context.ProfilePath -eq $profile -and $null -eq $context.ActiveConfigPath) 'Fallback was incorrectly attributed to current client'
    }
    Run-Case 'Sixteen MiB limit applies to active profile and provider files' {
        Write-FixturePreferences @{ currentProfileId=1 } 'oversize'
        foreach ($relative in @('oversize/config.yaml', 'oversize/profiles/1.yaml', 'oversize/profiles/providers/1/proxies/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')) {
            $path = Write-FixtureFile $relative ''
            $stream = [IO.File]::OpenWrite($path)
            try { $stream.SetLength(16777217) } finally { $stream.Dispose() }
        }
        $context = Get-FengWoLocalContext (Get-FixtureClient 'oversize')
        Assert-True ($null -eq $context.ActiveConfigPath -and $null -eq $context.ProfilePath -and $context.ProviderCachePaths.Count -eq 0) 'Oversize config was returned'
        $path = Join-Path $fixture 'oversize/config.yaml'
        $stream = [IO.File]::OpenWrite($path)
        try { $stream.SetLength(16777216) } finally { $stream.Dispose() }
        Assert-True ((Get-FengWoLocalContext (Get-FixtureClient 'oversize')).ActiveConfigPath -eq $path) 'Exact size limit was rejected'
    }
    Run-Case 'Logs retain latest thousand rows with safe hashed identities and omission counts' {
        $lines = @()
        for ($index=0; $index -lt 1200; $index++) { $lines += (New-FixtureLog $index | ConvertTo-Json -Depth 10 -Compress) }
        [void](Write-FixtureFile 'data/diagnostics/events.jsonl' ($lines -join "`n"))
        $context = Get-FengWoLocalContext (Get-FixtureClient)
        Assert-True ($context.Logs.Count -eq 1000 -and $context.Logs[0].fields.attempt -eq 200 -and $context.Logs[999].fields.attempt -eq 1199) 'Log tail bound was not respected'
        Assert-True ($context.Logs[0].fields.error_type -eq 'TimeoutException' -and $context.Logs[0].fields.port -eq 7890) 'Allowed diagnostic fields missing'
        $safe = $context.Logs | ConvertTo-Json -Compress -Depth 10
        Assert-True ($context.LogSnapshot.Stats.Truncated -and $context.LogSnapshot.Stats.TailOmittedLines -eq 200 -and $context.LogSnapshot.Stats.CountUnknown) 'Omitted history was not explicit'
        Assert-True ($context.Logs[0].session_ref -match '^[a-f0-9]{12}$' -and $context.Logs[0].event_id -match '^[a-f0-9]{24}$' -and $context.Logs[0].sequence -eq 200) 'Safe event identities missing'
        foreach ($private in @('fixture-', 'private.example', 'http', 'password', 'payload')) { Assert-True (-not $safe.Contains($private)) 'Private log field escaped allowlist' }
    }
    Run-Case 'Invalid log rows and secret-shaped allowed values are omitted' {
        $row = New-FixtureLog 1
        $row.fields.error_code = '11111111-2222-3333-4444-555555555555'
        $row.fields.stage = 'https://example.invalid/private'
        $row.fields.error_type = 'fixture-secret'
        $row.fields.port = 65536
        $lines = @('fixture-private-raw-log', '{broken', ($row | ConvertTo-Json -Depth 10 -Compress), '{"timestamp":"fixture-private-time","event":"core.failed"}', '{"timestamp":"2026-10-08T00:00:00Z","event":"https://example.invalid/token"}')
        [void](Write-FixtureFile 'data/diagnostics/events.jsonl' ($lines -join "`n"))
        $context = Get-FengWoLocalContext (Get-FixtureClient)
        Assert-True ($context.Logs.Count -eq 1) 'Invalid log rows were accepted'
        $safe = $context.Logs | ConvertTo-Json -Compress -Depth 10
        foreach ($private in @('fixture-', '11111111', 'http', '65536')) { Assert-True (-not $safe.Contains($private)) 'Private or invalid allowed-field value leaked'
        }
    }
    Run-Case 'All three recognized rotation files are merged without scanning other logs' {
        $old = Write-FixtureFile 'data/diagnostics/events.jsonl' (New-FixtureLog 1 | ConvertTo-Json -Depth 10 -Compress)
        $latest = Write-FixtureFile 'data/diagnostics/events.jsonl.1' (New-FixtureLog 2 | ConvertTo-Json -Depth 10 -Compress)
        [IO.File]::SetLastWriteTimeUtc($old, [DateTime]::UtcNow.AddMinutes(-10))
        [IO.File]::SetLastWriteTimeUtc($latest, [DateTime]::UtcNow)
        [void](Write-FixtureFile 'data/diagnostics/other-private.jsonl' (New-FixtureLog 3 | ConvertTo-Json -Depth 10 -Compress))
        $context = Get-FengWoLocalContext (Get-FixtureClient)
        Assert-True ($context.LogPath -eq $latest -and $context.Logs.Count -eq 2 -and $context.LogSnapshot.Stats.FilesRead -eq 2 -and @($context.Logs | Where-Object { $_.fields.attempt -eq 3 }).Count -eq 0) 'Rotation merge lost history or read an unrelated log'
    }
    Run-Case 'API failures retain safe stage reasons references and native codes' {
        $row = New-FixtureLog 11
        $row.event = 'api.secure_gateway.failed'
        $row.fields = @{ stage='secure_gateway'; reason='tls'; tls_reason='missing_issuer'; error_code='subscription_unavailable'; subscription_v2_code='subscription_unavailable'; failure='noAvailableHost'; endpoint_ref='abcdef123456'; next_endpoint_ref='123456abcdef'; request_ref='fedcba987654'; attempt_id='mhfq5jdf5_1'; elapsed_ms=1201; http_status=403; os_error_code=10060; win32_error=5; candidate_count=3; node_count=90; content_bytes=60001; running_requested=$true; system_proxy_requested=$true; mode='rule'; command='private command'; message='fixture-private-error'; error='fixture-private-error' }
        $path = Write-FixtureFile 'api/diagnostics/events.jsonl' ($row | ConvertTo-Json -Depth 10 -Compress)
        $rows = @(Get-FwSafeLogRows ([IO.FileInfo]$path))
        Assert-True ($rows.Count -eq 1) 'API event was dropped'
        $f = $rows[0].fields
        Assert-True ($f.reason -eq 'tls' -and $f.tls_reason -eq 'missing_issuer' -and $f.subscription_v2_code -eq 'subscription_unavailable') 'Failure category was dropped'
        Assert-True ($f.endpoint_ref -eq 'abcdef123456' -and $f.request_ref -eq 'fedcba987654' -and $f.attempt_id -eq 'mhfq5jdf5_1') 'Safe endpoint correlation was dropped'
        Assert-True ($f.win32_error -eq 5 -and $f.os_error_code -eq 10060 -and $f.node_count -eq 90 -and $f.content_bytes -eq 60001 -and $f.system_proxy_requested) 'Operational metrics were dropped'
        Assert-True (-not ($rows | ConvertTo-Json -Depth 10 -Compress).Contains('fixture-')) 'Raw error text leaked'
    }
    Run-Case 'Unsafe reference values cannot impersonate safe endpoint hashes or attempt IDs' {
        $row = New-FixtureLog 12
        $row.fields.endpoint_ref = 'https://private.example/secret'
        $row.fields.request_ref = '11111111-2222-3333-4444-555555555555'
        $row.fields.attempt_id = 'fixture-password-private'
        $row.fields.reason = 'https://private.example'
        $path = Write-FixtureFile 'api/diagnostics/events.jsonl' ($row | ConvertTo-Json -Depth 10 -Compress)
        $rows = @(Get-FwSafeLogRows ([IO.FileInfo]$path))
        $safe = $rows | ConvertTo-Json -Depth 10 -Compress
        foreach ($private in @('private.example', 'fixture-', '11111111', 'endpoint_ref', 'request_ref', 'attempt_id')) { Assert-True (-not $safe.Contains($private)) 'Untrusted reference or reason leaked' }
    }
    Run-Case 'Nested listener failures retain only explicit bind result fields' {
        $row = New-FixtureLog 13
        $row.event = 'core.listener.failed'
        $row.fields = @{ operation='setupConfig'; details=@{ stage='bind_failed'; listener='mixed'; protocol='tcp'; port=7890; tcp_ready=$false; udp_ready=$true; reason='address_in_use'; os_error_code=10048; bind_address='private.example'; error_message='fixture-secret'; server='private.example'; token='fixture-token' } }
        $path = Write-FixtureFile 'listener/diagnostics/events.jsonl' ($row | ConvertTo-Json -Depth 10 -Compress)
        $rows = @(Get-FwSafeLogRows ([IO.FileInfo]$path))
        Assert-True ($rows[0].fields.details.reason -eq 'address_in_use' -and $rows[0].fields.details.os_error_code -eq 10048 -and $rows[0].fields.details.port -eq 7890 -and -not $rows[0].fields.details.tcp_ready) 'Structured bind evidence missing'
        $safe = $rows | ConvertTo-Json -Depth 10 -Compress
        Assert-True (-not $safe.Contains('fixture') -and -not $safe.Contains('private.example') -and -not $safe.Contains('bind_address')) 'Nested text escaped allowlist'
    }
    Run-Case 'Rotation merge deduplicates sequences and sorts actual UTC timestamps' {
        $a = New-FixtureLog 20; $a.timestamp='2026-10-09T10:00:00+08:00'; $a.event='subscription.pipeline.started'
        $b = New-FixtureLog 21; $b.timestamp='2026-10-09T02:00:01Z'; $b.event='subscription.pipeline.failed'; $b.fields.error_code='subscription_unavailable'
        $c = New-FixtureLog 22; $c.timestamp='2026-10-09T02:00:02Z'; $c.event='system_proxy.apply.completed'
        [void](Write-FixtureFile 'timeline/diagnostics/events.jsonl.2' ($a | ConvertTo-Json -Depth 10 -Compress))
        [void](Write-FixtureFile 'timeline/diagnostics/events.jsonl.1' (($a | ConvertTo-Json -Depth 10 -Compress) + "`n" + ($b | ConvertTo-Json -Depth 10 -Compress)))
        [void](Write-FixtureFile 'timeline/diagnostics/events.jsonl' (($c | ConvertTo-Json -Depth 10 -Compress) + "`n{invalid"))
        [void](Write-FixtureFile 'timeline/diagnostics/private.jsonl' ($c | ConvertTo-Json -Depth 10 -Compress))
        $snapshot = Get-FwDiagnosticTimeline -Root (Join-Path $fixture 'timeline') -Limit 1000
        Assert-True ($snapshot.Rows.Count -eq 3 -and $snapshot.Stats.FilesRead -eq 3 -and $snapshot.Stats.DuplicateRows -eq 1 -and $snapshot.Stats.InvalidRows -eq 1) 'Merge counts or file boundary incorrect'
        Assert-True ($snapshot.Rows[0].sequence -eq 20 -and $snapshot.Rows[2].sequence -eq 22 -and $snapshot.Rows[0].timestamp.StartsWith('2026-10-09T02:00:00')) 'UTC event ordering failed'
        $limited = Get-FwDiagnosticTimeline -Root (Join-Path $fixture 'timeline') -Limit 2
        Assert-True ($limited.Rows.Count -eq 2 -and $limited.Rows[0].sequence -eq 21 -and $limited.Stats.DroppedRows -eq 1 -and $limited.Stats.Truncated) 'Global cap silently discarded history'
    }
    Run-Case 'Same timestamps and sequences from distinct sessions remain distinct' {
        $a=New-FixtureLog 30; $b=New-FixtureLog 30; $b.session='second-private-session'
        [void](Write-FixtureFile 'sessions/diagnostics/events.jsonl' (($a | ConvertTo-Json -Depth 10 -Compress) + "`n" + ($b | ConvertTo-Json -Depth 10 -Compress)))
        $snapshot = Get-FwDiagnosticTimeline -Root (Join-Path $fixture 'sessions')
        Assert-True ($snapshot.Rows.Count -eq 2 -and $snapshot.Rows[0].session_ref -ne $snapshot.Rows[1].session_ref) 'Separate sessions were conflated'
        Assert-True (-not ($snapshot | ConvertTo-Json -Depth 10 -Compress).Contains('private-session')) 'Raw session identity leaked'
    }
    Run-Case 'Fresh valid fallback preferences supersede stale roaming data with ambiguity recorded' {
        Write-FixturePreferences @{ currentProfileId=31 } 'old-root'
        Write-FixturePreferences @{ currentProfileId=32 } 'new-root'
        [void](Write-FixtureFile 'old-root/config.yaml' 'proxies: []')
        $newProfile = Write-FixtureFile 'new-root/profiles/32.yaml' 'proxies: []'
        [IO.File]::SetLastWriteTimeUtc((Join-Path $fixture 'old-root/shared_preferences.json'), [DateTime]::UtcNow.AddDays(-10))
        [IO.File]::SetLastWriteTimeUtc((Join-Path $fixture 'new-root/shared_preferences.json'), [DateTime]::UtcNow)
        $client = [pscustomobject]@{ DataDirectories=@((Join-Path $fixture 'old-root'), (Join-Path $fixture 'new-root')) }
        $context = Get-FengWoLocalContext $client
        Assert-True ($context.ProfilePath -eq $newProfile -and $context.DataDirectorySelection.Ambiguous -and $context.DataDirectorySelection.RecognizedCandidateCount -eq 2 -and -not $context.DataDirectorySelection.CurrentDirectoryConfirmed) 'Stale root was chosen or heuristic stated as proven'
    }
    Run-Case 'Recent recognized diagnostic log outranks older preference write times' {
        [void](Write-FixtureFile 'old-root/diagnostics/events.jsonl' (New-FixtureLog 31 | ConvertTo-Json -Depth 10 -Compress))
        [IO.File]::SetLastWriteTimeUtc((Join-Path $fixture 'old-root/diagnostics/events.jsonl'), [DateTime]::UtcNow.AddMinutes(1))
        $context = Get-FengWoLocalContext ([pscustomobject]@{ DataDirectories=@((Join-Path $fixture 'old-root'), (Join-Path $fixture 'new-root')) })
        Assert-True ($context.DataDirectory -eq (Join-Path $fixture 'old-root') -and $context.DataDirectorySelection.Ambiguous) 'Recognized log freshness was ignored'
    }
    Run-Case 'Unrecognized empty preferences and invalid log text do not override valid identity roots' {
        Write-FixturePreferences @{ currentProfileId=41 } 'valid-old-root'
        [IO.File]::SetLastWriteTimeUtc((Join-Path $fixture 'valid-old-root/shared_preferences.json'), [DateTime]::UtcNow.AddDays(-10))
        [void](Write-FixtureFile 'invalid-new-root/shared_preferences.json' '{}')
        [void](Write-FixtureFile 'invalid-new-root/diagnostics/events.jsonl' 'fixture-private-malformed-log')
        [void](Write-FixtureFile 'invalid-new-root/config.yaml' 'proxies: []')
        $context=Get-FengWoLocalContext ([pscustomobject]@{ DataDirectories=@((Join-Path $fixture 'valid-old-root'),(Join-Path $fixture 'invalid-new-root')) })
        Assert-True ($context.DataDirectory -eq (Join-Path $fixture 'valid-old-root') -and $context.Prefs.Parsed) 'Malformed recent root outranked validated preferences'
    }
    Run-Case 'Matched offline account exposes only explicitly cached subscription metadata' {
        $cache=@{ verified_at='2026-10-08T10:00:00Z'; subscription=@{ email='Fixture.User@Example.invalid'; expired_at=1791504000L; u=1000L; d=2000L; transfer_enable=10000L; token='fixture-private-token'; uuid='11111111-2222-3333-4444-555555555555'; subscribe_url='https://example.invalid/subscription?token=fixture-private'; plan=@{name='fixture-private-plan'} }; nodes=@(@{password='fixture-node-secret'}) }
        $prefs=@{ 'flutter.xboard.email'='fixture.user@example.invalid'; 'flutter.xboard.session_account'='FIXTURE.USER@example.invalid'; 'flutter.xboard.offline_cache'=($cache | ConvertTo-Json -Depth 12 -Compress); 'flutter.xboard.token'='fixture-top-token'; 'flutter.xboard.password'='fixture-top-password' }
        $account=Get-FwCachedAccountSummary $prefs
        Assert-True ($account.account_match -eq 'MATCHED' -and $account.account_ref -match '^[a-f0-9]{12}$' -and $account.is_cached_source -and $account.server_freshness -eq 'UNVERIFIED_CACHE') 'Cached account provenance missing'
        Assert-True ($account.total_bytes -eq 10000 -and $account.used_bytes -eq 3000 -and $account.remaining_bytes -eq 7000 -and $account.expires_at_epoch_seconds -eq 1791504000L -and $account.verified_at.StartsWith('2026-10-08T10:00:00')) 'Real cache schema was not parsed'
        $safe=$account | ConvertTo-Json -Depth 10 -Compress
        foreach ($private in @('fixture-', 'example.invalid', '11111111', 'password', 'token', 'plan')) { Assert-True (-not $safe.Contains($private)) 'Account metadata leaked private values' }
        [void](Write-FixtureFile 'account/shared_preferences.json' ($prefs | ConvertTo-Json -Depth 12 -Compress))
        $context=Get-FengWoLocalContext (Get-FixtureClient 'account')
        Assert-True ($context.Account.account_ref -eq $account.account_ref -and $context.Account.remaining_bytes -eq 7000) 'Context omitted cached account metadata'
    }
    Run-Case 'Cached account mismatch or conflicting stored identities never assigns quota to current user' {
        $cache=@{ verified_at='2026-10-08T10:00:00Z'; subscription=@{ email='old@example.invalid'; expired_at=1791504000L; u=1000L; d=2000L; transfer_enable=10000L } }
        foreach ($identities in @(@{'flutter.xboard.email'='new@example.invalid'}, @{'flutter.xboard.email'='old@example.invalid'; 'flutter.xboard.session_account'='new@example.invalid'}, @{})) {
            $prefs=$identities.Clone(); $prefs['flutter.xboard.offline_cache']=($cache | ConvertTo-Json -Depth 10 -Compress)
            $account=Get-FwCachedAccountSummary $prefs
            Assert-True ($account.account_match -eq 'UNKNOWN_ACCOUNT_MATCH' -and $null -eq $account.PSObject.Properties['remaining_bytes'] -and $null -eq $account.PSObject.Properties['expires_at_utc'] -and $null -eq $account.verified_at) 'Foreign cached quota was attributed to current account'
        }
    }
    Run-Case 'Malformed oversized future and unsafe cache fields remain explicitly unverified' {
        foreach ($bad in @('{broken', ('x' * 4194305))) {
            $account=Get-FwCachedAccountSummary @{'flutter.xboard.email'='old@example.invalid'; 'flutter.xboard.offline_cache'=$bad}
            Assert-True (-not $account.cache_parsed -and $account.account_match -eq 'UNKNOWN_ACCOUNT_MATCH') 'Malformed cache was trusted'
        }
        $cache=@{ verified_at='2999-01-01T00:00:00Z'; subscription=@{ email='old@example.invalid'; expired_at=-1; u=-1; d=2000; transfer_enable=10000 } }
        $account=Get-FwCachedAccountSummary @{'flutter.xboard.email'='old@example.invalid'; 'flutter.xboard.offline_cache'=($cache | ConvertTo-Json -Depth 10 -Compress)}
        Assert-True ($account.account_match -eq 'MATCHED' -and -not $account.cache_time_valid -and $null -eq $account.PSObject.Properties['remaining_bytes'] -and $null -eq $account.PSObject.Properties['expires_at_utc']) 'Future or negative cache values were presented as verified'
        $cache.subscription.expired_at=$null; $cache.subscription.u=11000
        $account=Get-FwCachedAccountSummary @{'flutter.xboard.session_account'='old@example.invalid'; 'flutter.xboard.offline_cache'=($cache | ConvertTo-Json -Depth 10 -Compress)}
        Assert-True ($account.cached_never_expires -and $account.remaining_bytes -eq 0 -and $account.cached_traffic_exhausted) 'Unlimited expiry or exhausted cached traffic was misclassified'
    }
    Run-Case 'Symbolic link files and parent directories cannot escape data root' {
        Write-FixturePreferences @{ currentProfileId=7 } 'linked'
        [void](Write-FixtureFile 'outside/config.yaml' 'private-outside')
        [void](Write-FixtureFile 'outside/7/proxies/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'private-outside')
        [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'linked/profiles'))
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $fixture 'linked/config.yaml') -Target (Join-Path $fixture 'outside/config.yaml'))
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path $fixture 'linked/profiles/providers') -Target (Join-Path $fixture 'outside'))
        $context = Get-FengWoLocalContext (Get-FixtureClient 'linked')
        Assert-True ($null -eq $context.ActiveConfigPath -and $context.ProviderCachePaths.Count -eq 0) 'Symlink escaped data root'
        Assert-True ($null -eq (Get-FwBoundedFile (Join-Path $fixture 'data') '../outside/config.yaml')) 'Traversal escaped data root'
    }
    Run-Case 'Discovery prefers running branded client deduplicates and excludes upstream' {
        $script:FixtureRunning = Write-FixtureFile 'running/FengWo.exe' ''
        $script:FixtureInstalled = Write-FixtureFile 'installed/fengwoacc.exe' ''
        $script:FixtureOriginal = Write-FixtureFile 'original/FlClash.exe' ''
        $script:FixtureRenamed = Write-FixtureFile 'renamed/FengWo.exe' ''
        function Get-FwRunningClientRecords {
            [pscustomobject]@{ Path=$script:FixtureRunning; ProcessId=1234; Source='process' }
            [pscustomobject]@{ Path=$script:FixtureOriginal; ProcessId=9876; Source='process' }
            [pscustomobject]@{ Path=$script:FixtureRenamed; ProcessId=9877; Source='process' }
        }
        function Get-FwRegistryClientRecords {
            [pscustomobject]@{ Path=$script:FixtureInstalled; ProcessId=0; Source='registry' }
            [pscustomobject]@{ Path=$script:FixtureRunning; ProcessId=0; Source='registry' }
        }
        function Get-FwShortcutClientRecords { [pscustomobject]@{ Path=$script:FixtureRunning; ProcessId=0; Source='shortcut' } }
        function Get-FwKnownClientRecords {}
        function Get-FwClientVersion([string]$Path) {
            if ($Path -eq $script:FixtureRenamed) { return [pscustomobject]@{ ProductName='FlClash'; OriginalFilename='FlClash.exe'; CompanyName='com.follow'; FileVersion='1.0.8' } }
            return [pscustomobject]@{ ProductName='蜂窝加速器'; OriginalFilename=[IO.Path]::GetFileName($Path); CompanyName='com.follow'; FileVersion='1.0.8' }
        }
        $clients = @(Find-FengWoClients)
        Assert-True ($clients.Count -eq 2 -and $clients[0].ExePath -eq $script:FixtureRunning) 'Running branded client was not prioritized or original was accepted'
        Assert-True ($clients[0].ProcessIds.Count -eq 1 -and $clients[0].ProcessIds[0] -eq 1234 -and $clients[0].DiscoverySources.Count -eq 3) 'Client deduplication lost evidence'
        Assert-True (@($clients[0].DataDirectories | Select-Object -Unique).Count -eq $clients[0].DataDirectories.Count) 'Data directories were duplicated'
    }
    Run-Case 'Directory names are sanitized and missing roots return an empty safe context' {
        Assert-True ((ConvertTo-FwDirectoryComponent 'company/bad:*? . ') -eq 'company_bad___ ') 'Metadata sanitization does not match path provider'
        $context = Get-FengWoLocalContext ([pscustomobject]@{ DataDirectories=@((Join-Path $fixture 'missing')) })
        Assert-True ($null -eq $context.ActiveConfigPath -and $context.ProviderCachePaths.Count -eq 0 -and $context.Logs.Count -eq 0 -and -not $context.Prefs.Found) 'Missing root fabricated evidence'
        Assert-True ($null -eq (Get-FwLocalFullPath '\\server\share\FengWo.exe')) 'Network path was accepted'
    }
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('RESULT passed=' + $script:Passed + ' failed=' + $script:Failures.Count)
foreach ($failure in $script:Failures) { Write-Host $failure }
if ($script:Failures.Count -gt 0) { exit 1 }
