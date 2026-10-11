param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../arm64/common.ps1')
$environment = Assert-FwNativeRunner -Architecture $Architecture
$BundleDirectory = (Resolve-Path -LiteralPath $BundleDirectory).Path
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$expectedMachine = if ($Architecture -eq 'arm64') { '0xaa64' } else { '0x8664' }
$corePath = Join-Path $BundleDirectory 'FengWoCore.exe'
if ((Get-FwPeIdentity $corePath).machine -cne $expectedMachine) { throw 'The chain tests require the actual native packaged FengWo Core' }
if (Get-NetTCPConnection -State Listen -LocalPort 17980, 31811, 31813, 31814, 31815, 31816 -ErrorAction SilentlyContinue) { throw 'Pre-existing fixture ports prevent isolation' }
Add-Type -Path (Join-Path $PSScriptRoot 'core_windows_fixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot '../arm64/coexistence_proxy_fixture.cs')
$proxyGuard = [FengWoCoexistenceTests.ProxyFixture]::new($Architecture)
$proxyBefore = $proxyGuard.Capture()
$fixture = $null
$pipe = $null
$core = $null
$failure = $null
$cleanupErrors = [Collections.Generic.List[string]]::new()
$results = [Collections.Generic.List[object]]::new()
$rpcFrames = [Collections.Generic.List[object]]::new()
$rpcSequence = 0
$scratch = Join-Path $env:RUNNER_TEMP ('fengwo-real-chain-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)

function Invoke-ChainRpc([string]$Method, [AllowNull()][object]$Arguments = $null) {
    $script:rpcSequence++
    $id = 'chain-' + $script:rpcSequence
    $pipe.Send((@{ id = $id; method = $Method; arguments = $Arguments } | ConvertTo-Json -Compress -Depth 16))
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt 20000) {
        $raw = $pipe.Receive([Math]::Max(1, 20000 - [int]$watch.ElapsedMilliseconds))
        $message = $raw | ConvertFrom-Json -AsHashtable
        if ($message -isnot [Collections.IDictionary]) { throw 'Core sent a non-object response' }
        if ($message['id'] -cne $id) { continue }
        $rpcFrames.Add([ordered]@{ method = $Method; elapsed_ms = $watch.ElapsedMilliseconds; response = $message })
        if ($message.Contains('error') -and $null -ne $message['error']) { throw ('Core rejected the synthetic ' + $Method + ' request') }
        if (-not $message.Contains('result')) { throw 'Core omitted its RPC result' }
        return $message['result']
    }
    throw ('Core RPC exceeded its deadline: ' + $Method)
}

function Request-ChainOrigin([string]$Name, [string]$Url, [int]$Timeout = 10) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = [FengWoRealWindowsTests.HttpProbe]::Get($Url, $Name, $Timeout, 17980)
        return [ordered]@{ status = $response.Status; body = $response.Body; elapsed_ms = $clock.ElapsedMilliseconds; error_type = $null }
    } catch {
        return [ordered]@{ status = $null; body = $null; elapsed_ms = $clock.ElapsedMilliseconds; error_type = $_.Exception.GetType().Name }
    }
}

function Stop-ChainCore {
    if (-not $core) { return }
    if (-not $core.HasExited) {
        if ((Invoke-ChainRpc 'shutdown') -ne $true) { throw 'The owned chain Core did not accept normal shutdown' }
    }
    if ($pipe) { $pipe.Dispose(); $script:pipe = $null }
    if (-not $core.WaitForExit(10000)) { throw 'The owned chain Core did not exit normally' }
    if ($core.ExitCode -ne 0) { throw 'The owned chain Core normal shutdown returned a failure' }
    $core.Dispose()
    $script:core = $null
}

