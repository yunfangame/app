[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
$module=Join-Path $root 'ClientObservation.ps1'
$tokens=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($module,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Observation module syntax errors' }
. (Join-Path $root 'ClientDiscovery.ps1')
$output=@(. $module)
$script:Passed=0
$script:Failures=New-Object 'System.Collections.Generic.List[string]'
function Assert-True([bool]$Value,[string]$Reason) { if (-not $Value) { throw $Reason } }
function Run-Case([string]$Name,[scriptblock]$Body) {
    try { & $Body; $script:Passed++;Write-Host ('PASS '+$Name) }
    catch { $script:Failures.Add($Name+': '+$_.Exception.Message);Write-Host ('FAIL '+$Name) }
}
function New-Row([string]$Event,$Fields=@{},[string]$Time='2026-10-09T03:00:05Z',[int]$Sequence=1) {
    return [pscustomobject]@{timestamp=$Time;event=$Event;session_ref='abcdef012345';sequence=$Sequence;fields=$Fields}
}
function New-Observation($Rows=@(),$Samples=@(),$Account=$null) {
    return [pscustomobject]@{StartedUtc='2026-10-09T03:00:00Z';EndedUtc='2026-10-09T03:00:45Z';CurrentEvents=@($Rows);Samples=@($Samples);Account=$Account}
}
function Find-Code($Rows,[string]$Code,$Samples=@(),$Account=$null) { return ,@(Get-FwFailureFindings (New-Observation $Rows $Samples $Account) | Where-Object { $_.Code -eq $Code }) }
Run-Case 'Module has BOM and loads without side effects' {
    $bytes=[IO.File]::ReadAllBytes($module)
    Assert-True ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191 -and $output.Count -eq 0) 'Unexpected module encoding or load output'
}
Run-Case 'Safe event projection strips all arbitrary text and hashes identity' {
    $row=New-Row 'auth.api.attempt.failed' @{reason='timeout';request_ref='123456abcdef';endpoint_ref='abcdef123456';password='fixture-secret-password';error='https://private.example/token?secret=abc';node='private-node';stage='secure_login'}
    $row | Add-Member NoteProperty session 'private-session'
    $safe=@(Get-FwObservationRows ([pscustomobject]@{Logs=@($row)}))
    Assert-True ($safe.Count -eq 1 -and $safe[0].event_id -match '^[a-f0-9]{24}$') 'Event identity unavailable'
    $json=$safe | ConvertTo-Json -Depth 10 -Compress
    Assert-True (-not $json.Contains('private-') -and -not $json.Contains('fixture') -and -not $json.Contains('https:')) 'Raw diagnostic value leaked'
}
Run-Case 'Invalid event timestamp and unknown event are ignored' {
    $rows=@((New-Row 'auth.api.attempt.failed' @{} 'bad-time'),(New-Row 'evil.raw' @{}))
    Assert-True (@(Get-FwObservationRows ([pscustomobject]@{Logs=$rows})).Count -eq 0) 'Invalid event accepted'
}
Run-Case 'LogSnapshot takes priority over legacy Logs and reports count metadata safely' {
    $context=[pscustomobject]@{Logs=@(New-Row 'core.lifecycle.failed' @{});LogSnapshot=[pscustomobject]@{Rows=@(New-Row 'connection.ready' @{});Stats=@{FilesRead=3;DroppedRows=100;TailOmittedLines=900;CountUnknown=$true;Truncated=$true;raw='private'}}}
    Assert-True (@(Get-FwObservationRows $context)[0].event -eq 'connection.ready') 'Timeline priority incorrect'
    $stats=Get-FwObservationLogStats $context
    Assert-True ($stats.DroppedRows -eq 100 -and $stats.TailOmittedLines -eq 900 -and $stats.CountUnknown) 'Truncation accounting lost'
    Assert-True (-not ($stats | ConvertTo-Json -Compress).Contains('private')) 'Stats arbitrary data leaked'
}
Run-Case 'Only valid unique configured ports are sampled' {
    $ports=@(Get-FwObservationPorts ([pscustomobject]@{Prefs=@{'mixed-port'=7890;port=7890;'socks-port'=65536;mixed_port=-1;socks_port=7891}}))
    Assert-True ($ports.Count -eq 2 -and $ports -contains 7890 -and $ports -contains 7891) 'Port allowlist failed'
}
Run-Case 'Historical failures are not current findings' {
    $rows=@(New-Row 'configuration.apply.failed' @{stage='core_setup';timed_out=$true} '2026-10-09T02:59:59Z')
    $results=@(Get-FwFailureFindings (New-Observation $rows))
    Assert-True ($results.Count -eq 1 -and $results[0].Code -eq 'NO_CURRENT_FAILURE_EVIDENCE') 'Historical failure attributed to observation'
}
Run-Case 'Future failures and unspecified time windows are not attributed' {
    $rows=@(New-Row 'configuration.apply.failed' @{} '2026-10-09T03:01:00Z')
    Assert-True ((Find-Code $rows 'NO_CURRENT_FAILURE_EVIDENCE').Count -eq 1) 'Future failure attributed'
    Assert-True (@(Get-FwFailureFindings ([pscustomobject]@{CurrentEvents=$rows}))[0].Code -eq 'NO_CURRENT_FAILURE_EVIDENCE') 'Missing window treated as current'
}
Run-Case 'Server subscription rejection has priority over timeout-shaped metadata' {
    $row=New-Row 'subscription.pipeline.failed' @{stage='fetch';error_code='subscription_unavailable';reason='timeout';http_status=403}
    $results=@(Get-FwFailureFindings (New-Observation @($row)))
    Assert-True ($results.Count -eq 1 -and $results[0].Code -eq 'SUBSCRIPTION_SERVER_REJECTED' -and $results[0].Layer -eq 'account_or_subscription') 'Business rejection mistaken for network timeout'
}
Run-Case 'API failure classification distinguishes timeout DNS TLS and signature' {
    foreach ($entry in @(@{reason='timeout';code='API_REQUEST_TIMEOUT'},@{reason='dns';code='API_DNS_FAILURE'},@{reason='tls';code='API_TLS_FAILURE'})) {
        $row=New-Row 'auth.api.attempt.failed' @{stage='subscription';reason=$entry.reason;request_ref='123456abcdef'}
        Assert-True ((Find-Code @($row) $entry.code).Count -eq 1) 'API reason not classified'
    }
    $row=New-Row 'auth.api.attempt.failed' @{subscription_v2_code='response_signature_failed'}
    Assert-True ((Find-Code @($row) 'SECURE_RESPONSE_VALIDATION_FAILED').Count -eq 1) 'Response verification classification missing'
}
Run-Case 'Authentication and rate-limit codes remain business errors' {
    Assert-True ((Find-Code @(New-Row 'auth.api.attempt.failed' @{subscription_v2_code='invalid_credentials'}) 'AUTHENTICATION_REJECTED').Count -eq 1) 'Authentication rejection lost'
    Assert-True ((Find-Code @(New-Row 'auth.api.attempt.failed' @{subscription_v2_code='rate_limited'}) 'LOGIN_RATE_LIMITED').Count -eq 1) 'Login rate limit lost'
}
Run-Case 'Recovered API and configuration failures remain evidence but are INFO' {
    $rows=@((New-Row 'auth.api.attempt.failed' @{stage='login';reason='timeout'} '2026-10-09T03:00:01Z' 1),(New-Row 'auth.api.attempt.completed' @{stage='login'} '2026-10-09T03:00:03Z' 2),(New-Row 'configuration.apply.failed' @{stage='core_setup'} '2026-10-09T03:00:04Z' 3),(New-Row 'configuration.apply.succeeded' @{stage='core_setup'} '2026-10-09T03:00:05Z' 4))
    foreach ($result in @(Get-FwFailureFindings (New-Observation $rows))) { Assert-True ($result.Status -eq 'INFO' -and $result.RecoveredLater) 'Recovered error presented as current failure' }
}
Run-Case 'Unrelated stage completion does not resolve a failure' {
    $rows=@((New-Row 'auth.api.attempt.failed' @{stage='login';reason='timeout'} '2026-10-09T03:00:01Z' 1),(New-Row 'auth.api.attempt.completed' @{stage='subscription'} '2026-10-09T03:00:03Z' 2))
    $result=(Find-Code $rows 'API_REQUEST_TIMEOUT')[0]
    Assert-True ($result.Status -eq 'FAIL' -and -not $result.RecoveredLater) 'Unrelated stage incorrectly recovered failure'
}
Run-Case 'Equal timestamp recovery uses safe sequence order' {
    $rows=@((New-Row 'configuration.apply.failed' @{stage='core_setup'} '2026-10-09T03:00:01Z' 1),(New-Row 'configuration.apply.succeeded' @{stage='core_setup'} '2026-10-09T03:00:01Z' 2))
    Assert-True ((Find-Code $rows 'CLIENT_CONFIGURATION_APPLY_FAILED')[0].RecoveredLater) 'Same timestamp success order was ignored'
}
Run-Case 'Normal core stop and cancellation do not become start failures' {
    $rows=@((New-Row 'core.lifecycle.failed' @{operation='stop'}),(New-Row 'core.lifecycle.completed' @{operation='close';outcome='stopped'}),(New-Row 'configuration.apply.failed' @{cancelled=$true}),(New-Row 'connection.listener.readiness' @{status='cancelled';port=7890}))
    Assert-True ((Find-Code $rows 'NO_CURRENT_FAILURE_EVIDENCE').Count -eq 1) 'Normal stop or cancelled action misreported'
}
Run-Case 'Core start and configuration apply failures point to local stages' {
    Assert-True ((Find-Code @(New-Row 'core.lifecycle.failed' @{operation='start';code='peer_verification_failed';phase='handshake'}) 'CLIENT_CORE_START_FAILED').Count -eq 1) 'Core failure not classified'
    Assert-True ((Find-Code @(New-Row 'configuration.apply.failed' @{stage='generate_config'}) 'CLIENT_CONFIGURATION_APPLY_FAILED').Count -eq 1) 'Config failure not classified'
}
Run-Case 'No listeners while stopped is UNKNOWN rather than failure' {
    $samples=@([pscustomobject]@{Timestamp='2026-10-09T03:00:01Z';Status='COMPLETE';Processes=@();Listeners=@();ListenerQueryStatus='COMPLETE'})
    $results=@(Get-FwFailureFindings (New-Observation @() $samples))
    Assert-True ($results.Count -eq 1 -and $results[0].Status -eq 'UNKNOWN') 'Stopped client attributed to missing listener'
}
Run-Case 'Foreign listening port alone is not a diagnosed failure' {
    $samples=@([pscustomobject]@{Timestamp='2026-10-09T03:00:05Z';Listeners=@([pscustomobject]@{Port=7890;OwnerProcessId=9000;OwnerRole='other_installation_or_application';OwnerVerified=$true;AddressClass='loopback'})})
    Assert-True ((Find-Code @() 'LOCAL_PORT_OWNED_BY_OTHER_PROCESS' $samples).Count -eq 0) 'Foreign port alone attributed to failed connection'
}
Run-Case 'Failed listener plus verified foreign port yields an occupancy finding' {
    $row=New-Row 'connection.listener.readiness' @{status='timedOut';port=7890}
    $samples=@([pscustomobject]@{Timestamp='2026-10-09T03:00:05Z';Listeners=@([pscustomobject]@{Port=7890;OwnerProcessId=9000;OwnerRole='other_installation_or_application';OwnerVerified=$true;AddressClass='wildcard'})})
    Assert-True ((Find-Code @($row) 'LOCAL_PORT_OWNED_BY_OTHER_PROCESS' $samples).Count -eq 1) 'Verified port conflict missing'
}
Run-Case 'Unverified owner specific binding and unrelated port do not prove occupancy' {
    $row=New-Row 'connection.listener.readiness' @{status='timedOut';port=7890}
    foreach ($owner in @(@{Port=7890;OwnerProcessId=9000;OwnerRole='other_installation_or_application';OwnerVerified=$false;AddressClass='loopback'},@{Port=7890;OwnerProcessId=9000;OwnerRole='other_installation_or_application';OwnerVerified=$true;AddressClass='specific_address'},@{Port=7891;OwnerProcessId=9000;OwnerRole='other_installation_or_application';OwnerVerified=$true;AddressClass='wildcard'})) {
        Assert-True ((Find-Code @($row) 'LOCAL_PORT_OWNED_BY_OTHER_PROCESS' @([pscustomobject]@{Timestamp='2026-10-09T03:00:05Z';Listeners=@($owner)})).Count -eq 0) 'Insufficient ownership evidence attributed'
    }
}
Run-Case 'Historical runtime owner snapshots cannot explain a current listener failure' {
    $row=New-Row 'connection.listener.readiness' @{status='timedOut';port=7890}
    $samples=@([pscustomobject]@{Timestamp='2026-10-09T02:00:05Z';Listeners=@([pscustomobject]@{Port=7890;OwnerProcessId=9000;OwnerRole='other_installation_or_application';OwnerVerified=$true;AddressClass='wildcard'})})
    Assert-True ((Find-Code @($row) 'LOCAL_PORT_OWNED_BY_OTHER_PROCESS' $samples).Count -eq 0) 'Historical ownership snapshot attributed to current failure'
}
Run-Case 'Connection ready after listener failure resolves it' {
    $rows=@((New-Row 'connection.listener.readiness' @{status='timedOut';port=7890} '2026-10-09T03:00:01Z' 1),(New-Row 'connection.ready' @{port=7890} '2026-10-09T03:00:03Z' 2))
    Assert-True ((Find-Code $rows 'LOCAL_LISTENER_NOT_READY')[0].RecoveredLater) 'Ready connection did not resolve listener failure'
}
Run-Case 'Connection-ready evidence does not claim external internet success' {
    $result=(Find-Code @(New-Row 'connection.ready' @{port=7890}) 'CLIENT_CONNECTION_READY_OBSERVED')[0]
    Assert-True ($result.Status -eq 'INFO' -and $result.Summary.Contains('不能独立证明')) 'Ready connection overclaims external connectivity'
}
Run-Case 'Matching expired cache is only UNKNOWN and fresh server verification is requested' {
    $account=@{account_match='MATCHED';cached_expired_at_collection_time=$true;cached_traffic_exhausted=$false}
    $result=(Find-Code @() 'CACHED_ACCOUNT_REQUIRES_SERVER_CHECK' @() $account)[0]
    Assert-True ($result.Status -eq 'UNKNOWN' -and $result.Evidence[0].Source -eq 'UNVERIFIED_CACHE') 'Cache expiry reported as current server rejection'
    Assert-True ((Find-Code @() 'CACHED_ACCOUNT_REQUIRES_SERVER_CHECK' @() @{account_match='UNKNOWN_ACCOUNT_MATCH';cached_expired_at_collection_time=$true}).Count -eq 0) 'Wrong-account cache attributed'
}
Run-Case 'Isolated success does not certify original client state or network health' {
    $results=@(Get-FwFailureFindings (New-Observation) @([pscustomobject]@{Status='PASS';raw='private-node'}))
    $result=@($results | Where-Object { $_.Code -eq 'ISOLATED_REQUEST_COMPLETED' })[0]
    Assert-True ($result.Status -eq 'INFO' -and $result.Summary.Contains('不能证明原客户端')) 'Isolated pass overclaims network health'
    Assert-True (-not ($results | ConvertTo-Json -Depth 10 -Compress).Contains('private-node')) 'Isolated input raw field leaked'
}
Run-Case 'Finding evidence contains safe request reference but never raw message' {
    $row=New-Row 'auth.api.attempt.failed' @{reason='timeout';request_ref='123456abcdef';error='fixture-private-error';message='fixture-private-message';raw_path='C:\Users\private-user';token='fixture-private-token'}
    $result=(Find-Code @($row) 'API_REQUEST_TIMEOUT')[0]
    Assert-True ($result.Evidence[0].request_ref -eq '123456abcdef') 'Safe request reference omitted'
    Assert-True (-not ($result | ConvertTo-Json -Depth 10 -Compress).Contains('private')) 'Sensitive evidence leaked'
}
Run-Case 'Evidence truncation and read errors produce explicit coverage limitations' {
    $observation=New-Observation
    $observation | Add-Member NoteProperty LogStats @([pscustomobject]@{Truncated=$true;DroppedRows=150;TailOmittedLines=2000;CountUnknown=$true})
    $observation | Add-Member NoteProperty LogRefreshFailures 1
    $observation | Add-Member NoteProperty DroppedCurrentEvents 0
    $results=@(Get-FwFailureFindings $observation)
    $limited=@($results | Where-Object { $_.Code -eq 'CLIENT_LOG_COVERAGE_LIMITED' })
    Assert-True ($limited.Count -eq 1 -and $limited[0].Status -eq 'UNKNOWN') 'Incomplete evidence hidden or treated as connectivity fault'
}
Run-Case 'Runtime inspection explicitly degrades on unsupported non-Windows host' {
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { return }
    $result=Get-FwClientRuntimeSnapshot ([pscustomobject]@{ExePath='/fixture/private-user/FengWo.exe'}) @(7890,7890,65536)
    Assert-True ($result.Status -eq 'UNKNOWN' -and $result.Reason -eq 'WINDOWS_RUNTIME_REQUIRED' -and $result.RequestedPorts.Count -eq 1) 'Unsupported runtime did not safely degrade'
    Assert-True (-not ($result | ConvertTo-Json -Depth 10 -Compress).Contains('private-user')) 'Runtime output leaked client installation path'
}
Run-Case 'Observation captures only new within-window rows and deduplicates rotation' {
    $script:Calls=0
    $script:Initial=New-Row 'auth.api.attempt.failed' @{reason='timeout'} ([DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')) 1
    $script:New=$null
    function Get-FengWoLocalContext($Client) {
        $script:Calls++
        if ($null -eq $script:New) { $script:New=New-Row 'connection.ready' @{port=7890} ([DateTimeOffset]::UtcNow.ToString('o')) 2 }
        return [pscustomobject]@{Logs=@($script:Initial,$script:New,$script:New);Prefs=@{'mixed-port'=7890};Account=$null;LogSnapshot=$null}
    }
    function Get-FwClientRuntimeSnapshot($Client,$Ports,$TimeoutMs) { return [pscustomobject]@{Timestamp=[DateTimeOffset]::UtcNow.ToString('o');Status='COMPLETE';Processes=@();Listeners=@();RequestedPorts=$Ports} }
    $context=[pscustomobject]@{Logs=@($script:Initial);Prefs=@{'mixed-port'=7890}}
    $result=Invoke-FwClientObservation ([pscustomobject]@{ExePath='/private-user/FengWo.exe'}) $context 1 1
    Assert-True ($result.CurrentEvents.Count -eq 1 -and $result.HistoryEventCount -eq 1 -and $result.CurrentEvents[0].event -eq 'connection.ready') 'Observation duplicated rotated event or included old failure'
    Assert-True ($result.Samples.Count -ge 1 -and $result.OriginalClientUntouched) 'Runtime samples or read-only flag missing'
    Assert-True (-not ($result | ConvertTo-Json -Depth 20 -Compress).Contains('private-user')) 'Observer output leaked client path'
}
Run-Case 'Newly discovered old and future rows are counted without attribution' {
    $script:OldRow=New-Row 'configuration.apply.failed' @{stage='core_setup'} ([DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')) 21
    $script:FutureRow=New-Row 'core.lifecycle.failed' @{operation='start'} ([DateTimeOffset]::UtcNow.AddHours(1).ToString('o')) 22
    function Get-FengWoLocalContext($Client) { return [pscustomobject]@{Logs=@($script:OldRow,$script:FutureRow);Prefs=@{}} }
    $result=Invoke-FwClientObservation ([pscustomobject]@{}) ([pscustomobject]@{Logs=@();Prefs=@{}}) 1 1
    Assert-True ($result.CurrentEvents.Count -eq 0 -and $result.PastNewRowsExcluded -eq 1 -and $result.FutureRowsExcluded -eq 1) 'Out-of-window counts or exclusions wrong'
    Assert-True ($result.Findings[0].Code -eq 'NO_CURRENT_FAILURE_EVIDENCE') 'Out-of-window error became diagnosis'
}
Write-Host ('RESULT passed='+$script:Passed+' failed='+$script:Failures.Count)
foreach ($failure in $script:Failures) { Write-Host $failure }
if ($script:Failures.Count -gt 0) { exit 1 }
