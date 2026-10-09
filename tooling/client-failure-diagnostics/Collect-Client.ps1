[CmdletBinding()]
param(
    [ValidateRange(60,1200)][int]$MaxSeconds=900,
    [ValidateRange(2,256)][int]$MaxNodes=256,
    [ValidateRange(1,90)][int]$ObserveSeconds=45,
    [switch]$NonInteractive,
    [switch]$LibraryOnly,
    [switch]$AllowNonWindows
)

$runLibraryOnly=$LibraryOnly;$runNonInteractive=$NonInteractive;$runAllowNonWindows=$AllowNonWindows;$runMaxSeconds=$MaxSeconds
$packageRoot=$PSScriptRoot
. (Join-Path $packageRoot 'Collect-Network.ps1') -LibraryOnly -NoTrace -Rounds 1 -MaxSeconds ([Math]::Min(600,$MaxSeconds)) -AllowNonWindows:$AllowNonWindows
. (Join-Path $packageRoot 'ClientDiscovery.ps1')
. (Join-Path $packageRoot 'ClientObservation.ps1')
. (Join-Path $packageRoot 'ClientProtocol.ps1')
. (Join-Path $packageRoot 'ClientReport.ps1')
$LibraryOnly=$runLibraryOnly;$NonInteractive=$runNonInteractive;$AllowNonWindows=$runAllowNonWindows;$MaxSeconds=$runMaxSeconds
$script:RpcSequence=0
$script:CoreLogCounts=@{}
$script:CoreWarnings=New-Object 'System.Collections.Generic.List[object]'
$script:CoreWarningsDropped=0
$script:Observation=$null;$script:Account=$null;$script:SelectedClient=$null

function Get-ConfigMapCount($Value) {
    if ($null -eq $Value) { return 0 }
    if ($Value -is [Collections.IDictionary]) { return $Value.Count }
    return @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' }).Count
}

function Get-CoreErrorClass([string]$Text) {
    if ($Text -match '(?i)certificate|x509|unknown authority|cert verify') { return 'CERTIFICATE' }
    if ($Text -match '(?i)no such host|dns.*(timeout|fail)|lookup.*(timeout|fail)') { return 'DNS' }
    if ($Text -match '(?i)authentication|unauthorized|invalid user|invalid password|invalid uuid|invalid credential') { return 'AUTHENTICATION' }
    if ($Text -match '(?i)refused') { return 'CONNECTION_REFUSED' }
    if ($Text -match '(?i)handshake|\btls(?:\s|:)') { return 'HANDSHAKE' }
    if ($Text -match '(?i)timeout|timed out|deadline') { return 'TIMEOUT' }
    if ($Text -match '(?i)reset by peer|EOF|closed by|broken pipe') { return 'REMOTE_CLOSED' }
    return 'OTHER'
}

function Get-SafeCoreError([string]$Text) {
    $tokens=New-Object 'System.Collections.Generic.List[string]'
    $patterns=@('certificate has expired','certificate is not yet valid','certificate signed by unknown authority','certificate verify failed','unknown authority','x509','no such host','temporary failure in name resolution','connection refused','connection reset by peer','forcibly closed by the remote host','unexpected EOF','\bEOF\b','broken pipe','context deadline exceeded','i/o timeout','operation timed out','TLS handshake timeout','handshake failed','invalid (?:user|password|uuid|authentication|credential)','authentication failed','unauthorized','access is denied','permission denied','network is unreachable','no route to host','connection attempt failed','actively refused','WSAECONNRESET','WSAECONNREFUSED','WSAETIMEDOUT','10060','10061','10054','remote error: tls: (?:handshake failure|bad certificate|unknown certificate|illegal parameter|protocol version|decrypt error)','reality verification failed','bad record MAC','protocol error','timeout','handshake')
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($Text,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            if (-not $tokens.Contains($match.Value)) { $tokens.Add($match.Value) }
        }
    }
    return $tokens.ToArray()
}

