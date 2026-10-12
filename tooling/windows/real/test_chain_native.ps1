param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release_common.ps1')
$environment = Assert-FwNativeRunner -Architecture $Architecture
$BundleDirectory = (Resolve-Path -LiteralPath $BundleDirectory).Path
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$expectedMachine = if ($Architecture -eq 'arm64') { '0xaa64' } else { '0x8664' }
$corePath = Join-Path $BundleDirectory 'FengWoCore.exe'
if ((Get-FwPeIdentity $corePath).machine -cne $expectedMachine) { throw 'The chain tests require the actual native packaged FengWo Core' }
if (Get-NetTCPConnection -State Listen -LocalPort 17980, 31811, 31812, 31813, 31814, 31815, 31816 -ErrorAction SilentlyContinue) { throw 'Pre-existing fixture ports prevent isolation' }
Add-Type -Path (Join-Path $PSScriptRoot 'core_windows_fixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot '../arm64/coexistence_proxy_fixture.cs')
$proxyGuard = [FengWoCoexistenceTests.ProxyFixture]::new()
$proxyBefore = $proxyGuard.Capture()
$fixture = $null
$pipe = $null
$core = $null
$failure = $null
$cleanupErrors = [Collections.Generic.List[string]]::new()
$results = [Collections.Generic.List[object]]::new()
$hotResults = [Collections.Generic.List[object]]::new()
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

function Get-ChainSelection([Collections.IDictionary]$Case) {
    $selected = @{}
    if ($Case['group']) { $selected['Synthetic Group'] = $Case['selected_node'] }
    if ($Case['mode'] -ceq 'global') {
        $selected['GLOBAL'] = if ($Case['disabled']) { 'Synthetic Group' } else { '蜂窝链式代理' }
    }
    return $selected
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
        $expectedNodePort = if ($case['selected_node'] -ceq 'Synthetic Node B') { 31812 } else { 31811 }
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
        $selected = Get-ChainSelection $case
        if ((Invoke-ChainRpc 'setupConfig' @{ 'selected-map' = $selected; 'test-url' = 'http://127.0.0.1:31815/probe' }) -cne '') { throw 'The product-generated chain configuration failed to apply' }
        if ((Invoke-ChainRpc 'startListener') -ne $true) { throw 'The actual Core mixed listener failed to start' }
        $listenerReadyMs = $activation.ElapsedMilliseconds
        $runtime = Invoke-ChainRpc 'getProxies'
        $wrapperVisibleMs = $activation.ElapsedMilliseconds
        $active = $case['disabled'] -ne $true -and $case['mode'] -cne 'direct'
        if ($runtime['proxies'].Contains('蜂窝链式代理') -ne $active) { throw 'The applied runtime wrapper does not match the requested chain state' }
        if ($case['mode'] -ceq 'global' -and $runtime['proxies']['GLOBAL']['now'] -cne '蜂窝链式代理') { throw 'Global mode did not select the chain wrapper' }
        if ($case['group'] -and $runtime['proxies']['Synthetic Group']['now'] -cne $case['selected_node']) { throw 'The runtime selected a different synthetic node' }
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
            if (@($node | Where-Object { $_.listener_port -eq $expectedNodePort -and $_.connected -and $_.authenticated -and $_.target_port -eq $(if ($case['exit_port']) { $case['exit_port'] } else { 31813 }) -and $_.up_bytes -gt 0 -and $_.down_bytes -gt 0 }).Count -eq 0) { throw 'The selected-node hop did not carry the exit tunnel' }
            if (@($exits | Where-Object { $_.peer_is_node -and $_.connected -and $_.authenticated -and $_.up_bytes -gt 0 -and $_.down_bytes -gt 0 }).Count -eq 0) { throw 'The exit hop did not carry the origin response' }
        }
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($name + '-hops.json')) $snapshot
        $results.Add([ordered]@{ name = $name; passed = $true; expected_failure = $case['failure']; restart_iteration = $case['restart_iteration']; selected_node = $(if ($case['group']) { $case['selected_node'] } else { 'Synthetic Node' }); mode = $case['mode']; wrapper_applied = $active; listener_ready_ms = $listenerReadyMs; wrapper_visible_ms = $wrapperVisibleMs; delay_ms = $(if ($delay) { $delay['value'] } else { $null }); core_pid = $core.Id; named_pipe_peer_pid = $peerPid; response_status = $response.status; response_elapsed_ms = $response.elapsed_ms; public = $public; node_connections = $node.Count; exit_connections = $exits.Count })
        Stop-ChainCore
    }

    $caseDirectory = Join-Path $scratch 'same-pid-hot-application'
    [void][IO.Directory]::CreateDirectory($caseDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'generated/restart-01-disabled.json') -Destination (Join-Path $caseDirectory 'config.yaml')
    $pipe = [FengWoRealWindowsTests.CorePipe]::new('FengWo')
    $core = Start-Process -FilePath $corePath -ArgumentList $pipe.Address -WorkingDirectory $BundleDirectory -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory 'hot-core-stdout.txt') -RedirectStandardError (Join-Path $EvidenceDirectory 'hot-core-stderr.txt')
    $hotCoreId = $core.Id
    $hotPeerPid = $pipe.Accept($hotCoreId, 10000)
    Assert-FwNativeProcess -ProcessId $hotCoreId -Architecture $Architecture
    if ((Invoke-ChainRpc 'initClash' @{ 'home-dir' = $caseDirectory; version = 2 }) -ne $true) { throw 'The hot-application Core initialization failed' }
    if ((Invoke-ChainRpc 'setupConfig' @{ 'selected-map' = @{ 'Synthetic Group' = 'Synthetic Node A'; GLOBAL = 'Synthetic Group' }; 'test-url' = 'http://127.0.0.1:31815/probe' }) -cne '') { throw 'The initial hot-application configuration failed' }
    if ((Invoke-ChainRpc 'startListener') -ne $true) { throw 'The initial hot-application listener failed' }
    foreach ($iteration in 1..20) {
        $templateName = ('restart-{0:d2}' -f $iteration)
        $case = @($cases | Where-Object { $_['name'] -ceq $templateName })[0].Clone()
        $name = ('hot-disabled-{0:d2}' -f $iteration)
        $case['name'] = $name
        $case['disabled'] = $true
        $expectedNodePort = if ($case['selected_node'] -ceq 'Synthetic Node B') { 31812 } else { 31811 }
        $delay = $null
        $response = $null
        [void](Invoke-RestMethod -Uri 'http://127.0.0.1:31816/case' -Method Post -NoProxy -ContentType 'application/json' -Body ($case | ConvertTo-Json -Compress) -TimeoutSec 5)
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('generated/' + $templateName + '-disabled.json')) -Destination (Join-Path $caseDirectory 'config.yaml')
        $applyClock = [Diagnostics.Stopwatch]::StartNew()
        if ((Invoke-ChainRpc 'setupConfig' @{ 'selected-map' = (Get-ChainSelection $case); 'test-url' = 'http://127.0.0.1:31815/probe' }) -cne '') { throw 'Hot chain disable failed to apply' }
        $disabledApplyMs = $applyClock.ElapsedMilliseconds
        $runtime = Invoke-ChainRpc 'getProxies'
        if ($runtime['proxies'].Contains('蜂窝链式代理')) { throw 'A disabled hot chain wrapper remained visible' }
        if ($runtime['proxies']['Synthetic Group']['now'] -cne $case['selected_node']) { throw 'Hot chain disable changed the selected original node' }
        $response = Request-ChainOrigin $name 'http://127.0.0.1:31815/hot-disabled' 4
        if ($response.status -ne 200 -or $response.body -cne 'FENGWO_CHAIN_FIXTURE_OK') { throw 'Hot chain disable did not restore the original selected node route' }
        $disabledSnapshot = Invoke-RestMethod -Uri ('http://127.0.0.1:31816/snapshot/' + $name) -NoProxy -TimeoutSec 5
        if (@($disabledSnapshot.connections | Where-Object { $_.role -in @('exit-a', 'exit-b') }).Count -ne 0 -or @($disabledSnapshot.origin_requests | Where-Object { $_.peer_role -eq 'node' -and $_.peer_listener_port -eq $expectedNodePort -and $_.expected_hop_verified }).Count -ne 1) { throw 'The disabled hot chain did not exclusively use the selected original node' }
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($name + '-hops.json')) $disabledSnapshot

        $case = @($cases | Where-Object { $_['name'] -ceq $templateName })[0].Clone()
        $name = ('hot-applied-{0:d2}' -f $iteration)
        $case['name'] = $name
        $delay = $null
        $response = $null
        [void](Invoke-RestMethod -Uri 'http://127.0.0.1:31816/case' -Method Post -NoProxy -ContentType 'application/json' -Body ($case | ConvertTo-Json -Compress) -TimeoutSec 5)
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('generated/' + $templateName + '.json')) -Destination (Join-Path $caseDirectory 'config.yaml')
        $selected = Get-ChainSelection $case
        $applyClock = [Diagnostics.Stopwatch]::StartNew()
        if ((Invoke-ChainRpc 'setupConfig' @{ 'selected-map' = $selected; 'test-url' = 'http://127.0.0.1:31815/probe' }) -cne '') { throw 'Hot chain enable failed to apply' }
        $hotApplyMs = $applyClock.ElapsedMilliseconds
        $runtime = Invoke-ChainRpc 'getProxies'
        if (-not $runtime['proxies'].Contains('蜂窝链式代理')) { throw 'An enabled hot chain wrapper did not appear' }
        if ($runtime['proxies']['Synthetic Group']['now'] -cne $case['selected_node']) { throw 'Hot chain enable changed the selected original node' }
        if ($case['mode'] -ceq 'global' -and $runtime['proxies']['GLOBAL']['now'] -cne '蜂窝链式代理') { throw 'The hot global chain did not preserve wrapper selection' }
        $delay = Invoke-ChainRpc 'asyncTestDelay' @{ 'proxy-name' = '蜂窝链式代理'; 'timeout' = 3000; 'test-url' = ('http://127.0.0.1:31815/probe?hot=' + $iteration) }
        if ($delay['value'] -le 0 -or $delay['name'] -cne '蜂窝链式代理') { throw 'A working hot chain failed the exact UI availability criterion' }
        $response = Request-ChainOrigin $name 'http://127.0.0.1:31815/hot-enabled' 4
        if ($response.status -ne 200 -or $response.body -cne 'FENGWO_CHAIN_FIXTURE_OK') { throw 'The hot chain did not carry the actual origin request' }
        $hotSnapshot = Invoke-RestMethod -Uri ('http://127.0.0.1:31816/snapshot/' + $name) -NoProxy -TimeoutSec 5
        if (@($hotSnapshot.origin_requests | Where-Object { $_.peer_role -in @('exit-a', 'exit-b') -and $_.expected_hop_verified }).Count -lt 2 -or @($hotSnapshot.connections | Where-Object { $_.role -eq 'node' -and $_.listener_port -eq $expectedNodePort -and $_.target_port -eq $case['exit_port'] -and $_.authenticated -and $_.connected }).Count -lt 2) { throw 'The hot chain did not use the currently configured two-hop exit' }
        if ($core.HasExited -or $core.Id -ne $hotCoreId -or @(Get-NetTCPConnection -State Listen -LocalPort 17980 -ErrorAction Stop | Where-Object OwningProcess -eq $hotCoreId).Count -lt 1) { throw 'Hot application replaced or lost the existing Core and listener PID' }
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($name + '-hops.json')) $hotSnapshot
        $hotResults.Add([ordered]@{ iteration = $iteration; passed = $true; core_pid = $hotCoreId; named_pipe_peer_pid = $hotPeerPid; mode = $case['mode']; selected_node = $case['selected_node']; exit_port = $case['exit_port']; disabled_apply_ms = $disabledApplyMs; enabled_apply_ms = $hotApplyMs; delay_ms = $delay['value']; origin_status = $response.status; original_node_restored_on_disable = $true; two_hops_verified = $true })
    }
    Stop-ChainCore
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
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'chain-verification.json') ([ordered]@{ passed = ($null -eq $failure -and $cleanupErrors.Count -eq 0 -and $results.Count -eq 32 -and $hotResults.Count -eq 20); failure = $failure; cleanup_failures = $cleanupErrors.ToArray(); environment = $environment; checks = $results.ToArray(); hot_applications = $hotResults.ToArray(); rpc = $rpcFrames.ToArray(); repeated_restart_count = @($results | Where-Object restart_iteration).Count; product_generated_config = $true; generator_source_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '../../../lib/common/chain_proxy.dart') -Algorithm SHA256).Hash.ToLowerInvariant(); synthetic_credentials_only = $true; real_subscription_tested = $false; ui_click_tested = $false; system_proxy_modified = $false; public_probe_required_for_chain_unit_success = $false })
}
if ($failure -or $cleanupErrors.Count -gt 0 -or $results.Count -ne 32 -or $hotResults.Count -ne 20) { throw ('Native chain verification failed: ' + $failure + '; cleanup=' + ($cleanupErrors -join '; ')) }
