param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or $env:RUNNER_ARCH.ToLowerInvariant() -ne $Architecture) {
    throw 'An isolated native Windows runner of the requested architecture is required'
}
if (Get-Process -Name FengWo, FengWoCore -ErrorAction SilentlyContinue) { throw 'Another client or Core is running' }
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
. (Join-Path $PSScriptRoot 'arm64/common.ps1')
$nativeEnvironment = if ($Architecture -eq 'arm64') { Assert-FwArmRunner } else { Assert-FwNativeRunner -Architecture $Architecture }
$applicationPath = Join-Path $bundle 'FengWo.exe'
$helperPath = Join-Path $bundle 'FengWoHelperService.exe'
foreach ($path in @($applicationPath, $helperPath, (Join-Path $bundle 'FengWoCore.exe'))) {
    if (-not (Get-FwPeIdentity $path)[$Architecture]) { throw 'The acceptance payload architecture is incorrect' }
}
$existingService = Get-CimInstance Win32_Service -Filter "Name='FengWoHelperService'"
if ($existingService) { throw 'A pre-existing Helper service prevents an isolated acceptance test' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
Add-Type -Path (Join-Path $PSScriptRoot 'arm64/coexistence_proxy_fixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'network_cleanup_native.cs')
$proxyFixture = if ($Architecture -eq 'arm64') { [FengWoCoexistenceTests.ProxyFixture]::new() } else { [FengWoCoexistenceTests.ProxyFixture]::new($Architecture) }
$profileDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'FengWo/蜂窝加速器'
$profileBackup = Join-Path $env:RUNNER_TEMP ('network-cleanup-profile-' + [Guid]::NewGuid())
$results = [Collections.Generic.List[object]]::new()
$process = $null
$helperInstalled = $false
$failure = $null
$cleanupErrors = [Collections.Generic.List[string]]::new()
$originalTestHome = $env:FENGWO_NETWORK_TEST_HOME
$routesBefore = @(Get-NetRoute -AddressFamily IPv4 | Select-Object InterfaceIndex, DestinationPrefix, NextHop, RouteMetric | Sort-Object InterfaceIndex, DestinationPrefix, NextHop | ConvertTo-Json -Compress)
$dnsBefore = @(Get-DnsClientServerAddress | Select-Object InterfaceIndex, AddressFamily, ServerAddresses | Sort-Object InterfaceIndex, AddressFamily)

function Invoke-TestHelper([string]$Command) {
    $helper = Start-Process -FilePath $helperPath -ArgumentList $Command -PassThru
    try {
        $null = $helper.Handle
        if (-not $helper.WaitForExit(30000) -or $helper.ExitCode -ne 0) { throw "Helper $Command failed" }
    } finally { $helper.Dispose() }
}

function Wait-TestPhase([string]$Name) {
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    do {
        $failed = Join-Path $env:FENGWO_NETWORK_TEST_HOME 'failed.json'
        if (Test-Path -LiteralPath $failed) { throw (Get-Content -LiteralPath $failed -Raw) }
        if (Test-Path -LiteralPath (Join-Path $env:FENGWO_NETWORK_TEST_HOME ($Name + '.json'))) { return }
        if ($process.HasExited) { throw "Application exited before $Name ($($process.ExitCode))" }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Application timed out before $Name"
}

function Send-TestCommand([string]$Command) {
    $temporary = Join-Path $env:FENGWO_NETWORK_TEST_HOME 'command.tmp'
    [IO.File]::WriteAllText($temporary, $Command, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination (Join-Path $env:FENGWO_NETWORK_TEST_HOME 'command.txt')
}

function Test-Internet([bool]$ExpectProxy = $false) {
    $responses = foreach ($uri in @('https://www.baidu.com', 'https://www.microsoft.com')) {
        $request = [Net.HttpWebRequest]::Create($uri)
        $request.Proxy = [Net.WebRequest]::GetSystemWebProxy()
        $selectedProxy = $request.Proxy.GetProxy([Uri]$uri)
        if ($ExpectProxy -and ($selectedProxy.Host -ne '127.0.0.1' -or $selectedProxy.Port -ne $mixedPort)) {
            throw 'The system-aware request did not select the enabled local proxy'
        }
        if (-not $ExpectProxy -and $selectedProxy.AbsoluteUri -cne ([Uri]$uri).AbsoluteUri) { throw 'The restored system request still selects a proxy' }
        $request.Timeout = 20000
        $request.ReadWriteTimeout = 20000
        $response = $request.GetResponse()
        try {
            if ([int]$response.StatusCode -ne 200) { throw "Internet probe failed: $uri" }
            [ordered]@{ uri = $uri; status = [int]$response.StatusCode }
        } finally { $response.Dispose() }
    }
    return @($responses)
}

function Assert-Active([object]$Mode, [int]$Port) {
    $snapshot = $proxyFixture.Capture()
    if ($Mode.proxy -and (($snapshot.Flags -band 2) -eq 0 -or $snapshot.Server -notmatch (':'+$Port+'(?:;|$)'))) {
        throw 'The native WinINet system proxy was not enabled'
    }
    if (-not $Mode.proxy -and ($snapshot.Flags -band 2) -ne 0) { throw 'TUN-only mode unexpectedly enabled a system proxy' }
    $adapters = @(Get-NetAdapter -IncludeHidden | Where-Object { $_.Name -eq $device -and $_.Status -eq 'Up' })
    $tunRoutes = @()
    if ($Mode.tun) {
        if ($adapters.Count -ne 1) { throw 'The real Wintun adapter was not active' }
        $script:ownedIndex = $adapters[0].InterfaceIndex
        $tunRoutes = @(Get-NetRoute -InterfaceIndex $ownedIndex -AddressFamily IPv4)
        if (@($tunRoutes | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1') }).Count -eq 0) {
            throw 'No live TUN routing rule was observed'
        }
    } elseif ($adapters.Count -ne 0) { throw 'Proxy-only mode unexpectedly activated TUN' }
    return [ordered]@{ proxy = $snapshot; tun_routes = @($tunRoutes | Select-Object InterfaceIndex, DestinationPrefix, NextHop); internet = @(Test-Internet $Mode.proxy) }
}

function Assert-Cleaned {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $snapshot = $proxyFixture.Capture()
        $adapters = @(Get-NetAdapter -IncludeHidden | Where-Object { $_.Name -eq $device -and $_.Status -eq 'Up' })
        $routes = if ($ownedIndex) { @(Get-NetRoute -InterfaceIndex $ownedIndex -ErrorAction SilentlyContinue) } else { @() }
        if (($snapshot.Flags -band 2) -eq 0 -and $adapters.Count -eq 0 -and $routes.Count -eq 0) { break }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    if (($snapshot.Flags -band 2) -ne 0 -or $adapters.Count -ne 0 -or $routes.Count -ne 0) { throw 'System proxy or TUN adapter/routes remained active after cleanup' }
    if ($mixedPort -gt 0 -and @(Get-NetTCPConnection -LocalPort $mixedPort -State Listen -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'The mixed listener remained active after cleanup'
    }
    Start-Sleep -Seconds 8
    if (($proxyFixture.Capture().Flags -band 2) -ne 0) { throw 'A delayed request re-enabled the system proxy' }
    $dnsAfter = @(Get-DnsClientServerAddress | Where-Object { $_.InterfaceIndex -in @($dnsBefore.InterfaceIndex) } | Select-Object InterfaceIndex, AddressFamily, ServerAddresses | Sort-Object InterfaceIndex, AddressFamily)
    if (($dnsBefore | ConvertTo-Json -Compress -Depth 6) -cne ($dnsAfter | ConvertTo-Json -Compress -Depth 6)) { throw 'Physical interface DNS was not restored' }
    return [ordered]@{ proxy = $snapshot; active_tun_adapters = $adapters.Count; tun_routes = $routes.Count; internet = @(Test-Internet) }
}

try {
    if (Test-Path -LiteralPath $profileDirectory) { Move-Item -LiteralPath $profileDirectory -Destination $profileBackup }
    $helperInstalled = $true
    Invoke-TestHelper 'install'
    foreach ($action in @('tray-exit', 'logout')) {
        foreach ($mode in @(@{ name = 'proxy'; proxy = $true; tun = $false }, @{ name = 'tun-only'; proxy = $false; tun = $true }, @{ name = 'proxy-and-tun'; proxy = $true; tun = $true })) {
            $case = $action + '-' + $mode.name
            $device = 'FengWoMeta'
            $script:ownedIndex = $null
            if (Get-NetAdapter -IncludeHidden | Where-Object { $_.Name -eq $device -and $_.Status -eq 'Up' }) { throw 'The fixture adapter was already active' }
            $portLease = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
            $portLease.Start()
            $mixedPort = if ($mode.proxy) { $portLease.LocalEndpoint.Port } else { 0 }
            $portLease.Stop()
            $null = $proxyFixture.SetDirect()
            New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
            $preferences = @{ 'flutter.version' = 1; 'flutter.xboard.auto_login' = $false; 'flutter.config' = (@{ appSettingProps = @{ locale = 'en'; autoRun = $false; autoCheckUpdate = $false } } | ConvertTo-Json -Compress -Depth 10) }
            [IO.File]::WriteAllText((Join-Path $profileDirectory 'shared_preferences.json'), ($preferences | ConvertTo-Json -Compress -Depth 10), [Text.UTF8Encoding]::new($false))
            $env:FENGWO_NETWORK_TEST_HOME = Join-Path $output $case
            New-Item -ItemType Directory -Path $env:FENGWO_NETWORK_TEST_HOME -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $env:FENGWO_NETWORK_TEST_HOME 'fixture.json'), (@{ port = $mixedPort; proxy = $mode.proxy; tun = $mode.tun; device = $device } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
            $process = Start-Process -FilePath $applicationPath -WorkingDirectory $bundle -PassThru
            Wait-TestPhase 'active'
            if ($Architecture -eq 'arm64') { Assert-FwArmProcess -ProcessId $process.Id } else { Assert-FwNativeProcess -ProcessId $process.Id -Architecture $Architecture }
            $active = Assert-Active $mode $mixedPort
            $logout = $null
            $reconnected = $null
            if ($action -eq 'logout') {
                Send-TestCommand 'logout'
                Wait-TestPhase 'logged-out'
                if ($process.HasExited) { throw 'Logout unexpectedly closed the application' }
                $logout = Assert-Cleaned
                Send-TestCommand 'reconnect'
                Wait-TestPhase 'reconnected'
                $reconnected = Assert-Active $mode $mixedPort
            }
            $trayItem = [FengWoNetworkCleanupTests.TrayCommand]::Exit($process.Id)
            if (-not $process.WaitForExit(45000) -or $process.ExitCode -ne 0) { throw 'The real tray Exit callback did not close cleanly' }
            $cleaned = Assert-Cleaned
            if (Get-Process -Name FengWoCore -ErrorAction SilentlyContinue) { throw 'The owned Core process survived tray exit' }
            $events = Join-Path $profileDirectory 'diagnostics/events.jsonl'
            Copy-Item -LiteralPath $events -Destination (Join-Path $env:FENGWO_NETWORK_TEST_HOME 'events.jsonl')
            $entries = @(Get-Content -LiteralPath $events | ForEach-Object { $_ | ConvertFrom-Json })
            $expectedEvents = @('app.exit.process_exit', 'connection.cleanup.completed')
            if ($mixedPort -gt 0) { $expectedEvents += 'system_proxy.cleanup.residual_checked' }
            if ($action -eq 'logout') { $expectedEvents += @('auth.logout.completed', 'app.logout.cleanup.completed') }
            foreach ($event in $expectedEvents) {
                if (@($entries | Where-Object event -eq $event).Count -eq 0) { throw "Missing production lifecycle evidence: $event" }
            }
            $results.Add([ordered]@{ case = $case; passed = $true; active = $active; logout = $logout; reconnected = $reconnected; cleaned = $cleaned; native_tray_item = $trayItem })
            $process.Dispose()
            $process = $null
            Remove-Item -LiteralPath $profileDirectory -Recurse -Force
        }
    }
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($process) { try { if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(10000) } } catch { $cleanupErrors.Add($_.Exception.Message) }; $process.Dispose() }
    if ($helperInstalled) { try { Invoke-TestHelper 'stop'; Invoke-TestHelper 'uninstall' } catch { $cleanupErrors.Add($_.Exception.Message) } }
    try { $restore = $proxyFixture.Restore(); if (-not $restore.Passed) { throw ($restore.Errors -join '; ') } } catch { $cleanupErrors.Add($_.Exception.Message) }
    if (Test-Path -LiteralPath $profileBackup) {
        try { if (Test-Path -LiteralPath $profileDirectory) { Remove-Item -LiteralPath $profileDirectory -Recurse -Force }; Move-Item -LiteralPath $profileBackup -Destination $profileDirectory } catch { $cleanupErrors.Add($_.Exception.Message) }
    }
    $env:FENGWO_NETWORK_TEST_HOME = $originalTestHome
    $routesAfter = @(Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.InterfaceIndex -in @($dnsBefore.InterfaceIndex) } | Select-Object InterfaceIndex, DestinationPrefix, NextHop, RouteMetric | Sort-Object InterfaceIndex, DestinationPrefix, NextHop | ConvertTo-Json -Compress)
    if (($routesBefore -join '') -cne ($routesAfter -join '')) { $cleanupErrors.Add('Physical IPv4 routes differ from the baseline') }
    [ordered]@{ passed = (-not $failure -and $cleanupErrors.Count -eq 0 -and $results.Count -eq 6); architecture = $Architecture; environment = $nativeEnvironment; cases = @($results.ToArray()); failure = $failure; cleanup_errors = @($cleanupErrors.ToArray()); real_customer_account_tested = $false; production_entrypoints = @('Tray.update native WM_COMMAND', 'Application.logoutXboard'); test_entry_not_shipped = $true } | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $output 'network-cleanup-verification.json') -Encoding utf8NoBOM
}
if ($failure) { throw $failure }
if ($cleanupErrors.Count -gt 0) { throw ($cleanupErrors -join '; ') }
if ($results.Count -ne 6) { throw 'Not all six native acceptance cases completed' }
