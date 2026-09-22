param(
    [ValidateSet('direct', 'upstream', 'current', 'current_no_ipv6', 'bracket', 'production')][string]$Mode,
    [string]$OutputDirectory,
    [switch]$ProbeOnly
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -and -not $ProbeOnly) { throw 'Requires disposable GitHub Actions Windows runner' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
Add-Type -Path "$PSScriptRoot/chrome_winhttp_probe.cs"
$proxyValue = if ($Mode -eq 'direct') { $null } else { '127.0.0.1:17890' }
$proxyCases = Get-Content "$PSScriptRoot/chrome_proxy_cases.json" -Raw | ConvertFrom-Json
$bypassValue = if ($Mode -eq 'direct') { '' } elseif ($Mode -eq 'bracket') { ($proxyCases.current | ForEach-Object { if ($_ -eq '::1') { '[::1]' } else { $_ } }) -join ';' } else { $proxyCases.$Mode -join ';' }
if ($Mode -eq 'production' -and -not $ProbeOnly) {
    $bypassValue = [IO.File]::ReadAllText("$OutputDirectory/normalized-bypass.txt", [Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($bypassValue)) { throw 'Production normalized fixture is missing' }
}
$installerUrl = 'https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463C-AFF1-A69D9E530F96%7D%26appname%3DGoogle%2520Chrome%26needsadmin%3Dtrue%26ap%3Dx64-stable/update2/installers/ChromeSetup.exe'
function Invoke-NetworkProbe {
    $results = @()
    foreach ($url in @('https://update.googleapis.com/service/update2', $installerUrl)) {
        foreach ($access in @(0, 4, 3)) {
            $explicitProxy = if ($access -eq 3) { '127.0.0.1:17890' } else { $null }
            $results += [ChromeNetworkProbe]::Get($url, $access, $explicitProxy)
        }
    }
    return @{ identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name; mode = $Mode; results = $results }
}
if ($ProbeOnly) {
    Invoke-NetworkProbe | ConvertTo-Json -Depth 8 | Set-Content "$OutputDirectory/system-probe.json"
    exit 0
}
$report = @{ mode=$Mode; bypass=$bypassValue; os=[Environment]::OSVersion.VersionString; installer_url=$installerUrl; started=(Get-Date).ToUniversalTime().ToString('o'); system_probe_limitation='SYSTEM does not inherit runner HKCU and this CI runner may lack an interactive logged-on user; direct SYSTEM auto-proxy is not a FengWo failure.' }
$proxyProcess = $null
$taskName = 'FengWoChromeNetworkProbe'
$internetSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$originalProxy = Get-ItemProperty $internetSettings
try {
    $proxyProcess = Start-Process python -ArgumentList @("$PSScriptRoot/chrome_probe_proxy.py", '--port', '17890', '--log', "$OutputDirectory/proxy.jsonl") -PassThru -RedirectStandardError "$OutputDirectory/proxy-stderr.txt"
    Start-Sleep -Seconds 2
    if ($proxyProcess.HasExited) { throw 'Local CONNECT proxy failed to start' }
    $installer = "$OutputDirectory/ChromeSetup.exe"
    $bootstrapArgs = @('--fail', '--silent', '--show-error', '--location', '--noproxy', '*', '--connect-timeout', '15', '--max-time', '90', '--output', $installer, $installerUrl)
    $bootstrapProcess = Start-Process curl.exe -ArgumentList $bootstrapArgs -PassThru -RedirectStandardError "$OutputDirectory/bootstrap-stderr.txt" -RedirectStandardOutput "$OutputDirectory/bootstrap-stdout.txt"
    $bootstrapHandle = $bootstrapProcess.Handle
    if (-not $bootstrapProcess.WaitForExit(100000)) { & taskkill /PID $bootstrapProcess.Id /T /F | Out-Null; throw 'Direct bootstrap timed out' }
    $report.bootstrap_exit_code = $bootstrapProcess.ExitCode
    if ($bootstrapProcess.ExitCode -ne 0) { throw "Direct bootstrap download failed: $($bootstrapProcess.ExitCode)" }
    $signature = Get-AuthenticodeSignature $installer
    $report.installer_signature = @{status=$signature.Status.ToString(); subject=$signature.SignerCertificate.Subject; sha256=(Get-FileHash $installer -Algorithm SHA256).Hash; bytes=(Get-Item $installer).Length}
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Google LLC') { throw 'Official installer signature validation failed' }
    $report.bootstrap_purpose = 'Verified direct bootstrap before applying proxy; does not count as proxy success'
    [ChromeNetworkProbe]::SetProxy($proxyValue, $bypassValue)
    $report.user_probe = Invoke-NetworkProbe
    $report.user_probe | ConvertTo-Json -Depth 8 | Set-Content "$OutputDirectory/user-probe.json"
    $report.user_probe | ConvertTo-Json -Depth 8 | Write-Output
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Mode ' + $Mode + ' -OutputDirectory "' + $OutputDirectory + '" -ProbeOnly')
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    $deadline = (Get-Date).AddSeconds(110)
    while (-not (Test-Path "$OutputDirectory/system-probe.json") -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    $report.system_probe_complete = Test-Path "$OutputDirectory/system-probe.json"
    $report.winhttp_default = (& netsh winhttp show proxy | Out-String)
    $report.user_proxy = Get-ItemProperty $internetSettings | Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL
    $chromePaths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
    $report.preexisting_chrome = @($chromePaths | Where-Object { Test-Path $_ } | ForEach-Object { @{path=$_; version=(Get-Item $_).VersionInfo.FileVersion} })
    Get-Process chrome, GoogleUpdater, GoogleUpdate -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($chrome in $report.preexisting_chrome) {
        $setups = Get-ChildItem (Split-Path $chrome.path) -Filter setup.exe -Recurse -ErrorAction SilentlyContinue
        foreach ($setup in $setups) {
            $uninstaller = Start-Process $setup.FullName -ArgumentList '--uninstall --system-level --force-uninstall' -PassThru
            $uninstallerHandle = $uninstaller.Handle
            if (-not $uninstaller.WaitForExit(45000)) { & taskkill /PID $uninstaller.Id /T /F | Out-Null }
        }
    }
    $report.chrome_present_before_online_install = @($chromePaths | Where-Object { Test-Path $_ })
    $downloadArgs = @('--fail', '--silent', '--show-error', '--location', '--connect-timeout', '15', '--max-time', '60', '--output', "$OutputDirectory/bootstrap-through-proxy.exe")
    if ($Mode -ne 'direct') { $downloadArgs += @('--proxy', 'http://127.0.0.1:17890') }
    $curlProcess = Start-Process curl.exe -ArgumentList ($downloadArgs + @($installerUrl)) -PassThru -RedirectStandardError "$OutputDirectory/curl-stderr.txt" -RedirectStandardOutput "$OutputDirectory/curl-stdout.txt"
    $curlHandle = $curlProcess.Handle
    if (-not $curlProcess.WaitForExit(70000)) { & taskkill /PID $curlProcess.Id /T /F | Out-Null }
    $report.curl_download_exit_code = $curlProcess.ExitCode
    $started = Get-Date
    $process = Start-Process $installer -ArgumentList '--install --silent --system --enable-logging --vmodule=*/chrome/updater/*=2' -PassThru
    $installerHandle = $process.Handle
    $completed = $process.WaitForExit(210000)
    if (-not $completed) { & taskkill /PID $process.Id /T /F | Out-Null }
    $report.online_installer = @{completed=$completed; exit_code=if($completed){$process.ExitCode}else{$null}; elapsed_seconds=((Get-Date)-$started).TotalSeconds}
    Start-Sleep -Seconds 10
    $report.installed_chrome = @($chromePaths | Where-Object { Test-Path $_ } | ForEach-Object { @{path=$_; version=(Get-Item $_).VersionInfo.FileVersion} })
    $report.google_services = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'Google|gupdate' } | Select-Object Name, State, StartName, PathName)
} catch {
    $report.script_error = @{message=$_.Exception.Message; hresult=$_.Exception.HResult; line=$_.InvocationInfo.ScriptLineNumber}
} finally {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    try { [ChromeNetworkProbe]::SetProxy($(if($originalProxy.ProxyEnable -eq 1){$originalProxy.ProxyServer}else{$null}), $originalProxy.ProxyOverride) } catch {}
    if ($proxyProcess -and -not $proxyProcess.HasExited) { Stop-Process -Id $proxyProcess.Id -Force -ErrorAction SilentlyContinue }
    $logRoots = @("$env:ProgramFiles\Google", "${env:ProgramFiles(x86)}\Google", "$env:ProgramData\Google", "$env:LOCALAPPDATA\Google", "$env:SystemRoot\System32\config\systemprofile\AppData\Local\Google")
    $logDirectory = New-Item -ItemType Directory -Force "$OutputDirectory/google-logs"
    $index = 0
    foreach ($root in $logRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($log in Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'updater.*log|chrome_installer.log|GoogleUpdate.log' }) {
            $index++
            Copy-Item $log.FullName "$logDirectory/$index-$($log.Name)" -ErrorAction SilentlyContinue
        }
    }
    $report.invalid_handle_matches = @(Get-ChildItem $logDirectory -File | Select-String -Pattern '80070006|INVALID_HANDLE|invalid handle' | ForEach-Object { @{file=$_.Filename; line=$_.LineNumber; text=$_.Line} })
    Remove-Item "$OutputDirectory/ChromeSetup.exe" -Force -ErrorAction SilentlyContinue
    Remove-Item "$OutputDirectory/bootstrap-through-proxy.exe" -Force -ErrorAction SilentlyContinue
    $report.finished = (Get-Date).ToUniversalTime().ToString('o')
    $report | ConvertTo-Json -Depth 12 | Set-Content "$OutputDirectory/report.json"
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
if ($report.script_error) { exit 1 }