function Add-FwCoreMessages($Reply) {
    $messages=@(Get-Field $Reply 'arguments' @())
    if ((Get-Field $Reply 'type') -eq 'log') { $messages=@($Reply) }
    foreach ($message in $messages) {
        if ((Get-Field $message 'type') -ne 'log') { continue }
        $data=Get-Field $message 'data' $null
        $payload=[string](Get-Field $data 'Payload' (Get-Field $data 'payload' ''))
        if (-not $payload) { continue }
        $nodeMatch=[regex]::Match($payload,'\bdial (node-[0-9]{3})\b')
        $nodeId='core';if ($nodeMatch.Success) { $nodeId=$nodeMatch.Groups[1].Value }
        $errorText=$payload;$separator=$payload.IndexOf(' error: ',[StringComparison]::Ordinal)
        if ($separator -ge 0) { $errorText=$payload.Substring($separator+8) }
        $category=Get-CoreErrorClass $errorText
        if ($category -eq 'OTHER' -and -not $nodeMatch.Success) { continue }
        if (-not $script:CoreLogCounts.ContainsKey($category)) { $script:CoreLogCounts[$category]=0 }
        $script:CoreLogCounts[$category]++
        if ($script:CoreWarnings.Count -ge 3000) { $script:CoreWarningsDropped++;continue }
        $detail=[pscustomobject]@{Time=[DateTime]::UtcNow.ToString('o');NodeId=$nodeId;Category=$category;ErrorTokens=@(Get-SafeCoreError $errorText);Source='OWNED_DIAGNOSTIC_CORE';OtherTextOmitted=$true}
        $script:CoreWarnings.Add($detail)
        Add-Result $nodeId 'protocol.core.error' 'INFO' $detail
    }
}

function Invoke-CoreRpc($Session,[string]$Method,$Arguments,[int]$TimeoutMs=7000) {
    $script:RpcSequence++
    $id='diagnostic-'+$script:RpcSequence
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $budget=Get-Budget $TimeoutMs
    $Session.SendFrame((@{id=$id;method=$Method;arguments=$Arguments} | ConvertTo-Json -Depth 60 -Compress),$budget)
    while ($true) {
        $remaining=$budget-[int]$timer.ElapsedMilliseconds
        if ($remaining -le 0) { throw 'CORE_RPC_TIMEOUT' }
        $reply=$Session.ReadFrame($remaining) | ConvertFrom-Json
        if ((Get-Field $reply 'id') -eq $id) {
            $rpcError=Get-Field $reply 'error' $null
            if ($rpcError) {
                Add-Result 'client' 'core.rpc.error' 'UNKNOWN' @{Method=$Method;ErrorTokens=@(Get-SafeCoreError ([string](Get-Field $rpcError 'message')));Details=(Get-FwSafeLogFields (Get-Field $rpcError 'details' $null))}
                throw 'CORE_RPC_ERROR'
            }
            return (Get-Field $reply 'result' $null)
        }
        Add-FwCoreMessages $reply
    }
}

function Get-FwNativeExceptionCodes($Exception) {
    $codes=New-Object 'System.Collections.Generic.List[int]'
    for ($level=0;$level -lt 5 -and $null -ne $Exception;$level++) {
        $native=$Exception.PSObject.Properties['NativeErrorCode']
        if ($null -ne $native -and [int]$native.Value -gt 0 -and -not $codes.Contains([int]$native.Value)) { $codes.Add([int]$native.Value) }
        $Exception=$Exception.InnerException
    }
    return $codes.ToArray()
}

function Get-NodeCandidates($RawConfig,[string]$Source) {
    $nodes=New-Object 'System.Collections.Generic.List[object]'
    $index=0
    foreach ($proxy in @(Get-Field $RawConfig 'proxies' @())) {
        if ($null -eq $proxy) { continue }
        $index++
        $type=[string](Get-Field $proxy 'type')
        $server=[string](Get-Field $proxy 'server')
        $port=0;[void][int]::TryParse([string](Get-Field $proxy 'port'),[ref]$port)
        if (-not $type -or -not (Test-AddressName $server) -or $port -lt 1 -or $port -gt 65535) { continue }
        $dependency=''
        foreach ($field in @('certificate','private-key','ca')) {
            $value=[string](Get-Field $proxy $field '')
            if ($value -and $value -notmatch '^\s*-----BEGIN ') { $dependency='TLS_FILE_DEPENDENCY_NOT_REPLAYED' }
        }
        $nodes.Add([pscustomobject]@{Id='';Type=$type.ToLowerInvariant();Server=$server;Port=$port;Raw=$proxy;Source=$Source;Position=$index;Dependency=$dependency;Chain=([bool](Get-Field $proxy 'dialer-proxy'))})
    }
    return $nodes.ToArray()
}

