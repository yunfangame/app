param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

. (Join-Path $PSScriptRoot 'common.ps1')
$environment = Assert-FwArmRunner
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
$corePath = Join-Path $bundle 'FlClashCore.exe'
$helperPath = Join-Path $bundle 'FlClashHelperService.exe'
foreach ($path in @($corePath, $helperPath)) { if (-not (Get-FwPeIdentity $path).arm64) { throw 'The runtime fixture requires native ARM64 Core and Helper binaries' } }
if (Get-Process -Name FengWo, FlClashCore -ErrorAction SilentlyContinue) { throw 'The runner has another client or Core process; refusing a shared runtime test' }
$originalService = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
if ($originalService -and $originalService.PathName.Trim('"') -ine $helperPath) { throw 'A foreign Helper service is registered' }
if ($originalService -and $originalService.State -ne 'Stopped') { throw 'A Helper session is already running' }
Add-Type -Path (Join-Path $PSScriptRoot 'core_fixture.cs')
$checks = New-Object 'Collections.Generic.List[object]'
$frames = New-Object 'Collections.Generic.List[object]'
$fixtureHome = Join-Path $EvidenceDirectory 'synthetic-core-home'
[void][IO.Directory]::CreateDirectory($fixtureHome)
$pipe = $null
$direct = $null
$helperOwned = $false
$helperSession = $null
$failure = $null
$cleanupErrors = New-Object 'Collections.Generic.List[string]'
$rpcSequence = 0
$origin = New-Object FengWoArm64Tests.LoopbackHttp
$originUrl = 'http://127.0.0.1:' + $origin.Port + '/arm64-fixture'
$defaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceIndex, DestinationPrefix, NextHop, RouteMetric | Sort-Object InterfaceIndex, NextHop | ConvertTo-Json -Compress)
$dnsBefore = @(Get-DnsClientServerAddress | Select-Object InterfaceIndex, AddressFamily, ServerAddresses | Sort-Object InterfaceIndex, AddressFamily)

function Invoke-FwCoreRpc {
    param([string]$Method, [AllowNull()][object]$Arguments = $null)
    $script:rpcSequence++
    $id = 'arm64-' + $script:rpcSequence
    $pipe.Send((@{ id = $id; method = $Method; arguments = $Arguments } | ConvertTo-Json -Compress -Depth 12))
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt 20000) {
        $message = $pipe.Receive([Math]::Max(1, 20000 - [int]$watch.ElapsedMilliseconds)) | ConvertFrom-Json
        if ($message.id -cne $id) { continue }
        $frames.Add([ordered]@{ method = $Method; response = $message })
        if ($message.error) { throw ($Method + ': ' + ($message.error | ConvertTo-Json -Compress -Depth 8)) }
        return $message.result
    }
    throw ('Core RPC deadline: ' + $Method)
}

function Invoke-FwHelperHttp {
    param([string]$Method, [string]$Path, [AllowNull()][object]$Body = $null, [int]$ExpectedStatus = 200)
    $parameters = @{ Uri = ('http://127.0.0.1:47906/' + $Path); Method = $Method; NoProxy = $true; TimeoutSec = 15; SkipHttpErrorCheck = $true }
    if ($null -ne $Body) { $parameters.ContentType = 'application/json'; $parameters.Body = ($Body | ConvertTo-Json -Compress) }
    $response = Invoke-WebRequest @parameters
    if ($response.StatusCode -ne $ExpectedStatus) { throw ('Unexpected Helper HTTP status: ' + $Path + ' (' + $response.StatusCode + ')') }
    return $response
}

function Invoke-FwHelperCommand {
    param([string]$Command)
    $process = Start-Process -FilePath $helperPath -ArgumentList $Command -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory ('helper-' + $Command + '-stdout.txt')) -RedirectStandardError (Join-Path $EvidenceDirectory ('helper-' + $Command + '-stderr.txt'))
    try {
        $processHandle = $process.Handle
        if (-not $process.WaitForExit(20000)) { $process.Kill(); throw ('Owned Helper command timed out: ' + $Command) }
        if ($process.ExitCode -ne 0) { throw ('Helper command failed: ' + $Command + ' (' + $process.ExitCode + ')') }
    } finally { $process.Dispose() }
}

function Assert-FwRpcSuccess {
    param([string]$Method, [object]$Arguments, [object]$Expected)
    $result = Invoke-FwCoreRpc $Method $Arguments
    if ($result -cne $Expected) { throw ('Unexpected Core result: ' + $Method) }
}

