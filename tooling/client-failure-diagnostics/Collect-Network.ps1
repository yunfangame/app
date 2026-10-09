[CmdletBinding()]
param(
    [string]$TargetsFile = '',
    [switch]$NoTrace,
    [switch]$NonInteractive,
    [switch]$LibraryOnly,
    [switch]$SnapshotOnly,
    [switch]$AllowNonWindows,
    [ValidateRange(30,600)][int]$MaxSeconds = 240,
    [ValidateRange(1,5)][int]$Rounds = 3
)

$ErrorActionPreference = 'Stop'
$script:ToolRoot = $PSScriptRoot
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Watch = [Diagnostics.Stopwatch]::StartNew()
$script:Events = New-Object 'System.Collections.Generic.List[object]'
$script:CurlExe = $null
$script:ReportRoot = $null

function Get-Field($Value, [string]$Name, $Default = '') {
    if ($null -eq $Value) { return $Default }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $Default
    }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Get-Budget([int]$Requested = 5000) {
    $left = ($MaxSeconds * 1000) - [int]$script:Watch.ElapsedMilliseconds
    if ($left -le 0) { throw 'DIAGNOSTIC_DEADLINE' }
    return [Math]::Min($Requested, $left)
}

function Test-AddressName([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 253) { return $false }
    $address = $null
    if ([Net.IPAddress]::TryParse($Value.Trim('[',']'), [ref]$address)) { return $true }
    if ($Value -match '[^a-zA-Z0-9_.-]' -or $Value.StartsWith('-')) { return $false }
    return [Uri]::CheckHostName($Value) -eq [UriHostNameType]::Dns
}