function Select-DiagnosticNodes($Candidates,[int]$Limit) {
    $unique=New-Object 'System.Collections.Generic.List[object]'
    $seen=@{}
    foreach ($node in $Candidates) {
        $identity=$node.Raw | ConvertTo-Json -Depth 40 -Compress | ConvertFrom-Json
        $identity.PSObject.Properties.Remove('name')
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $key=[Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($identity | ConvertTo-Json -Depth 40 -Compress)))) } finally { $sha.Dispose() }
        if ($seen.ContainsKey($key)) { $seen[$key].Positions+=@($node.Position);continue }
        $node | Add-Member -NotePropertyName Positions -NotePropertyValue @($node.Position) -Force
        $seen[$key]=$node;$unique.Add($node)
    }
    $selected=New-Object 'System.Collections.Generic.List[object]'
    foreach ($group in @($unique.ToArray() | Group-Object Type)) {
        foreach ($node in @($group.Group | Select-Object -First 2)) { if ($selected.Count -lt $Limit) { $selected.Add($node) } }
    }
    if ($unique.Count -gt 0) {
        for ($i=0;$i -lt $Limit*2 -and $selected.Count -lt $Limit;$i++) {
            $at=[Math]::Min($unique.Count-1,[int][Math]::Floor($i*$unique.Count/([double]($Limit*2))))
            if (-not $selected.Contains($unique[$at])) { $selected.Add($unique[$at]) }
        }
    }
    foreach ($node in $unique) { if ($selected.Count -ge $Limit) { break };if (-not $selected.Contains($node)) { $selected.Add($node) } }
    $i=0;foreach ($node in $selected) { $i++;$node.Id=('node-{0:D3}' -f $i) }
    return $selected.ToArray()
}

function New-IsolatedConfiguration($Nodes,$Original) {
    $leaf=New-Object 'System.Collections.Generic.List[object]'
    foreach ($node in $Nodes) {
        if ($node.Chain -or (Get-Field $node 'Dependency' '')) { continue }
        $copy=$node.Raw | ConvertTo-Json -Depth 40 -Compress | ConvertFrom-Json
        $copy | Add-Member -NotePropertyName name -NotePropertyValue $node.Id -Force
        $leaf.Add($copy)
    }
    return [ordered]@{
        'mixed-port'=0;port=0;'socks-port'=0;'redir-port'=0;'tproxy-port'=0
        'allow-lan'=$false;'bind-address'='127.0.0.1';mode='rule';'log-level'='warning'
        ipv6=[bool](Get-Field $Original 'ipv6' $false)
        'unified-delay'=[bool](Get-Field $Original 'unified-delay' $false)
        'tcp-concurrent'=[bool](Get-Field $Original 'tcp-concurrent' $false)
        'global-client-fingerprint'=[string](Get-Field $Original 'global-client-fingerprint' '')
        'find-process-mode'='off';'geo-auto-update'=$false
        'external-controller'='';'external-controller-tls'='';'external-controller-pipe'='';'external-controller-unix'=''
        'external-ui'='';'external-ui-url'='';'external-doh-server'='';secret=''
        authentication=@();tunnels=@();listeners=@();'ss-config'='';'vmess-config'=''
        tun=@{enable=$false;'auto-route'=$false;'auto-redirect'=$false;'dns-hijack'=@()}
        dns=@{enable=$false;listen='';ipv6=[bool](Get-Field $Original 'ipv6' $false);'respect-rules'=$false;nameserver=@();'default-nameserver'=@('system');fallback=@();'proxy-server-nameserver'=@();'nameserver-policy'=@{};'proxy-server-nameserver-policy'=@{};'fallback-filter'=@{geoip=$false;geosite=@();domain=@();'ipcidr'=@()};'use-hosts'=$true;'use-system-hosts'=$true}
        hosts=(Get-Field $Original 'hosts' @{})
        ntp=@{enable=$false;'write-to-system'=$false};'tuic-server'=@{enable=$false};iptables=@{enable=$false};sniffer=@{enable=$false}
        profile=@{'store-selected'=$false;'store-fake-ip'=$false}
        tls=@{'custom-certifactes'=@(Get-Field (Get-Field $Original 'tls' $null) 'custom-certifactes' @() | Where-Object { $_ })}
        proxies=@($leaf.ToArray());'proxy-groups'=@();'proxy-providers'=@{};'rule-providers'=@{};rules=@('MATCH,DIRECT')
    }
}