try {
    $ready = Join-Path $scratch 'ready.json'
    $fixture = Start-Process -FilePath (Get-Command python).Source -ArgumentList @((Join-Path $PSScriptRoot 'chain_fixture.py'), '--ready', $ready) -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory 'fixture-stdout.txt') -RedirectStandardError (Join-Path $EvidenceDirectory 'fixture-stderr.txt')
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($fixture.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'The controlled chain fixture did not start' }
        Start-Sleep -Milliseconds 100
    }
    $fixtureIdentity = Get-Content -LiteralPath $ready -Raw | ConvertFrom-Json
    if ($fixtureIdentity.pid -ne $fixture.Id -or $fixtureIdentity.synthetic_only -ne $true) { throw 'The controlled fixture PID did not verify' }
    $cases = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'generated/cases.json') -Raw | ConvertFrom-Json -AsHashtable
    foreach ($case in $cases) {
        $name = $case['name']
        $activation = [Diagnostics.Stopwatch]::StartNew()
        [void](Invoke-RestMethod -Uri 'http://127.0.0.1:31816/case' -Method Post -NoProxy -ContentType 'application/json' -Body ($case | ConvertTo-Json -Compress) -TimeoutSec 5)
        $caseDirectory = Join-Path $scratch $name
        [void][IO.Directory]::CreateDirectory($caseDirectory)
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('generated/' + $name + '.json')) -Destination (Join-Path $caseDirectory 'config.yaml')
        $pipe = [FengWoRealWindowsTests.CorePipe]::new('FengWo')
        $core = Start-Process -FilePath $corePath -ArgumentList $pipe.Address -WorkingDirectory $BundleDirectory -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory ($name + '-core-stdout.txt')) -RedirectStandardError (Join-Path $EvidenceDirectory ($name + '-core-stderr.txt'))
        $peerPid = $pipe.Accept($core.Id, 10000)
        Assert-FwNativeProcess -ProcessId $core.Id -Architecture $Architecture
        if ((Invoke-ChainRpc 'initClash' @{ 'home-dir' = $caseDirectory; version = 2 }) -ne $true) { throw 'Core initialization failed' }
        $selected = if ($case['mode'] -ceq 'global') { @{ GLOBAL = '蜂窝链式代理' } } else { @{} }
        if ((Invoke-ChainRpc 'setupConfig' @{ 'selected-map' = $selected; 'test-url' = 'http://127.0.0.1:31815/probe' }) -cne '') { throw 'The product-generated chain configuration failed to apply' }
        if ((Invoke-ChainRpc 'startListener') -ne $true) { throw 'The actual Core mixed listener failed to start' }
        $listenerReadyMs = $activation.ElapsedMilliseconds
        $runtime = Invoke-ChainRpc 'getProxies'
        $wrapperVisibleMs = $activation.ElapsedMilliseconds
        $active = $case['disabled'] -ne $true -and $case['mode'] -cne 'direct'
        if ($runtime['proxies'].Contains('蜂窝链式代理') -ne $active) { throw 'The applied runtime wrapper does not match the requested chain state' }
        if ($case['mode'] -ceq 'global' -and $runtime['proxies']['GLOBAL']['now'] -cne '蜂窝链式代理') { throw 'Global mode did not select the chain wrapper' }
        $listener = @(Get-NetTCPConnection -State Listen -LocalPort 17980 -ErrorAction Stop | Where-Object OwningProcess -eq $core.Id)
        if ($listener.Count -lt 1) { throw 'The synthetic mixed listener is not owned by the tested Core PID' }
        $delay = $null
        if ($active) {
            $delay = Invoke-ChainRpc 'asyncTestDelay' @{ 'proxy-name' = '蜂窝链式代理'; 'timeout' = 3000; 'test-url' = 'http://127.0.0.1:31815/probe' }
            if ($delay['name'] -cne '蜂窝链式代理') { throw 'The delay response did not correspond to the actual wrapper' }
            if ($case.Contains('failure')) {
                if ($delay['value'] -gt 0) { throw 'A rejected chain was incorrectly reported available' }
            } elseif ($delay['value'] -le 0) { throw 'A working two-hop chain failed the same delay criterion used by the UI' }
        }
        $response = Request-ChainOrigin $name 'http://127.0.0.1:31815/chain' 4
        if ($case.Contains('failure')) {
            if ($response.status -eq 200 -and $response.body -ceq 'FENGWO_CHAIN_FIXTURE_OK') { throw 'A rejected chain unexpectedly reached the origin' }
        } elseif ($response.status -ne 200 -or $response.body -cne 'FENGWO_CHAIN_FIXTURE_OK') { throw ('The controlled origin did not traverse the expected chain: ' + $name) }
        $public = $null
        $defaultDelay = $null
        if ($name -ceq 'rule-auth-ip') {
            $defaultDelay = Invoke-ChainRpc 'asyncTestDelay' @{ 'proxy-name' = '蜂窝链式代理'; 'timeout' = 5000; 'test-url' = 'http://cp.cloudflare.com/generate_204' }
            $publicResponse = Request-ChainOrigin $name 'https://www.cloudflare.com/cdn-cgi/trace' 20
            $public = [ordered]@{ url = 'https://www.cloudflare.com/cdn-cgi/trace'; status = $publicResponse.status; elapsed_ms = $publicResponse.elapsed_ms; expected_https_origin_verified = ($publicResponse.status -eq 200 -and $publicResponse.body -match '(?m)^h=www.cloudflare.com\r?$'); error_type = $publicResponse.error_type; default_ui_probe_url = 'http://cp.cloudflare.com/generate_204'; default_ui_probe_delay_ms = $defaultDelay['value'] }
            Save-FwArmEvidence (Join-Path $EvidenceDirectory 'public-chain-probe.json') $public
        }
        Start-Sleep -Milliseconds 150
        $snapshot = Invoke-RestMethod -Uri ('http://127.0.0.1:31816/snapshot/' + $name) -NoProxy -TimeoutSec 5
        $node = @($snapshot.connections | Where-Object role -eq 'node')
        $exits = @($snapshot.connections | Where-Object { $_.role -in @('exit-a', 'exit-b') })
        if ($case.Contains('failure')) {
            if (@($snapshot.origin_requests).Count -ne 0) { throw 'A rejected chain leaked a request to the origin' }
            if ($name -ceq 'node-wrong-password' -and ($exits.Count -ne 0 -or @($node | Where-Object error -eq 'authentication_rejected').Count -eq 0)) { throw 'First-hop authentication failure did not remain isolated' }
            if ($name -ceq 'exit-wrong-password' -and @($exits | Where-Object error -eq 'authentication_rejected').Count -eq 0) { throw 'Exit authentication rejection was not observed' }
            if ($name -ceq 'exit-connect-rejected' -and @($exits | Where-Object error -eq 'connect_rejected').Count -eq 0) { throw 'Exit CONNECT rejection was not observed' }
            if ($name -ceq 'exit-handshake-timeout' -and @($exits | Where-Object error -eq 'synthetic_handshake_timeout').Count -eq 0) { throw 'The controlled timeout was not observed' }
        } elseif ($case['mode'] -ceq 'direct') {
            if ($node.Count -ne 0 -or $exits.Count -ne 0) { throw 'Direct mode unexpectedly traversed a chain' }
        } elseif ($case['disabled'] -eq $true) {
            if ($exits.Count -ne 0 -or @($node | Where-Object { $_.connected -and $_.up_bytes -gt 0 -and $_.down_bytes -gt 0 }).Count -eq 0) { throw 'Disabled chain did not preserve the original node route' }
        } else {
            if (@($node | Where-Object { $_.connected -and $_.authenticated -and $_.target_port -eq $(if ($case['exit_port']) { $case['exit_port'] } else { 31813 }) -and $_.up_bytes -gt 0 -and $_.down_bytes -gt 0 }).Count -eq 0) { throw 'The selected-node hop did not carry the exit tunnel' }
            if (@($exits | Where-Object { $_.peer_is_node -and $_.connected -and $_.authenticated -and $_.up_bytes -gt 0 -and $_.down_bytes -gt 0 }).Count -eq 0) { throw 'The exit hop did not carry the origin response' }
        }
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($name + '-hops.json')) $snapshot
        $results.Add([ordered]@{ name = $name; passed = $true; expected_failure = $case['failure']; restart_iteration = $case['restart_iteration']; selected_node = 'Synthetic Node'; mode = $case['mode']; wrapper_applied = $active; listener_ready_ms = $listenerReadyMs; wrapper_visible_ms = $wrapperVisibleMs; delay_ms = $(if ($delay) { $delay['value'] } else { $null }); core_pid = $core.Id; named_pipe_peer_pid = $peerPid; response_status = $response.status; response_elapsed_ms = $response.elapsed_ms; public = $public; node_connections = $node.Count; exit_connections = $exits.Count })
        Stop-ChainCore
    }
} catch {
    $failure = $_.Exception.Message
    if ($name -and $fixture -and -not $fixture.HasExited) {
        try {
            $lastSnapshot = Invoke-RestMethod -Uri ('http://127.0.0.1:31816/snapshot/' + $name) -NoProxy -TimeoutSec 5
            Save-FwArmEvidence (Join-Path $EvidenceDirectory 'failed-case.json') ([ordered]@{ name = $name; delay = $delay; origin_response = $response; hops = $lastSnapshot })
        } catch { $cleanupErrors.Add('The failing synthetic case snapshot could not be saved') }
    }
} finally {
    try { Stop-ChainCore } catch {
        $cleanupErrors.Add($_.Exception.Message)
        if ($core -and -not $core.HasExited) { $core.Kill(); [void]$core.WaitForExit(5000) }
        if ($pipe) { $pipe.Dispose() }
    }
    if ($fixture) { if (-not $fixture.HasExited) { $fixture.Kill(); [void]$fixture.WaitForExit(5000) }; $fixture.Dispose() }
    try {
        if (-not [FengWoCoexistenceTests.ProxyFixture]::Same($proxyBefore, $proxyGuard.Capture())) { throw 'The no-account chain Core test changed system proxy settings' }
        $restore = $proxyGuard.Restore()
        if (-not $restore.Passed) { throw 'The exact native system proxy snapshot was not restored' }
    } catch { $cleanupErrors.Add($_.Exception.Message) }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'chain-verification.json') ([ordered]@{ passed = ($null -eq $failure -and $cleanupErrors.Count -eq 0 -and $results.Count -eq 32); failure = $failure; cleanup_failures = $cleanupErrors.ToArray(); environment = $environment; checks = $results.ToArray(); rpc = $rpcFrames.ToArray(); repeated_restart_count = @($results | Where-Object restart_iteration).Count; product_generated_config = $true; generator_source_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '../../../lib/common/chain_proxy.dart') -Algorithm SHA256).Hash.ToLowerInvariant(); synthetic_credentials_only = $true; real_subscription_tested = $false; ui_click_tested = $false; system_proxy_modified = $false; public_probe_required_for_chain_unit_success = $false })
}
if ($failure -or $cleanupErrors.Count -gt 0 -or $results.Count -ne 32) { throw ('Native chain verification failed: ' + $failure + '; cleanup=' + ($cleanupErrors -join '; ')) }
