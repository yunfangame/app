param([string]$OutputParent = $PSScriptRoot)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Protect-DiagnosticText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    foreach ($path in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $text = [regex]::Replace($text, [regex]::Escape($path), '<用户目录>', 'IgnoreCase')
        }
    }
    $text = [regex]::Replace($text, '(?i)([a-z]:\\+(?:Users|Documents and Settings)\\+)[^\\\s"''<>]+', '$1<用户>')
    $text = [regex]::Replace($text, '(?im)(?:authorization|proxy-authorization|cookie|set-cookie)\s*:\s*[^\r\n]+', '<认证信息已隐藏>')
    $text = [regex]::Replace($text, '(?i)\b(?:Bearer|Basic)\s+[A-Za-z0-9_+/.=:-]+', '<认证信息已隐藏>')
    $text = [regex]::Replace($text, '(?i)(["'']?(?:password|passwd|pwd|[a-z0-9_-]*token|api[-_]?key|x-goog-api-key|[a-z0-9_-]*secret|session[-_]?id|user[-_]?id|user[-_]?name|email)["'']?\s*[:=]\s*)(?:"[^"\r\n]*"|''[^''\r\n]*''|[^\s,;&}\]]+)', '$1<已隐藏>')
    $text = [regex]::Replace($text, '(?i)https?://[^\s"''<>]+', [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        try {
            $uri = [Uri]$match.Value
            $builder = New-Object System.UriBuilder($uri)
            $builder.UserName = ''
            $builder.Password = ''
            $builder.Query = ''
            $builder.Fragment = ''
            return $builder.Uri.AbsoluteUri
        } catch {
            return '<链接已隐藏>'
        }
    })
    $text = [regex]::Replace($text, '(?i)(?<![\w])[^;\s="''<>]+:[^;\s@"''<>]+@(?=[a-z0-9\[])', '<凭证已隐藏>@')
    $text = [regex]::Replace($text, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '<邮箱已隐藏>')
    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        $text = [regex]::Replace($text, '(?i)(?<![\w])' + [regex]::Escape($env:USERNAME) + '(?![\w])', '<用户>')
    }
    if ($text.Length -gt 8192) { $text = $text.Substring(0, 8192) + ' <本行已截断>' }
    return $text
}

function Get-SafeFailure {
    param([System.Management.Automation.ErrorRecord]$Record)
    return [ordered]@{
        状态 = '无法读取'
        错误类型 = $Record.Exception.GetType().FullName
        错误码 = ('0x{0:X8}' -f ($Record.Exception.HResult -band 0xffffffffL))
        详情 = Protect-DiagnosticText $Record.Exception.Message
    }
}

function Get-RegistryValueOrNull {
    param([Microsoft.Win32.RegistryKey]$Key, [string]$Name)
    return $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function Get-ChromeOsSummary {
    $key = $null
    $identity = $null
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion', $false)
        if ($null -eq $key) { throw '无法读取 Windows 版本注册表' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return [ordered]@{
            状态 = '已读取'
            产品名称 = Get-RegistryValueOrNull $key 'ProductName'
            显示版本 = Get-RegistryValueOrNull $key 'DisplayVersion'
            构建号 = Get-RegistryValueOrNull $key 'CurrentBuildNumber'
            更新修订号 = Get-RegistryValueOrNull $key 'UBR'
            实际系统版本 = [Environment]::OSVersion.Version.ToString()
            系统位数 = $(if ([Environment]::Is64BitOperatingSystem) { 64 } else { 32 })
            PowerShell版本 = $PSVersionTable.PSVersion.ToString()
            当前进程拥有管理员权限 = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    } catch { return Get-SafeFailure $_ }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $identity) { $identity.Dispose() }
    }
}

function Get-ChromeInternetSettings {
    $key = $null
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Internet Settings', $false)
        if ($null -eq $key) { return [ordered]@{ 状态 = '注册表项不存在' } }
        $result = [ordered]@{ 状态 = '已读取' }
        foreach ($name in @('ProxyEnable', 'AutoDetect', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL')) {
            $value = Get-RegistryValueOrNull $key $name
            if ($null -eq $value) { $result[$name] = $null }
            elseif ($value -is [string]) { $result[$name] = Protect-DiagnosticText $value }
            else { $result[$name] = $value }
        }
        return $result
    } catch { return Get-SafeFailure $_ }
    finally { if ($null -ne $key) { $key.Dispose() } }
}

