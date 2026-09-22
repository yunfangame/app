param(
    [string]$TargetsFile = '',
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This collector requires Windows PowerShell 5.1 or later on Windows.'
}

$clock = [Diagnostics.Stopwatch]::StartNew()
$totalSeconds = 105
$errors = [Collections.Generic.List[string]]::new()
$conclusions = [Collections.Generic.List[string]]::new()
$originalTls = [Net.ServicePointManager]::SecurityProtocol
$report = [ordered]@{
    collector_version = 1
    collected_at = (Get-Date).ToString('o')
    time_zone = [TimeZoneInfo]::Local.Id
    windows_version = [Environment]::OSVersion.Version.ToString()
    powershell_version = $PSVersionTable.PSVersion.ToString()
    process_is_64_bit = [Environment]::Is64BitProcess
    total_budget_seconds = $totalSeconds
    connection_mode = '直连；无认证；不跟随重定向；不保存响应正文'
    dotnet_tls = 'TLS 1.2；仅本诊断进程，结束后恢复'
    dotnet_original_tls = $originalTls.ToString()
    curl = $null
    root_certificates = @()
    root_update_policy = @()
    processes = @()
    endpoints = @()
    conclusions = @()
    collection_errors = @()
    elapsed_seconds = 0
}

function Get-RemainingSeconds {
    return [Math]::Max(0, [Math]::Floor($totalSeconds - $clock.Elapsed.TotalSeconds))
}

function Get-ShortError {
    param([Exception]$Exception)
    $messages = [Collections.Generic.List[string]]::new()
    $current = $Exception
    for ($i = 0; $i -lt 4 -and $null -ne $current; $i++) {
        $entry = $current.GetType().Name + ' [0x' + $current.HResult.ToString('X8') + ']'
        if ($current -is [ComponentModel.Win32Exception]) { $entry += ' NativeError=' + $current.NativeErrorCode }
        $message = ($current.Message -replace '[\r\n]+', ' ')
        if ($message.Length -gt 240) { $message = $message.Substring(0, 240) }
        $messages.Add($entry + ': ' + $message)
        $current = $current.InnerException
    }
    return ($messages -join ' -> ')
}