function Test-FwMixedProxy {
    param([int]$Port)
    $request = [Net.HttpWebRequest]::Create($originUrl)
    $request.Proxy = New-Object Net.WebProxy(('http://127.0.0.1:' + $Port), $false)
    $request.Timeout = 10000
    $request.ReadWriteTimeout = 10000
    $response = $request.GetResponse()
    $reader = New-Object IO.StreamReader($response.GetResponseStream())
    try {
        if ([int]$response.StatusCode -ne 200 -or $reader.ReadToEnd() -cne 'FENGWO_ARM64_LOOPBACK_OK') { throw 'The Core mixed proxy did not reach the owned loopback HTTP fixture' }
    } finally { $reader.Dispose(); $response.Dispose() }
}

try {
    $portLease = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $portLease.Start()
    $mixedPort = $portLease.LocalEndpoint.Port
    $portLease.Stop()
    $config = @"
mixed-port: $mixedPort
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: warning
ipv6: false
find-process-mode: off
external-controller: ''
geodata-mode: false
geo-auto-update: false
dns:
  enable: false
tun:
  enable: false
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
"@
    [IO.File]::WriteAllText((Join-Path $fixtureHome 'config.yaml'), $config, (New-Object Text.UTF8Encoding($false)))
    $pipe = New-Object FengWoArm64Tests.CorePipe
    $direct = Start-Process -FilePath $corePath -ArgumentList $pipe.Address -WorkingDirectory $bundle -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory 'direct-core-stdout.txt') -RedirectStandardError (Join-Path $EvidenceDirectory 'direct-core-stderr.txt')
    $peerPid = $pipe.Accept($direct.Id, 10000)
    Assert-FwArmProcess $direct.Id
    Assert-FwRpcSuccess 'getIsInit' $null $false
    Assert-FwRpcSuccess 'initClash' @{ 'home-dir' = $fixtureHome; version = 2 } $true
    Assert-FwRpcSuccess 'getIsInit' $null $true
    $checks.Add([ordered]@{ name = 'direct-core-native-arm64-pipe-roundtrip'; passed = $true; peer_pid_verified = $peerPid })
    Assert-FwRpcSuccess 'shutdown' $null $true
    $pipe.Dispose()
    $pipe = $null
    if (-not $direct.WaitForExit(10000) -or $direct.ExitCode -ne 0) { throw 'The direct Core did not exit cleanly after IPC closure' }
    $direct.Dispose()
    $direct = $null

    $helperOwned = $true
    Invoke-FwHelperCommand 'install'
    $manifest = Get-Content -LiteralPath (Join-Path $bundle 'manifest.json') -Raw | ConvertFrom-Json
    $ping = Invoke-FwHelperHttp 'GET' ('ping?coreSha256=' + $manifest.coreSha256)
    if ($ping.StatusCode -ne 200 -or $ping.Content.Trim() -ine $helperPath -or $ping.Headers['x-flclash-helper-protocol'] -ne '6') { throw 'The privileged Helper handshake did not verify the installed binary and Core hash' }
    $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
    if ($service.State -ne 'Running' -or $service.PathName.Trim('"') -ine $helperPath) { throw 'The expected native Helper is not running in SCM' }
    Assert-FwArmProcess $service.ProcessId
    $checks.Add([ordered]@{ name = 'native-arm64-helper-scm-and-protocol-six'; passed = $true })
    $pipe = New-Object FengWoArm64Tests.CorePipe
    $helperSession = $pipe.SessionId
    $start = (Invoke-FwHelperHttp 'POST' 'start' @{ address = $pipe.Address; sessionId = $helperSession }).Content | ConvertFrom-Json
    if ($start.sessionId -cne $helperSession -or $start.pid -le 0) { throw 'Helper returned a different Core lease' }
    $peerPid = $pipe.Accept($start.pid, 10000)
    Assert-FwArmProcess $start.pid
    Assert-FwRpcSuccess 'initClash' @{ 'home-dir' = $fixtureHome; version = 2 } $true
    Assert-FwRpcSuccess 'setupConfig' @{ 'selected-map' = @{}; 'test-url' = $originUrl } ''
    Assert-FwRpcSuccess 'startListener' $null $true
    Test-FwMixedProxy $mixedPort
    $checks.Add([ordered]@{ name = 'helper-owned-arm64-core-pipe-and-mixed-http'; passed = $true; peer_pid_verified = $peerPid })
    $foreignSession = [Guid]::NewGuid().ToString('N')
    $foreign = (Invoke-FwHelperHttp 'POST' 'stop' @{ sessionId = $foreignSession } -ExpectedStatus 409).Content | ConvertFrom-Json
    if ($foreign.sessionId -cne $foreignSession -or $foreign.stopped -ne $false -or $foreign.reason -cne 'sessionMismatch') { throw 'Helper accepted stop for a different session' }
    Assert-FwRpcSuccess 'getIsInit' $null $true
    Test-FwMixedProxy $mixedPort
    $checks.Add([ordered]@{ name = 'foreign-helper-session-cannot-stop-owned-core'; passed = $true })

    $device = 'FengWoArm64-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    if (Get-NetAdapter -IncludeHidden | Where-Object Name -eq $device) { throw 'The synthetic adapter name already exists' }
    Assert-FwRpcSuccess 'updateConfig' @{ tun = @{ enable = $true; device = $device; stack = 'gvisor'; 'auto-route' = $false; 'dns-hijack' = @() } } ''
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $adapter = @(Get-NetAdapter -IncludeHidden | Where-Object { $_.Name -eq $device -and $_.Status -eq 'Up' })
        if ($adapter.Count -eq 1) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($adapter.Count -ne 1) { throw 'The ARM64 Wintun adapter was not observed active after Core readiness succeeded' }
    Test-FwMixedProxy $mixedPort
    $checks.Add([ordered]@{ name = 'native-arm64-helper-creates-active-wintun-adapter'; passed = $true; adapter_name = $device; auto_route = $false; dns_hijack = @() })
    Assert-FwRpcSuccess 'updateConfig' @{ tun = @{ enable = $false; 'auto-route' = $false; 'dns-hijack' = @() } } ''
    Assert-FwRpcSuccess 'stopListener' $null $true
    $stopped = (Invoke-FwHelperHttp 'POST' 'stop' @{ sessionId = $helperSession }).Content | ConvertFrom-Json
    if ($stopped.sessionId -cne $helperSession -or $stopped.stopped -ne $true) { throw 'Helper did not confirm owned Core termination' }
    $process = Get-Process -Id $start.pid -ErrorAction SilentlyContinue
    if ($process -and -not $process.WaitForExit(5000)) { throw 'Helper reported stopped while the owned Core remained alive' }
    if ($process) { $process.Dispose() }
    $helperSession = $null
    $checks.Add([ordered]@{ name = 'helper-stop-confirms-owned-core-exit'; passed = $true })
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($helperSession) { try { [void](Invoke-FwHelperHttp 'POST' 'stop' @{ sessionId = $helperSession }) } catch { $cleanupErrors.Add($_.Exception.Message) } }
    if ($pipe) { try { $pipe.Dispose() } catch { $cleanupErrors.Add($_.Exception.Message) } }
    if ($direct) {
        try {
            if (-not $direct.HasExited) { $direct.Kill(); if (-not $direct.WaitForExit(5000)) { throw 'Owned direct Core cleanup failed' } }
        } catch { $cleanupErrors.Add($_.Exception.Message) } finally { $direct.Dispose() }
    }
    if ($helperOwned) {
        try { Invoke-FwHelperCommand 'stop' } catch { $cleanupErrors.Add($_.Exception.Message) }
        if (-not $originalService) { try { Invoke-FwHelperCommand 'uninstall' } catch { $cleanupErrors.Add($_.Exception.Message) } }
    }
    try { $origin.Dispose() } catch { $cleanupErrors.Add($_.Exception.Message) }
    try {
        $defaultRoutesAfter = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceIndex, DestinationPrefix, NextHop, RouteMetric | Sort-Object InterfaceIndex, NextHop | ConvertTo-Json -Compress)
        if (($defaultRoutes -join '') -cne ($defaultRoutesAfter -join '')) { throw 'The owned no-auto-route fixture changed a default route' }
        $dnsAfter = @(Get-DnsClientServerAddress | Where-Object { $_.InterfaceIndex -in @($dnsBefore.InterfaceIndex) } | Select-Object InterfaceIndex, AddressFamily, ServerAddresses | Sort-Object InterfaceIndex, AddressFamily)
        if (($dnsBefore | ConvertTo-Json -Compress -Depth 6) -cne ($dnsAfter | ConvertTo-Json -Compress -Depth 6)) { throw 'The owned fixture changed DNS on an existing network interface' }
    } catch { $cleanupErrors.Add($_.Exception.Message) }
    $cleanupFailure = $cleanupErrors -join '; '
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'runtime-verification.json') ([ordered]@{ passed = (-not $failure -and -not $cleanupFailure); environment = $environment; checks = @($checks.ToArray()); rpc = @($frames.ToArray()); failure = $failure; cleanup_failure = $cleanupFailure; owned_loopback_fixtures_only = $true; no_real_account = $true; no_system_proxy_write = $true; tun_auto_route = $false; tun_dns_hijack = @() })
}
if ($failure) { throw $failure }
if ($cleanupFailure) { throw $cleanupFailure }