function Get-EndpointTarget($Node) {
    $raw=$Node.Raw;$security='none';$transport=[string](Get-Field $raw 'network' 'tcp')
    $type=$Node.Type;$protocol=$type
    if ($type -eq 'shadowsocks') { $protocol='ss' }
    if (@('vless','vmess','trojan','anytls','ss','hy2','hysteria2','tuic') -notcontains $protocol) { $protocol='unknown' }
    if ([bool](Get-Field $raw 'tls' $false) -or @('trojan','anytls','hysteria2','hy2','tuic') -contains $type) { $security='tls' }
    if (Get-Field $raw 'reality-opts' $null) { $security='reality' }
    $sni=[string](Get-Field $raw 'servername' (Get-Field $raw 'sni' ''))
    $ws=Get-Field $raw 'ws-opts' $null;$path=[string](Get-Field $ws 'path' '/');$headers=Get-Field $ws 'headers' $null
    $hostHeader=[string](Get-Field $headers 'Host' '')
    $target=Convert-NodeInput (@{protocol=$protocol;host=$Node.Server;port=$Node.Port;security=$security;transport=$transport;sni=$sni;httpHost=$hostHeader;path=$path} | ConvertTo-Json -Compress) 'problem' 1
    $target.Label=$Node.Id
    if (@('hysteria','tuic','hy2','hysteria2') -contains $type) { $target.UdpOnly=$true;$target.Transport='quic' }
    return $target
}

function Get-SafeDnsSummary($Original) {
    $dns=Get-Field $Original 'dns' $null
    $resolvers=New-Object 'System.Collections.Generic.List[string]'
    foreach ($field in @('nameserver','default-nameserver','proxy-server-nameserver')) {
        foreach ($value in @(Get-Field $dns $field @())) {
            $text=[string]$value;$uri=$null
            if ([Uri]::TryCreate($text,[UriKind]::Absolute,[ref]$uri) -and $uri.Host) { $text=$uri.Scheme+'://'+$uri.DnsSafeHost }
            elseif ($text -notmatch '^[0-9a-fA-F:.]+$') { $text='CUSTOM_RESOLVER_REDACTED' }
            if (-not $resolvers.Contains($text)) { $resolvers.Add($text) }
        }
    }
    return @{Enabled=[bool](Get-Field $dns 'enable' $false);Mode=[string](Get-Field $dns 'enhanced-mode' 'unknown');RespectRules=[bool](Get-Field $dns 'respect-rules' $false);ResolverHosts=$resolvers.ToArray();DiagnosticDns='SYSTEM_DNS_BASELINE';Note='The diagnostic core uses system DNS and original node protocol options. Client DNS/rules/cache/chain state is not replayed.'}
}

function Write-ClientSummary($Nodes,$Completion) {
    Write-FwClientReport $Nodes $Completion
}