function Invoke-Curl {
    param([string]$Path, [string[]]$Arguments, [int]$WaitSeconds)
    $start = [Diagnostics.Stopwatch]::StartNew()
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $Path
    $process.StartInfo.Arguments = (($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $finished = $process.WaitForExit($WaitSeconds * 1000)
        if (-not $finished) {
            return [pscustomobject]@{ exit_code = $null; timed_out = $true; stdout = ''; stderr = ''; elapsed_seconds = [Math]::Round($start.Elapsed.TotalSeconds, 2) }
        }
        return [pscustomobject]@{ exit_code = $process.ExitCode; timed_out = $false; stdout = $stdout.GetAwaiter().GetResult(); stderr = $stderr.GetAwaiter().GetResult(); elapsed_seconds = [Math]::Round($start.Elapsed.TotalSeconds, 2) }
    } finally {
        $process.Dispose()
    }
}

function Test-CurlEndpoint {
    param([string]$Url, [string]$CurlPath, [bool]$HasSchannel)
    if (-not $HasSchannel) {
        return [pscustomobject]@{ status = 'unavailable'; tls_succeeded = $null; http_status = $null; detail = 'Windows 自带 curl 缺失、未使用 Schannel 或版本低于 7.77；未发起 curl 请求。' }
    }
    $seconds = [Math]::Min(6, (Get-RemainingSeconds) - 1)
    if ($seconds -lt 1) {
        return [pscustomobject]@{ status = 'budget_exhausted'; tls_succeeded = $null; http_status = $null; detail = '达到总时间预算，未执行。' }
    }
    try {
        $result = Invoke-Curl -Path $CurlPath -WaitSeconds ($seconds + 1) -Arguments @(
            '--disable', '--silent', '--show-error', '--verbose', '--noproxy', '*',
            '--globoff', '--no-ssl-auto-client-cert',
            '--proto', '=https', '--connect-timeout', '4', '--max-time', "$seconds",
            '--max-filesize', '1048576', '--output', 'NUL',
            '--write-out', 'HTTP_STATUS:%{http_code}\nVERIFY_RESULT:%{ssl_verify_result}\n',
            '--url', $Url
        )
        $httpStatus = 0
        if ($result.stdout -match 'HTTP_STATUS:(\d{3})') { $httpStatus = [int]$Matches[1] }
        $tlsLines = @($result.stderr -split '\r?\n' | Where-Object {
            $_ -match '^\*.*(?i:schannel|ssl|tls|certificate|connect|resolve|timed out)' -or $_ -match '^curl: \(\d+\)'
        } | Select-Object -First 20)
        $detail = ($tlsLines -join [Environment]::NewLine)
        if ($detail.Length -gt 2400) { $detail = $detail.Substring(0, 2400) }
        return [pscustomobject]@{
            status = $(if ($httpStatus -gt 0) { 'http_response' } elseif ($result.timed_out) { 'timeout' } else { 'failed' })
            tls_succeeded = ($httpStatus -gt 0)
            http_status = $httpStatus
            exit_code = $result.exit_code
            elapsed_seconds = $result.elapsed_seconds
            detail = $detail
        }
    } catch {
        return [pscustomobject]@{ status = 'failed'; tls_succeeded = $null; http_status = $null; detail = (Get-ShortError $_.Exception) }
    }
}

function Test-DotNetEndpoint {
    param([string]$Url)
    $seconds = [Math]::Min(6, (Get-RemainingSeconds))
    if ($seconds -lt 1) {
        return [pscustomobject]@{ status = 'budget_exhausted'; tls_succeeded = $null; http_status = $null; detail = '达到总时间预算，未执行。' }
    }
    $start = [Diagnostics.Stopwatch]::StartNew()
    $request = $null
    $response = $null
    $pending = $null
    try {
        $request = [Net.HttpWebRequest]::Create($Url)
        $request.Method = 'GET'
        $request.Proxy = $null
        $request.Credentials = $null
        $request.UseDefaultCredentials = $false
        $request.AllowAutoRedirect = $false
        $request.KeepAlive = $false
        $request.Timeout = $seconds * 1000
        $request.ReadWriteTimeout = $seconds * 1000
        $request.UserAgent = 'FengWo-TLS-Diagnostics/1'
        $pending = $request.BeginGetResponse($null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($seconds * 1000)) {
            return [pscustomobject]@{ status = 'timeout'; tls_succeeded = $false; http_status = $null; elapsed_seconds = [Math]::Round($start.Elapsed.TotalSeconds, 2); detail = '连接或 TLS 检测超时。' }
        }
        try {
            $response = $request.EndGetResponse($pending)
        } catch [Net.WebException] {
            if ($null -ne $_.Exception.Response) {
                $response = $_.Exception.Response
            } else {
                return [pscustomobject]@{ status = $_.Exception.Status.ToString(); tls_succeeded = $false; http_status = $null; elapsed_seconds = [Math]::Round($start.Elapsed.TotalSeconds, 2); detail = (Get-ShortError $_.Exception) }
            }
        }
        return [pscustomobject]@{ status = 'http_response'; tls_succeeded = $true; http_status = [int]$response.StatusCode; elapsed_seconds = [Math]::Round($start.Elapsed.TotalSeconds, 2); detail = '已完成系统证书验证并收到 HTTP 响应；未读取响应正文。' }
    } catch {
        return [pscustomobject]@{ status = 'failed'; tls_succeeded = $false; http_status = $null; elapsed_seconds = [Math]::Round($start.Elapsed.TotalSeconds, 2); detail = (Get-ShortError $_.Exception) }
    } finally {
        if ($null -ne $request) { $request.Abort() }
        if ($null -ne $response) { $response.Close() }
        if ($null -ne $pending) { $pending.AsyncWaitHandle.Close() }
    }
}

function Get-PublicRoots {
    $names = @('Certum Trusted Network CA', 'ISRG Root X1', 'GlobalSign Root CA', 'ISRG Root X2', 'DigiCert Global Root CA', 'DigiCert Global Root G2', 'GlobalSign Root CA - R3', 'USERTrust RSA Certification Authority', 'GTS Root R1', 'Amazon Root CA 1')
    $expectedThumbprints = @{
        'Certum Trusted Network CA' = '07E032E020B72C3F192F0628A2593A19A70F069E'
        'ISRG Root X1' = 'CABD2A79A1076A31F21D253635CB039D4329A5E8'
    }
    $found = [Collections.Generic.List[object]]::new()
    foreach ($location in @('CurrentUser', 'LocalMachine')) {
        foreach ($storeName in @('Root', 'Disallowed')) {
            $store = [Security.Cryptography.X509Certificates.X509Store]::new($storeName, $location)
            try {
                $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly -bor [Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly)
                foreach ($certificate in $store.Certificates) {
                    $name = $certificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
                    if ($names -contains $name) {
                        $found.Add([pscustomobject]@{
                            name = $name
                            store = "$location\$storeName"
                            thumbprint = $certificate.Thumbprint
                            expected_fingerprint_matches = $(if ($expectedThumbprints.ContainsKey($name)) { $certificate.Thumbprint -eq $expectedThumbprints[$name] } else { $null })
                            not_before = $certificate.NotBefore.ToString('o')
                            not_after = $certificate.NotAfter.ToString('o')
                            valid_at_local_time = ((Get-Date) -ge $certificate.NotBefore -and (Get-Date) -le $certificate.NotAfter)
                            disallowed = ($storeName -eq 'Disallowed')
                        })
                    }
                }
            } catch {
                $errors.Add("公共根证书存储 $location\${storeName} 无法读取：$(Get-ShortError $_.Exception)")
            } finally {
                $store.Close()
            }
        }
    }
    foreach ($name in $names) {
        $matchesForName = @($found | Where-Object { $_.name -eq $name })
        $matchingCertificates = @($matchesForName | Where-Object { $_.expected_fingerprint_matches -ne $false })
        [pscustomobject]@{
            name = $name
            expected_thumbprint = $expectedThumbprints[$name]
            present_in_root = (@($matchingCertificates | Where-Object { -not $_.disallowed }).Count -gt 0)
            present_in_disallowed = (@($matchingCertificates | Where-Object { $_.disallowed }).Count -gt 0)
            certificates = $matchesForName
        }
    }
}

function Get-RootUpdatePolicy {
    foreach ($hive in @('HKLM', 'HKCU')) {
        $path = "${hive}:\SOFTWARE\Policies\Microsoft\SystemCertificates\AuthRoot"
        $value = $null
        $state = 'not_configured'
        try {
            if (Test-Path -LiteralPath $path) {
                $item = Get-ItemProperty -LiteralPath $path -Name 'DisableRootAutoUpdate' -ErrorAction SilentlyContinue
                if ($null -ne $item -and $null -ne $item.DisableRootAutoUpdate) {
                    $value = [int]$item.DisableRootAutoUpdate
                    $state = $(if ($value -eq 1) { 'disabled' } else { 'not_disabled_by_this_policy' })
                }
            }
        } catch {
            $state = 'unavailable'
        }
        [pscustomobject]@{ scope = $hive; policy = 'DisableRootAutoUpdate'; value = $value; state = $state }
    }
}

function Get-ExeHash {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\') { return '未计算：路径不可用或不是本地磁盘。' }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($Path))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) { return '未计算：仅读取本地固定磁盘。' }
    $stream = $null
    $hash = $null
    $started = [Diagnostics.Stopwatch]::StartNew()
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        if ($stream.Length -gt 536870912) { return '未计算：文件超过 512 MiB。' }
        $hash = [Security.Cryptography.SHA256]::Create()
        $buffer = New-Object byte[] 131072
        while (($count = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($started.Elapsed.TotalSeconds -gt 3 -or (Get-RemainingSeconds) -lt 1) { return '未计算：达到哈希读取时间预算。' }
            $null = $hash.TransformBlock($buffer, 0, $count, $buffer, 0)
        }
        $null = $hash.TransformFinalBlock([byte[]]@(), 0, 0)
        return ([BitConverter]::ToString($hash.Hash)).Replace('-', '').ToLowerInvariant()
    } catch {
        return ('未计算：' + (Get-ShortError $_.Exception))
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $hash) { $hash.Dispose() }
    }
}

