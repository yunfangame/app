param(
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
  throw 'Service repair tests require an isolated GitHub Actions Windows runner'
}
if (Get-Service -Name FlClashHelperService -ErrorAction SilentlyContinue) {
  throw 'An existing helper service must not be replaced by this test'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$installDirectory = Join-Path $env:RUNNER_TEMP 'fengwo-helper-repair'
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$helper = Join-Path $installDirectory 'FlClashHelperService.exe'
$heldService = [IntPtr]::Zero
$manager = [IntPtr]::Zero
$legacyListener = $null
$conflictListener = $null
$results = [System.Collections.Generic.List[object]]::new()
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FengWoScmTest {
  public static int LastError { get; private set; }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
  private static extern IntPtr OpenSCManagerW(string machine, string database, uint access);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
  private static extern IntPtr OpenServiceW(IntPtr manager, string name, uint access);
  [DllImport("advapi32.dll", SetLastError = true)]
  public static extern bool CloseServiceHandle(IntPtr handle);
  public static IntPtr OpenLocalManager() {
    var handle = OpenSCManagerW(null, null, 1);
    LastError = Marshal.GetLastWin32Error();
    return handle;
  }
  public static IntPtr OpenHelperQueryHandle(IntPtr manager) {
    var handle = OpenServiceW(manager, "FlClashHelperService", 4);
    LastError = Marshal.GetLastWin32Error();
    return handle;
  }
}
'@

function Install-Package {
  $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$installDirectory", '/TASKS=')
  $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw "Package installer failed: $($process.ExitCode)" }
}

function Invoke-Helper([string]$Command, [int]$ExpectedCode = 0) {
  $prefix = Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N') + "-$Command")
  $process = Start-Process -FilePath $helper -ArgumentList $Command -PassThru -RedirectStandardOutput "$prefix.stdout.txt" -RedirectStandardError "$prefix.stderr.txt"
  if (-not $process.WaitForExit(45000)) {
    $process | Stop-Process -Force
    throw "Helper $Command exceeded its deadline"
  }
  if ($process.ExitCode -ne $ExpectedCode) {
    Get-Content -LiteralPath "$prefix.stderr.txt" | Write-Host
    throw "Helper $Command returned $($process.ExitCode), expected $ExpectedCode"
  }
}

function Assert-Service([string]$State) {
  $service = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
  if ($null -eq $service -or $service.State -ne $State) { throw "Expected helper service state $State" }
  if ($service.PathName.Trim('"') -ine $helper) { throw 'Service repair did not retain the current helper path' }
  if ($service.StartMode -ne 'Auto' -or $service.StartName -ne 'LocalSystem') { throw 'Service repair did not restore automatic LocalSystem configuration' }
  if ($State -eq 'Running') {
    $manifest = Get-Content -LiteralPath (Join-Path $installDirectory 'manifest.json') -Raw | ConvertFrom-Json
    $ping = Invoke-WebRequest -Uri "http://127.0.0.1:47906/ping?coreSha256=$($manifest.coreSha256)" -NoProxy
    if ($ping.StatusCode -ne 200 -or $ping.Content.Trim() -ine $helper) { throw 'Repaired helper does not match the installed application' }
    if ($ping.Headers['x-flclash-helper-protocol'] -ne '6') { throw 'Unexpected repaired helper protocol' }
  }
}

function Start-ExclusiveListener([int]$Port) {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
  $listener.ExclusiveAddressUse = $true
  $listener.Start()
  return $listener
}

function Assert-Listener([System.Net.Sockets.TcpListener]$Listener) {
  $client = [System.Net.Sockets.TcpClient]::new()
  $accepted = $null
  try {
    $accept = $Listener.AcceptTcpClientAsync()
    $connect = $client.ConnectAsync([System.Net.IPAddress]::Loopback, $Listener.LocalEndpoint.Port)
    if (-not $connect.Wait(5000) -or -not $accept.Wait(5000)) { throw 'External listener stopped accepting connections' }
    $accepted = $accept.Result
    if (-not $client.Connected -or -not $accepted.Connected) { throw 'External listener connection was interrupted' }
    $client.Dispose()
    $accepted.ReceiveTimeout = 5000
    if ($accepted.GetStream().ReadByte() -ne -1) { throw 'External listener did not close the probe connection cleanly' }
  } finally {
    if ($null -ne $accepted) { $accepted.Dispose() }
    $client.Dispose()
  }
}

