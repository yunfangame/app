function Get-FwObservationValue {
    param($Value, [string]$Name, $Default = $null)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $Default
    }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Get-FwObservationRows {
    param($Context)
    $snapshot = Get-FwObservationValue $Context 'LogSnapshot'
    $source = Get-FwObservationValue $snapshot 'Rows'
    if ($null -eq $source) { $source = Get-FwObservationValue $Context 'Logs' @() }
    foreach ($row in @($source)) {
        $event = ConvertTo-FwSafeLogCode (Get-FwObservationValue $row 'event') 'event'
        $time = [DateTimeOffset]::MinValue
        if (-not $event -or -not [DateTimeOffset]::TryParse([string](Get-FwObservationValue $row 'timestamp'), [ref]$time)) { continue }
        $fields = Get-FwSafeLogFields (Get-FwObservationValue $row 'fields')
        $reference = [string](Get-FwObservationValue $row 'session_ref')
        if ($reference -notmatch '^[a-f0-9]{12}$') { $reference = $null }
        $sequence = ConvertTo-FwSafeInteger (Get-FwObservationValue $row 'sequence') 9007199254740991L
        $identity = [string](Get-FwObservationValue $row 'event_id')
        $timestamp = $time.ToUniversalTime().ToString('o')
        if ($identity -notmatch '^[a-f0-9]{24}$') {
            $identity = Get-FwFingerprint ($timestamp + '|' + $event + '|' + $reference + '|' + $sequence + '|' + ($fields | ConvertTo-Json -Depth 8 -Compress)) 24
        }
        [pscustomobject]@{ timestamp=$timestamp; event=$event; event_id=$identity; session_ref=$reference; sequence=$sequence; fields=$fields }
    }
}

function Get-FwObservationLogStats {
    param($Context)
    $snapshot = Get-FwObservationValue $Context 'LogSnapshot'
    $source = Get-FwObservationValue $snapshot 'Stats'
    $result = [ordered]@{}
    foreach ($key in @('FilesFound','FilesRead','ReadFailed','ValidRows','RetainedRows','DuplicateRows','InvalidRows','DroppedRows','TailOmittedLines')) {
        $value = ConvertTo-FwSafeInteger (Get-FwObservationValue $source $key) 9007199254740991L
        if ($null -ne $value) { $result[$key] = $value }
    }
    foreach ($key in @('Truncated','CountUnknown')) {
        $value = Get-FwObservationValue $source $key
        if ($value -is [bool]) { $result[$key] = $value }
    }
    return [pscustomobject]$result
}

function Get-FwObservationPorts {
    param($Context)
    $preferences = Get-FwObservationValue $Context 'Prefs'
    $seen = @{}
    foreach ($key in @('mixed-port','port','socks-port','mixed_port','socks_port')) {
        $port = ConvertTo-FwSafeInteger (Get-FwObservationValue $preferences $key) 65535 1
        if ($null -ne $port -and -not $seen.ContainsKey([string]$port)) { $seen[[string]$port] = $true; [int]$port }
    }
}