Write-Host '正在只读检查蜂窝 Windows TLS，通常在两分钟内结束。请保持客户端原状。'
$targets = @('https://house.zryc.tech/ConFigOss4.json', 'https://zryc.oss-cn-beijing.aliyuncs.com/ConFigOss4.json')
if (-not [string]::IsNullOrWhiteSpace($TargetsFile)) {
    try {
        $fullTargetsPath = [IO.Path]::GetFullPath($TargetsFile)
        if ($fullTargetsPath -match '(?i)(^|[\\/])(?:\.private|\.env)(?:[\\/.]|$)' -or [IO.Path]::GetExtension($fullTargetsPath) -ne '.json') {
            throw 'TargetsFile must be a public URL JSON array outside private directories.'
        }
        $file = Get-Item -LiteralPath $fullTargetsPath
        if ($file.Length -gt 16384) { throw 'TargetsFile exceeds 16 KiB.' }
        $content = [IO.File]::ReadAllText($file.FullName)
        if (-not $content.TrimStart().StartsWith('[')) { throw 'TargetsFile must contain a JSON array.' }
        $parsedTargets = @($content | ConvertFrom-Json)
        if ($parsedTargets.Count -lt 1 -or $parsedTargets.Count -gt 8) { throw 'TargetsFile must contain 1 to 8 URLs.' }
        $validatedTargets = @()
        foreach ($target in $parsedTargets) {
            if ($target -isnot [string]) { throw 'Each target must be a URL string.' }
            $uri = [Uri]::new($target, [UriKind]::Absolute)
            if ($uri.Scheme -ne 'https' -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
                throw 'Only HTTPS URLs without credentials, queries or fragments are accepted.'
            }
            $validatedTargets += $uri.AbsoluteUri
        }
        $targets = @($validatedTargets | Select-Object -Unique)
    } catch {
        $errors.Add('端点文件校验失败，已仅检查两个默认公开配置地址；未在报告中记录文件内容。')
    }
}

