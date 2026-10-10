[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$InspectOnly,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$report = [ordered]@{
    SchemaVersion = 1
    StartedAt = (Get-Date).ToString('o')
    FinishedAt = $null
    InspectOnly = [bool]$InspectOnly
    Status = 'pending'
    Before = $null
    Attempts = @()
    After = $null
    Observations = @()
    Verification = @()
    Errors = @()
}
$exitCode = 0
$outputPath = $null
$utf8 = New-Object System.Text.UTF8Encoding($true)

function Test-WindowOnPrimary($window, $monitor) {
    if ($null -eq $window -or $null -eq $monitor -or $null -eq $window.Rect) { return $false }
    $rect = $window.Rect
    $work = $monitor.WorkArea
    return ($window.Visible -and -not $window.Minimized -and -not $window.Hung -and
        $window.DwmCloaked -eq $false -and
        $rect.Right -gt $rect.Left -and $rect.Bottom -gt $rect.Top -and
        $rect.Left -ge $work.Left -and $rect.Top -ge $work.Top -and
        $rect.Right -le $work.Right -and $rect.Bottom -le $work.Bottom)
}

try {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $base = [Environment]::GetFolderPath('Desktop')
        if ([string]::IsNullOrWhiteSpace($base)) { $base = [IO.Path]::GetTempPath() }
        $OutputDirectory = Join-Path $base ('FengWo-Window-Report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
    }
    try {
        $outputPath = [IO.Directory]::CreateDirectory($OutputDirectory).FullName
    } catch {
        $outputPath = [IO.Directory]::CreateDirectory((Join-Path ([IO.Path]::GetTempPath()) ('FengWo-Window-Report-' + [Guid]::NewGuid().ToString('N')))).FullName
        $report.Errors += 'Requested output folder unavailable; using temporary folder.'
    }
    Write-Host '正在检查蜂窝窗口和显示器……' -ForegroundColor Cyan
    Add-Type -Path (Join-Path $PSScriptRoot 'window_recovery_native.cs')
    $report.Before = [FengWoWindowRecovery.NativeProbe]::Capture()
    $report.After = $report.Before
    $windows = @($report.Before.Windows)
    if ($InspectOnly) {
        $report.Status = 'inspection_only'
    } elseif (-not $report.Before.Dpi.Applied) {
        $report.Status = 'dpi_context_unavailable'
    } elseif ($windows.Count -eq 0) {
        $report.Status = 'no_matching_window'
    } elseif (@($report.Before.Monitors | Where-Object { $_.Primary }).Count -eq 0) {
        $report.Status = 'primary_monitor_unavailable'
    } else {
        Write-Host '正在将现有蜂窝窗口移回主屏；不会结束进程……' -ForegroundColor Cyan
        foreach ($window in $windows) {
            $report.Attempts += [FengWoWindowRecovery.NativeProbe]::Recover($window.ProcessId, $window.Handle)
        }
        for ($sample = 0; $sample -lt 10; $sample++) {
            Start-Sleep -Milliseconds 500
            $snapshot = [FengWoWindowRecovery.NativeProbe]::Capture()
            $report.After = $snapshot
            $report.Observations += [ordered]@{ CapturedAt = (Get-Date).ToString('o'); Snapshot = $snapshot }
        }
        $primary = @($report.After.Monitors | Where-Object { $_.Primary } | Select-Object -First 1)
        foreach ($target in $windows) {
            $afterWindow = @($report.After.Windows | Where-Object { $_.Handle -eq $target.Handle -and $_.ProcessId -eq $target.ProcessId } | Select-Object -First 1)
            $onPrimary = $false
            if ($report.After.Dpi.Applied -and $primary.Count -eq 1 -and $afterWindow.Count -eq 1) {
                $onPrimary = Test-WindowOnPrimary $afterWindow[0] $primary[0]
            }
            $report.Verification += [ordered]@{
                ProcessId = $target.ProcessId
                Handle = $target.Handle
                PresentAfter = ($afterWindow.Count -eq 1)
                ResponsiveUncloakedWindowOnPrimary = [bool]$onPrimary
            }
        }
        $failed = @($report.Verification | Where-Object { -not $_.ResponsiveUncloakedWindowOnPrimary })
        if ($failed.Count -eq 0) { $report.Status = 'window_on_primary' }
        else { $report.Status = 'window_recovery_unconfirmed' }
    }
} catch {
    $report.Status = 'tool_error'
    $report.Errors += $_.Exception.Message
    $exitCode = 2
} finally {
    $report.FinishedAt = (Get-Date).ToString('o')
    if ($outputPath) {
        try {
            [IO.File]::WriteAllText((Join-Path $outputPath 'window-report.json'), ($report | ConvertTo-Json -Depth 24), $utf8)
        } catch {
            Write-Host ('报告保存失败：' + $_.Exception.Message) -ForegroundColor Red
            $exitCode = 2
        }
    }
}

switch ($report.Status) {
    'window_on_primary' {
        Write-Host '已核对：蜂窝窗口位于主屏范围内，未最小化；Windows 未报告窗口无响应。' -ForegroundColor Green
        Write-Host '请确认界面是否出现；若仍看不到，请把下面的报告发回客服。'
    }
    'no_matching_window' {
        Write-Host '未找到当前登录会话中可恢复的蜂窝主窗口。请把报告发回客服，不必反复重装。' -ForegroundColor Yellow
        if ($report.Before -and $report.Before.CurrentIntegrityLevel -notin @('high', 'system', 'High', 'System')) {
            Write-Host '若蜂窝是以管理员身份运行，可右键 Recover-FengWo-Window.cmd，选择“以管理员身份运行”后重试一次。'
        }
    }
    'inspection_only' { Write-Host '已完成检查，未移动窗口。' }
    default {
        Write-Host '暂未确认窗口恢复，请把报告发回客服。' -ForegroundColor Yellow
        if ($report.Before -and $report.Before.CurrentIntegrityLevel -notin @('high', 'system', 'High', 'System')) {
            Write-Host '若蜂窝是以管理员身份运行，可右键 Recover-FengWo-Window.cmd，选择“以管理员身份运行”后重试一次。'
        }
    }
}
if ($outputPath) {
    $jsonPath = Join-Path $outputPath 'window-report.json'
    Write-Host ('报告文件：' + $jsonPath) -ForegroundColor Cyan
    try {
        $zipPath = $outputPath + '.zip'
        Compress-Archive -LiteralPath $jsonPath -DestinationPath $zipPath -Force
        Write-Host ('可发送此压缩包：' + $zipPath) -ForegroundColor Cyan
    } catch {
        Write-Host '压缩未完成，直接发送 window-report.json 即可。' -ForegroundColor Yellow
    }
}
exit $exitCode