try {
  $legacyListener = Start-ExclusiveListener -Port 47890
  Install-Package
  Invoke-Helper -Command 'install'
  Assert-Service -State 'Running'
  Assert-Listener -Listener $legacyListener
  $results.Add(@{ case = 'helper-starts-with-legacy-port-occupied'; passed = $true })

  Invoke-Helper -Command 'stop'
  $conflictListener = Start-ExclusiveListener -Port 47906
  Invoke-Helper -Command 'install' -ExpectedCode 10048
  Assert-Service -State 'Stopped'
  $failedService = Get-CimInstance Win32_Service -Filter "Name='FlClashHelperService'"
  if ($failedService.ExitCode -ne 10048) { throw 'Service status did not preserve the port conflict error' }
  Assert-Listener -Listener $conflictListener
  Assert-Listener -Listener $legacyListener
  $results.Add(@{ case = 'occupied-helper-port-reports-10048-without-stopping-listeners'; passed = $true })
  $conflictListener.Stop()
  $conflictListener = $null
  Invoke-Helper -Command 'install'
  Assert-Service -State 'Running'
  $results.Add(@{ case = 'helper-recovers-after-conflicting-port-is-released'; passed = $true })

  $manager = [FengWoScmTest]::OpenLocalManager()
  if ($manager -eq [IntPtr]::Zero) { throw "Cannot open test service manager (Win32 $([FengWoScmTest]::LastError))" }
  $heldService = [FengWoScmTest]::OpenHelperQueryHandle($manager)
  if ($heldService -eq [IntPtr]::Zero) { throw "Cannot retain a service query handle (Win32 $([FengWoScmTest]::LastError))" }
  Invoke-Helper -Command 'install'
  Assert-Service -State 'Running'
  $results.Add(@{ case = 'repair-with-external-service-handle'; passed = $true })

  Invoke-Helper -Command 'stop'
  Assert-Service -State 'Stopped'
  & sc.exe config FlClashHelperService start= disabled binPath= 'C:\missing-fengwo-helper.exe' | Write-Host
  if ($LASTEXITCODE -ne 0) { throw 'Cannot stage stale service configuration' }
  Invoke-Helper -Command 'install'
  Assert-Service -State 'Running'
  $results.Add(@{ case = 'repair-disabled-stale-service-configuration'; passed = $true })

  Install-Package
  Assert-Service -State 'Stopped'
  Invoke-Helper -Command 'install'
  Assert-Service -State 'Running'
  Assert-Listener -Listener $legacyListener
  $results.Add(@{ case = 'overwrite-installer-retains-service-registration'; passed = $true })

  Invoke-Helper -Command 'uninstall' -ExpectedCode 1072
  Invoke-Helper -Command 'install' -ExpectedCode 1072
  [void][FengWoScmTest]::CloseServiceHandle($heldService)
  $heldService = [IntPtr]::Zero
  Invoke-Helper -Command 'install'
  Assert-Service -State 'Running'
  $results.Add(@{ case = 'pending-deletion-reports-1072-and-recovers-after-handle-release'; passed = $true })
  Invoke-Helper -Command 'uninstall'
  if (Get-Service -Name FlClashHelperService -ErrorAction SilentlyContinue) { throw 'Uninstall did not remove the helper service' }
  Assert-Listener -Listener $legacyListener
  $results.Add(@{ case = 'explicit-uninstall-removes-service'; passed = $true })
} finally {
  if ($null -ne $conflictListener) { $conflictListener.Stop() }
  if ($null -ne $legacyListener) { $legacyListener.Stop() }
  if ($heldService -ne [IntPtr]::Zero) { [void][FengWoScmTest]::CloseServiceHandle($heldService) }
  if ($manager -ne [IntPtr]::Zero) { [void][FengWoScmTest]::CloseServiceHandle($manager) }
  if (Test-Path -LiteralPath $helper) { & $helper uninstall 2>&1 | Write-Host }
  $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'helper-repair-results.json') -Encoding utf8NoBOM
}
