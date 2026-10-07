param(
    [Alias('ExecutablePath')][string]$AppPath = '',
    [string]$OutputDirectory = '',
    [ValidateRange(5, 120)][int]$ObserveSeconds = 60,
    [ValidateRange(1, 7)][int]$Days = 1,
    [switch]$NoLaunch,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows is required.' }
$utf8 = New-Object Text.UTF8Encoding($true)
$startedAt = Get-Date
$collectionErrors = New-Object 'Collections.Generic.List[string]'
$findings = New-Object 'Collections.Generic.List[object]'
$observations = New-Object 'Collections.Generic.List[object]'
$candidates = New-Object 'Collections.Generic.List[string]'
$nativeReady = $false
$selectedPath = ''
$before = @()
$after = @()
$dataDirectories = @()
$launch = [ordered]@{ status = 'not_attempted'; startedPid = $null; startErrorNativeCode = $null; exitCode = $null; exitCodeHex = $null; classification = 'not_observed' }
$folderName = 'FengWo-Windows-Startup-Report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = [Environment]::GetFolderPath('Desktop') }
try {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'Desktop is unavailable.' }
    $folder = Join-Path $OutputDirectory $folderName
    $null = [IO.Directory]::CreateDirectory($folder)
} catch {
    $folder = Join-Path ([IO.Path]::GetTempPath()) $folderName
    $null = [IO.Directory]::CreateDirectory($folder)
    $collectionErrors.Add('Requested output directory unavailable; using TEMP: ' + $_.Exception.Message)
}

function Protect-Text {
    param([AllowNull()][object]$Value)
    $text = [string]$Value
    $text = [regex]::Replace($text, '(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', '[email-redacted]')
    $text = [regex]::Replace($text, '(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+', '$1[redacted]')
    $text = [regex]::Replace($text, '(?i)(https?://[^\s"''<>?]+)\?[^\s"''<>]*', '$1?[query-redacted]')
    $text = [regex]::Replace($text, '(?i)((?:password|passwd|token|secret|authorization|cookie|auth_data)\s*[=:]\s*)[^\s,;]+', '$1[redacted]')
    return $text
}

function Protect-Value {
    param([AllowNull()][object]$Value, [int]$Depth = 0)
    if ($null -eq $Value -or $Depth -gt 12) { return $null }
    if ($Value -is [string]) { return (Protect-Text $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ([string]$key -match '(?i)password|passwd|secret|token|authorization|cookie|credential|auth.?data|email|account|subscription.?url') { $result[$key] = '[redacted]' }
            else { $result[$key] = Protect-Value $Value[$key] ($Depth + 1) }
        }
        return $result
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -match '(?i)password|passwd|secret|token|authorization|cookie|credential|auth.?data|email|account|subscription.?url') { $result[$property.Name] = '[redacted]' }
            else { $result[$property.Name] = Protect-Value $property.Value ($Depth + 1) }
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable]) { return ,@($Value | ForEach-Object { Protect-Value $_ ($Depth + 1) }) }
    return $Value
}

function Save-Text {
    param([string]$Name, [AllowNull()][object]$Value)
    [IO.File]::WriteAllText((Join-Path $folder $Name), [string]$Value, $utf8)
}

function Save-Json {
    param([string]$Name, [AllowNull()][object]$Value)
    Save-Text $Name (ConvertTo-Json -InputObject $Value -Depth 18)
}

function Add-Finding {
    param([string]$Code, [string]$Message)
    $findings.Add([ordered]@{ code = $Code; message = $Message })
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ('正在采集 / Collecting: ' + $Name)
    try { & $Action | Out-Null }
    catch { $collectionErrors.Add($Name + ': ' + (Protect-Text $_.Exception.Message)); Write-Host ('该项不可用，继续其他检查 / Partial: ' + $Name) }
}

function Invoke-NativeRead {
    param([string]$File, [string]$Arguments, [int]$TimeoutSeconds = 12)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            return [ordered]@{ timeout = $true; exitCode = $null; output = 'Diagnostic read command timed out.' }
        }
        $null = $stdout.Wait(2000)
        $null = $stderr.Wait(2000)
        return [ordered]@{ timeout = $false; exitCode = $process.ExitCode; output = (Protect-Text ($stdout.Result + $stderr.Result)) }
    } finally { $process.Dispose() }
}