$report.root_certificates = @(Get-PublicRoots)
$report.root_update_policy = @(Get-RootUpdatePolicy)
$hashes = @{}
foreach ($client in @(Get-Process -Name 'FengWo', 'fengwoacc' -ErrorAction SilentlyContinue | Select-Object -First 8)) {
    $processInfo = [ordered]@{ name = $client.ProcessName; pid = $client.Id; path = $null; started_at = $null; file_version = $null; product_version = $null; exe_sha256 = $null; status = 'available' }
    try {
        $processInfo.path = $client.Path
        $processInfo.started_at = $client.StartTime.ToString('o')
        if (-not [string]::IsNullOrWhiteSpace($processInfo.path)) {
            $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($processInfo.path)
            $processInfo.file_version = $version.FileVersion
            $processInfo.product_version = $version.ProductVersion
            if (-not $hashes.ContainsKey($processInfo.path)) { $hashes[$processInfo.path] = Get-ExeHash $processInfo.path }
            $processInfo.exe_sha256 = $hashes[$processInfo.path]
        }
    } catch {
        $processInfo.status = 'partial: ' + (Get-ShortError $_.Exception)
    }
    $report.processes += [pscustomobject]$processInfo
}

$curlPath = Join-Path $env:SystemRoot 'System32\curl.exe'
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    $curlPath = Join-Path $env:SystemRoot 'Sysnative\curl.exe'
}
$hasSchannel = $false
$supportsNoClientCert = $false
try {
    if (Test-Path -LiteralPath $curlPath) {
        $curlVersion = Invoke-Curl -Path $curlPath -Arguments @('--disable', '--version') -WaitSeconds 3
        $firstLine = ($curlVersion.stdout -split '\r?\n' | Select-Object -First 1)
        $hasSchannel = ($curlVersion.exit_code -eq 0 -and $firstLine -match '(?i)Schannel')
        if ($firstLine -match '^curl (\d+\.\d+\.\d+)') { $supportsNoClientCert = ([Version]$Matches[1] -ge [Version]'7.77.0') }
        $report.curl = [ordered]@{ path = $curlPath; version = $firstLine; schannel = $hasSchannel; supports_no_client_certificate = $supportsNoClientCert }
    } else {
        $report.curl = [ordered]@{ path = $curlPath; version = $null; schannel = $false }
    }
} catch {
    $errors.Add('Windows 自带 curl 无法运行：' + (Get-ShortError $_.Exception))
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($target in $targets) {
        Write-Host ('检查：' + $target)
        $curlResult = Test-CurlEndpoint -Url $target -CurlPath $curlPath -HasSchannel ($hasSchannel -and $supportsNoClientCert)
        $dotnetResult = Test-DotNetEndpoint -Url $target
        $endpointConclusion = '两种检测均未确认 TLS 成功；需结合错误码区分证书、DNS、网络或超时。'
        if ($curlResult.tls_succeeded -eq $true -and $dotnetResult.tls_succeeded -eq $true) {
            $endpointConclusion = 'curl Schannel 与 .NET 均已完成 TLS；此路径的系统证书验证正常。'
        } elseif ($curlResult.tls_succeeded -eq $true -or $dotnetResult.tls_succeeded -eq $true) {
            $endpointConclusion = '至少一种检测已完成 TLS，但两种结果不同；需要核对各自错误码和客户端 TLS 实现。'
        }
        $report.endpoints += [pscustomobject]@{ url = $target; curl_schannel = $curlResult; dotnet_tls12 = $dotnetResult; conclusion = $endpointConclusion }
    }
} catch {
    $errors.Add('网络检测未全部完成：' + (Get-ShortError $_.Exception))
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $originalTls
}