function New-FwReportDirectory([string]$PrimaryRoot,[string]$FallbackRoot) {
    $name='FengWo-Client-Timeout-Report-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
    foreach ($base in @($PrimaryRoot,$FallbackRoot,[IO.Path]::GetTempPath())) {
        if (-not $base -or -not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        $candidate=Join-Path $base $name
        try { [void](New-Item -ItemType Directory -Path $candidate -ErrorAction Stop);return $candidate } catch {}
    }
    throw 'REPORT_DIRECTORY_UNWRITABLE'
}

if ($LibraryOnly) { return }
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and -not $AllowNonWindows) { throw 'WINDOWS_REQUIRED' }
$session=$null;$workDir=$null;$nodes=@();$completion='completed'
try {
    $desktop=[Environment]::GetFolderPath('Desktop');if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { $desktop=$packageRoot }
    $script:ReportRoot=New-FwReportDirectory $desktop $packageRoot
    $script:Watch.Restart()
    Write-Host '蜂窝客户端自动诊断：无需输入节点。请保持客户端已登录。' -ForegroundColor Cyan
    Write-Host '检测账号缓存、日志、进程、端口及全部本地节点。节点较多时约 5～15 分钟。'
    Write-Host '不会重装或修改客户端设置；不会刷新订阅或反复登录。'
    if (-not ('FengWoNetworkProbe' -as [type])) { Add-Type -Path (Join-Path $packageRoot 'NetworkProbe.cs') }
    Add-Result 'system' 'network' 'INFO' (Get-BoundedNetworkSnapshot)
    $clients=@(Find-FengWoClients)
    if ($clients.Count -eq 0) { Add-Result 'client' 'discovery' 'FAIL' @{Reason='CLIENT_NOT_FOUND';Action='Please open the installed FengWo client, log in, and run this script again.'};throw 'CLIENT_NOT_FOUND' }
    $client=$clients[0];$script:SelectedClient=$client;$context=Get-FengWoLocalContext $client;$script:Account=$context.Account
    Add-Result 'client' 'discovery' 'PASS' @{Executable=[IO.Path]::GetFileName($client.ExePath);Running=$client.Running;ProcessIds=$client.ProcessIds;CandidateCount=$clients.Count;Version=[Diagnostics.FileVersionInfo]::GetVersionInfo($client.ExePath).ProductVersion}
    Add-Result 'client' 'preferences' 'INFO' $context.Prefs
    Add-Result 'client' 'data-directory.selection' 'INFO' $context.DataDirectorySelection
    Add-Result 'client' 'account.cached' 'INFO' $context.Account
    Add-Result 'client' 'client.logs' 'INFO' $context.LogSnapshot
    Write-Host ('开始观察 '+$ObserveSeconds+' 秒：现在请在蜂窝客户端点一次连接或延迟测速；无需输入账号和节点。') -ForegroundColor Yellow
    $script:Observation=Invoke-FwClientObservation -Client $client -Context $context -Seconds $ObserveSeconds -SampleInterval 3
    Add-Result 'client' 'observation' 'INFO' $script:Observation
    $context=Get-FengWoLocalContext $client;$script:Account=$context.Account
    Write-Host '观察结束，开始逐节点检测。' -ForegroundColor Cyan
    $corePath=Join-Path ([IO.Path]::GetDirectoryName($client.ExePath)) 'FlClashCore.exe'
    if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) { Add-Result 'client' 'core.locate' 'FAIL' @{Reason='BUNDLED_CORE_NOT_FOUND'};throw 'BUNDLED_CORE_NOT_FOUND' }
    Add-Result 'client' 'core.locate' 'PASS' @{Executable='FlClashCore.exe';Size=(Get-Item -LiteralPath $corePath).Length}
    if (-not ('FengWoNetworkProbe' -as [type])) { Add-Type -Path (Join-Path $packageRoot 'NetworkProbe.cs') }
    if (-not ('FengWoDiagnosticCoreSession' -as [type])) { Add-Type -Path (Join-Path $packageRoot 'ClientCoreSession.cs') }
    $session=[FengWoDiagnosticCoreSession]::Start($corePath,(Get-Budget 8000))
    Add-Result 'client' 'core.start' 'PASS' @{OwnedDiagnosticPid=$session.OwnedPid;PeerIdentityVerified=$session.PeerIdentityVerified;OriginalClientUntouched=$true}
    $candidates=New-Object 'System.Collections.Generic.List[object]';$original=$null;$source=''
    foreach ($entry in @(@{Path=$context.ActiveConfigPath;Kind='active-config'},@{Path=$context.ProfilePath;Kind='current-profile'})) {
        if (-not $entry.Path -or -not (Test-Path -LiteralPath $entry.Path -PathType Leaf)) { continue }
        try {
            $raw=Invoke-CoreRpc $session 'getConfig' ([string]$entry.Path) 6000
            $found=@(Get-NodeCandidates $raw $entry.Kind)
            Add-Result 'client' ('configuration.'+$entry.Kind) 'PASS' @{File=[IO.Path]::GetFileName($entry.Path);Updated=(Get-Item -LiteralPath $entry.Path).LastWriteTime.ToString('o');InlineNodes=$found.Count;ProviderCount=(Get-ConfigMapCount (Get-Field $raw 'proxy-providers' $null))}
            if ($found.Count -gt 0 -or $null -eq $original) { $original=$raw;$source=$entry.Kind }
            foreach ($node in $found) { $candidates.Add($node) }
            if ($found.Count -gt 0) { break }
        } catch { Add-Result 'client' ('configuration.'+$entry.Kind) 'FAIL' @{ErrorType=$_.Exception.GetType().Name;Reason='LOCAL_CONFIG_READ_OR_PARSE_FAILED'};if ($session.IsDisposed) { throw } }
    }
    if ($null -eq $original) { Add-Result 'client' 'configuration' 'FAIL' @{Reason='NO_READABLE_CONFIG';Action='Keep client logged in and load its subscription before running again.'};throw 'NO_READABLE_CONFIG' }
    $providerCount=Get-ConfigMapCount (Get-Field $original 'proxy-providers' $null)
    if ($providerCount -gt 0) {
        Add-Result 'client' 'provider.cache' 'UNKNOWN' @{Reason='PROVIDER_STATE_NOT_REPLAYED';ConfiguredProviders=$providerCount;LocalCaches=@($context.ProviderCachePaths).Count;Note='Provider filters/overrides/inline payload and cached freshness are not reconstructed. Unreferenced caches are not treated as current nodes.'}
    }
    Add-Result 'client' 'dns.settings' 'INFO' (Get-SafeDnsSummary $original)
    $mixed=[int](Get-Field $original 'mixed-port' 0)
    if ($mixed -gt 0 -and $mixed -le 65535) {
        $local=[FengWoNetworkProbe]::ProbeTcp('127.0.0.1',$mixed,(Get-Budget 1200))
        $status='UNKNOWN';if ($local.Success) { $status='PASS' }
        Add-Result 'client' 'local.mixed-listener' $status @{Port=$mixed;Reachable=$local.Success;Note='No connection can also mean the client connection is stopped. TCP reachability alone does not establish process ownership.'}
    }
    $nodes=@(Select-DiagnosticNodes $candidates.ToArray() $MaxNodes)
    Add-Result 'client' 'sample' 'INFO' @{AvailableNodes=$candidates.Count;SelectedNodes=$nodes.Count;Limit=$MaxNodes;Source=$source;Coverage=$(if($nodes.Count -lt $candidates.Count){'LIMIT_OR_IDENTICAL_CONFIGURATION_DEDUPLICATION'}else{'ALL_LOCAL_INLINE_NODES'});Selection='All distinct complete protocol configurations up to limit; credentials and paths distinguish nodes, not just endpoints.'}
    if ($nodes.Count -eq 0) { Add-Result 'client' 'sample' 'FAIL' @{Reason='NO_NODE_ENDPOINTS_IN_LOCAL_CONFIG'};throw 'NO_NODE_ENDPOINTS_IN_LOCAL_CONFIG' }
    $workDir=Join-Path ([IO.Path]::GetTempPath()) ('FengWo-Diagnostic-'+[Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $workDir)
    $testUrl=[string]$context.TestUrl
    if (-not $testUrl) { $testUrl='http://cp.cloudflare.com/generate_204' }
    $testTargets=@([pscustomobject]@{Id='client-target';Url=$testUrl},[pscustomobject]@{Id='alternate-target';Url='https://www.gstatic.com/generate_204'})
    if ($testUrl -match '(?i)gstatic\.com') { $testTargets[1].Url='http://cp.cloudflare.com/generate_204' }
    foreach ($target in $testTargets) {
        $uri=[Uri]$target.Url
        Add-Result 'client' 'test.target' 'INFO' @{Id=$target.Id;Scheme=$uri.Scheme;Host=$uri.DnsSafeHost;Port=$uri.Port;PathRedacted=$true;OriginalClientTargetPreserved=($target.Id -eq 'client-target')}
    }
    $curl=Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) { $script:CurlExe=$curl.Source }
    foreach ($target in $testTargets) {
        if (-not $script:CurlExe) { Add-Result 'client' 'test.target.baseline' 'UNKNOWN' @{TargetId=$target.Id;Reason='CURL_NOT_AVAILABLE'};continue }
        $reply=Invoke-BoundedProcess $script:CurlExe @('--noproxy','*','--head','--silent','--connect-timeout','3','--max-time','5','--max-filesize','1024','--url',$target.Url) (Get-Budget 6000)
        $statusCode=0;$matches=[regex]::Matches($reply.Output,'(?m)^HTTP/[0-9.]+ ([0-9]{3})')
        if ($matches.Count -gt 0) { $statusCode=[int]$matches[$matches.Count-1].Groups[1].Value }
        $state='FAIL';if ($reply.ExitCode -eq 0 -and $statusCode -ge 200 -and $statusCode -lt 400) { $state='PASS' }
        if ($statusCode -ge 400 -or $reply.TimedOut) { $state='UNKNOWN' }
        Add-Result 'client' 'test.target.baseline' $state @{TargetId=$target.Id;HttpStatus=$statusCode;CurlExitCode=$reply.ExitCode;TimedOut=$reply.TimedOut;HttpProxyBypassed=$true;TunRoutesMayStillApply=$true}
    }
    [void](Invoke-CoreRpc $session 'initClash' @{'home-dir'=$workDir;version=0} 4000)
    [void](Invoke-CoreRpc $session 'startLog' $null 2000)
    $eligible=New-Object 'System.Collections.Generic.List[object]'
    foreach ($node in $nodes) {
        Add-Result $node.Id 'node' 'INFO' @{Type=$node.Type;Server=$node.Server;Port=$node.Port;Source=$node.Source;Position=$node.Position;Chained=$node.Chain}
        if ($node.Chain -or (Get-Field $node 'Dependency' '')) { Add-Result $node.Id 'protocol.http' 'UNKNOWN' @{Reason='CHAIN_OR_TLS_FILE_DEPENDENCY_NOT_REPLAYED'} }
        else { $eligible.Add($node) }
    }
    $entryCache=@{}
    for ($offset=0;$offset -lt $eligible.Count;$offset+=4) {
        [void](Get-Budget 100)
        $batch=@($eligible.ToArray() | Select-Object -Skip $offset -First 4)
        Write-Host ('协议检测 '+($offset+1)+'～'+[Math]::Min($offset+4,$eligible.Count)+' / '+$eligible.Count) -ForegroundColor Cyan
        $plan=Get-FwProtocolListenerConfiguration -Nodes $batch
        $isolated=New-IsolatedConfiguration $nodes $original;$isolated.listeners=$plan.Listeners
        [IO.File]::WriteAllText((Join-Path $workDir 'config.yaml'),($isolated | ConvertTo-Json -Depth 60),$script:Utf8)
        try {
            $setup=Invoke-CoreRpc $session 'setupConfig' @{'selected-map'=@{};'test-url'=$testUrl} 12000
            if (-not [string]::IsNullOrEmpty([string]$setup)) { throw 'ISOLATED_CONFIG_APPLY_FAILED' }
            $ready=Invoke-CoreRpc $session 'startListener' $null 5000
            if ($ready -ne $true) { throw 'ISOLATED_LISTENER_NOT_READY' }
            Add-Result 'client' 'core.configuration' 'PASS' @{Dns='SYSTEM_DNS_BASELINE';LoopbackOnly=$true;TemporaryAuthenticatedListeners=$batch.Count;Tun=$false;SubscriptionRefresh=$false;OriginalClientUntouched=$true}
            $httpRows=@(Invoke-FwHttpBatch -Bindings $plan.Bindings -Targets $testTargets -TimeoutMs (Get-Budget 5000) -RpcPoll {param($targetId,$nodeIds) [void](Invoke-CoreRpc $session 'getTraffic' $false 1200)})
            foreach ($row in $httpRows) {
                $status='FAIL'
                if ($row.HttpResponseReceived -and $row.HttpStatus -ge 200 -and $row.HttpStatus -lt 400) { $status='PASS' }
                elseif ($row.HttpResponseReceived -or $row.Category -match '^LOCAL_|INTERNAL') { $status='UNKNOWN' }
                Add-Result $row.NodeId 'protocol.http' $status $row
            }
        } catch {
            if ($_.Exception.Message -eq 'DIAGNOSTIC_DEADLINE' -or $session.IsDisposed) { throw }
            foreach ($node in $batch) { Add-Result $node.Id 'protocol.http' 'UNKNOWN' @{Reason='ISOLATED_BATCH_UNAVAILABLE';ErrorType=$_.Exception.GetType().Name} }
        }
        [void](Invoke-CoreRpc $session 'getTraffic' $false 1200)
    }
    foreach ($node in $eligible) {
        $target=Get-EndpointTarget $node
        $key=$target.Host+'|'+$target.Port+'|'+$target.Protocol+'|'+$target.Transport+'|'+$target.Security+'|'+$target.Sni+'|'+$target.HttpHost+'|'+$target.Path
        if ($entryCache.ContainsKey($key)) {
            foreach ($event in $entryCache[$key]) {
                Add-Result $node.Id $event.Stage $event.Status @{SharedEntranceEvidence=$event.Target;ObservedUtc=$event.Time;Result=$event.Data}
            }
            continue
        }
        $before=$script:Events.Count
        try { Invoke-TargetProbe $target }
        catch { if ($_.Exception.Message -eq 'DIAGNOSTIC_DEADLINE') { throw };Add-Result $node.Id 'entrance.probe' 'UNKNOWN' @{Reason='PROBE_NOT_APPLICABLE_OR_FAILED';ErrorType=$_.Exception.GetType().Name} }
        $entryCache[$key]=@($script:Events.ToArray() | Select-Object -Skip $before | Where-Object { $_.Target -eq $node.Id })
    }
    $script:Observation.Findings=@(Get-FwFailureFindings $script:Observation @($script:Events.ToArray() | Where-Object { $_.Stage -eq 'protocol.http' }))

} catch {
    $completion='partial';$reason='COLLECTOR_ERROR';$safeErrors=@('DIAGNOSTIC_DEADLINE','CLIENT_NOT_FOUND','BUNDLED_CORE_NOT_FOUND','NO_READABLE_CONFIG','NO_NODE_ENDPOINTS_IN_LOCAL_CONFIG','ISOLATED_CONFIG_APPLY_FAILED','ISOLATED_LISTENER_NOT_READY','CORE_RPC_TIMEOUT','CORE_RPC_ERROR','REPORT_DIRECTORY_UNWRITABLE')
    if ($safeErrors -contains $_.Exception.Message) { $reason=$_.Exception.Message }
    Write-Host ('部分检测未完成：'+$reason+'。已有结果仍会保留。') -ForegroundColor Yellow
    if ($script:ReportRoot) { Add-Result 'collector' 'error' 'UNKNOWN' @{Reason=$reason;ErrorType=$_.Exception.GetType().Name;NativeErrorCodes=@(Get-FwNativeExceptionCodes $_.Exception);Line=$_.InvocationInfo.ScriptLineNumber} }
} finally {
    if ($session) {
        try { if (-not $session.IsDisposed) { [void](Invoke-CoreRpc $session 'shutdown' $null 1800) } } catch {}
        $session.Dispose()
    }
    if ($workDir -and (Test-Path -LiteralPath $workDir)) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $workDir) { $completion='partial';Add-Result 'collector' 'temporary.cleanup' 'UNKNOWN' @{Reason='TEMP_CONFIG_CLEANUP_FAILED';DirectoryName=[IO.Path]::GetFileName($workDir)} }
    }
    if ($script:ReportRoot) {
        try {
            Write-ClientSummary $nodes $completion
            $zip=$script:ReportRoot+'.zip'
            Compress-Archive -Path (Join-Path $script:ReportRoot '*') -DestinationPath $zip -CompressionLevel Optimal
            Write-Host ('检测结束，报告：'+$zip) -ForegroundColor Green
            Write-Host '请打开报告文件夹里的 检测报告.html 查看中文结论，并将 ZIP 发给客服。'
            Write-Host '请勿发送客户端原配置、数据库和密码。'
            if (-not $AllowNonWindows -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { Start-Process -FilePath (Join-Path $script:ReportRoot '检测报告.html') -ErrorAction SilentlyContinue }
        } catch { Write-Host ('打包失败，已有结果保存在：'+$script:ReportRoot) -ForegroundColor Yellow }
    }
    if (-not $NonInteractive) { [void](Read-Host '按回车关闭') }
}