function Convert-Base64Text([string]$Value) {
    $encoded = $Value.Replace('-','+').Replace('_','/')
    while (($encoded.Length % 4) -ne 0) { $encoded += '=' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
}

function Convert-NodeInput([string]$Value, [string]$Role, [int]$Index) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 32768) { throw 'INVALID_NODE_INPUT' }
    $protocol = ''; $targetHost = ''; $targetPort = 0; $security = 'unknown'
    $transport = 'tcp'; $sni = ''; $httpHost = ''; $requestPath = '/'
    if ($Value.Trim().StartsWith('{')) {
        $item = $Value | ConvertFrom-Json
        $protocol = [string](Get-Field $item 'protocol' 'unknown')
        $targetHost = [string](Get-Field $item 'host')
        $targetPort = [int](Get-Field $item 'port' 0)
        $security = [string](Get-Field $item 'security' 'unknown')
        $transport = [string](Get-Field $item 'transport' 'tcp')
        $sni = [string](Get-Field $item 'sni')
        $httpHost = [string](Get-Field $item 'httpHost')
        $requestPath = [string](Get-Field $item 'path' '/')
    } elseif ($Value -match '^vmess://') {
        $item = (Convert-Base64Text $Value.Substring(8)) | ConvertFrom-Json
        $protocol = 'vmess'; $targetHost = [string](Get-Field $item 'add')
        $targetPort = [int](Get-Field $item 'port' 0)
        $transport = [string](Get-Field $item 'net' 'tcp')
        $security = [string](Get-Field $item 'tls' 'none')
        if ([string]::IsNullOrEmpty($security)) { $security = 'none' }
        $sni = [string](Get-Field $item 'sni')
        $httpHost = [string](Get-Field $item 'host')
        $requestPath = [string](Get-Field $item 'path' '/')
    } else {
        $raw = $Value.Trim()
        if ($raw -notmatch '^[a-zA-Z0-9+.-]+://') { $raw = 'tcp://' + $raw }
        $uri = $null
        if (-not [Uri]::TryCreate($raw, [UriKind]::Absolute, [ref]$uri)) { throw 'INVALID_NODE_URI' }
        $protocol = $uri.Scheme.ToLowerInvariant(); $targetHost = $uri.DnsSafeHost.Trim('[',']')
        $targetPort = $uri.Port
        if ($targetPort -lt 1) { throw 'EXPLICIT_NODE_PORT_REQUIRED' }
        $query = @{}
        foreach ($entry in $uri.Query.TrimStart('?').Split('&')) {
            if (-not $entry) { continue }
            $pair = $entry.Split('=',2)
            $key = [Uri]::UnescapeDataString($pair[0]).ToLowerInvariant()
            $val = ''; if ($pair.Length -eq 2) { $val = [Uri]::UnescapeDataString($pair[1].Replace('+',' ')) }
            if (@('security','tls','sni','peer','servername','type','net','host','path') -contains $key) { $query[$key] = $val }
        }
        if (@('trojan','anytls','hysteria2','hy2','tuic','tls') -contains $protocol) { $security = 'tls' }
        if (@('vless','ss') -contains $protocol) { $security = 'none' }
        if ($query.ContainsKey('security')) { $security = $query['security'] }
        if ($query.ContainsKey('tls') -and $query['tls'] -match '^(true|1|tls)$') { $security = 'tls' }
        foreach ($key in @('sni','peer','servername')) { if ($query.ContainsKey($key)) { $sni = $query[$key]; break } }
        foreach ($key in @('type','net')) { if ($query.ContainsKey($key)) { $transport = $query[$key]; break } }
        if ($query.ContainsKey('host')) { $httpHost = $query['host'] }
        if ($query.ContainsKey('path')) { $requestPath = $query['path'] }
    }
    $protocol = $protocol.ToLowerInvariant(); $transport = $transport.ToLowerInvariant(); $security = $security.ToLowerInvariant()
    if (@('vless','vmess','trojan','anytls','hy2','hysteria2','tuic','ss','tcp','tls','unknown') -notcontains $protocol) { throw 'UNSUPPORTED_NODE_PROTOCOL' }
    $targetHost = $targetHost.Trim('[',']')
    if (-not (Test-AddressName $targetHost) -or $targetPort -lt 1 -or $targetPort -gt 65535) { throw 'INVALID_NODE_HOST_OR_PORT' }
    if ($sni -and -not (Test-AddressName $sni)) { throw 'INVALID_SNI' }
    if ($httpHost -and $httpHost -notmatch '^[a-zA-Z0-9_.:\[\]-]+$') { throw 'INVALID_HTTP_HOST' }
    if ($requestPath.Length -gt 4096 -or $requestPath -match '[\r\n\x00\x22]') { throw 'INVALID_HTTP_PATH' }
    if (-not $requestPath.StartsWith('/')) { $requestPath = '/' + $requestPath }
    if (-not $sni -and [Uri]::CheckHostName($targetHost) -eq [UriHostNameType]::Dns) { $sni = $targetHost }
    if (-not $httpHost) { $httpHost = $targetHost }
    if (@('hy2','hysteria2','tuic') -contains $protocol) { $transport = 'quic' }
    $label = 'problem-' + $Index; if ($Role -eq 'control') { $label = 'known-working-vless' }
    return [pscustomobject]@{ Label=$label; Role=$Role; Host=$targetHost; Port=$targetPort; Protocol=$protocol; Transport=$transport; Security=$security; Sni=$sni; HttpHost=$httpHost; Path=$requestPath; UdpOnly=(@('hy2','hysteria2','tuic') -contains $protocol) }
}

function Get-SafeTarget($Target) {
    return [pscustomobject]@{ Label=$Target.Label; Role=$Target.Role; Host=$Target.Host; Port=$Target.Port; Protocol=$Target.Protocol; Transport=$Target.Transport; Security=$Target.Security; Sni=$Target.Sni; HttpHost=$Target.HttpHost; HasCustomPath=($Target.Path -ne '/'); UdpOnly=$Target.UdpOnly }
}

function Add-Result([string]$Label, [string]$Stage, [string]$Status, $Data) {
    $record = [pscustomobject]@{ Time=(Get-Date).ToString('o'); Target=$Label; Stage=$Stage; Status=$Status; Data=$Data }
    $script:Events.Add($record)
    if ($script:ReportRoot) {
        [IO.File]::AppendAllText((Join-Path $script:ReportRoot 'results.jsonl'), (($record | ConvertTo-Json -Depth 12 -Compress) + [Environment]::NewLine), $script:Utf8)
    }
    Write-Host ('[{0}] {1} / {2}' -f $Status,$Label,$Stage)
}

