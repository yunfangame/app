param(
    [ValidateSet('Menu', 'Collect', 'Watch', 'Trace', 'Guided', 'Repair')][string]$Mode = 'Menu',
    [ValidateRange(1, 65535)][int]$Port = 17980,
    [string]$OutputDirectory = '',
    [switch]$SkipNetwork,
    [ValidateRange(5, 180)][int]$ObserveSeconds = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows PowerShell 5.1 or later on Windows is required.' }
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
Import-Module (Join-Path $PSScriptRoot 'ProxyDiagnostics.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ProxyWriterTrace.psm1') -Force
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $env:LOCALAPPDATA 'FengWoProxyDiagnostics' }
$runDirectory = Join-Path $OutputDirectory $runId
$publicDirectory = Join-Path $runDirectory 'report'
$null = [IO.Directory]::CreateDirectory($publicDirectory)
$encoding = New-Object Text.UTF8Encoding($false)
$originalTls = [Net.ServicePointManager]::SecurityProtocol
$trace = $null
$liveProcesses = @{}
$report = [ordered]@{
    toolVersion = '1.0.0'; runId = $runId; startedUtc = [DateTime]::UtcNow.ToString('o')
    osVersion = [Environment]::OSVersion.Version.ToString(); powershellVersion = $PSVersionTable.PSVersion.ToString()
    processArchitecture = $env:PROCESSOR_ARCHITECTURE; is64BitProcess = [Environment]::Is64BitProcess
    mode = ''; port = $Port; proxyConfigurationWrittenByTool = $false; tunOrRoutesModified = $false
    repair = $null; phases = @(); fatalError = $null; environment = $null; writerTrace = $null; observationSamples = 0; disableTransitions = @()
    limitations = @('Refresh does not prove the client is fixed.', 'No explicit HTTP proxy is not a TUN bypass.', 'HTTP responses do not prove every application uses a proxy.', 'Private backup is excluded from the report ZIP.')
}

function Save-Report {
    [IO.File]::WriteAllText((Join-Path $publicDirectory 'report.json'), (ConvertTo-Json -InputObject $report -Depth 24), $encoding)
}

function Add-Event {
    param([string]$Name, $Fields)
    $row = [ordered]@{ atUtc = [DateTime]::UtcNow.ToString('o'); event = $Name; fields = $Fields }
    [IO.File]::AppendAllText((Join-Path $publicDirectory 'events.jsonl'), (ConvertTo-Json -InputObject $row -Depth 24 -Compress) + "`n", $encoding)
}

function Get-NetworkChecks {
    if ($SkipNetwork) { return @() }
    $items = @()
    foreach ($target in @('domestic', 'public')) {
        foreach ($direct in @($true, $false)) {
            $items += [FengWoProxyDiagnostics.Native]::Probe($target, $direct)
        }
    }
    return $items
}

function Add-Phase {
    param([string]$Phase, $Baseline)
    $snapshot = Get-FwProxySnapshot
    $assessment = Get-FwPhaseAssessment $Phase $snapshot $Baseline $Port
    $public = ConvertTo-FwPublicSnapshot $snapshot $Port
    $entry = [ordered]@{ phase = $Phase; assessment = $assessment; snapshot = $public; network = @(Get-NetworkChecks) }
    $report.phases += $entry
    Add-Event 'phase.completed' $entry
    Save-Report
    Write-Host ('结果 / Result: ' + $Phase + ' = ' + $assessment.passed)
    return $snapshot
}

