param(
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$LegacyBundleDirectory,
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

. (Join-Path $PSScriptRoot 'release_common.ps1')
$environment = Assert-FwNativeRunner -Architecture $Architecture
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'The isolated Helper coexistence test requires administrator privileges' }
} finally { $identity.Dispose() }
$BundleDirectory = (Resolve-Path -LiteralPath $BundleDirectory).Path
$LegacyBundleDirectory = (Resolve-Path -LiteralPath $LegacyBundleDirectory).Path
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$oldDirectory = Join-Path $env:RUNNER_TEMP ('fengwo-old-helper-' + [Guid]::NewGuid().ToString('N'))
$old = [ordered]@{ name = 'FlClash'; service = 'FlClashHelperService'; directory = $oldDirectory; port = 47906; header = 'x-flclash-helper-protocol'; helper_pid = 0; lease = $null; created = $false }
$new = [ordered]@{ name = 'FengWo'; service = 'FengWoHelperService'; directory = $BundleDirectory; port = 47907; header = 'x-fengwo-helper-protocol'; helper_pid = 0; lease = $null; created = $false }
$checks = [Collections.Generic.List[object]]::new()
$cleanupFailures = [Collections.Generic.List[string]]::new()
$failure = $null
$uninstalled = $false

function Invoke-CoexistenceChild([string]$File, [string[]]$Arguments, [string]$Stage, [int]$TimeoutSeconds = 120) {
    $argumentString = (@($Arguments | ForEach-Object { '"' + ([regex]::Replace(([regex]::Replace($_, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"' }) -join ' ')
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $File -ArgumentList $argumentString -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory ($Stage + '-stdout.txt')) -RedirectStandardError (Join-Path $EvidenceDirectory ($Stage + '-stderr.txt'))
    try {
        $handle = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill(); [void]$process.WaitForExit(5000); throw ('The owned Helper test child exceeded its deadline: ' + $Stage) }
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-result.json')) ([ordered]@{ stage = $Stage; exit_code = $process.ExitCode; elapsed_ms = $watch.ElapsedMilliseconds })
        if ($process.ExitCode -ne 0) { throw ('The owned Helper test child failed: ' + $Stage + ' (' + $process.ExitCode + ')') }
    } finally { $process.Dispose() }
}

function Invoke-CoexistenceHelper([object]$Helper, [string]$Endpoint, [AllowNull()][object]$Body, [string]$Stage) {
    $arguments = @{ Uri = ('http://127.0.0.1:' + $Helper.port + '/' + $Endpoint); NoProxy = $true; TimeoutSec = 5; ErrorAction = 'Stop'; SkipHttpErrorCheck = $true }
    if ($null -ne $Body) { $arguments.Method = 'Post'; $arguments.ContentType = 'application/json'; $arguments.Body = ($Body | ConvertTo-Json -Compress) }
    $response = Invoke-WebRequest @arguments
    $result = [ordered]@{ stage = $Stage; helper = $Helper.name; port = $Helper.port; http_status = [int]$response.StatusCode; protocol = ($response.Headers[$Helper.header] -join ''); body = [string]$response.Content }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-http.json')) $result
    if ($result.http_status -ne 200) { throw ('The exact Helper request failed: ' + $Stage + ' (' + $result.http_status + ')') }
    return $result
}

function Assert-CoexistenceHelper([object]$Helper, [string]$Stage, [bool]$PreservePid = $true) {
    $expectedPath = Join-Path $Helper.directory ($Helper.service + '.exe')
    $service = Get-CimInstance Win32_Service -Filter ("Name='" + $Helper.service + "'")
    if (-not $service -or $service.State -cne 'Running' -or $service.ProcessId -le 0 -or -not [StringComparer]::OrdinalIgnoreCase.Equals($service.PathName.Trim('"'), $expectedPath)) { throw ('The exact Helper SCM identity failed: ' + $Stage) }
    if ($PreservePid -and $Helper.helper_pid -gt 0 -and $service.ProcessId -ne $Helper.helper_pid) { throw ('Another operation replaced the protected Helper process: ' + $Stage) }
    if ($Helper.name -ceq 'FengWo') { Assert-FwNativeProcess -ProcessId $service.ProcessId -Architecture $Architecture }
    $response = Invoke-CoexistenceHelper $Helper ('ping?coreSha256=' + $Helper.core_hash) $null ($Stage + '-ping')
    if ($response.protocol -cne '6' -or -not [StringComparer]::OrdinalIgnoreCase.Equals($response.body.Trim(), $expectedPath)) { throw ('The exact Helper protocol and executable path failed: ' + $Stage) }
    $Helper.helper_pid = [int]$service.ProcessId
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-scm.json')) ([ordered]@{ name = $service.Name; pid = $service.ProcessId; state = $service.State; executable = $expectedPath; port = $Helper.port; protocol_header = $Helper.header; process_machines = @([FengWoArm64Environment]::Machines($service.ProcessId)) })
}

function Start-CoexistenceHelper([object]$Helper, [string]$Stage) {
    $Helper.created = $true
    Invoke-CoexistenceChild (Join-Path $Helper.directory ($Helper.service + '.exe')) @('install') ($Stage + '-install') 30
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        try { Assert-CoexistenceHelper $Helper $Stage $false; return } catch { if ([DateTime]::UtcNow -ge $deadline) { throw }; Start-Sleep -Milliseconds 100 }
    } while ($true)
}

function Start-CoexistenceCore([object]$Helper, [string]$Stage) {
    if ($Helper.lease) { throw 'The Helper already has a recorded owned Core lease' }
    $pipe = [FengWoRealWindowsTests.CorePipe]::new($Helper.name)
    try {
        $response = Invoke-CoexistenceHelper $Helper 'start' @{ address = $pipe.Address; sessionId = $pipe.SessionId } ($Stage + '-start')
        $value = $response.body | ConvertFrom-Json
        if ($value.sessionId -cne $pipe.SessionId -or $value.pid -le 0) { throw ('The owned Core lease did not verify: ' + $Stage) }
        $process = [Diagnostics.Process]::GetProcessById([int]$value.pid)
        $handle = $process.Handle
        $Helper.lease = [ordered]@{ pipe = $pipe; process = $process; session_id = $pipe.SessionId; pid = [int]$value.pid; ownership_verified = $false }
        [void]$pipe.Accept($value.pid, 10000)
        $expectedPath = Join-Path $Helper.directory ($Helper.name + 'Core.exe')
        $actual = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $value.pid)
        if (-not $actual -or -not [StringComparer]::OrdinalIgnoreCase.Equals($actual.ExecutablePath, $expectedPath)) { throw ('The Helper launched a Core outside its own installation: ' + $Stage) }
        if ($Helper.name -ceq 'FengWo') { Assert-FwNativeProcess -ProcessId $value.pid -Architecture $Architecture }
        $Helper.lease.ownership_verified = $true
        Assert-CoexistenceCore $Helper $Stage
    } catch { if (-not $Helper.lease) { $pipe.Dispose() }; throw }
}

function Assert-CoexistenceCore([object]$Helper, [string]$Stage) {
    if (-not $Helper.lease -or -not $Helper.lease.ownership_verified -or $Helper.lease.process.HasExited) { throw ('The protected Core is no longer alive: ' + $Stage) }
    $request = [ordered]@{ id = ('coexist-' + $Stage); method = 'getIsInit'; arguments = $null }
    $Helper.lease.pipe.Send(($request | ConvertTo-Json -Compress))
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $index = 0
    do {
        $raw = $Helper.lease.pipe.Receive([Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds))
        $index++
        [IO.File]::WriteAllText((Join-Path $EvidenceDirectory ($Stage + '-rpc-' + $index + '.json')), $raw, [Text.UTF8Encoding]::new($false))
        $value = $raw | ConvertFrom-Json -AsHashtable
        if ($value -isnot [Collections.IDictionary]) { throw 'The actual Core sent a non-object frame' }
    } while ($value['id'] -cne $request.id -and [DateTime]::UtcNow -lt $deadline)
    if ($value['id'] -cne $request.id -or ($value.Contains('error') -and $null -ne $value['error']) -or -not $value.Contains('result') -or $value['result'] -isnot [bool] -or $value['result'] -ne $false) { throw ('The protected Core RPC did not verify: ' + $Stage) }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-lease.json')) ([ordered]@{ helper = $Helper.name; core_pid = $Helper.lease.pid; pipe = $Helper.lease.pipe.Address; request = $request; result = $value['result']; peer_pid_verified = $true })
}

function Stop-CoexistenceCore([object]$Helper, [string]$Stage) {
    if (-not $Helper.lease) { return }
    $lease = $Helper.lease
    if (-not $lease.ownership_verified) { throw 'Stopping an unverified Core lease is not permitted' }
    $response = Invoke-CoexistenceHelper $Helper 'stop' @{ sessionId = $lease.session_id } $Stage
    $value = $response.body | ConvertFrom-Json
    if ($value.sessionId -cne $lease.session_id -or $value.stopped -ne $true -or -not $lease.process.WaitForExit(5000)) { throw ('The exact Helper could not stop its owned Core: ' + $Stage) }
    $lease.pipe.Dispose(); $lease.process.Dispose(); $Helper.lease = $null
}

function Wait-CoexistenceHelperStopped([object]$Helper, [string]$Stage) {
    $expectedPath = Join-Path $Helper.directory ($Helper.service + '.exe')
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $service = Get-CimInstance Win32_Service -Filter ("Name='" + $Helper.service + "'")
        if (-not $service -or -not [StringComparer]::OrdinalIgnoreCase.Equals($service.PathName.Trim('"'), $expectedPath)) { throw ('The stopped Helper SCM identity failed: ' + $Stage) }
        if ($service.State -ceq 'Stopped' -and $service.ProcessId -eq 0) {
            Save-FwArmEvidence (Join-Path $EvidenceDirectory ($Stage + '-scm.json')) ([ordered]@{ name = $service.Name; state = $service.State; pid = $service.ProcessId; executable = $expectedPath })
            return
        }
        if ([DateTime]::UtcNow -ge $deadline) { throw ('The owned Helper SCM did not reach Stopped with PID 0: ' + $Stage) }
        Start-Sleep -Milliseconds 100
    } while ($true)
}

function Clear-CoexistenceCoreLease([object]$Helper) {
    if (-not $Helper.lease) { return }
    try {
        if ($Helper.lease.ownership_verified) {
            try { if (-not $Helper.lease.process.HasExited) { Stop-CoexistenceCore $Helper ($Helper.name + '-cleanup-core') } } catch { $cleanupFailures.Add($_.Exception.Message) }
        } else { $cleanupFailures.Add('Cleanup refused to terminate a Core whose executable and pipe peer were not verified') }
    } finally {
        if ($Helper.lease) {
            $lease = $Helper.lease
            try { if ($lease.ownership_verified -and -not $lease.process.HasExited) { $lease.process.Kill(); [void]$lease.process.WaitForExit(5000) } } catch { $cleanupFailures.Add($_.Exception.Message) }
            finally { $lease.pipe.Dispose(); $lease.process.Dispose(); $Helper.lease = $null }
        }
    }
}

try {
    if (Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService' OR Name='FengWoHelperService'") { throw 'Existing Helper SCM registrations prevent isolation' }
    if (Get-NetTCPConnection -State Listen -LocalPort 47906, 47907 -ErrorAction SilentlyContinue) { throw 'Existing Helper listener ports prevent isolation' }
    Add-Type -Path (Join-Path $PSScriptRoot 'core_windows_fixture.cs')
    [void][IO.Directory]::CreateDirectory($oldDirectory)
    foreach ($name in @('FlClashHelperService.exe', 'FlClashCore.exe', 'manifest.json')) { Copy-Item -LiteralPath (Join-Path $LegacyBundleDirectory $name) -Destination (Join-Path $oldDirectory $name) }
    foreach ($helper in @($old, $new)) {
        $manifest = Get-Content -LiteralPath (Join-Path $helper.directory 'manifest.json') -Raw | ConvertFrom-Json
        $coreIdentity = Get-FwPeIdentity (Join-Path $helper.directory ($helper.name + 'Core.exe'))
        $helperIdentity = Get-FwPeIdentity (Join-Path $helper.directory ($helper.service + '.exe'))
        if ($manifest.coreSha256 -cne $coreIdentity.sha256) { throw 'An actual Core did not match its Helper integrity manifest' }
        if ($helper.name -ceq 'FlClash') {
            if ($coreIdentity.machine -cne '0x8664' -or $helperIdentity.machine -cne '0x8664' -or $coreIdentity.sha256 -cne '0ceb4c710838ebc4de54f9e956e9f737d48ba4db0cfb777bdb0e7f8f458d40e4' -or $helperIdentity.sha256 -cne 'e624e524300188b5d0444753d8cf8f576c2e8d1a2b2f7e3b06e470e0263ece9d') { throw 'The legacy binaries differ from the verified October 7 release' }
        } elseif (($Architecture -ceq 'x64' -and (-not $coreIdentity.x64 -or -not $helperIdentity.x64)) -or ($Architecture -ceq 'arm64' -and (-not $coreIdentity.arm64 -or -not $helperIdentity.arm64))) { throw 'The new Helper and Core are not native to the tested Windows architecture' }
        $helper.core_hash = $coreIdentity.sha256
        Save-FwArmEvidence (Join-Path $EvidenceDirectory ($helper.name + '-payload.json')) ([ordered]@{ core = $coreIdentity; helper = $helperIdentity; expected_port = $helper.port; expected_protocol_header = $helper.header })
    }
    Start-CoexistenceHelper $old 'old-initial'
    Start-CoexistenceCore $old 'old-initial'
    Start-CoexistenceHelper $new 'new-initial'
    Start-CoexistenceCore $new 'new-initial'
    Assert-CoexistenceHelper $old 'old-after-new-start'
    Assert-CoexistenceCore $old 'old-after-new-start'
    $checks.Add([ordered]@{ name = 'actual-old-and-new-helper-core-pairs'; passed = $true; old_port = 47906; new_port = 47907 })
    for ($i = 1; $i -le 20; $i++) {
        Stop-CoexistenceCore $new ('new-stop-' + $i)
        Assert-CoexistenceHelper $old ('old-after-new-stop-' + $i)
        Assert-CoexistenceCore $old ('old-after-new-stop-' + $i)
        Start-CoexistenceCore $new ('new-restart-' + $i)
    }
    $checks.Add([ordered]@{ name = 'twenty-new-core-cycles-preserve-old-pid-and-rpc'; passed = $true; cycles = 20 })
    Invoke-CoexistenceChild (Join-Path $BundleDirectory 'FengWoHelperService.exe') @('stop') 'new-scm-stop' 30
    Wait-CoexistenceHelperStopped $new 'new-scm-stop'
    if (-not $new.lease.process.WaitForExit(5000)) { throw 'The new SCM stop did not stop its owned Core' }
    $new.lease.pipe.Dispose(); $new.lease.process.Dispose(); $new.lease = $null
    Assert-CoexistenceHelper $old 'old-after-new-scm-stop'
    Assert-CoexistenceCore $old 'old-after-new-scm-stop'
    Start-CoexistenceHelper $new 'new-scm-restart'
    Start-CoexistenceCore $new 'new-scm-restart'
    $checks.Add([ordered]@{ name = 'new-scm-stop-restart-preserves-old-helper-and-core'; passed = $true })
    Stop-CoexistenceCore $old 'old-stop-with-new-live'
    Assert-CoexistenceHelper $new 'new-after-old-stop'
    Assert-CoexistenceCore $new 'new-after-old-stop'
    Start-CoexistenceCore $old 'old-restart-with-new-live'
    Assert-CoexistenceHelper $new 'new-after-old-restart'
    Assert-CoexistenceCore $new 'new-after-old-restart'
    $checks.Add([ordered]@{ name = 'old-core-stop-restart-preserves-new-helper-and-core'; passed = $true })
    Invoke-CoexistenceChild $InstallerPath @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR=' + $BundleDirectory), '/TASKS=', ('/LOG=' + (Join-Path $EvidenceDirectory 'new-overwrite.log'))) 'new-overwrite'
    if (-not $new.lease.process.WaitForExit(5000)) { throw 'The owned overwrite did not stop its new Core' }
    $new.lease.pipe.Dispose(); $new.lease.process.Dispose(); $new.lease = $null
    Assert-CoexistenceHelper $old 'old-after-new-overwrite'
    Assert-CoexistenceCore $old 'old-after-new-overwrite'
    Start-CoexistenceHelper $new 'new-after-overwrite'
    Start-CoexistenceCore $new 'new-after-overwrite'
    $checks.Add([ordered]@{ name = 'actual-new-installer-overwrite-preserves-old-helper-and-core'; passed = $true })
    Invoke-CoexistenceChild (Join-Path $BundleDirectory 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG=' + (Join-Path $EvidenceDirectory 'new-uninstall.log'))) 'new-uninstall'
    $uninstalled = $true
    if (-not $new.lease.process.WaitForExit(5000) -or (Get-CimInstance Win32_Service -Filter "Name='FengWoHelperService'") -or (Test-Path -LiteralPath (Join-Path $BundleDirectory 'FengWo.exe'))) { throw 'Uninstall did not remove the exact new installation and Helper' }
    $new.lease.pipe.Dispose(); $new.lease.process.Dispose(); $new.lease = $null
    Assert-CoexistenceHelper $old 'old-after-new-uninstall'
    Assert-CoexistenceCore $old 'old-after-new-uninstall'
    $checks.Add([ordered]@{ name = 'actual-new-uninstall-preserves-old-helper-and-core'; passed = $true })
} catch { $failure = $_.Exception.Message }
finally {
    foreach ($helper in @($new, $old)) {
        Clear-CoexistenceCoreLease $helper
        if ($helper.created) {
            try {
                $service = Get-CimInstance Win32_Service -Filter ("Name='" + $helper.service + "'")
                if ($service) {
                    $path = Join-Path $helper.directory ($helper.service + '.exe')
                    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($service.PathName.Trim('"'), $path)) { throw 'Cleanup refused a Helper service outside the recorded owned directory' }
                    Invoke-CoexistenceChild $path @('uninstall') ($helper.name + '-cleanup-service') 30
                    if (Get-CimInstance Win32_Service -Filter ("Name='" + $helper.service + "'")) { throw 'The recorded owned Helper service survived cleanup' }
                }
            } catch { $cleanupFailures.Add($_.Exception.Message) }
        }
    }
    if (-not $uninstalled -and (Test-Path -LiteralPath (Join-Path $BundleDirectory 'unins000.exe') -PathType Leaf)) {
        try { Invoke-CoexistenceChild (Join-Path $BundleDirectory 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'new-final-uninstall'; $uninstalled = $true } catch { $cleanupFailures.Add($_.Exception.Message) }
    }
    try { if (Test-Path -LiteralPath $oldDirectory) { Remove-Item -LiteralPath $oldDirectory -Recurse -Force } } catch { $cleanupFailures.Add($_.Exception.Message) }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'helper-port-coexistence.json') ([ordered]@{ passed = (-not $failure -and -not $cleanupFailures.Count -and $checks.Count -eq 6); failure = $failure; cleanup_failures = @($cleanupFailures.ToArray()); checks = @($checks.ToArray()); environment = $environment; architecture = $Architecture; old_helper_port = 47906; new_helper_port = 47907; old_binary_execution = $(if ($Architecture -ceq 'arm64') { 'actual x64 October 7 release under Windows ARM64 emulation' } else { 'actual native x64 October 7 release' }); new_binary_execution = ('actual native ' + $Architecture + ' candidate release'); customer_data_uploaded = $false; system_proxy_or_tun_started = $false })
}
if ($failure) { throw $failure }
if ($cleanupFailures.Count) { throw ($cleanupFailures -join '; ') }
if ($checks.Count -ne 6) { throw 'All six actual old/new Helper coexistence stages are required' }