function Get-FwClientRuntimeSnapshot {
    param([Parameter(Mandatory=$true)]$Client, [int[]]$Ports = @(), [ValidateRange(200,10000)][int]$TimeoutMs = 2500)
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $empty = [ordered]@{ Timestamp=$timestamp; Status='UNKNOWN'; ProcessQueryStatus='UNKNOWN'; ListenerQueryStatus='UNKNOWN'; Processes=@(); Listeners=@(); RequestedPorts=@(); Reason='RUNTIME_SNAPSHOT_UNAVAILABLE' }
    $portsSafe = @($Ports | Where-Object { $_ -ge 1 -and $_ -le 65535 } | Select-Object -Unique -First 12)
    $empty.RequestedPorts = $portsSafe
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { $empty.Reason='WINDOWS_RUNTIME_REQUIRED'; return [pscustomobject]$empty }
    $path = Get-FwLocalFullPath ([string](Get-FwObservationValue $Client 'ExePath'))
    if (-not $path) { $empty.Reason='CLIENT_PATH_UNAVAILABLE'; return [pscustomobject]$empty }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    if (-not [IO.File]::Exists($powershell)) { $powershell = Join-Path $PSHOME 'pwsh.exe' }
    if (-not [IO.File]::Exists($powershell) -or -not (Get-Command Invoke-BoundedProcess -ErrorAction SilentlyContinue)) { $empty.Reason='BOUNDED_RUNTIME_UNAVAILABLE'; return [pscustomobject]$empty }
    $inputText = @{ Path=$path; Ports=$portsSafe } | ConvertTo-Json -Compress
    $inputBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($inputText))
    $child = @'
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$inputData=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__INPUT__')) | ConvertFrom-Json
$expected=[IO.Path]::GetFullPath($inputData.Path)
$directory=[IO.Path]::GetDirectoryName($expected)
$rows=New-Object 'System.Collections.Generic.List[object]'
$listeners=New-Object 'System.Collections.Generic.List[object]'
$known=@{}
$pathDenied=0
foreach ($name in @('FengWo','fengwoacc','FlClashCore','FlClashHelperService')) {
    foreach ($item in @([Diagnostics.Process]::GetProcessesByName($name) | Select-Object -First 128)) {
        try {
            $full=[IO.Path]::GetFullPath($item.MainModule.FileName)
            $role=$null
            if ($full.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) { $role='client' }
            elseif ($full.Equals((Join-Path $directory 'FlClashCore.exe'),[StringComparison]::OrdinalIgnoreCase)) { $role='core' }
            elseif ($full.Equals((Join-Path $directory 'FlClashHelperService.exe'),[StringComparison]::OrdinalIgnoreCase)) { $role='helper' }
            if ($role) {
                $start=$null
                try { $start=$item.StartTime.ToUniversalTime().ToString('o') } catch {}
                $rows.Add([pscustomobject]@{Role=$role;ProcessId=$item.Id;Alive=(-not $item.HasExited);StartedUtc=$start;SameInstallation=$true})
                $known[[string]$item.Id]=$role
            }
        } catch { $pathDenied++ }
        finally { $item.Dispose() }
    }
}
$listenerStatus='NOT_REQUESTED'
if (@($inputData.Ports).Count -gt 0) {
    try {
        $entries=@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $inputData.Ports -contains $_.LocalPort } | Select-Object -First 128)
        foreach ($entry in $entries) {
            $owner='unknown';$verified=$false
            $ownerKey=[string]$entry.OwningProcess
            if ($known.ContainsKey($ownerKey)) { $owner=$known[$ownerKey];$verified=$true }
            else {
                $ownerProcess=$null
                try {
                    $ownerProcess=[Diagnostics.Process]::GetProcessById([int]$entry.OwningProcess)
                    $ownerPath=[IO.Path]::GetFullPath($ownerProcess.MainModule.FileName)
                    if (-not $ownerProcess.HasExited) {
                        if ($ownerPath.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) { $owner='client' }
                        elseif ($ownerPath.Equals((Join-Path $directory 'FlClashCore.exe'),[StringComparison]::OrdinalIgnoreCase)) { $owner='core' }
                        elseif ($ownerPath.Equals((Join-Path $directory 'FlClashHelperService.exe'),[StringComparison]::OrdinalIgnoreCase)) { $owner='helper' }
                        else { $owner='other_installation_or_application' }
                        $verified=$true
                    }
                } catch {}
                finally { if ($null -ne $ownerProcess) { $ownerProcess.Dispose() } }
            }
            $addressClass='specific_address'
            if ($entry.LocalAddress -in @('0.0.0.0','::')) { $addressClass='wildcard' }
            elseif ($entry.LocalAddress -in @('127.0.0.1','::1')) { $addressClass='loopback' }
            $listeners.Add([pscustomobject]@{Port=[int]$entry.LocalPort;OwnerProcessId=[int]$entry.OwningProcess;OwnerRole=$owner;OwnerVerified=$verified;AddressClass=$addressClass})
        }
        $listenerStatus='COMPLETE'
    } catch { $listenerStatus='UNAVAILABLE' }
}
[pscustomobject]@{Timestamp=[DateTimeOffset]::UtcNow.ToString('o');Status='COMPLETE';ProcessQueryStatus=$(if ($pathDenied -gt 0) {'PARTIAL'} else {'COMPLETE'});ListenerQueryStatus=$listenerStatus;Processes=@($rows.ToArray());Listeners=@($listeners.ToArray());RequestedPorts=@($inputData.Ports);Reason='READ_ONLY_SNAPSHOT'} | ConvertTo-Json -Depth 8 -Compress
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child.Replace('__INPUT__',$inputBase64)))
    $reply = Invoke-BoundedProcess $powershell @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) $TimeoutMs
    if (Get-FwObservationValue $reply 'TimedOut' $false) { $empty.Reason='RUNTIME_QUERY_TIMED_OUT'; return [pscustomobject]$empty }
    if ((Get-FwObservationValue $reply 'ExitCode' -1) -ne 0) { $empty.Reason='RUNTIME_QUERY_FAILED'; return [pscustomobject]$empty }
    try { $result = ([string](Get-FwObservationValue $reply 'Output')) | ConvertFrom-Json -ErrorAction Stop } catch { $empty.Reason='RUNTIME_QUERY_INVALID_RESULT'; return [pscustomobject]$empty }
    $empty.Status='COMPLETE';$empty.Reason='READ_ONLY_SNAPSHOT'
    foreach ($key in @('ProcessQueryStatus','ListenerQueryStatus')) {
        $value = [string](Get-FwObservationValue $result $key)
        if ($value -in @('COMPLETE','PARTIAL','UNAVAILABLE','NOT_REQUESTED')) { $empty[$key]=$value }
    }
    foreach ($process in @(Get-FwObservationValue $result 'Processes' @()) | Select-Object -First 256) {
        $role = [string](Get-FwObservationValue $process 'Role')
        $id = ConvertTo-FwSafeInteger (Get-FwObservationValue $process 'ProcessId') 2147483647 1
        $alive = Get-FwObservationValue $process 'Alive'
        if ($role -notin @('client','core','helper') -or $null -eq $id -or $alive -isnot [bool]) { continue }
        $start = [DateTimeOffset]::MinValue;$startText=$null
        if ([DateTimeOffset]::TryParse([string](Get-FwObservationValue $process 'StartedUtc'),[ref]$start)) { $startText=$start.ToUniversalTime().ToString('o') }
        $empty.Processes += [pscustomobject]@{Role=$role;ProcessId=$id;Alive=$alive;StartedUtc=$startText;SameInstallation=$true}
    }
    foreach ($listener in @(Get-FwObservationValue $result 'Listeners' @()) | Select-Object -First 128) {
        $port = ConvertTo-FwSafeInteger (Get-FwObservationValue $listener 'Port') 65535 1
        $ownerId = ConvertTo-FwSafeInteger (Get-FwObservationValue $listener 'OwnerProcessId') 2147483647
        $owner = [string](Get-FwObservationValue $listener 'OwnerRole')
        $verified = Get-FwObservationValue $listener 'OwnerVerified'
        $addressClass = [string](Get-FwObservationValue $listener 'AddressClass')
        if ($portsSafe -notcontains $port -or $null -eq $ownerId -or $owner -notin @('client','core','helper','other_installation_or_application','unknown') -or $verified -isnot [bool] -or $addressClass -notin @('loopback','wildcard','specific_address')) { continue }
        $empty.Listeners += [pscustomobject]@{Port=$port;OwnerProcessId=$ownerId;OwnerRole=$owner;OwnerVerified=$verified;AddressClass=$addressClass}
    }
    return [pscustomobject]$empty
}

