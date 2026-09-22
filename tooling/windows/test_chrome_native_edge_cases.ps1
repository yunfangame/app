param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Requires disposable Windows CI' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
Add-Type -Path "$PSScriptRoot/chrome_winhttp_probe.cs"
$cases = Get-Content "$PSScriptRoot/chrome_proxy_cases.json" -Raw | ConvertFrom-Json
$rawBypass = $cases.current -join ';'
$bracketBypass = ($cases.current | ForEach-Object { if ($_ -eq '::1') { '[::1]' } else { $_ } }) -join ';'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$original = Get-ItemProperty $key
$results = @()
$proxy = $null
function Test-Current([string]$name) {
    $state = Get-ItemProperty $key | Select-Object ProxyEnable, ProxyServer, ProxyOverride
    $result = [ChromeNetworkProbe]::Get('https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe', 4, $null)
    return @{name=$name; state=$state; result=$result}
}
try {
    $proxy = Start-Process python -ArgumentList @("$PSScriptRoot/chrome_probe_proxy.py", '--port', '17890', '--log', "$OutputDirectory/proxy.jsonl") -PassThru -RedirectStandardError "$OutputDirectory/proxy-stderr.txt"
    Start-Sleep -Seconds 2
    [ChromeNetworkProbe]::SetProxy('127.0.0.1:17890', $rawBypass)
    $results += Test-Current 'raw_enabled'
    [ChromeNetworkProbe]::SetProxyFlags(1)
    $results += Test-Current 'raw_disabled_flags_only'
    [ChromeNetworkProbe]::SetProxy('127.0.0.1:17890', $bracketBypass)
    $results += Test-Current 'bracket_enabled'
    [ChromeNetworkProbe]::SetProxyFlags(1)
    $results += Test-Current 'bracket_disabled_flags_only'
    [ChromeNetworkProbe]::SetProxy('127.0.0.1:17890', $rawBypass)
    [ChromeNetworkProbe]::SetProxyFlags(1)
    [ChromeNetworkProbe]::SetProxy('127.0.0.1:17890', $bracketBypass)
    [ChromeNetworkProbe]::SetProxyFlags(1)
    $results += Test-Current 'raw_disabled_then_valid_start_then_stop'
} finally {
    try { [ChromeNetworkProbe]::SetProxy($(if($original.ProxyEnable -eq 1){$original.ProxyServer}else{$null}), $original.ProxyOverride) } catch {}
    if ($proxy -and -not $proxy.HasExited) { Stop-Process -Id $proxy.Id -Force -ErrorAction SilentlyContinue }
    $results | ConvertTo-Json -Depth 9 | Set-Content "$OutputDirectory/edge-report.json"
    $results | ConvertTo-Json -Depth 9 | Write-Output
}
if ($results.Count -ne 5) { throw 'Incomplete native matrix' }