function Resolve-AppFile {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $valuePath = [Environment]::ExpandEnvironmentVariables($Value.Trim().Trim('"'))
    if (Test-Path -LiteralPath $valuePath -PathType Container) { $valuePath = Join-Path $valuePath 'FengWo.exe' }
    if ($valuePath.EndsWith('.lnk', [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $valuePath)) {
        $shell = New-Object -ComObject WScript.Shell
        try { $valuePath = $shell.CreateShortcut($valuePath).TargetPath } finally { $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
    if ((Test-Path -LiteralPath $valuePath -PathType Leaf) -and [IO.Path]::GetExtension($valuePath) -ieq '.exe') { return [IO.Path]::GetFullPath($valuePath) }
    return ''
}

function Add-Candidate {
    param([string]$Value)
    try {
        $resolved = Resolve-AppFile $Value
        if ($resolved -and -not $candidates.Contains($resolved)) { $candidates.Add($resolved) }
    } catch {}
}

function Get-ClientProcesses {
    $items = New-Object 'Collections.Generic.List[object]'
    $all = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^(FengWo|fengwoacc|FlClash|FlClashCore|FlClashHelperService)$' -or
        ($selectedPath -and $_.ProcessName -eq [IO.Path]::GetFileNameWithoutExtension($selectedPath))
    })
    foreach ($process in $all) {
        try {
            $path = $null
            $integrity = 'unknown'
            $windows = @()
            try { $path = $process.Path } catch {}
            if ($nativeReady) {
                $windows = @([FengWoStartupDiagnostics.NativeProbe]::SnapshotWindows($process.Id))
                $integrity = [FengWoStartupDiagnostics.NativeProbe]::GetIntegrityLevel($process.Id)
            } elseif ($process.MainWindowHandle -ne [IntPtr]::Zero) {
                $windows = @([ordered]@{ Handle = $process.MainWindowHandle.ToInt64().ToString('X'); Title = Protect-Text $process.MainWindowTitle; Visible = $null; Minimized = $null })
            }
            $items.Add([ordered]@{ pid = $process.Id; name = $process.ProcessName; path = $path; sessionId = $process.SessionId; integrity = $integrity; mainWindowHandle = $process.MainWindowHandle.ToInt64().ToString('X'); windows = $windows })
        } catch { $items.Add([ordered]@{ pid = $process.Id; error = Protect-Text $_.Exception.Message }) }
    }
    return ,@($items.ToArray())
}

function Get-FileMetadata {
    param([string]$Path, [switch]$Hash)
    $item = Get-Item -LiteralPath $Path -Force
    $result = [ordered]@{ path = $item.FullName; directory = $item.PSIsContainer; attributes = $item.Attributes.ToString(); lastWriteUtc = $item.LastWriteTimeUtc.ToString('o') }
    if (-not $item.PSIsContainer) {
        $result.bytes = $item.Length
        if ($Hash) { $result.sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    try { $acl = Get-Acl -LiteralPath $Path; $result.owner = $acl.Owner; $result.sddl = $acl.Sddl } catch { $result.aclError = Protect-Text $_.Exception.Message }
    return $result
}

function Collect-DataDirectory {
    param([string]$Directory, [int]$Index, [string]$Stage)
    $result = [ordered]@{ path = $Directory; exists = (Test-Path -LiteralPath $Directory -PathType Container); files = @(); parents = @() }
    $parent = $Directory
    for ($i = 0; $i -lt 3 -and $parent; $i++) {
        if (Test-Path -LiteralPath $parent) {
            try {
                $metadata = Get-FileMetadata $parent
                $metadata.icacls = Invoke-NativeRead "$env:SystemRoot\System32\icacls.exe" ('"' + $parent + '"')
                $result.parents += $metadata
            } catch { $collectionErrors.Add('Data ACL: ' + (Protect-Text $_.Exception.Message)) }
        }
        $parent = Split-Path -Parent $parent
    }
    if ($result.exists) {
        $files = @(Get-ChildItem -LiteralPath $Directory -File -Force | Where-Object { $_.Name -match '^(shared_preferences\.json|database\.sqlite|FlClash\.lock|fengwo.*secret)' } | Select-Object -First 60)
        foreach ($file in $files) {
            try {
                $metadata = Get-FileMetadata $file.FullName
                if ($file.Name -match '^shared_preferences\.json' -and $file.Length -lt 5MB) {
                    try {
                        $preferences = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
                        $metadata.jsonValid = $true
                        $metadata.jsonRootType = $preferences.GetType().FullName
                    } catch { $metadata.jsonValid = $false; $metadata.parseError = 'JSON invalid or unreadable; content excluded.' }
                }
                $result.files += $metadata
            } catch { $collectionErrors.Add('Data file: ' + (Protect-Text $_.Exception.Message)) }
        }
        $logDirectory = Join-Path $Directory 'diagnostics'
        if (Test-Path -LiteralPath $logDirectory -PathType Container) {
            $logs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'events.jsonl*' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
            foreach ($log in $logs) {
                $safeLines = New-Object 'Collections.Generic.List[string]'
                foreach ($line in @(Get-Content -LiteralPath $log.FullName -Tail 400 -Encoding UTF8)) {
                    try { $safeLines.Add((ConvertTo-Json -InputObject (Protect-Value ($line | ConvertFrom-Json)) -Depth 18 -Compress)) }
                    catch { $safeLines.Add('[Unparseable diagnostic line omitted]') }
                }
                Save-Text ("data-$Index-$Stage-" + $log.Name + '.redacted.txt') ($safeLines -join "`r`n")
            }
        }
    }
    Save-Json "data-$Index-$Stage.json" $result
}

function Collect-Events {
    param([string]$LogName, [string]$Name, [int[]]$Ids = @())
    $filter = @{ LogName = $LogName; StartTime = $startedAt.AddDays(-$Days) }
    if ($Ids.Count) { $filter.Id = $Ids }
    $result = [ordered]@{ logName = $LogName; status = 'unavailable'; matched = @(); scanned = 0; limit = 1500; limitReached = $false }
    try {
        $logInfo = Get-WinEvent -ListLog $LogName
        $result.enabled = $logInfo.IsEnabled
        try { $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 1500) }
        catch { if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $events = @() } else { throw } }
        $result.scanned = $events.Count
        $result.limitReached = $events.Count -ge 1500
        $needle = 'FengWo|FlClash|fengwoacc|蜂窝加速器'
        if ($selectedPath) { $needle += '|' + [regex]::Escape([IO.Path]::GetFileName($selectedPath)) }
        foreach ($event in $events) {
            $xml = $event.ToXml()
            if ($xml -match $needle) {
                $result.matched += [ordered]@{ time = $event.TimeCreated.ToString('o'); id = $event.Id; provider = $event.ProviderName; level = $event.LevelDisplayName; message = Protect-Text $event.Message; xml = Protect-Text $xml }
            }
        }
        $result.status = 'collected'
    } catch { $result.error = Protect-Text $_.Exception.Message; $collectionErrors.Add($LogName + ': ' + $result.error) }
    Save-Json ($Name + '.json') $result
}

try {
    Write-Host '蜂窝客户端启动诊断 / FengWo startup diagnostics'
    Write-Host '将记录当前状态并尝试启动一次客户端；不会结束现有客户端进程。'
    Write-Host ('报告目录 / Report: ' + $folder)
    Invoke-Step 'native inspection helper' {
        Add-Type -Path (Join-Path $PSScriptRoot 'startup_diagnostics_native.cs')
        $script:nativeReady = $true
    }
    Invoke-Step 'system and identity' {
        $version = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $system = [ordered]@{
            collectedAt = $startedAt.ToString('o'); powershell = $PSVersionTable.PSVersion.ToString(); languageMode = $ExecutionContext.SessionState.LanguageMode.ToString()
            process64Bit = [Environment]::Is64BitProcess; os64Bit = [Environment]::Is64BitOperatingSystem
            productName = $version.ProductName; displayVersion = $version.DisplayVersion; build = $version.CurrentBuild; ubr = $version.UBR
            sessionId = (Get-Process -Id $PID).SessionId; elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            appDataEnvironment = $env:APPDATA; appDataKnownFolder = [Environment]::GetFolderPath('ApplicationData')
            localAppDataEnvironment = $env:LOCALAPPDATA; localAppDataKnownFolder = [Environment]::GetFolderPath('LocalApplicationData')
            temp = [IO.Path]::GetTempPath(); timeZone = [TimeZoneInfo]::Local.Id
            whoami = Invoke-NativeRead "$env:SystemRoot\System32\whoami.exe" '/all'
        }
        if ($nativeReady) { $system.collectorIntegrity = [FengWoStartupDiagnostics.NativeProbe]::GetIntegrityLevel($PID) }
        Save-Json 'system.json' $system
        Save-Json 'gpu.json' @(Get-CimInstance Win32_VideoController -OperationTimeoutSec 15 | Select-Object Name, DriverVersion, DriverDate, Status, VideoModeDescription)
    }
    Invoke-Step 'installed client discovery' {
        foreach ($process in @(Get-Process -Name FengWo, fengwoacc, FlClash -ErrorAction SilentlyContinue)) { try { Add-Candidate $process.Path } catch {} }
        $registrations = @()
        foreach ($base in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
            if (-not (Test-Path $base)) { continue }
            foreach ($key in @(Get-ChildItem $base)) {
                $entry = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
                if ($entry.DisplayName -match 'FengWo|FlClash|蜂窝加速器') {
                    $registrations += $entry | Select-Object DisplayName, DisplayVersion, InstallLocation, DisplayIcon, PSPath
                    if ($entry.InstallLocation) { Add-Candidate (Join-Path $entry.InstallLocation 'FengWo.exe') }
                    if ($entry.DisplayIcon) { Add-Candidate ($entry.DisplayIcon -replace ',\s*-?\d+$', '') }
                }
            }
        }
        foreach ($base in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))) {
            if (-not $base -or -not (Test-Path -LiteralPath $base)) { continue }
            foreach ($link in @(Get-ChildItem -LiteralPath $base -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '蜂窝|FengWo|FlClash' } | Select-Object -First 30)) { Add-Candidate $link.FullName }
        }
        foreach ($base in @($PSScriptRoot, "$env:ProgramFiles\FengWo", "$env:ProgramFiles\FlClash", "$env:LOCALAPPDATA\Programs\FengWo")) { Add-Candidate (Join-Path $base 'FengWo.exe') }
        Save-Json 'installations.json' ([ordered]@{ registry = $registrations; candidates = @($candidates.ToArray()) })
    }
    if ($AppPath) { $selectedPath = Resolve-AppFile $AppPath }
    elseif ($candidates.Count -eq 1) { $selectedPath = $candidates[0] }
    elseif (-not $NonInteractive) {
        for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host (([string]($i + 1)) + '. ' + $candidates[$i]) }
        Write-Host '请选择出问题的客户端编号，或把桌面快捷方式/FengWo.exe 拖入窗口后回车。找不到可直接回车继续采集。'
        $answer = Read-Host '编号或路径 / Number or path'
        $choice = 0
        if ([int]::TryParse($answer, [ref]$choice) -and $choice -ge 1 -and $choice -le $candidates.Count) { $selectedPath = $candidates[$choice - 1] }
        else { $selectedPath = Resolve-AppFile $answer }
    }
    if (-not $selectedPath) {
        Add-Finding 'executable_not_found_or_not_selected' '没有定位到客户端程序。报告保留系统记录；请核对桌面快捷方式和实际安装目录。'
        $launch.classification = 'executable_not_found'
    }
    $metadataCompany = 'com.follow'
    $metadataProduct = '蜂窝加速器'
    if ($selectedPath) {
        Write-Host ('已选择 / Selected: ' + $selectedPath)
        Invoke-Step 'application files and dependencies' {
            $appFile = Get-Item -LiteralPath $selectedPath
            $bundle = $appFile.DirectoryName
            if ($appFile.VersionInfo.CompanyName) { $script:metadataCompany = $appFile.VersionInfo.CompanyName }
            if ($appFile.VersionInfo.ProductName) { $script:metadataProduct = $appFile.VersionInfo.ProductName }
            $metadata = Get-FileMetadata $selectedPath -Hash
            $metadata.version = $appFile.VersionInfo | Select-Object FileVersion, ProductVersion, CompanyName, ProductName
            $signature = Get-AuthenticodeSignature -LiteralPath $selectedPath
            $metadata.signature = [ordered]@{ status = $signature.Status.ToString(); message = $signature.StatusMessage; signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null } }
            try { $metadata.zoneIdentifier = Get-Content -LiteralPath $selectedPath -Stream Zone.Identifier -ErrorAction Stop | Where-Object { $_ -match '^ZoneId=' } } catch { $metadata.zoneIdentifier = $null }
            Save-Json 'application.json' $metadata
            $files = @(Get-ChildItem -LiteralPath $bundle -File -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 3000)
            Save-Json 'bundle-files.json' @($files | ForEach-Object { [ordered]@{ relativePath = $_.FullName.Substring($bundle.Length).TrimStart('\'); bytes = $_.Length; modifiedUtc = $_.LastWriteTimeUtc.ToString('o') } })
            $required = @('flutter_windows.dll', 'data\icudtl.dat', 'data\app.so', 'data\flutter_assets')
            $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $bundle $_)) })
            Save-Json 'required-files.json' ([ordered]@{ expected = $required; missing = $missing })
            if ($missing.Count) { Add-Finding 'bundle_files_missing' ('安装目录缺少文件或目录：' + ($missing -join ', ') + '。需结合实际版本确认安装是否完整。') }
            if ($nativeReady) {
                $peFiles = @($files | Where-Object { $_.Extension -match '^\.(exe|dll)$' } | Select-Object -First 150)
                $peResults = @()
                foreach ($file in $peFiles) {
                    $pe = [FengWoStartupDiagnostics.NativeProbe]::ReadPe($file.FullName)
                    $dependencies = @()
                    foreach ($name in $pe.Imports) {
                        $resolution = 'not_found_in_checked_locations'
                        if ($name -match '^(api-ms-|ext-ms-)') { $resolution = 'windows_api_set_contract' }
                        elseif (Test-Path -LiteralPath (Join-Path $bundle $name)) { $resolution = 'application_directory' }
                        elseif (Test-Path -LiteralPath (Join-Path $file.DirectoryName $name)) { $resolution = 'module_directory' }
                        elseif (Test-Path -LiteralPath (Join-Path "$env:SystemRoot\System32" $name)) { $resolution = 'system_directory' }
                        $dependencies += [ordered]@{ name = $name; resolution = $resolution }
                    }
                    $peResults += [ordered]@{ path = $file.FullName; pe = $pe; dependencies = $dependencies }
                }
                Save-Json 'pe-dependencies.json' $peResults
            }
            Save-Json 'install-directory-acl.json' (Get-FileMetadata $bundle)
            Save-Json 'install-directory-icacls.json' (Invoke-NativeRead "$env:SystemRoot\System32\icacls.exe" ('"' + $bundle + '"'))
        }
    }
    $dataDirectories = @(@($env:APPDATA, [Environment]::GetFolderPath('ApplicationData'), $env:LOCALAPPDATA, [Environment]::GetFolderPath('LocalApplicationData')) | Where-Object { $_ } | ForEach-Object { Join-Path (Join-Path $_ $metadataCompany) $metadataProduct } | Select-Object -Unique)
    for ($i = 0; $i -lt $dataDirectories.Count; $i++) { Invoke-Step ('data before launch ' + $i) { Collect-DataDirectory $dataDirectories[$i] $i 'before' } }
    Invoke-Step 'processes before launch' { $script:before = Get-ClientProcesses; Save-Json 'processes-before.json' $before }
    Invoke-Step 'startup observation' {
        $newProcess = $null
        if ($selectedPath -and -not $NoLaunch) {
            try {
                $startInfo = New-Object Diagnostics.ProcessStartInfo
                $startInfo.FileName = $selectedPath
                $startInfo.WorkingDirectory = Split-Path -Parent $selectedPath
                $startInfo.UseShellExecute = $false
                $newProcess = New-Object Diagnostics.Process
                $newProcess.StartInfo = $startInfo
                $null = $newProcess.Start()
                $launch.status = 'started'
                $launch.startedPid = $newProcess.Id
            } catch {
                $launch.status = 'start_failed'
                $exception = $_.Exception
                while ($exception.InnerException) { $exception = $exception.InnerException }
                $launch.startErrorNativeCode = $exception.NativeErrorCode
                $launch.error = Protect-Text $exception.Message
                $launch.classification = 'start_failed'
                Add-Finding 'process_start_failed' ('Windows 创建进程失败，错误码：' + $launch.startErrorNativeCode + '。详见 summary.json。')
            }
        } elseif ($NoLaunch) { $launch.status = 'skipped_by_request'; $launch.classification = 'launch_skipped' }
        Write-Host ('开始观察 / Observing for ' + $ObserveSeconds + ' seconds. 请保留弹窗，不要重复点击客户端。')
        $watch = [Diagnostics.Stopwatch]::StartNew()
        do {
            $snapshot = Get-ClientProcesses
            $observations.Add([ordered]@{ elapsedSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1); processes = $snapshot })
            if ($newProcess) {
                $newProcess.Refresh()
                if ($newProcess.HasExited) {
                    $launch.status = 'exited'
                    $launch.exitCode = $newProcess.ExitCode
                    $launch.exitCodeHex = '0x' + [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$newProcess.ExitCode), 0).ToString('X8')
                }
            }
            Start-Sleep -Milliseconds 1000
        } while ($watch.Elapsed.TotalSeconds -lt $ObserveSeconds)
        $script:after = Get-ClientProcesses
        Save-Json 'processes-after.json' $after
        $visible = @($after | Where-Object { $_.pid -eq $launch.startedPid } | ForEach-Object { $_.windows } | Where-Object { $_.Visible -eq $true })
        $otherClient = @($after | Where-Object { $_.name -match '^(FengWo|fengwoacc|FlClash)$' -and $_.pid -ne $launch.startedPid })
        if ($newProcess) {
            if ($launch.status -eq 'exited') {
                if ($launch.exitCode -ne 0) { $launch.classification = 'exited_nonzero'; Add-Finding 'nonzero_exit' ('进程退出码 ' + $launch.exitCodeHex + '，需结合崩溃、系统拦截和依赖记录定位。') }
                elseif ($otherClient.Count) { $launch.classification = 'exit_zero_existing_instance'; Add-Finding 'existing_instance' '新进程正常退出且仍有其他客户端进程，可能触发单实例激活；请核对旧进程路径、会话与窗口。' }
                else { $launch.classification = 'exit_zero_no_client'; Add-Finding 'exit_zero_no_client' '新进程退出码为 0，但没有其他客户端进程；需检查文件锁、配置目录访问及启动日志。' }
            } elseif ($visible.Count) { $launch.classification = 'process_running_window_visible' }
            else { $launch.classification = 'process_running_no_visible_window'; Add-Finding 'running_no_visible_window' '观察结束时进程仍在但未检测到可见顶层窗口，可能仍在初始化、静默启动或窗口未显示；这不是已确认的崩溃。' }
            $newProcess.Dispose()
        }
        Save-Json 'process-observation.json' @($observations.ToArray())
    }
    for ($i = 0; $i -lt $dataDirectories.Count; $i++) { Invoke-Step ('data after launch ' + $i) { Collect-DataDirectory $dataDirectories[$i] $i 'after' } }
    Invoke-Step 'application crash and loader events' { Collect-Events 'Application' 'events-application' @(1000, 1001, 1002, 1026, 33, 35, 59) }
    Invoke-Step 'Windows application control events' { Collect-Events 'Microsoft-Windows-CodeIntegrity/Operational' 'events-code-integrity' }
    Invoke-Step 'AppLocker application events' { Collect-Events 'Microsoft-Windows-AppLocker/EXE and DLL' 'events-applocker-exe' }
    Invoke-Step 'AppLocker script events' { Collect-Events 'Microsoft-Windows-AppLocker/MSI and Script' 'events-applocker-script' }
    Invoke-Step 'Defender events' { Collect-Events 'Microsoft-Windows-Windows Defender/Operational' 'events-defender' }
    Invoke-Step 'runtime and compatibility settings' {
        $settings = @()
        foreach ($path in @('HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\FengWo.exe')) {
            if (Test-Path $path) { $settings += [ordered]@{ path = $path; values = Get-ItemProperty $path | Select-Object Version, Installed, Major, Minor, Bld, Debugger, GlobalFlag, MitigationOptions } }
        }
        $layers = @()
        foreach ($path in @('HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers', 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers')) {
            if (Test-Path $path) { foreach ($property in (Get-ItemProperty $path).PSObject.Properties) { if ($property.Name -match 'FengWo|FlClash|蜂窝') { $layers += [ordered]@{ path = $property.Name; flags = $property.Value } } } }
        }
        Save-Json 'runtime-compatibility.json' ([ordered]@{ registry = $settings; compatibilityLayers = $layers })
        Save-Json 'antivirus-products.json' @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -OperationTimeoutSec 10 | Select-Object displayName, productState)
    }
    Invoke-Step 'Windows error reports' {
        $reports = @()
        foreach ($rootPath in @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive", "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue")) {
            if (-not (Test-Path -LiteralPath $rootPath)) { continue }
            foreach ($directory in @(Get-ChildItem -LiteralPath $rootPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $startedAt.AddDays(-$Days) -and $_.Name -match 'FengWo|FlClash|fengwoacc' } | Sort-Object LastWriteTime -Descending | Select-Object -First 15)) {
                $reportFile = Join-Path $directory.FullName 'Report.wer'
                $lines = @()
                if (Test-Path -LiteralPath $reportFile) { $lines = @(Get-Content -LiteralPath $reportFile | Where-Object { $_ -match '^(EventType|AppName|AppPath|FriendlyEventName|Sig\[\d+\]\.(Name|Value)|DynamicSig\[\d+\]\.(Name|Value))=' } | ForEach-Object { Protect-Text $_ }) }
                $reports += [ordered]@{ directory = $directory.FullName; report = $lines; files = @(Get-ChildItem -LiteralPath $directory.FullName -File | Select-Object Name, Length, LastWriteTimeUtc) }
            }
        }
        Save-Json 'windows-error-reports.json' $reports
    }
} catch {
    $collectionErrors.Add('Collector: ' + (Protect-Text $_.Exception.Message))
} finally {
    $summary = [ordered]@{
        collectorVersion = 1; collectedAt = $startedAt.ToString('o'); completedAt = (Get-Date).ToString('o')
        appPath = $selectedPath; nativeHelperAvailable = $nativeReady; launch = $launch
        observations = @($observations.ToArray()); findings = @($findings.ToArray()); collectionErrors = @($collectionErrors.ToArray())
        beforeProcesses = $before; afterProcesses = $after; dataDirectories = $dataDirectories
        limitations = @('该工具收集证据，不直接认定根因。', '进程正常退出不代表窗口正常显示；签名状态和依赖文件存在不能单独证明系统允许启动。', '事件查询有时间和数量上限，未读到拦截记录不等于没有拦截。', '不上传报告，不修改权限、防护、代理或注册表，不终止客户端；启动客户端本身可能执行其正常恢复、登录或自动连接流程。', '不收集密码、订阅配置、数据库内容或内存转储；结构化诊断日志会脱敏。')
    }
    Save-Json 'summary.json' $summary
    $lines = @('蜂窝 Windows 启动诊断', '程序：' + $selectedPath, '启动观察：' + $launch.classification, '进程退出码：' + $launch.exitCodeHex, '创建进程错误码：' + $launch.startErrorNativeCode, '')
    foreach ($finding in $findings) { $lines += '[' + $finding.code + '] ' + $finding.message }
    if (-not $findings.Count) { $lines += '未发现可直接归类的异常，请结合其他报告文件进一步分析。' }
    $lines += @('', '未完成的采集项：' + $collectionErrors.Count, '部分项目无权限或不可用时，其余报告仍会保留。', '', '请把整个 ZIP 报告发回客服。')
    Save-Text 'summary.txt' ($lines -join "`r`n")
    Save-Text 'collection-errors.txt' ($collectionErrors -join "`r`n")
    $archive = $folder + '.zip'
    try {
        Compress-Archive -LiteralPath $folder -DestinationPath $archive -CompressionLevel Optimal
        Write-Host ''
        Write-Host '诊断完成 / Finished. 请把下面的 ZIP 发回客服：'
        Write-Host $archive
    } catch {
        Write-Host '压缩失败，报告文件已保留。请将以下文件夹手动压缩后发回客服：'
        Write-Host $folder
        Save-Text 'archive-error.txt' (Protect-Text $_.Exception.Message)
    }
}