function Initialize-ChromeWinHttpReader {
    if ('FengWoChromeReadOnly.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace FengWoChromeReadOnly {
    [StructLayout(LayoutKind.Sequential)]
    public struct ProxyInfo {
        public uint AccessType;
        public IntPtr Proxy;
        public IntPtr Bypass;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct UserProxyInfo {
        [MarshalAs(UnmanagedType.Bool)] public bool AutoDetect;
        public IntPtr AutoConfigUrl;
        public IntPtr Proxy;
        public IntPtr Bypass;
    }
    public static class Native {
        [DllImport("winhttp.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool WinHttpGetDefaultProxyConfiguration(out ProxyInfo info);
        [DllImport("winhttp.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool WinHttpGetIEProxyConfigForCurrentUser(out UserProxyInfo info);
        [DllImport("kernel32.dll")]
        public static extern IntPtr GlobalFree(IntPtr memory);
    }
}
'@
}

function Get-ChromeWinHttpSettings {
    param([switch]$CurrentUser)
    $pointers = @()
    try {
        Initialize-ChromeWinHttpReader
        if ($CurrentUser) {
            $info = New-Object FengWoChromeReadOnly.UserProxyInfo
            $success = [FengWoChromeReadOnly.Native]::WinHttpGetIEProxyConfigForCurrentUser([ref]$info)
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $pointers = @($info.AutoConfigUrl, $info.Proxy, $info.Bypass)
        } else {
            $info = New-Object FengWoChromeReadOnly.ProxyInfo
            $success = [FengWoChromeReadOnly.Native]::WinHttpGetDefaultProxyConfiguration([ref]$info)
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $pointers = @($info.Proxy, $info.Bypass)
        }
        if (-not $success) { return [ordered]@{ 状态 = '读取失败'; Win32错误码 = $errorCode } }
        $result = [ordered]@{
            状态 = '已读取'
            ProxyServer = Protect-DiagnosticText ([Runtime.InteropServices.Marshal]::PtrToStringUni($info.Proxy))
            ProxyOverride = Protect-DiagnosticText ([Runtime.InteropServices.Marshal]::PtrToStringUni($info.Bypass))
        }
        if ($CurrentUser) {
            $result['AutoDetect'] = $info.AutoDetect
            $result['AutoConfigURL'] = Protect-DiagnosticText ([Runtime.InteropServices.Marshal]::PtrToStringUni($info.AutoConfigUrl))
        } else { $result['AccessType'] = $info.AccessType }
        return $result
    } catch { return Get-SafeFailure $_ }
    finally {
        foreach ($pointer in $pointers) {
            if ($pointer -ne [IntPtr]::Zero) { [void][FengWoChromeReadOnly.Native]::GlobalFree($pointer) }
        }
    }
}

function Get-ChromeServices {
    try {
        $services = @(Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE 'GoogleUpdater%' OR Name = 'gupdate' OR Name = 'gupdatem' OR Name = 'GoogleUpdate' OR Name = 'WinHttpAutoProxySvc'" -OperationTimeoutSec 10 -ErrorAction Stop)
        $items = @($services | ForEach-Object {
            [ordered]@{
                服务名称 = Protect-DiagnosticText $_.Name
                状态 = $_.State
                启动方式 = $_.StartMode
                退出码 = $_.ExitCode
                服务退出码 = $_.ServiceSpecificExitCode
            }
        })
        return [ordered]@{ 状态 = '已读取'; 列表 = $items; 未安装的服务不会出现 = $true }
    } catch {
        $failure = Get-SafeFailure $_
        try {
            $items = @(Get-Service -Name 'GoogleUpdater*', 'gupdate', 'gupdatem', 'GoogleUpdate', 'WinHttpAutoProxySvc' -ErrorAction SilentlyContinue | ForEach-Object {
                [ordered]@{ 服务名称 = Protect-DiagnosticText $_.Name; 状态 = $_.Status.ToString() }
            })
            return [ordered]@{ 状态 = '仅获取到基本状态'; CIM错误 = $failure; 列表 = $items }
        } catch { return $failure }
    }
}

function Get-KnownChromeLocations {
    $bases = @()
    foreach ($entry in @(
        @{ Path = $env:LOCALAPPDATA; Scope = '当前用户' },
        @{ Path = ${env:ProgramFiles(x86)}; Scope = '系统32位目录' },
        @{ Path = $env:ProgramW6432; Scope = '系统64位目录' },
        @{ Path = $env:ProgramFiles; Scope = '系统程序目录' }
    )) {
        if (-not [string]::IsNullOrWhiteSpace($entry.Path) -and -not (@($bases | ForEach-Object { $_.Path }) -contains $entry.Path)) {
            $bases += [pscustomobject]$entry
        }
    }
    return $bases
}

function Get-ChromeBinaryRecord {
    param([string]$Path, [string]$Kind, [string]$Scope)
    $record = [ordered]@{ 类型 = $Kind; 范围 = $Scope; 路径 = Protect-DiagnosticText $Path }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.PSIsContainer) { throw '目标不是文件' }
        $record['状态'] = '已读取'
        $record['文件版本'] = Protect-DiagnosticText $item.VersionInfo.FileVersion
        $record['产品版本'] = Protect-DiagnosticText $item.VersionInfo.ProductVersion
        $record['修改时间UTC'] = $item.LastWriteTimeUtc.ToString('o')
    } catch {
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound') { $record['状态'] = '不存在' }
        else { $record['错误'] = Get-SafeFailure $_ }
    }
    return $record
}

function Get-ChromeBinaryVersions {
    $records = @()
    foreach ($base in @(Get-KnownChromeLocations)) {
        $records += Get-ChromeBinaryRecord (Join-Path $base.Path 'Google\Chrome\Application\chrome.exe') 'Chrome' $base.Scope
        $records += Get-ChromeBinaryRecord (Join-Path $base.Path 'Google\Update\GoogleUpdate.exe') '旧版更新器' $base.Scope
        $root = Join-Path $base.Path 'Google\GoogleUpdater'
        try {
            $versions = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop | Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 16)
            foreach ($version in $versions) {
                $records += Get-ChromeBinaryRecord (Join-Path $version.FullName 'updater.exe') 'GoogleUpdater' $base.Scope
            }
        } catch {
            if ($_.CategoryInfo.Category -ne 'ObjectNotFound') {
                $records += [ordered]@{ 类型 = 'GoogleUpdater目录'; 范围 = $base.Scope; 路径 = Protect-DiagnosticText $root; 错误 = Get-SafeFailure $_ }
            }
        }
    }
    return $records
}

function Read-ChromeLogTail {
    param([string]$Path, [string]$Kind)
    $record = [ordered]@{ 类型 = $Kind; 路径 = Protect-DiagnosticText $Path }
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $length = $stream.Length
        $offset = [Math]::Max(0, $length - 131072)
        [void]$stream.Seek($offset, [IO.SeekOrigin]::Begin)
        $buffer = New-Object byte[] ([int]($length - $offset))
        $read = 0
        while ($read -lt $buffer.Length) {
            $count = $stream.Read($buffer, $read, $buffer.Length - $read)
            if ($count -eq 0) { break }
            $read += $count
        }
        $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        $lines = @($text -split '\r?\n')
        if ($offset -gt 0 -and $lines.Count -gt 1) { $lines = @($lines | Select-Object -Skip 1) }
        $lines = @($lines | Select-Object -Last 250 | ForEach-Object { Protect-DiagnosticText $_ })
        $record['状态'] = '已读取'
        $record['文件字节数'] = $length
        $record['读取字节数'] = $read
        $record['截取行数'] = $lines.Count
        $record['末尾内容'] = $lines
    } catch {
        $cause = $_.Exception.GetBaseException()
        if ($cause -is [IO.FileNotFoundException] -or $cause -is [IO.DirectoryNotFoundException]) { $record['状态'] = '不存在' }
        else { $record['错误'] = Get-SafeFailure $_ }
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    return $record
}

function Get-ChromeLogRecords {
    $paths = @{}
    foreach ($base in @(Get-KnownChromeLocations)) {
        $paths[(Join-Path $base.Path 'Google\GoogleUpdater\updater.log')] = 'GoogleUpdater日志'
    }
    foreach ($tempPath in @($env:TEMP, $env:TMP)) {
        if (-not [string]::IsNullOrWhiteSpace($tempPath)) {
            $paths[(Join-Path $tempPath 'updater.log')] = '用户更新器退出日志'
            $paths[(Join-Path $tempPath 'chrome_installer.log')] = '用户Chrome安装日志'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:windir)) {
        $paths[(Join-Path $env:windir 'SystemTemp\updater.log')] = '系统更新器退出日志'
        $paths[(Join-Path $env:windir 'Temp\chrome_installer.log')] = '系统Chrome安装日志'
        $paths[(Join-Path $env:windir 'SystemTemp\chrome_installer.log')] = '系统Chrome安装日志'
    }
    foreach ($path in @($paths.Keys | Sort-Object)) { Read-ChromeLogTail $path $paths[$path] }
}

function Invoke-FengWoChromeDiagnostics {
    param([string]$OutputParent = $PSScriptRoot)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '此诊断工具仅支持 Windows。' }
    Write-Host '正在采集 Chrome 安装与更新诊断信息，不修改系统设置，不请求网络。'
    $folderName = 'FengWo-Chrome-Diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
    try {
        $output = Join-Path $OutputParent $folderName
        [void][IO.Directory]::CreateDirectory($output)
    } catch {
        $output = Join-Path ([IO.Path]::GetTempPath()) $folderName
        [void][IO.Directory]::CreateDirectory($output)
        Write-Host '原目录不可写，报告将保存到当前用户的临时目录。'
    }
    $report = [ordered]@{
        工具版本 = '1.0'
        采集时间UTC = [DateTime]::UtcNow.ToString('o')
        说明 = '只读采集；权限不足和文件不存在会单独标记；不包含账号、浏览器历史、Cookie文件或完整注册表。'
        系统信息 = Get-ChromeOsSummary
        相关服务 = Get-ChromeServices
        当前用户代理注册表 = Get-ChromeInternetSettings
        WinHTTP系统默认代理 = Get-ChromeWinHttpSettings
        WinHTTP读取当前用户代理 = Get-ChromeWinHttpSettings -CurrentUser
        程序版本 = @(Get-ChromeBinaryVersions)
        官方位置日志尾部 = @(Get-ChromeLogRecords)
    }
    $encoding = New-Object Text.UTF8Encoding($true)
    $json = $report | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText((Join-Path $output 'diagnostics.json'), $json, $encoding)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('FengWo / Chrome 安装更新诊断报告')
    $lines.Add('采集时间UTC：' + $report['采集时间UTC'])
    $lines.Add('注册表 AutoDetect 缺失不等于关闭，以 WinHTTP 读取当前用户代理中的结果辅助核对。')
    $lines.Add('服务停止不一定是故障：按需启动的服务可能正常处于停止状态。')
    foreach ($section in @('系统信息', '相关服务', '当前用户代理注册表', 'WinHTTP系统默认代理', 'WinHTTP读取当前用户代理', '程序版本', '官方位置日志尾部')) {
        $lines.Add('')
        $lines.Add('========== ' + $section + ' ==========')
        $lines.Add(($report[$section] | ConvertTo-Json -Depth 12))
    }
    [IO.File]::WriteAllLines((Join-Path $output 'diagnostics.txt'), $lines, $encoding)
    $readme = @'
Chrome 安装与更新诊断结果

请将本目录的 diagnostics.json 和 diagnostics.txt 提供给客服，注明出现错误的时间，以及当时使用系统代理、虚拟网卡还是两者同时开启。

本工具只读取本机信息，不修改代理、证书、服务或注册表，不提权，不结束进程，不联网。文件不存在或权限不足会保留状态，其他项目继续采集。

日志限于 GoogleUpdater 官方目录、当前用户 TEMP/TMP、Windows Temp/SystemTemp 下的 updater.log 和 chrome_installer.log。每份最多读取末尾 128 KiB、保留 250 行；不扫描浏览器资料或其他用户目录。报告会移除用户路径、邮箱、链接凭证/查询参数以及常见认证字段。日志属于自由文本，发送前请再快速确认是否有不希望分享的内容。

服务停止不一定意味着故障。当前报告仅用于定位原因，不代表已修复。WinHTTP 系统默认代理与当前用户代理可能不同，需结合 Chrome 更新器日志判断实际采用哪一项。

官方位置依据：
https://chromium.googlesource.com/chromium/src/+/HEAD/docs/updater/functional_spec.md
https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/installer/util/logging_installer.cc
'@
    [IO.File]::WriteAllText((Join-Path $output '说明.txt'), $readme, $encoding)
    Write-Host '采集完成。请将下列目录中的报告发给客服：'
    Write-Host $output
    return $output
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-FengWoChromeDiagnostics -OutputParent $OutputParent | Out-Null }