function Get-FwFailureEvidence {
    param($Row)
    $value = [ordered]@{Timestamp=$Row.timestamp;Event=$Row.event;EventRef=$Row.event_id}
    foreach ($key in @('error_code','subscription_v2_code','code','reason','stage','phase','operation','status','request_ref','endpoint_ref','attempt_id','http_status','port','os_error_code','last_os_error_code')) {
        $field = Get-FwObservationValue $Row.fields $key
        if ($null -ne $field) { $value[$key]=$field }
    }
    return [pscustomobject]$value
}

function Test-FwFailureRecovered {
    param($Row, $Rows)
    $prefix = $Row.event -replace '\.(failed|failure|timed_out|timeout)$',''
    if ($Row.event -eq 'system_proxy.native_apply.failed') { $prefix='system_proxy.apply' }
    $afterOriginal=$false
    foreach ($later in @($Rows)) {
        if (-not $afterOriginal) { if ($later.event_id -eq $Row.event_id) { $afterOriginal=$true }; continue }
        if ($later.timestamp -lt $Row.timestamp) { continue }
        if ($Row.event -eq 'connection.listener.readiness' -and ($later.event -eq 'connection.ready' -or ($later.event -eq 'connection.listener.readiness' -and (Get-FwObservationValue $later.fields 'status') -eq 'ready'))) { return $true }
        if ($later.event -notin @(($prefix+'.completed'),($prefix+'.succeeded'),($prefix+'.ready'),($prefix+'.success'))) { continue }
        $stage = Get-FwObservationValue $Row.fields 'stage'
        if ($stage -and (Get-FwObservationValue $later.fields 'stage') -ne $stage) { continue }
        $operation = Get-FwObservationValue $Row.fields 'operation'
        if ($operation -and (Get-FwObservationValue $later.fields 'operation') -ne $operation) { continue }
        if ((Get-FwObservationValue $later.fields 'success') -eq $false) { continue }
        if ((Get-FwObservationValue $later.fields 'outcome') -in @('failed','cancelled','superseded')) { continue }
        return $true
    }
    return $false
}