function Save-LiveProcessIdentities {
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            $key = [string]$process.Id
            $value = [ordered]@{ name = $process.ProcessName + '.exe'; observedUtc = $process.StartTime.ToUniversalTime(); source = 'process_snapshot' }
            if (-not $liveProcesses.ContainsKey($key)) { $liveProcesses[$key] = @() }
            if (@($liveProcesses[$key] | Where-Object { $_.observedUtc -eq $value.observedUtc }).Count -eq 0) { $liveProcesses[$key] += $value }
        } catch {}
    }
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host '蜂窝 Windows 系统代理诊断工具'
    Write-Host '请使用运行蜂窝的同一个 Windows 用户。无需卸载、覆盖安装或提供账号密码。'
    Write-Host '工具不会删除 PAC、修改组策略、重置网络或关闭其他软件。'
    if ($Mode -eq 'Menu') {
        Write-Host '1. 只读检测（默认）'
        Write-Host '2. 监控开关变化 45 秒（只读，不定位写入进程）'
        Write-Host '3. 引导测试：连接、断开、托盘退出'
        Write-Host '4. 刷新修复：需先退出代理客户端；不改代理地址/PAC'
        Write-Host '5. 追踪谁修改代理（需同用户管理员授权）'
        $choice = Read-Host '输入 1/2/3/4/5，直接回车为只读检测'
        $Mode = switch ($choice) { '2' { 'Watch' }; '3' { 'Guided' }; '4' { 'Repair' }; '5' { 'Trace' }; default { 'Collect' } }
    }
    $report.mode = $Mode
    Initialize-FwProxyNative
    $report.environment = Get-FwEnvironmentEvidence
    if ($Mode -in @('Watch', 'Trace')) {
        if ($Mode -eq 'Trace') {
            Write-Host '会临时采集注册表写入/进程事件，最多 45 秒；报告仅导出代理项的写入进程，不导出原始 ETL。'
            Write-Host '原始事件在本机私有目录中采集，结束后加密；不修改审核策略或代理设置。'
            $traceConsent = Read-Host '确认同意临时追踪请输入 TRACE；其他输入改为普通状态监控'
            if ($traceConsent -ceq 'TRACE') {
                $trace = Start-FwProxyWriterTrace (Join-Path $runDirectory 'private') $ObserveSeconds
                $report.writerTrace = [ordered]@{ status = 'started'; maximumSeconds = $trace.maximumSeconds }
            } else { $report.writerTrace = [ordered]@{ status = 'consent_not_given' } }
        }
        Write-Host ('监控开始，持续 ' + $ObserveSeconds + ' 秒。现在可到 Windows 网络设置中打开手动代理，等待它自动关闭。')
        Write-Host '请不要连续重试，不要在这次监控中切换网线/热点；换网络后另跑一份报告。'
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $samples = New-Object 'Collections.Generic.List[object]'
        do {
            Save-LiveProcessIdentities
            $snapshot = Get-FwProxySnapshot -RegistryOnly
            $public = ConvertTo-FwPublicSnapshot $snapshot $Port
            $samples.Add($public)
            Add-Event 'observation.snapshot' $public
            $report.observationSamples++
            Start-Sleep -Milliseconds 700
        } while ($watch.Elapsed.TotalSeconds -lt $ObserveSeconds)
        if ($null -ne $trace) {
            $report.writerTrace = Complete-FwProxyWriterTrace $trace $liveProcesses
            $trace = $null
            Add-Event 'writer_trace.completed' $report.writerTrace
        }
        $writers = if ($null -ne $report.writerTrace -and $report.writerTrace.Contains('writers')) { @($report.writerTrace.writers) } else { @() }
        $report.disableTransitions = @(Get-FwDisableTransitions @($samples.ToArray()) $writers)
        Add-Event 'observation.disabled_transitions' $report.disableTransitions
        $report.monitorPerformedWininetQueries = $false
        $report.monitorPerformedNetworkProbes = $false
        Write-Host ('捕获的代理关闭次数：' + $report.disableTransitions.Count)
    } elseif ($Mode -eq 'Guided') {
        Write-Host '先在蜂窝中断开连接；记录当前 TUN 状态，不要为检测而改动 TUN 或其他代理软件。'
        $null = Read-Host '完成后按回车，记录初始状态'
        $baseline = Add-Phase 'before' $null
        if (-not $report.phases[0].assessment.passed) {
            Write-Host '初始代理状态不一致或仍指向蜂窝，本次只收集证据，不能判定恢复成功。'
        }
        $null = Read-Host '点击蜂窝连接按钮；若弹出错误，不要连续重试。保持现场后按回车'
        $null = Add-Phase 'connected' $baseline
        $null = Read-Host '点击蜂窝断开连接，等待界面稳定后按回车'
        $null = Add-Phase 'disconnected' $baseline
        $null = Read-Host '重新连接一次，再从托盘菜单选择退出；不要只点窗口 X。退出后按回车'
        $null = Add-Phase 'exited' $baseline
        Write-Host '测试结果会分别记录。未看到“已连接”或能打开网站，不代表所有应用均经过代理。'
    } elseif ($Mode -eq 'Repair') {
        Write-Host '请先完全退出蜂窝和其他代理客户端；不要修改公司代理策略。'
        Write-Host '本步骤只刷新 Windows 代理缓存/通知，不重写任何代理地址或 PAC。'
        $consent = Read-Host '确认后输入 REFRESH；其他输入只做检测'
        $backup = Join-Path $runDirectory 'private-backup.dpapi'
        $backupAction = { param($Snapshot) Save-FwEncryptedBackup $Snapshot $backup }.GetNewClosure()
        $report.repair = Invoke-FwRefreshRepair -Consent ($consent -ceq 'REFRESH') -Backup $backupAction
        Add-Event 'repair.completed' $report.repair
        Write-Host ('刷新结果 / Refresh: ' + $report.repair.status)
        Write-Host '刷新完成不等于故障已修复。请重新打开工具，选择 3，做完整连接/断开/退出测试。'
        $null = Add-Phase 'before' $null
    } else {
        $null = Add-Phase 'before' $null
    }
} catch {
    $report.fatalError = [ordered]@{ type = $_.Exception.GetType().Name; hresult = $_.Exception.HResult }
    Add-Event 'collection.failed' $report.fatalError
    Write-Host '部分检测未完成。错误码已保存，不会执行网络重置或强制覆盖代理。'
} finally {
    if ($null -ne $trace) {
        try { $report.writerTrace = Complete-FwProxyWriterTrace $trace $liveProcesses }
        catch { $report.writerTrace = [ordered]@{ status = 'trace_completion_failed'; errorType = $_.Exception.GetType().Name } }
    }
    [Net.ServicePointManager]::SecurityProtocol = $originalTls
    $report.completedUtc = [DateTime]::UtcNow.ToString('o')
    Save-Report
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $runDirectory ('FengWo-Proxy-Report-' + $runId + '.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($publicDirectory, $zip)
    Write-Host ('请将这个日志 ZIP 发给客服：' + $zip)
    Write-Host '不要发送 private-backup.dpapi；备份仅供本 Windows 用户本机恢复分析。'
}
if ($null -ne $report.fatalError) { exit 1 }
exit 0