function Quote-Argument([string]$Value) {
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-BoundedProcess([string]$Executable, [string[]]$Arguments, [int]$TimeoutMs) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (($Arguments | ForEach-Object { Quote-Argument $_ }) -join ' ')
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $script:Utf8; $start.StandardErrorEncoding = $script:Utf8
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and [IO.Path]::GetFileName($Executable) -eq 'tracert.exe') { $start.StandardOutputEncoding=[Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) {
            try { $process.Kill() } catch {}
            [void]$process.WaitForExit(1000)
            return [pscustomobject]@{ ExitCode=-1; TimedOut=$true; Output=''; ErrorType='PROCESS_TIMEOUT' }
        }
        return [pscustomobject]@{ ExitCode=$process.ExitCode; TimedOut=$false; Output=$stdoutTask.GetAwaiter().GetResult(); ErrorType='' }
    } catch {
        return [pscustomobject]@{ ExitCode=-2; TimedOut=$false; Output=''; ErrorType=$_.Exception.GetType().Name }
    } finally { $process.Dispose() }
}

function Test-WebSocket($Target, [string]$Address) {
    if (-not $script:CurlExe) { return [pscustomobject]@{ Status='UNKNOWN'; Reason='CURL_NOT_AVAILABLE' } }
    if (@('tls','none') -notcontains $Target.Security) { return [pscustomobject]@{ Status='SKIPPED'; Reason='NONSTANDARD_OR_UNKNOWN_TLS' } }
    $budget = Get-Budget 4500
    $scheme = 'http'; $name = $Target.Host
    if ($Target.Security -eq 'tls') { $scheme='https'; $name=$Target.Sni; if (-not $name) { return [pscustomobject]@{ Status='UNKNOWN'; Reason='SNI_NOT_PROVIDED' } } }
    if ($name.Contains(':')) { $name = '[' + $name.Trim('[',']') + ']' }
    $connectIP = $Address; if ($Address.Contains(':')) { $connectIP='['+$Address+']' }
    $nonce = New-Object byte[] 16
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($nonce) } finally { $random.Dispose() }
    $key = [Convert]::ToBase64String($nonce)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try { $expected=[Convert]::ToBase64String($sha1.ComputeHash([Text.Encoding]::ASCII.GetBytes($key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))) } finally { $sha1.Dispose() }
    $headerFile = [IO.Path]::GetTempFileName()
    $nullFile = 'NUL'; if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { $nullFile='/dev/null' }
    try {
        $arguments = @('--silent','--noproxy','*','--http1.1','--connect-timeout','3','--max-time',([Math]::Max(1,[Math]::Floor(($budget-300)/1000))).ToString(),'--max-filesize','1048576','--output',$nullFile,'--dump-header',$headerFile,'--connect-to',('{0}:{1}:{2}:{1}' -f $name,$Target.Port,$connectIP),'--header',('Host: '+$Target.HttpHost),'--header','Connection: Upgrade','--header','Upgrade: websocket','--header','Sec-WebSocket-Version: 13','--header',('Sec-WebSocket-Key: '+$key),('--url'),('{0}://{1}:{2}{3}' -f $scheme,$name,$Target.Port,$Target.Path))
        $result = Invoke-BoundedProcess $script:CurlExe $arguments $budget
        $headers = [IO.File]::ReadAllText($headerFile)
        $blocks=@($headers -split '\r?\n\r?\n' | Where-Object { $_ -match '^HTTP/' })
        if ($blocks.Count -gt 0) { $headers=$blocks[$blocks.Count-1] }
        $statusCodes = [regex]::Matches($headers,'(?m)^HTTP/\S+\s+(\d{3})')
        $statusCode = 0; if ($statusCodes.Count -gt 0) { $statusCode=[int]$statusCodes[$statusCodes.Count-1].Groups[1].Value }
        $connectionTokens=@([regex]::Matches($headers,'(?im)^Connection:[ \t]*([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Split(',') } | ForEach-Object { $_.Trim() })
        $accepted = $statusCode -eq 101 -and $headers -match '(?im)^Upgrade:[ \t]*websocket[ \t]*\r?$' -and $connectionTokens -contains 'Upgrade' -and $headers -match ('(?im)^Sec-WebSocket-Accept:[ \t]*'+[regex]::Escape($expected)+'[ \t]*\r?$')
        $status='FAIL';if ($accepted) { $status='PASS' }
        return [pscustomobject]@{ Status=$status; HttpStatus=$statusCode; ValidUpgrade=$accepted; CurlExitCode=$result.ExitCode; TimedOut=$result.TimedOut; ErrorType=$result.ErrorType; Note='HTTP/WS reachability only; no proxy authentication was attempted.' }
    } finally { Remove-Item -LiteralPath $headerFile -Force -ErrorAction SilentlyContinue }
}

function Get-NetworkSnapshot {
    $snapshot = [ordered]@{ OS=[Environment]::OSVersion.VersionString; PowerShell=$PSVersionTable.PSVersion.ToString(); DotNet=[Environment]::Version.ToString(); Time=(Get-Date).ToString('o'); TimeZone=[TimeZoneInfo]::Local.Id; Adapters=@(); Routes=@(); Dns=@(); ProxyEnabled=$null; ProxyServerConfigured=$null; PacConfigured=$null; ProbeRouting='TCP/SSL and curl --noproxy bypass HTTP proxy only; VPN/TUN routes may still apply.' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $snapshot }
    try { $snapshot.Adapters=@(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Select-Object ifIndex,Name,InterfaceDescription,Status,Virtual,HardwareInterface) } catch { $snapshot.AdapterError=$_.Exception.GetType().Name }
    try { $snapshot.Routes=@(Get-NetRoute -ErrorAction Stop | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1','::/0','::/1','8000::/1') } | Select-Object ifIndex,DestinationPrefix,NextHop,RouteMetric) } catch { $snapshot.RouteError=$_.Exception.GetType().Name }
    try { $snapshot.Dns=@(Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object InterfaceIndex,AddressFamily,ServerAddresses) } catch { $snapshot.DnsError=$_.Exception.GetType().Name }
    try { $proxy=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings';$snapshot.ProxyEnabled=([int]$proxy.ProxyEnable -eq 1);$snapshot.ProxyServerConfigured=(-not [string]::IsNullOrEmpty([string]$proxy.ProxyServer));$snapshot.PacConfigured=(-not [string]::IsNullOrEmpty([string]$proxy.AutoConfigURL)) } catch {}
    return $snapshot
}

function Get-BoundedNetworkSnapshot {
    $executable=Join-Path $PSHOME 'powershell.exe'
    if ($PSVersionTable.PSEdition -eq 'Core') { $executable=Join-Path $PSHOME 'pwsh.exe' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { $executable=Join-Path $PSHOME 'pwsh' }
    $result=Invoke-BoundedProcess $executable @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $script:ToolRoot 'Collect-Network.ps1'),'-SnapshotOnly') (Get-Budget 12000)
    if (-not $result.TimedOut -and $result.ExitCode -eq 0) {
        try { return ($result.Output | ConvertFrom-Json) } catch {}
    }
    return [ordered]@{ OS=[Environment]::OSVersion.VersionString; PowerShell=$PSVersionTable.PSVersion.ToString(); Time=(Get-Date).ToString('o'); SnapshotStatus='PARTIAL'; SnapshotError='Network inventory unavailable or exceeded 12 seconds; node probes will continue.' }
}

function Invoke-TargetProbe($Target) {
    Write-Host ('正在检查 {0}：{1}:{2} ({3}/{4}/{5})' -f $Target.Label,$Target.Host,$Target.Port,$Target.Protocol,$Target.Transport,$Target.Security) -ForegroundColor Cyan
    Add-Result $Target.Label 'target' 'INFO' (Get-SafeTarget $Target)
    $addresses = New-Object 'System.Collections.Generic.List[string]'
    $parsed = $null
    if ([Net.IPAddress]::TryParse($Target.Host,[ref]$parsed)) {
        $addresses.Add($parsed.ToString());Add-Result $Target.Label 'dns.numeric' 'SKIPPED' @{ Addresses=@($parsed.ToString()) }
    } else {
        $system=[FengWoNetworkProbe]::ResolveSystem($Target.Host,(Get-Budget 4000))
        $status='FAIL';if ($system.Addresses.Count -gt 0) { $status='PASS' }
        Add-Result $Target.Label 'dns.system' $status $system
        foreach ($ip in $system.Addresses) { if (-not $addresses.Contains($ip)) { $addresses.Add($ip) } }
        foreach ($resolver in @('223.5.5.5','119.29.29.29')) {
            foreach ($kind in @('A','AAAA')) {
                $dns=[FengWoNetworkProbe]::QueryDns($Target.Host,$resolver,$kind,(Get-Budget 1500))
                $status='UNKNOWN'
                if (-not $dns.Truncated -and -not $dns.Error) {
                    if ($dns.Rcode -eq 0) { $status='PASS' }
                    elseif ($dns.Rcode -gt 0) { $status='FAIL' }
                } elseif (-not $dns.Truncated -and $dns.Rcode -gt 0) { $status='FAIL' }
                Add-Result $Target.Label ('dns.'+$resolver+'.'+$kind) $status $dns
                foreach ($ip in $dns.Addresses) { if (-not $addresses.Contains($ip)) { $addresses.Add($ip) } }
            }
        }
    }
    if ($addresses.Count -eq 0) { Add-Result $Target.Label 'node.overall' 'UNKNOWN' @{ Reason='NO_RESOLVED_ADDRESS'; Note='DNS unresolved; this does not establish an ISP block.' };return }
    $selected=@(@($addresses | Where-Object { $_ -notmatch ':' } | Select-Object -First 2)+@($addresses | Where-Object { $_ -match ':' } | Select-Object -First 1))
    Add-Result $Target.Label 'address.selection' 'INFO' @{ Available=@($addresses.ToArray()); Tested=$selected; Note='At most 2 IPv4 and 1 IPv6 addresses sampled; DNS differences alone do not prove poisoning.' }
    if ($Target.UdpOnly) {
        Add-Result $Target.Label 'quic.protocol' 'UNKNOWN' @{ Reason='QUIC_CORE_TEST_REQUIRED'; Note='Hy2/TUIC use UDP/QUIC. TCP/TLS probes are deliberately not used to judge them. Use matching client logs and a second network.' }
        return
    }
    $connected = New-Object 'System.Collections.Generic.List[string]'
    foreach ($ip in $selected) {
        for ($round=1;$round -le $Rounds;$round++) {
            $tcp=[FengWoNetworkProbe]::ProbeTcp($ip,$Target.Port,(Get-Budget 2200))
            $status='FAIL';if ($tcp.Success) { $status='PASS';if (-not $connected.Contains($ip)) { $connected.Add($ip) } }
            Add-Result $Target.Label 'tcp' $status @{ Address=$ip; Port=$Target.Port; Round=$round; Milliseconds=$tcp.Milliseconds; Error=$tcp.Error }
        }
    }
    if ($Target.Security -eq 'reality') {
        Add-Result $Target.Label 'reality.protocol' 'UNKNOWN' @{ Reason='MATCHING_CORE_REQUIRED'; Note='Ordinary TLS cannot validate REALITY authentication, fingerprint, shortId or flow.' }
    } elseif ($Target.Security -eq 'tls') {
        if (-not $Target.Sni) { Add-Result $Target.Label 'tls' 'UNKNOWN' @{ Reason='SNI_NOT_PROVIDED'; Note='No substitute SNI was guessed.' } }
        else {
            foreach ($ip in @($connected.ToArray() | Select-Object -First 2)) {
                $tls=[FengWoNetworkProbe]::ProbeTls($ip,$Target.Port,$Target.Sni,(Get-Budget 5000),$false)
                $status='FAIL';if ($tls.Success) { $status='PASS' }
                Add-Result $Target.Label 'tls.default' $status @{ Address=$ip; Sni=$Target.Sni; Result=$tls; Note='Windows TLS probe differs from client uTLS/ALPN; failure is not proof of a protocol block.' }
                if (-not $tls.Success) {
                    $tls12=[FengWoNetworkProbe]::ProbeTls($ip,$Target.Port,$Target.Sni,(Get-Budget 4000),$true)
                    $status='FAIL';if ($tls12.Success) { $status='PASS' }
                    Add-Result $Target.Label 'tls.1.2' $status @{ Address=$ip; Sni=$Target.Sni; Result=$tls12 }
                }
            }
        }
    } else { Add-Result $Target.Label 'tls' 'SKIPPED' @{ Reason=('NODE_SECURITY_'+$Target.Security.ToUpperInvariant()) } }
    if (@('ws','websocket') -contains $Target.Transport) {
        if ($connected.Count -gt 0) { $ws=Test-WebSocket $Target $connected[0];Add-Result $Target.Label 'websocket' $ws.Status $ws }
        else { Add-Result $Target.Label 'websocket' 'SKIPPED' @{ Reason='NO_TCP_CONNECTION' } }
    } elseif (@('grpc','xhttp','h2','httpupgrade') -contains $Target.Transport) { Add-Result $Target.Label 'transport.protocol' 'UNKNOWN' @{ Reason='MATCHING_CORE_REQUIRED'; Transport=$Target.Transport } }
    Add-Result $Target.Label 'proxy.authentication' 'UNKNOWN' @{ Reason='NOT_TESTED_BY_ENTRANCE_PROBE'; Note='This entrance probe does not send node authentication. Separate protocol.http tests use the original node credentials internally. TCP/TLS/WS success alone does not establish proxy authentication or outbound access.' }
    if (-not $NoTrace -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $trace=Get-Command tracert.exe -ErrorAction SilentlyContinue
        if ($trace) {
            $ip=$selected[0];$family='-4';if ($ip -match ':') { $family='-6' }
            $traceResult=Invoke-BoundedProcess $trace.Source @('-d',$family,'-h','12','-w','350',$ip) (Get-Budget 12000)
            Add-Result $Target.Label 'route.trace' 'INFO' @{ Address=$ip; ExitCode=$traceResult.ExitCode; TimedOut=$traceResult.TimedOut; Output=$traceResult.Output; Note='Missing ICMP hops are not evidence of blocking.' }
        }
    }
}

function Write-Summary($Targets, [string]$NetworkLabel, $SystemInfo, [string]$Completion) {
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('蜂窝 · 江苏移动节点入口对照诊断')
    $lines.Add('网络标记：'+$NetworkLabel);$lines.Add('时间：'+(Get-Date).ToString('o'));$lines.Add('完成状态：'+$Completion)
    $lines.Add('这里只判读DNS/TCP/TLS/WS层，不把探针失败直接认定为运营商封锁。')
    $lines.Add('API登录成功与节点数据路径分别独立；TCP直连仍可能经过系统VPN/TUN路由。')
    $lines.Add('')
    foreach ($target in $Targets) {
        $rows=@($script:Events | Where-Object { $_.Target -eq $target.Label })
        $tcp=@($rows | Where-Object { $_.Stage -eq 'tcp' });$passed=@($tcp | Where-Object { $_.Status -eq 'PASS' })
        $tls=@($rows | Where-Object { $_.Stage -eq 'tls.default' });$tlsPassed=@($tls | Where-Object { $_.Status -eq 'PASS' })
        $lines.Add(('{0}: {1}:{2} | {3}/{4}/{5}' -f $target.Label,$target.Host,$target.Port,$target.Protocol,$target.Transport,$target.Security))
        if ($target.UdpOnly) { $lines.Add('  DNS结果请见明细；QUIC/UDP是否可用待客户端协议日志确认，未用TCP结果判定。') }
        elseif ($tcp.Count -eq 0) { $lines.Add('  未完成TCP检测：查看DNS结果或是否达到检测时间上限。') }
        elseif ($passed.Count -eq 0) { $lines.Add('  所测IP的TCP连接均失败。可能是入口IP/端口、路由、服务监听或过滤；需对照其他运营商。') }
        elseif ($passed.Count -lt $tcp.Count) { $lines.Add(('  TCP {0}/{1} 次成功：有间歇性或不同IP/地址族差异，查看results.jsonl。' -f $passed.Count,$tcp.Count)) }
        else { $lines.Add(('  TCP {0}/{1} 次成功。' -f $passed.Count,$tcp.Count)) }
        if ($tls.Count -gt 0) { $lines.Add(('  标准TLS {0}/{1} 次成功；这是探针结果，不等同节点协议认证。' -f $tlsPassed.Count,$tls.Count)) }
        if ($target.Security -eq 'reality') { $lines.Add('  Reality认证未测试，普通TLS探针无法替代。') }
        $ws=@($rows | Where-Object { $_.Stage -eq 'websocket' });if ($ws.Count -gt 0) { $lines.Add('  WS结果：'+$ws[0].Status+'，HTTP状态 '+$ws[0].Data.HttpStatus) }
        $lines.Add('')
    }
    $control=@($script:Events | Where-Object { $_.Target -eq 'known-working-vless' -and $_.Stage -eq 'tcp' })
    if ($control.Count -gt 0 -and @($control | Where-Object { $_.Status -eq 'PASS' }).Count -eq 0) { $lines.Add('注意：已知可用对照在本次TCP探针也全部失败，先核对链接、检测时网络及TUN状态，不能直接解释为协议被封。') }
    $lines.Add('下一步：保持同一组节点，在联通/电信热点再运行一次；把两份ZIP和当时客户端导出的日志一起发给客服。')
    $lines.Add('若入口层均正常而客户端仍超时，应检查真实协议认证、节点出口和测速目标；需要服务端抓包/日志才能继续区分。')
    $lines.Add('日志未包含UUID、密码、订阅链接、完整节点链接或WS路径；包含检测所需的节点域名/IP/SNI、网络路由信息。')
    [IO.File]::WriteAllLines((Join-Path $script:ReportRoot 'summary.txt'),$lines.ToArray(),$script:Utf8)
    $report=[ordered]@{ Version='1.0'; Network=$NetworkLabel; Completion=$Completion; System=$SystemInfo; Targets=@($Targets | ForEach-Object { Get-SafeTarget $_ }); Results=@($script:Events.ToArray()) }
    [IO.File]::WriteAllText((Join-Path $script:ReportRoot 'report.json'),($report | ConvertTo-Json -Depth 16),$script:Utf8)
}

if ($SnapshotOnly) {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    [Console]::Write((Get-NetworkSnapshot | ConvertTo-Json -Depth 8 -Compress))
    return
}
if ($LibraryOnly) { return }
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and -not $AllowNonWindows) { throw 'This diagnostic package runs on Windows 10/11.' }
$targets=New-Object 'System.Collections.Generic.List[object]'
$networkLabel='江苏移动';$completion='completed';$systemInfo=$null
try {
    Write-Host '蜂窝 · 节点超时对照诊断（不修改网络设置）' -ForegroundColor Cyan
    Write-Host '先断开蜂窝/其他代理的连接和虚拟网卡模式，保留普通网络；不要卸载应用。'
    Write-Host '检测不发送节点密码，不自动上传报告。TCP探针仍受VPN/TUN路由影响。'
    if (-not $NonInteractive) {
        [void](Read-Host '准备好后按回车开始')
        $label=Read-Host '网络标记：江苏移动/联通热点/电信热点（回车默认江苏移动）'
        if ($label) { $networkLabel=($label -replace '[\r\n]',' ').Substring(0,[Math]::Min(40,$label.Length)) }
    }
    if ($TargetsFile) {
        $items=@([IO.File]::ReadAllText((Resolve-Path -LiteralPath $TargetsFile)) | ConvertFrom-Json)
        if ($items.Count -lt 2 -or $items.Count -gt 4) { throw 'TARGETS_FILE_REQUIRES_2_TO_4_NODES' }
        for ($i=0;$i -lt $items.Count;$i++) { $role='problem';if ($i -eq 0) { $role='control' };$targets.Add((Convert-NodeInput ($items[$i] | ConvertTo-Json -Compress) $role $i)) }
    } else {
        if ($NonInteractive) { throw 'TARGETS_FILE_REQUIRED' }
        for ($i=0;$i -lt 4;$i++) {
            $prompt='粘贴第'+$i+'个超时节点链接（VLESS/VMess/Trojan/AnyTLS/Hy2/TUIC；回车结束）'
            $role='problem';if ($i -eq 0) { $role='control';$prompt='粘贴一个已确认可用的直连VLESS分享链接' }
            $value=Read-Host $prompt
            if ([string]::IsNullOrWhiteSpace($value)) { if ($i -lt 2) { throw 'ONE_CONTROL_AND_ONE_PROBLEM_REQUIRED' };break }
            try { $targets.Add((Convert-NodeInput $value $role $i)) } catch { throw ('NODE_'+$i+'_INVALID: '+$_.Exception.GetType().Name+'，请核对分享链接，或用targets.example.json填写域名、端口和SNI。') } finally { $value=$null }
        }
    }
    $desktop=[Environment]::GetFolderPath('Desktop');if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { $desktop=$script:ToolRoot }
    $name='FengWo-Network-Report-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
    $script:ReportRoot=Join-Path $desktop $name;[void](New-Item -ItemType Directory -Path $script:ReportRoot)
    $script:Watch.Restart()
    $systemInfo=Get-BoundedNetworkSnapshot
    [IO.File]::WriteAllText((Join-Path $script:ReportRoot 'system.json'),($systemInfo | ConvertTo-Json -Depth 8),$script:Utf8)
    if (-not ('FengWoNetworkProbe' -as [type])) { Add-Type -Path (Join-Path $script:ToolRoot 'NetworkProbe.cs') }
    $curl=Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl -and $AllowNonWindows) { $curl=Get-Command curl -CommandType Application -ErrorAction SilentlyContinue }
    if ($curl) { $script:CurlExe=$curl.Source }
    foreach ($target in $targets) { Invoke-TargetProbe $target }
} catch {
    $completion='partial'
    $reason=$_.Exception.GetType().Name
    if ($_.Exception.Message -eq 'DIAGNOSTIC_DEADLINE') { $reason='DIAGNOSTIC_DEADLINE' }
    Write-Host ('检测未全部完成：'+$reason+'。已有结果仍会保存。') -ForegroundColor Yellow
    if ($script:ReportRoot) { Add-Result 'collector' 'error' 'UNKNOWN' @{ Type=$reason; Line=$_.InvocationInfo.ScriptLineNumber } }
    else { Write-Host '尚未生成报告。请确认已填写一个正常节点和至少一个异常节点；也可使用targets.example.json。' }
} finally {
    if ($script:ReportRoot) {
        try {
            Write-Summary $targets.ToArray() $networkLabel $systemInfo $completion
            $zip=$script:ReportRoot+'.zip'
            Compress-Archive -Path (Join-Path $script:ReportRoot '*') -DestinationPath $zip -CompressionLevel Optimal
            Write-Host ('检测结束，报告：'+$zip) -ForegroundColor Green
            Write-Host '请把ZIP发回分析；若只有部分结果，ZIP仍有诊断价值。'
        } catch { Write-Host ('打包失败，原始报告保留在：'+$script:ReportRoot) -ForegroundColor Yellow }
    }
    if (-not $NonInteractive) { [void](Read-Host '按回车关闭') }
}
