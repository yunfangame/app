param([switch]$RunCollector)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'collect_chrome_diagnostics.ps1')

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Hidden {
    param([string]$Source, [string[]]$Secrets)
    $result = Protect-DiagnosticText $Source
    foreach ($secret in $Secrets) {
        Assert-Condition (-not $result.Contains($secret)) ('脱敏失败：' + $secret)
    }
    return $result
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('fengwo chrome diagnostic tests ' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)
$oldUser = $env:USERNAME
$oldProfile = $env:USERPROFILE
$oldLocal = $env:LOCALAPPDATA
$oldRoaming = $env:APPDATA
try {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'collect_chrome_diagnostics.ps1'), [ref]$tokens, [ref]$parseErrors)
    Assert-Condition ($parseErrors.Count -eq 0) '脚本存在解析错误'
    $env:USERNAME = 'PrivateAlice'
    $env:USERPROFILE = 'C:\Users\PrivateAlice'
    $env:LOCALAPPDATA = 'C:\Users\PrivateAlice\AppData\Local'
    $env:APPDATA = 'C:\Users\PrivateAlice\AppData\Roaming'
    [void](Assert-Hidden 'C:\Users\PrivateAlice\file.log other C:\Users\PrivateBob\Downloads\chrome.exe' @('PrivateAlice', 'PrivateBob'))
    [void](Assert-Hidden 'C:\\Users\\PrivateBob\\Downloads\\chrome.exe' @('PrivateBob'))
    [void](Assert-Hidden 'mail=private_person@example.test Auth: Bearer SECRETBEARER==' @('private_person', 'SECRETBEARER'))
    [void](Assert-Hidden 'Authorization: Basic SECRETBASE64 rest' @('SECRETBASE64'))
    [void](Assert-Hidden 'Cookie: session=SECRETCOOKIE' @('SECRETCOOKIE'))
    [void](Assert-Hidden 'Set-Cookie: private=SECRETCOOKIE' @('SECRETCOOKIE'))
    [void](Assert-Hidden '{"access_token":"SECRETTOKEN", "password": "SECRET PASSWORD", "api-key":"SECRETKEY"}' @('SECRETTOKEN', 'SECRET PASSWORD', 'SECRETKEY'))
    [void](Assert-Hidden 'username=SECRETUSER refresh_token=SECRETREFRESH x-goog-api-key: SECRETGOOGLEKEY' @('SECRETUSER', 'SECRETREFRESH', 'SECRETGOOGLEKEY'))
    $url = Assert-Hidden 'https://PRIVATEURLUSER:PRIVATEURLPASS@proxy.example.test:8443/proxy.pac?token=PRIVATEQUERY#PRIVATEFRAGMENT' @('PRIVATEURLUSER', 'PRIVATEURLPASS', 'PRIVATEQUERY', 'PRIVATEFRAGMENT')
    Assert-Condition ($url.Contains('proxy.example.test:8443/proxy.pac')) 'URL脱敏破坏主机、端口或路径'
    [void](Assert-Hidden 'http=PRIVATEPROXYUSER:PRIVATEPROXYPASS@proxy.example.test:8080;https=127.0.0.1:7890' @('PRIVATEPROXYUSER', 'PRIVATEPROXYPASS'))
    $diagnostic = Protect-DiagnosticText 'https://update.googleapis.com/service/update2 HRESULT=0x80070006 Win32=6 TCP 127.0.0.1:7890'
    Assert-Condition ($diagnostic.Contains('0x80070006') -and $diagnostic.Contains('127.0.0.1:7890') -and $diagnostic.Contains('update.googleapis.com')) '关键诊断字段被误删'
    Assert-Condition ((Protect-DiagnosticText ('x' * 10000)).Length -lt 8300) '单行上限未生效'

    $logPath = Join-Path $tempRoot 'chrome_installer.log'
    $content = (1..1800 | ForEach-Object { 'line-' + $_ + ' token=SECRETLOGTOKEN ' + ('x' * 100) }) -join "`r`n"
    [IO.File]::WriteAllText($logPath, $content, (New-Object Text.UTF8Encoding($false)))
    $before = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash
    $record = Read-ChromeLogTail $logPath '测试日志'
    Assert-Condition ($record['状态'] -eq '已读取') '尾部读取失败'
    Assert-Condition ($record['读取字节数'] -le 131072) '读取超过128KiB'
    Assert-Condition ($record['截取行数'] -le 250) '输出超过250行'
    $recordJson = $record | ConvertTo-Json -Depth 8
    Assert-Condition (-not $recordJson.Contains('SECRETLOGTOKEN')) '日志脱敏失败'
    Assert-Condition ($recordJson.Contains('line-1800')) '未保留最新日志行'
    Assert-Condition (-not $recordJson.Contains('line-1 ')) '未截掉旧日志'
    Assert-Condition ($before -eq (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash) '原始日志发生变化'
    $missing = Read-ChromeLogTail (Join-Path $tempRoot 'not-present.log') '不存在测试'
    Assert-Condition ($missing['状态'] -eq '不存在') '未正确记录不存在的日志'
    [IO.File]::WriteAllText($logPath, '')
    $empty = Read-ChromeLogTail $logPath '空日志'
    Assert-Condition ($empty['状态'] -eq '已读取' -and $empty['读取字节数'] -eq 0) '空日志读取失败'
    $env:USERNAME = $oldUser
    $env:USERPROFILE = $oldProfile
    $env:LOCALAPPDATA = $oldLocal
    $env:APPDATA = $oldRoaming
    if ($RunCollector) {
        $output = Invoke-FengWoChromeDiagnostics -OutputParent $tempRoot
        foreach ($name in @('diagnostics.json', 'diagnostics.txt', '说明.txt')) {
            Assert-Condition ([IO.File]::Exists((Join-Path $output $name))) ('未生成 ' + $name)
        }
        $parsed = [IO.File]::ReadAllText((Join-Path $output 'diagnostics.json')) | ConvertFrom-Json
        Assert-Condition ($parsed.'系统信息'.'状态' -eq '已读取') '实际Windows系统信息读取失败'
        Assert-Condition ($parsed.'WinHTTP系统默认代理'.'状态' -eq '已读取') '实际WinHTTP系统代理读取失败'
        Assert-Condition ($parsed.'WinHTTP读取当前用户代理'.'状态' -eq '已读取') '实际WinHTTP用户代理读取失败'
    }
    Write-Host 'PASS：解析、脱敏、路径空格、日志大小与行数限制、缺失/空日志、原始日志未改动。'
} finally {
    $env:USERNAME = $oldUser
    $env:USERPROFILE = $oldProfile
    $env:LOCALAPPDATA = $oldLocal
    $env:APPDATA = $oldRoaming
    if ([IO.Directory]::Exists($tempRoot)) { [IO.Directory]::Delete($tempRoot, $true) }
}
