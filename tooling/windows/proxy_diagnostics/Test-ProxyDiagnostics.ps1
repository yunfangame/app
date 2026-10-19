param([string]$OutputDirectory = '', [switch]$Portable)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'ProxyDiagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProxyWriterTrace.psm1') -Force
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:TEMP ('FengWo-Proxy-Tests-' + [Guid]::NewGuid().ToString('N')) }
$null = [IO.Directory]::CreateDirectory($OutputDirectory)
$checks = New-Object 'Collections.Generic.List[object]'
function Assert-Check {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $checks.Add([ordered]@{ name = $Name; passed = $true })
    Write-Host ('PASS: ' + $Name)
}
function New-Snapshot {
    $config = [pscustomobject]@{ Flags = [uint32]13; Server = 'secret-user:secret-pass@corporate.invalid:8080'; Bypass = '*.secret-company.invalid;<local>'; Pac = 'https://secret-user:secret-pass@private.invalid/pac?token=private-token' }
    $queries = [ordered]@{}
    foreach ($name in @('wideUi', 'ansiUi', 'wideEffective', 'ansiEffective')) {
        $queries[$name] = [pscustomobject]@{ Success = $true; Error = 0; OptionError = 0; Configuration = ($config | ConvertTo-Json | ConvertFrom-Json) }
    }
    $registry = [ordered]@{}
    foreach ($hive in @('CurrentUser', 'LocalMachine')) {
        $registry[$hive] = [ordered]@{
            ProxyEnable = [ordered]@{ exists = $true; kind = 'DWord'; value = 0; error = 0 }
            ProxyServer = [ordered]@{ exists = $true; kind = 'String'; value = $config.Server; error = 0 }
            ProxyOverride = [ordered]@{ exists = $true; kind = 'String'; value = $config.Bypass; error = 0 }
            AutoConfigURL = [ordered]@{ exists = $true; kind = 'String'; value = $config.Pac; error = 0 }
        }
    }
    return [ordered]@{ atUtc = [DateTime]::UtcNow.ToString('o'); queries = $queries; registry = $registry; policies = @(); processes = @() }
}
function Copy-Snapshot {
    param($Value)
    $bytes = [Management.Automation.PSSerializer]::Serialize($Value, 20)
    return [Management.Automation.PSSerializer]::Deserialize($bytes)
}
$fixture = New-Snapshot
Assert-Check ((Get-FwRepairGuard $fixture) -eq 'allowed') 'Unmanaged PAC fixture permits cache refresh without clearing PAC'
$public = ConvertTo-FwPublicSnapshot $fixture
$text = ConvertTo-Json -InputObject $public -Depth 24
Assert-Check ($text -notmatch 'secret-user|secret-pass|secret-company|private\.invalid|private-token|corporate\.invalid') 'Public report excludes proxy credentials, PAC content and bypass names'
Assert-Check ($public.queries.wideUi.flags -eq 13 -and $public.queries.wideUi.automaticEnabled -and -not $public.queries.wideUi.manualEnabled) 'Manual-off automatic-proxy state is not interpreted as direct routing'
Assert-Check ((ConvertTo-FwPrivateReference $null).length -eq 0) 'Null references are safely redacted'
$bad = Copy-Snapshot $fixture
$bad.policies = @([ordered]@{ data = [ordered]@{ exists = $true; error = 0 } })
Assert-Check ((Get-FwRepairGuard $bad) -eq 'managed_proxy_policy_present') 'Managed policy blocks refresh repair'
$bad.policies[0].data.error = -1
Assert-Check ((Get-FwRepairGuard $bad) -eq 'policy_unreadable') 'Unreadable policy blocks repair'
$bad = Copy-Snapshot $fixture
$bad.processes = @(@{ name = 'FengWo'; pid = 1 })
Assert-Check ((Get-FwRepairGuard $bad) -eq 'close_proxy_clients_first') 'Running proxy client blocks repair'
$bad = Copy-Snapshot $fixture
$bad.queries.ansiUi.Configuration.Flags = 3
Assert-Check ((Get-FwRepairGuard $bad) -eq 'wide_ansi_disagree') 'Conflicting Unicode and ANSI views block repair'
$bad = Copy-Snapshot $fixture
$bad.queries.wideUi.Success = $false
Assert-Check ((Get-FwRepairGuard $bad) -eq 'wininet_ui_read_failed') 'Unreadable WinINet UI state blocks repair'
$bad = Copy-Snapshot $fixture
$bad.registry.CurrentUser.ProxyEnable.value = 1
Assert-Check ((Get-FwRepairGuard $bad) -eq 'wininet_registry_disagree') 'WinINet and registry mismatch is classified separately'
$script:calls = @()
$script:backups = 0
$read = { $fixture }.GetNewClosure()
$refresh = { param($Option) $script:calls += $Option; [pscustomobject]@{ Success = $true; Error = 0 } }
$backup = { param($Snapshot) $script:backups++ }
$result = Invoke-FwRefreshRepair -Consent $false -ReadSnapshot $read -Refresh $refresh -Backup $backup
Assert-Check ($result.status -eq 'consent_required' -and $script:calls.Count -eq 0 -and $script:backups -eq 0) 'Repair requires explicit consent and otherwise performs no notifications or backup'
$result = Invoke-FwRefreshRepair -Consent $true -ReadSnapshot $read -Refresh $refresh -Backup $backup
Assert-Check ($result.status -eq 'refresh_completed_configuration_preserved' -and ($script:calls -join ',') -eq '95,39,37' -and $script:backups -eq 1 -and -not $result.proxyConnectionVerified) 'Refresh only uses allowed notifications and does not claim a verified connection'
$script:calls = @()
$thrown = $false
try { $null = Invoke-FwRefreshRepair -Consent $true -ReadSnapshot $read -Refresh $refresh -Backup { throw 'Backup unavailable' } } catch { $thrown = $true }
Assert-Check ($thrown -and $script:calls.Count -eq 0) 'Backup failure prevents refresh'
$raceState = @{ reads = 0 }
$racing = Copy-Snapshot $fixture
$racing.registry.CurrentUser.AutoConfigURL.value = 'https://another-application.invalid/pac'
$racedRead = { $raceState.reads++; if ($raceState.reads -eq 1) { $fixture } else { $racing } }.GetNewClosure()
$result = Invoke-FwRefreshRepair -Consent $true -ReadSnapshot $racedRead -Refresh $refresh -Backup $backup
Assert-Check ($result.status -eq 'state_changed_before_refresh' -and $script:calls.Count -eq 0) 'Concurrent changes prevent refresh and are not overwritten'
$connected = Copy-Snapshot $fixture
foreach ($name in @('wideUi', 'ansiUi', 'wideEffective', 'ansiEffective')) { $connected.queries[$name].Configuration.Flags = 3; $connected.queries[$name].Configuration.Server = '127.0.0.1:17980' }
$connected.registry.CurrentUser.ProxyEnable.value = 1
$connected.registry.CurrentUser.ProxyServer.value = '127.0.0.1:17980'
Assert-Check ((Get-FwPhaseAssessment 'connected' $connected $fixture).passed) 'Coherent loopback manual proxy passes the connected phase'
Assert-Check (-not (Get-FwPhaseAssessment 'connected' $fixture $fixture).passed) 'Original automatic configuration does not pass as a manual-proxy connection'
Assert-Check ((Get-FwPhaseAssessment 'disconnected' $fixture $fixture).passed) 'Disconnect restores original PAC rather than deleting it'
Assert-Check ((Get-FwPhaseAssessment 'exited' $fixture $fixture).passed) 'Exit requires a restored original configuration'
$fixture.processes = @(@{ name = 'FengWo'; pid = 123 })
Assert-Check (-not (Get-FwPhaseAssessment 'exited' $fixture $fixture).passed) 'A running client fails the tray-exit assertion'
$fixture.processes = @()
$on = ConvertTo-FwPublicSnapshot $connected
$off = ConvertTo-FwPublicSnapshot $fixture
$on.atUtc = '2026-10-19T15:00:00.000Z'
$off.atUtc = '2026-10-19T15:00:01.000Z'
$writer = @{ atUtc = '2026-10-19T15:00:00.500Z'; valueName = 'ProxyEnable'; nativeStatus = '0x0'; processId = 123; processName = 'fixture.exe' }
$transitions = @(Get-FwDisableTransitions @($on, $off) @($writer))
Assert-Check ($transitions.Count -eq 1 -and $transitions[0].candidates.Count -eq 1 -and -not $transitions[0].causalityConfirmed) 'Off transition correlates candidate writers without inventing confirmed causality'
$transitions = @(Get-FwDisableTransitions @($on, $off))
Assert-Check ($transitions[0].status -eq 'writer_not_determined') 'Uncaptured writers remain unknown'
$transitions = @(Get-FwDisableTransitions @($off, $off) @($writer))
Assert-Check ($transitions.Count -eq 0) 'An already-off proxy does not invent a new shutdown event'
function New-EtwRecord {
    param([string]$Provider, [int]$Id, [int]$Opcode, [int]$WriterPid, [string]$At, [string]$Data)
    $record = [pscustomobject]@{ ProviderName = $Provider; Id = $Id; Opcode = $Opcode; ProcessId = $WriterPid; TimeCreated = [DateTime]::Parse($At).ToUniversalTime(); Xml = '<Event><EventData>' + $Data + '</EventData></Event>' }
    $record | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
    return $record
}
$events = @(
    (New-EtwRecord 'Microsoft-Windows-Kernel-Process' 1 1 77 '2026-10-19T15:00:00Z' '<Data Name="ProcessID">77</Data><Data Name="ImageName">C:\Windows\fixture.exe</Data>'),
    (New-EtwRecord 'Microsoft-Windows-Kernel-Registry' 2 33 77 '2026-10-19T15:00:01Z' '<Data Name="KeyObject">0x123</Data><Data Name="BaseName"></Data><Data Name="RelativeName">\REGISTRY\USER\S-1-test\Software\Microsoft\Windows\CurrentVersion\Internet Settings</Data>'),
    (New-EtwRecord 'Microsoft-Windows-Kernel-Registry' 5 36 77 '2026-10-19T15:00:02Z' '<Data Name="KeyObject">0x123</Data><Data Name="KeyName"></Data><Data Name="ValueName">ProxyEnable</Data><Data Name="Status">0x0</Data><Data Name="Data">private-token</Data>')
)
$writerResult = $events | ConvertTo-FwWriterEvidence -CurrentUserSid 'S-1-test'
Assert-Check ($writerResult.writers.Count -eq 1 -and $writerResult.writers[0].processId -eq 77 -and $writerResult.writers[0].processName -eq 'fixture.exe') 'ETW stream resolves a key handle and an exited writer process'
Assert-Check ((ConvertTo-Json -InputObject $writerResult -Depth 20) -notmatch 'S-1-test|private-token|C:\\Windows') 'Writer evidence excludes user SID, full image path and value contents'
$unresolved = @($events[-1]) | ConvertTo-FwWriterEvidence -CurrentUserSid 'S-1-test'
Assert-Check ($unresolved.status -eq 'writer_not_determined' -and $unresolved.counts.unresolvedProxyNamedWrites -eq 1) 'Unresolved registry handles do not invent a writer attribution'
$explicit = New-EtwRecord 'Microsoft-Windows-Kernel-Registry' 5 36 77 '2026-10-19T15:00:03Z' '<Data Name="KeyName">\REGISTRY\USER\S-1-test\Software\Microsoft\Windows\CurrentVersion\Internet Settings</Data><Data Name="ValueName">ProxyEnable</Data><Data Name="Status">0x0</Data><Data Name="Type">4</Data><Data Name="CapturedDataSize">4</Data><Data Name="CapturedData">00000000</Data><Data Name="PreviousDataType">4</Data><Data Name="PreviousDataCapturedSize">4</Data><Data Name="PreviousData">01000000</Data>'
$direct = @($events[0], $explicit) | ConvertTo-FwWriterEvidence -CurrentUserSid 'S-1-test'
Assert-Check ($direct.writers[0].directDisableWriteConfirmed -and $direct.writers[0].manualEnabledBefore -and -not $direct.writers[0].manualEnabledAfter) 'Captured ProxyEnable DWORD transition identifies the registry disable writer while exporting booleans only'
if (-not $Portable) {
Initialize-FwProxyNative
$nativeBefore = Get-FwProxySnapshot
$nativeFingerprint = Get-FwConfigurationFingerprint $nativeBefore
Assert-Check ($nativeBefore.queries.wideUi.Success -and $nativeBefore.queries.ansiUi.Success) 'Real native Unicode and ANSI WinINet queries succeed'
$nativeAfter = Get-FwProxySnapshot
Assert-Check ($nativeFingerprint -ceq (Get-FwConfigurationFingerprint $nativeAfter)) 'Native read-only collection preserves all proxy and policy configuration'
$backupPath = Join-Path $OutputDirectory 'test-backup.dpapi'
Save-FwEncryptedBackup $fixture $backupPath
$encrypted = [IO.File]::ReadAllBytes($backupPath)
Assert-Check ([Text.Encoding]::UTF8.GetString($encrypted) -notmatch 'secret-pass|private-token') 'DPAPI backup is not plaintext'
$decrypted = [Security.Cryptography.ProtectedData]::Unprotect($encrypted, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
Assert-Check ([Text.Encoding]::UTF8.GetString($decrypted) -match 'private-token') 'Same-user DPAPI backup can recover the original snapshot'
}
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ProxyNative.cs'))
Assert-Check ($source -notmatch 'SetValue\(|RegSet|INTERNET_OPTION_PER_CONNECTION_OPTION' -and $source -match 'option != 95 && option != 39 && option != 37') 'Customer native component cannot write proxy values or connection-option payloads'
$parseErrors = @()
foreach ($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps*' -File)) {
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($null -ne $errors) { $parseErrors += @($errors) }
}
Assert-Check ($parseErrors.Count -eq 0) 'All shipped PowerShell files parse on the recorded test runtime'
$summary = [ordered]@{ passed = $true; checks = @($checks.ToArray()); powershell = $PSVersionTable.PSVersion.ToString(); architecture = $env:PROCESSOR_ARCHITECTURE; testedAt = [DateTime]::UtcNow.ToString('o'); customerFailureReproduced = $false; nativeChecksSkipped = [bool]$Portable }
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'tests.json'), (ConvertTo-Json -InputObject $summary -Depth 18), (New-Object Text.UTF8Encoding($false)))