function Get-FwFailureFindings {
    param([Parameter(Mandatory=$true)]$Observation, $IsolatedResults = @())
    $context = [pscustomobject]@{Logs=(Get-FwObservationValue $Observation 'CurrentEvents' @())}
    $rows = @(Get-FwObservationRows $context | Sort-Object timestamp,session_ref,sequence)
    $start = [DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MaxValue
    $hasWindow = [DateTimeOffset]::TryParse([string](Get-FwObservationValue $Observation 'StartedUtc'),[ref]$start) -and [DateTimeOffset]::TryParse([string](Get-FwObservationValue $Observation 'EndedUtc'),[ref]$end)
    if ($hasWindow) { $rows=@($rows | Where-Object { [DateTimeOffset]::Parse($_.timestamp) -ge $start -and [DateTimeOffset]::Parse($_.timestamp) -le $end }) }
    else { $rows=@() }
    $findings = New-Object 'System.Collections.Generic.List[object]'
    foreach ($row in $rows) {
        $fields=$row.fields
        if ((Get-FwObservationValue $fields 'cancelled') -eq $true -or (Get-FwObservationValue $fields 'status') -in @('cancelled','superseded') -or $row.event -match '\.(superseded|cancelled)$') { continue }
        $codes=@((Get-FwObservationValue $fields 'error_code'),(Get-FwObservationValue $fields 'subscription_v2_code'),(Get-FwObservationValue $fields 'code')) | Where-Object { $_ }
        $failureCode=$null;$layer=$null;$explanation=$null;$next=$null
        $failed=$row.event -match '\.(failed|failure|timed_out|timeout)$' -or (Get-FwObservationValue $fields 'success') -eq $false
        if ($codes -contains 'subscription_unavailable') {
            $failureCode='SUBSCRIPTION_SERVER_REJECTED';$layer='account_or_subscription'
            $explanation='本次日志记录服务端拒绝提供订阅。不能将这个业务拒绝判为网络超时。'
            $next='核对同一账号服务端最新套餐有效期、流量、账号状态与订阅权限。'
        } elseif ($failed -and ($row.event -match '^(auth|api|subscription)\.')) {
            $reason=[string](Get-FwObservationValue $fields 'reason')
            if ($codes -contains 'invalid_credentials') { $failureCode='AUTHENTICATION_REJECTED';$layer='account_or_subscription';$explanation='本次日志记录账号认证被拒绝。';$next='核对账号与服务端认证结果。' }
            elseif ($codes -contains 'rate_limited') { $failureCode='LOGIN_RATE_LIMITED';$layer='account_or_subscription';$explanation='本次日志记录登录被限流。';$next='核对服务端限流记录与连续登录次数。' }
            elseif ($reason -eq 'timeout') { $failureCode='API_REQUEST_TIMEOUT';$layer='api_request';$explanation='本次 API 请求阶段记录超时；该证据不等于代理节点超时。';$next='按阶段、接口引用与请求引用核对服务端访问日志。' }
            elseif ($reason -eq 'dns') { $failureCode='API_DNS_FAILURE';$layer='api_request';$explanation='本次 API 请求记录 DNS 解析失败。';$next='核对该接口域名的解析结果与请求引用。' }
            elseif ($reason -eq 'tls') { $failureCode='API_TLS_FAILURE';$layer='api_request';$explanation='本次 API 请求记录 TLS 校验或握手失败。';$next='核对系统时间、证书错误分类与接口引用。' }
            elseif ($codes -contains 'response_signature_failed') { $failureCode='SECURE_RESPONSE_VALIDATION_FAILED';$layer='api_response_validation';$explanation='本次日志记录安全响应校验失败。';$next='用请求引用核对网关响应签名与客户端校验结果。' }
            else { $failureCode='API_OR_SUBSCRIPTION_STAGE_FAILED';$layer='api_or_subscription';$explanation='本次 API 或订阅处理阶段记录失败；当前安全字段不足以判定具体原因。';$next='按错误代码和请求引用进一步核对服务端记录。' }
        } elseif ($row.event -eq 'connection.listener.readiness' -and (Get-FwObservationValue $fields 'status') -in @('timedOut','invalidPort')) {
            $failureCode='LOCAL_LISTENER_NOT_READY';$layer='local_core_listener';$explanation='客户端本次连接记录本地代理监听未就绪。';$next='核对同时间的核心启动、配置应用记录与监听端口归属。'
        } elseif ($row.event -eq 'core.lifecycle.failed' -and (Get-FwObservationValue $fields 'operation') -notin @('stop','close')) {
            $failureCode='CLIENT_CORE_START_FAILED';$layer='local_core';$explanation='本次日志记录客户端核心启动或重启失败。';$next='核对核心失败阶段、helper 进程与系统应用控制事件。'
        } elseif ($row.event -eq 'configuration.apply.failed') {
            $failureCode='CLIENT_CONFIGURATION_APPLY_FAILED';$layer='local_configuration';$explanation='本次日志记录配置未成功应用，磁盘中有配置文件不能证明核心已加载。';$next='按失败阶段核对订阅获取、配置生成及核心应用结果。'
        } elseif ($failed -and $row.event -match '^system_proxy\.(apply|native_apply|guard|recheck)\.') {
            $failureCode='SYSTEM_PROXY_OPERATION_FAILED';$layer='system_proxy';$explanation='本次日志记录系统代理操作失败。';$next='核对原客户端监听端口归属与系统代理写入、回读结果。'
        } elseif ($failed -and $row.event -match '^delay\.') {
            $failureCode='CLIENT_DELAY_TEST_FAILED';$layer='node_or_delay_target';$explanation='本次日志记录节点延迟测试失败；不能仅凭延迟失败区分节点与测速目标问题。';$next='结合隔离核心实际代理请求、替代测速目标和核心错误分类判断。'
        }
        if (-not $failureCode) { continue }
        $recovered=Test-FwFailureRecovered $row $rows
        $findings.Add([pscustomobject]@{Code=$failureCode;Status=$(if ($recovered) {'INFO'} else {'FAIL'});Layer=$layer;Summary=$explanation;RecoveredLater=$recovered;RecoveryMeaning=$(if ($recovered) {'同一阶段随后出现成功记录，不能直接视为仍在失败。'} else {''});Evidence=@(Get-FwFailureEvidence $row);NextCheck=$next})
    }
    $samples=@(Get-FwObservationValue $Observation 'Samples' @())
    $samples=@($samples | Where-Object { $sampleTime=[DateTimeOffset]::MinValue; $hasWindow -and [DateTimeOffset]::TryParse([string](Get-FwObservationValue $_ 'Timestamp'),[ref]$sampleTime) -and $sampleTime -ge $start -and $sampleTime -le $end })
    $listenerFailures=@($findings.ToArray() | Where-Object { $_.Code -eq 'LOCAL_LISTENER_NOT_READY' -and -not $_.RecoveredLater })
    if ($listenerFailures.Count -gt 0) {
        $owners=@($samples | ForEach-Object { @(Get-FwObservationValue $_ 'Listeners' @()) } | Where-Object { (Get-FwObservationValue $_ 'OwnerVerified') -eq $true -and (Get-FwObservationValue $_ 'OwnerRole') -eq 'other_installation_or_application' -and (Get-FwObservationValue $_ 'AddressClass') -in @('loopback','wildcard') -and $null -ne (ConvertTo-FwSafeInteger (Get-FwObservationValue $_ 'OwnerProcessId') 2147483647 1) })
        foreach ($port in @($listenerFailures | ForEach-Object { $_.Evidence[0].port } | Where-Object { $_ } | Select-Object -Unique)) {
            $matching=@($owners | Where-Object { $_.Port -eq $port })
            if ($matching.Count -gt 0) {
                $findings.Add([pscustomobject]@{Code='LOCAL_PORT_OWNED_BY_OTHER_PROCESS';Status='FAIL';Layer='local_core_listener';Summary='监听未就绪的端口在观察期间由另一个安装或应用占用。';RecoveredLater=$false;RecoveryMeaning='';Evidence=@([pscustomobject]@{Port=$port;OwnerProcessIds=@($matching | ForEach-Object { $_.OwnerProcessId } | Select-Object -Unique);OwnershipVerified=$true});NextCheck='核对冲突进程或在客户端更换代理端口。'})
            }
        }
    }
    $account=Get-FwObservationValue $Observation 'Account'
    if ((Get-FwObservationValue $account 'account_match') -eq 'MATCHED' -and ((Get-FwObservationValue $account 'cached_expired_at_collection_time') -eq $true -or (Get-FwObservationValue $account 'cached_traffic_exhausted') -eq $true)) {
        $findings.Add([pscustomobject]@{Code='CACHED_ACCOUNT_REQUIRES_SERVER_CHECK';Status='UNKNOWN';Layer='account_or_subscription';Summary='本地同账号缓存显示套餐已过期或流量已耗尽；这是缓存，需核对服务端最新状态。';RecoveredLater=$false;RecoveryMeaning='';Evidence=@([pscustomobject]@{Source='UNVERIFIED_CACHE';CachedExpired=(Get-FwObservationValue $account 'cached_expired_at_collection_time' $false);CachedTrafficExhausted=(Get-FwObservationValue $account 'cached_traffic_exhausted' $false)});NextCheck='核对服务端最新套餐有效期、流量及账号状态。'})
    }
    if ($findings.Count -eq 0) {
        $ready=@($rows | Where-Object { $_.event -eq 'connection.ready' })
        if ($ready.Count -gt 0) { $findings.Add([pscustomobject]@{Code='CLIENT_CONNECTION_READY_OBSERVED';Status='INFO';Layer='local_connection';Summary='观察期间客户端记录连接就绪；该记录不能独立证明外网访问成功。';RecoveredLater=$false;RecoveryMeaning='';Evidence=@(Get-FwFailureEvidence $ready[-1]);NextCheck='若仍不能访问，结合实际代理 HTTP 请求与核心错误分类。'}) }
        else { $findings.Add([pscustomobject]@{Code='NO_CURRENT_FAILURE_EVIDENCE';Status='UNKNOWN';Layer='unknown';Summary='观察期间没有取得可归因的本次失败记录，不能用历史错误或未连接时缺少监听端口判定原因。';RecoveredLater=$false;RecoveryMeaning='';Evidence=@();NextCheck='在观察期间复现一次失败并导出客户端日志。'}) }
    }
    $futureExcluded=ConvertTo-FwSafeInteger (Get-FwObservationValue $Observation 'FutureRowsExcluded') 9007199254740991L
    if ($null -ne $futureExcluded -and $futureExcluded -gt 0) {
        $findings.Add([pscustomobject]@{Code='CLIENT_LOG_TIME_OUTSIDE_OBSERVATION';Status='UNKNOWN';Layer='evidence_coverage';Summary='部分客户端事件时间晚于本机观察时间，已排除，不能当成本次失败。';RecoveredLater=$false;RecoveryMeaning='';Evidence=@([pscustomobject]@{ExcludedFutureRows=$futureExcluded});NextCheck='核对系统时间与诊断日志来源，重新在观察期间复现。'})
    }
    $coverage=@(Get-FwObservationValue $Observation 'LogStats' @())
    $limited=@($coverage | Where-Object { (Get-FwObservationValue $_ 'Truncated') -eq $true -or (Get-FwObservationValue $_ 'ReadFailed' 0) -gt 0 })
    $refreshFailures=ConvertTo-FwSafeInteger (Get-FwObservationValue $Observation 'LogRefreshFailures')
    $droppedCurrent=ConvertTo-FwSafeInteger (Get-FwObservationValue $Observation 'DroppedCurrentEvents') 9007199254740991L
    if ($limited.Count -gt 0 -or $refreshFailures -gt 0 -or $droppedCurrent -gt 0) {
        $findings.Add([pscustomobject]@{Code='CLIENT_LOG_COVERAGE_LIMITED';Status='UNKNOWN';Layer='evidence_coverage';Summary='日志存在读取失败或有界采集截断，报告只说明已采到的证据，不能证明未记录的阶段正常。';RecoveredLater=$false;RecoveryMeaning='';Evidence=@([pscustomobject]@{LimitedSnapshots=$limited.Count;RefreshFailures=$refreshFailures;DroppedCurrentEvents=$droppedCurrent});NextCheck='查看日志采集统计；必要时导出客户端日志补充同时间证据。'})
    }
    $passes=@($IsolatedResults | Where-Object { (Get-FwObservationValue $_ 'Status') -eq 'PASS' })
    if ($passes.Count -gt 0) { $findings.Add([pscustomobject]@{Code='ISOLATED_REQUEST_COMPLETED';Status='INFO';Layer='isolated_test';Summary='隔离核心有请求成功；该结果不能证明原客户端的配置、DNS、规则和当前节点状态正常。';RecoveredLater=$false;RecoveryMeaning='';Evidence=@([pscustomobject]@{PassedRequests=$passes.Count});NextCheck='对照原客户端同时间失败事件及配置应用记录。'}) }
    return $findings.ToArray()
}

function Invoke-FwClientObservation {
    param([Parameter(Mandatory=$true)]$Client, $Context, [ValidateRange(1,120)][int]$Seconds = 45, [ValidateRange(1,10)][int]$SampleInterval = 3)
    if ($null -eq $Context) { $Context=Get-FengWoLocalContext $Client }
    $baseline=@(Get-FwObservationRows $Context)
    $seen=@{}
    foreach ($row in $baseline) { $seen[$row.event_id]=$true }
    $current=New-Object 'System.Collections.Generic.List[object]'
    $samples=New-Object 'System.Collections.Generic.List[object]'
    $stats=New-Object 'System.Collections.Generic.List[object]'
    $stats.Add((Get-FwObservationLogStats $Context))
    $started=[DateTimeOffset]::UtcNow
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $futureRows=0;$oldNewRows=0;$refreshFailures=0;$droppedCurrent=0
    Write-Host ('开始观察 {0} 秒。现在回到蜂窝客户端，点击一次连接或延迟测试；失败提示请保留。' -f $Seconds) -ForegroundColor Green
    while ($watch.ElapsedMilliseconds -lt ($Seconds*1000)) {
        $remaining=($Seconds*1000)-[int]$watch.ElapsedMilliseconds
        if ($remaining -lt 200) { break }
        $ports=@(Get-FwObservationPorts $Context)
        $samples.Add((Get-FwClientRuntimeSnapshot -Client $Client -Ports $ports -TimeoutMs ([Math]::Min(2500,$remaining))))
        try {
            $Context=Get-FengWoLocalContext $Client
            $stats.Add((Get-FwObservationLogStats $Context))
            $now=[DateTimeOffset]::UtcNow
            foreach ($row in @(Get-FwObservationRows $Context)) {
                if ($seen.ContainsKey($row.event_id)) { continue }
                $seen[$row.event_id]=$true
                $time=[DateTimeOffset]::Parse($row.timestamp)
                if ($time -lt $started) { $oldNewRows++; continue }
                if ($time -gt $now) { $futureRows++; continue }
                $current.Add($row)
                if ($current.Count -gt 4000) { $current.RemoveAt(0);$droppedCurrent++ }
            }
        } catch { $refreshFailures++ }
        $remaining=($Seconds*1000)-[int]$watch.ElapsedMilliseconds
        if ($remaining -gt 0) { Start-Sleep -Milliseconds ([Math]::Min($SampleInterval*1000,$remaining)) }
    }
    try {
        $Context=Get-FengWoLocalContext $Client
        $stats.Add((Get-FwObservationLogStats $Context))
        $now=[DateTimeOffset]::UtcNow
        foreach ($row in @(Get-FwObservationRows $Context)) {
            if ($seen.ContainsKey($row.event_id)) { continue }
            $seen[$row.event_id]=$true
            $time=[DateTimeOffset]::Parse($row.timestamp)
            if ($time -lt $started) { $oldNewRows++; continue }
            if ($time -gt $now) { $futureRows++; continue }
            $current.Add($row)
            if ($current.Count -gt 4000) { $current.RemoveAt(0);$droppedCurrent++ }
        }
    } catch { $refreshFailures++ }
    $ended=[DateTimeOffset]::UtcNow
    $result=[pscustomobject]@{StartedUtc=$started.ToString('o');EndedUtc=$ended.ToString('o');RequestedSeconds=$Seconds;ObservedSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,3);HistoryEventCount=$baseline.Count;CurrentEvents=@($current.ToArray() | Sort-Object timestamp,session_ref,sequence);Samples=@($samples.ToArray());LogStats=@($stats.ToArray());PastNewRowsExcluded=$oldNewRows;FutureRowsExcluded=$futureRows;LogRefreshFailures=$refreshFailures;DroppedCurrentEvents=$droppedCurrent;Account=(Get-FwObservationValue $Context 'Account');Findings=@();OriginalClientUntouched=$true}
    $result.Findings=@(Get-FwFailureFindings $result)
    Write-Host ('观察结束：本次新增 {0} 条安全事件。' -f $result.CurrentEvents.Count)
    return $result
}