$conclusions.Add('这是当前时间、当前用户、直连路径的检测结果；不代替客户端登录或代理路径测试。401、403、404 等 HTTP 响应仍代表 TLS 已成功。')
if ($report.processes.Count -eq 0) { $conclusions.Add('未找到运行中的 FengWo/fengwoacc，无法确认客户实际启动的程序路径、版本和 SHA-256。') }
if (@($report.root_update_policy | Where-Object { $_.state -eq 'disabled' }).Count -gt 0) {
    $conclusions.Add('检测到禁止自动根证书更新的策略；这可能影响公共 CA 信任链更新，请结合实际 TLS 错误判断。')
}
$conclusions.Add('指定公共根证书未出现在本地 Root 存储不等于证书链必然失败；Windows 可能按需获取受信任根。出现 Disallowed 记录需要进一步核对。')
$conclusions.Add('请核对报告时间是否正确。脚本未修改证书、系统代理或系统安全设置，未停止客户端，未读取登录密码或会话，未上传数据。')
$report.conclusions = @($conclusions.ToArray())
$report.collection_errors = @($errors.ToArray())
$report.elapsed_seconds = [Math]::Round($clock.Elapsed.TotalSeconds, 2)

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = [Environment]::GetFolderPath('Desktop') }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = [IO.Path]::GetTempPath() }
try {
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
} catch {
    $OutputDirectory = [IO.Path]::GetTempPath()
}
$baseName = 'FengWo-TLS-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
$jsonPath = Join-Path $OutputDirectory ($baseName + '.json')
$textPath = Join-Path $OutputDirectory ($baseName + '.txt')
$utf8 = [Text.UTF8Encoding]::new($true)
[IO.File]::WriteAllText($jsonPath, ($report | ConvertTo-Json -Depth 12), $utf8)
$lines = [Collections.Generic.List[string]]::new()
$lines.Add('蜂窝 Windows TLS 只读诊断报告')
$lines.Add('时间：' + $report.collected_at + '；时区：' + $report.time_zone)
$lines.Add('耗时：' + $report.elapsed_seconds + ' 秒；Windows：' + $report.windows_version + '；PowerShell：' + $report.powershell_version)
$lines.Add('连接方式：' + $report.connection_mode)
$lines.Add('.NET 模式：' + $report.dotnet_tls + '；原模式：' + $report.dotnet_original_tls)
$lines.Add('')
foreach ($conclusion in $report.conclusions) { $lines.Add('• ' + $conclusion) }
$lines.Add('')
$lines.Add('各端点检测')
foreach ($endpoint in $report.endpoints) {
    $lines.Add($endpoint.url)
    $lines.Add('  结论：' + $endpoint.conclusion)
    foreach ($mode in @('curl_schannel', 'dotnet_tls12')) {
        $result = $endpoint.$mode
        $lines.Add('  ' + $mode + '：' + $result.status + '；HTTP=' + $result.http_status + '；TLS成功=' + $result.tls_succeeded)
        $lines.Add('  ' + $result.detail)
    }
}
$lines.Add('')
$lines.Add('公共根证书（只核对指定公共 CA，未读取个人证书存储）')
foreach ($root in $report.root_certificates) {
    $lines.Add($root.name + '：Root存在=' + $root.present_in_root + '；Disallowed存在=' + $root.present_in_disallowed)
    if ($null -ne $root.expected_thumbprint) { $lines.Add('  官方根预期指纹：' + $root.expected_thumbprint) }
    foreach ($certificate in $root.certificates) {
        $lines.Add('  ' + $certificate.store + '；指纹=' + $certificate.thumbprint + '；匹配官方指纹=' + $certificate.expected_fingerprint_matches + '；当前有效=' + $certificate.valid_at_local_time + '；到期=' + $certificate.not_after)
    }
}
foreach ($policy in $report.root_update_policy) { $lines.Add($policy.scope + ' DisableRootAutoUpdate=' + $policy.value + '；状态=' + $policy.state) }
$lines.Add('')
$lines.Add('客户端进程')
foreach ($client in $report.processes) {
    $lines.Add($client.name + ' PID=' + $client.pid + '；启动=' + $client.started_at)
    $lines.Add('  路径：' + $client.path)
    $lines.Add('  文件版本：' + $client.file_version + '；产品版本：' + $client.product_version)
    $lines.Add('  SHA-256：' + $client.exe_sha256 + '；状态：' + $client.status)
}
if ($errors.Count -gt 0) {
    $lines.Add('')
    $lines.Add('采集限制')
    foreach ($item in $errors) { $lines.Add($item) }
}
[IO.File]::WriteAllLines($textPath, $lines.ToArray(), $utf8)
Write-Host ''
Write-Host '完成。请将以下 TXT 和 JSON 两个报告文件交给支持人员：'
Write-Host $textPath
Write-Host $jsonPath
