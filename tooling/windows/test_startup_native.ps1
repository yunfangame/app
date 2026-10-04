param(
    [Parameter(Mandatory = $true)][string]$ProbeExecutable,
    [string]$OutputDirectory,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows') {
    throw 'Requires an isolated GitHub Actions Windows runner'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) { throw 'RUNNER_TEMP is required' }
    $OutputDirectory = Join-Path $env:RUNNER_TEMP 'fengwo-startup-native'
}
$ProbeExecutable = (Get-Item -LiteralPath $ProbeExecutable).FullName
if (-not [IO.File]::Exists($ProbeExecutable) -or [IO.Path]::GetExtension($ProbeExecutable) -ine '.exe') {
    throw 'ProbeExecutable must be an existing Windows executable'
}
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$reportPath = Join-Path $OutputDirectory 'native-report.json'
$supervisorPath = Join-Path $OutputDirectory 'supervisor-report.json'
$stdoutPath = Join-Path $OutputDirectory 'native-stdout.txt'
$stderrPath = Join-Path $OutputDirectory 'native-stderr.txt'
foreach ($path in @($reportPath, $supervisorPath, $stdoutPath, $stderrPath)) {
    if (Test-Path -LiteralPath $path) { throw 'Native startup output files must not already exist' }
}

if (-not ('FengWoStartupProxySnapshot' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public sealed class FengWoStartupProxySnapshot {
    [StructLayout(LayoutKind.Explicit)]
    private struct OptionValue {
        [FieldOffset(0)] public uint Number;
        [FieldOffset(0)] public IntPtr Text;
        [FieldOffset(0)] public uint FileTimeLow;
        [FieldOffset(4)] public uint FileTimeHigh;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ConnectionOption {
        public uint Option;
        public OptionValue Value;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ConnectionOptions {
        public uint Size;
        public IntPtr Connection;
        public uint Count;
        public uint Error;
        public IntPtr Options;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RasEntryName {
        public uint Size;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 257)] public byte[] Name;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 261)] public byte[] Phonebook;
    }

    private sealed class ConnectionState {
        public byte[] Name;
        public uint Flags;
        public byte[][] Strings;
    }

    [DllImport("wininet.dll", EntryPoint = "InternetQueryOptionA", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Query(IntPtr internet, uint option, ref ConnectionOptions options, ref uint size);

    [DllImport("wininet.dll", EntryPoint = "InternetSetOptionA", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Set(IntPtr internet, uint option, ref ConnectionOptions options, uint size);

    [DllImport("wininet.dll", EntryPoint = "InternetSetOptionW", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Notify(IntPtr internet, uint option, IntPtr buffer, uint size);

    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern IntPtr GlobalFree(IntPtr memory);

    [DllImport("rasapi32.dll", EntryPoint = "RasEnumEntriesA", ExactSpelling = true)]
    private static extern uint EnumEntries(IntPtr reserved, IntPtr phonebook, IntPtr entries, ref uint size, out uint count);

    private readonly List<ConnectionState> states;
    public int ConnectionCount { get { return states.Count; } }

    private FengWoStartupProxySnapshot(List<ConnectionState> values) { states = values; }

    private static byte[] ReadBytes(IntPtr pointer) {
        if (pointer == IntPtr.Zero) return null;
        int length = 0;
        while (Marshal.ReadByte(pointer, length) != 0) {
            if (++length > 1048576) throw new InvalidOperationException("Unexpected proxy value length");
        }
        var result = new byte[length];
        Marshal.Copy(pointer, result, 0, length);
        return result;
    }

    private static IntPtr AllocateBytes(byte[] value) {
        if (value == null) return IntPtr.Zero;
        var pointer = Marshal.AllocHGlobal(value.Length + 1);
        Marshal.Copy(value, 0, pointer, value.Length);
        Marshal.WriteByte(pointer, value.Length, 0);
        return pointer;
    }

    private static bool EqualBytes(byte[] left, byte[] right) {
        int leftLength = left == null ? 0 : left.Length;
        int rightLength = right == null ? 0 : right.Length;
        if (leftLength != rightLength) return false;
        for (int index = 0; index < leftLength; index++) {
            if (left[index] != right[index]) return false;
        }
        return true;
    }

    private static List<byte[]> ConnectionNames() {
        var result = new List<byte[]> { null };
        int entrySize = Marshal.SizeOf(typeof(RasEntryName));
        uint bytes = (uint)entrySize;
        uint count;
        IntPtr buffer = Marshal.AllocHGlobal(entrySize);
        try {
            Marshal.WriteInt32(buffer, entrySize);
            uint error = EnumEntries(IntPtr.Zero, IntPtr.Zero, buffer, ref bytes, out count);
            if (error == 603) {
                Marshal.FreeHGlobal(buffer);
                buffer = IntPtr.Zero;
                if (bytes > 16777216) throw new InvalidOperationException("Unexpected connection enumeration size");
                buffer = Marshal.AllocHGlobal(checked((int)bytes));
                Marshal.WriteInt32(buffer, entrySize);
                error = EnumEntries(IntPtr.Zero, IntPtr.Zero, buffer, ref bytes, out count);
            }
            if (error != 0) throw new Win32Exception((int)error, "Connection enumeration failed");
            if ((ulong)count * (ulong)entrySize > bytes) throw new InvalidOperationException("Invalid connection enumeration");
            for (int index = 0; index < count; index++) {
                var entry = (RasEntryName)Marshal.PtrToStructure(IntPtr.Add(buffer, index * entrySize), typeof(RasEntryName));
                int length = Array.IndexOf(entry.Name, (byte)0);
                if (length < 1) throw new InvalidOperationException("Invalid connection name");
                var name = new byte[length];
                Array.Copy(entry.Name, name, length);
                result.Add(name);
            }
        } finally {
            if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
        }
        return result;
    }

    private static ConnectionState Read(byte[] name) {
        int optionSize = Marshal.SizeOf(typeof(ConnectionOption));
        var options = new ConnectionOptions {
            Size = (uint)Marshal.SizeOf(typeof(ConnectionOptions)),
            Connection = AllocateBytes(name),
            Count = 4,
            Options = Marshal.AllocHGlobal(optionSize * 4)
        };
        try {
            for (int index = 0; index < 4; index++) {
                Marshal.StructureToPtr(new ConnectionOption { Option = index == 0 ? 10 : (uint)(index + 1) }, IntPtr.Add(options.Options, index * optionSize), false);
            }
            uint size = options.Size;
            if (!Query(IntPtr.Zero, 75, ref options, ref size)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Proxy snapshot query failed");
            var state = new ConnectionState { Name = name, Strings = new byte[3][] };
            for (int index = 0; index < 4; index++) {
                var option = (ConnectionOption)Marshal.PtrToStructure(IntPtr.Add(options.Options, index * optionSize), typeof(ConnectionOption));
                if (index == 0) state.Flags = option.Value.Number;
                else state.Strings[index - 1] = ReadBytes(option.Value.Text);
            }
            return state;
        } finally {
            for (int index = 1; index < 4; index++) {
                var option = (ConnectionOption)Marshal.PtrToStructure(IntPtr.Add(options.Options, index * optionSize), typeof(ConnectionOption));
                if (option.Value.Text != IntPtr.Zero) GlobalFree(option.Value.Text);
            }
            Marshal.FreeHGlobal(options.Options);
            if (options.Connection != IntPtr.Zero) Marshal.FreeHGlobal(options.Connection);
        }
    }

    private static void Write(ConnectionState state) {
        int optionSize = Marshal.SizeOf(typeof(ConnectionOption));
        var strings = new IntPtr[3];
        var options = new ConnectionOptions {
            Size = (uint)Marshal.SizeOf(typeof(ConnectionOptions)),
            Connection = AllocateBytes(state.Name),
            Count = 4,
            Options = Marshal.AllocHGlobal(optionSize * 4)
        };
        try {
            for (int index = 0; index < 4; index++) {
                var option = new ConnectionOption { Option = (uint)(index + 1) };
                if (index == 0) option.Value.Number = state.Flags;
                else {
                    strings[index - 1] = AllocateBytes(state.Strings[index - 1]);
                    option.Value.Text = strings[index - 1];
                }
                Marshal.StructureToPtr(option, IntPtr.Add(options.Options, index * optionSize), false);
            }
            if (!Set(IntPtr.Zero, 75, ref options, options.Size)) throw new Win32Exception(Marshal.GetLastWin32Error(), "Proxy restoration failed");
        } finally {
            foreach (var pointer in strings) if (pointer != IntPtr.Zero) Marshal.FreeHGlobal(pointer);
            Marshal.FreeHGlobal(options.Options);
            if (options.Connection != IntPtr.Zero) Marshal.FreeHGlobal(options.Connection);
        }
    }

    public static FengWoStartupProxySnapshot Capture() {
        var states = new List<ConnectionState>();
        foreach (var name in ConnectionNames()) states.Add(Read(name));
        return new FengWoStartupProxySnapshot(states);
    }

    public void Restore() {
        int failures = 0;
        foreach (var state in states) {
            try { Write(state); } catch { failures++; }
        }
        if (!Notify(IntPtr.Zero, 39, IntPtr.Zero, 0)) failures++;
        if (!Notify(IntPtr.Zero, 37, IntPtr.Zero, 0)) failures++;
        if (failures != 0) throw new InvalidOperationException("Proxy restoration or refresh failed");
    }

    public bool MatchesCurrent() {
        var names = ConnectionNames();
        if (names.Count != states.Count) return false;
        foreach (var state in states) {
            if (!names.Exists(name => EqualBytes(name, state.Name))) return false;
            var current = Read(state.Name);
            if (current.Flags != state.Flags) return false;
            for (int index = 0; index < 3; index++) {
                if (!EqualBytes(current.Strings[index], state.Strings[index])) return false;
            }
        }
        return true;
    }
}
'@
}

function Get-NativeProcesses {
    return @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId, Name, CreationDate -OperationTimeoutSec 5)
}

function Update-OwnedProcesses {
    $processes = Get-NativeProcesses
    do {
        $added = $false
        foreach ($item in $processes) {
            $processId = [int]$item.ProcessId
            if ($owned.ContainsKey($processId) -or -not $owned.ContainsKey([int]$item.ParentProcessId)) { continue }
            try {
                $child = [Diagnostics.Process]::GetProcessById($processId)
                $null = $child.Handle
                $parent = $owned[[int]$item.ParentProcessId]
                $childStarted = $child.StartTime.ToUniversalTime()
                $observedStarted = ([DateTime]$item.CreationDate).ToUniversalTime()
                if ([Math]::Abs($childStarted.Ticks - $observedStarted.Ticks) -gt 10 -or $childStarted -lt $parent.StartTime.ToUniversalTime() -or ($parent.HasExited -and $childStarted -gt $parent.ExitTime.ToUniversalTime())) {
                    $child.Dispose()
                    continue
                }
                $owned[$processId] = $child
                $added = $true
            } catch [ArgumentException] {
            } catch [InvalidOperationException] {
            } catch [ComponentModel.Win32Exception] {
                if (Get-Process -Id $processId -ErrorAction SilentlyContinue) { throw }
            }
        }
    } while ($added)
}

function Get-OwnedRemaining {
    return @($owned.Values | Where-Object { -not $_.HasExited })
}

function Stop-OwnedProcesses {
    $stopFailures = 0
    foreach ($process in @(Get-OwnedRemaining)) {
        if ($process.HasExited) { continue }
        try {
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            $startInfo.Arguments = '/PID ' + $process.Id + ' /T /F'
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $killer = [Diagnostics.Process]::Start($startInfo)
            try {
                $killer.BeginOutputReadLine()
                $killer.BeginErrorReadLine()
                if (-not $killer.WaitForExit(5000)) {
                    $killer.Kill()
                    $null = $killer.WaitForExit(5000)
                    $stopFailures++
                }
            } finally { $killer.Dispose() }
        } catch { $stopFailures++ }
    }
    foreach ($process in $owned.Values) {
        if (-not $process.HasExited -and -not $process.WaitForExit(5000)) { $stopFailures++ }
    }
    if ($stopFailures -ne 0) { throw 'Owned process cleanup failed' }
}

function Get-LoopbackListeners([int]$Port) {
    $properties = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
    $tcp = @($properties.GetActiveTcpListeners() | Where-Object {
        $_.Port -eq $Port -and ([Net.IPAddress]::IsLoopback($_.Address) -or $_.Address.Equals([Net.IPAddress]::Any) -or $_.Address.Equals([Net.IPAddress]::IPv6Any))
    })
    $udp = @($properties.GetActiveUdpListeners() | Where-Object {
        $_.Port -eq $Port -and ([Net.IPAddress]::IsLoopback($_.Address) -or $_.Address.Equals([Net.IPAddress]::Any) -or $_.Address.Equals([Net.IPAddress]::IPv6Any))
    })
    return @{ tcp = $tcp.Count; udp = $udp.Count }
}

function Add-SupervisorFailure([string]$Stage, [Management.Automation.ErrorRecord]$Failure = $null) {
    $failures.Add($Stage)
    $exception = if ($null -ne $Failure) { $Failure.Exception.GetBaseException() } else { $null }
    $message = $stageMessages[$Stage]
    if ($null -ne $exception -and $safeMessages -ccontains $exception.Message) { $message = $exception.Message }
    if ([string]::IsNullOrWhiteSpace($message)) { $message = 'Native startup verification failed' }
    if ($message.Length -gt 240) { $message = $message.Substring(0, 240) }
    $exceptionType = if ($null -ne $exception) { $exception.GetType().FullName } else { 'VerificationFailure' }
    if ($exceptionType.Length -gt 160) { $exceptionType = $exceptionType.Substring(0, 160) }
    $failureDetails.Add([ordered]@{
        stage = $Stage
        exception_type = $exceptionType
        message = $message
        hresult = $(if ($null -ne $exception) { $exception.HResult } else { $null })
        native_error_code = $(if ($exception -is [ComponentModel.Win32Exception]) { $exception.NativeErrorCode } else { $null })
    })
}

$owned = @{}
$proxySnapshot = $null
$probe = $null
$nativeReport = $null
$mixedPort = 0
$failures = [Collections.Generic.List[string]]::new()
$failureDetails = [Collections.Generic.List[object]]::new()
$stageMessages = @{
    existing_process_guard = 'Could not confirm an idle Windows runner without application, Core, or Helper processes'
    proxy_snapshot = 'Could not capture the current-user WinINet proxy configuration'
    probe_launch = 'Could not launch the native executable with redirected output'
    probe_execution = 'Native probe exited with an error or exceeded its configured deadline'
    probe_report = 'Native probe report is missing, malformed, or violates the required evidence contract'
    native_cleanup_verification = 'Native probe did not leave a clean process and loopback listener state'
    owned_process_discovery = 'Could not enumerate the descendants of the native probe'
    owned_process_cleanup = 'Could not terminate every process owned by the native probe'
    proxy_restore = 'Could not restore or refresh every captured WinINet connection'
    proxy_restore_verification = 'Current WinINet proxy configuration does not match the captured snapshot'
    remaining_processes = 'Application-owned processes or Core processes remain after cleanup'
    process_cleanup_verification = 'Could not independently verify process cleanup'
    remaining_listeners = 'TCP or UDP loopback listeners remain at the reported mixed port'
    listener_cleanup_verification = 'Could not independently verify TCP and UDP listener cleanup'
}
$safeMessages = @(
    'Existing application, Core, or Helper processes prevent isolated native testing',
    'Native startup probe timed out',
    'Native startup probe failed',
    'Native startup report did not pass',
    'Native startup report must explicitly exclude actual login verification',
    'Native startup report did not confirm isolated test data',
    'Native startup report has no integer mixed port',
    'Native startup report has an invalid mixed port',
    'Native startup report did not confirm clean shutdown',
    'Native probe left processes or listeners behind',
    'Owned process cleanup failed',
    'Unexpected proxy value length',
    'Unexpected connection enumeration size',
    'Connection enumeration failed',
    'Invalid connection enumeration',
    'Invalid connection name',
    'Proxy snapshot query failed',
    'Proxy restoration failed',
    'Proxy restoration or refresh failed'
)
$environmentNames = @('FENGWO_STARTUP_NATIVE_REPORT', 'FENGWO_STARTUP_NATIVE_CI')
$originalEnvironment = @{}
foreach ($name in $environmentNames) { $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$evidence = [ordered]@{
    status = 'failed'
    actual_login_verified = $false
    ci_windows_guard = $true
    timeout_seconds = $TimeoutSeconds
    timed_out = $false
    probe_exit_code = $null
    probe_report_passed = $false
    data_directory_isolated = $false
    native_cleanup_verified = $false
    forced_cleanup_used = $false
    proxy_snapshot_connection_count = 0
    proxy_restore_completed = $false
    proxy_matches_snapshot = $false
    owned_processes_remaining = $null
    core_processes_remaining = $null
    mixed_port = $null
    tcp_loopback_listeners_remaining = $null
    udp_loopback_listeners_remaining = $null
    failures = @()
    errors = @()
}
$stage = 'existing_process_guard'
try {
    $existing = @(Get-NativeProcesses | Where-Object { $_.Name -in @('FengWo.exe', 'FlClash.exe', 'FlClashCore.exe', 'FlClashHelperService.exe') })
    if ($existing.Count -ne 0) { throw 'Existing application, Core, or Helper processes prevent isolated native testing' }
    $stage = 'proxy_snapshot'
    $proxySnapshot = [FengWoStartupProxySnapshot]::Capture()
    $evidence.proxy_snapshot_connection_count = $proxySnapshot.ConnectionCount
    [Environment]::SetEnvironmentVariable('FENGWO_STARTUP_NATIVE_REPORT', $reportPath, 'Process')
    [Environment]::SetEnvironmentVariable('FENGWO_STARTUP_NATIVE_CI', '1', 'Process')
    $stage = 'probe_launch'
    $probe = Start-Process -FilePath $ProbeExecutable -WorkingDirectory ([IO.Path]::GetDirectoryName($ProbeExecutable)) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $null = $probe.Handle
    $owned[[int]$probe.Id] = $probe
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $stage = 'probe_execution'
    do {
        Update-OwnedProcesses
        if ($probe.WaitForExit(200)) { break }
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    if (-not $probe.HasExited) {
        $evidence.timed_out = $true
        throw 'Native startup probe timed out'
    }
    $evidence.probe_exit_code = $probe.ExitCode
    if ($probe.ExitCode -ne 0) { throw 'Native startup probe failed' }
    $stage = 'probe_report'
    $nativeReport = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($nativeReport.status -cne 'passed') { throw 'Native startup report did not pass' }
    if ($nativeReport.auth.actual_login_verified -isnot [bool] -or $nativeReport.auth.actual_login_verified) { throw 'Native startup report must explicitly exclude actual login verification' }
    if ($nativeReport.bootstrap.data_directory_isolated -isnot [bool] -or -not $nativeReport.bootstrap.data_directory_isolated) { throw 'Native startup report did not confirm isolated test data' }
    $evidence.data_directory_isolated = $true
    if ($nativeReport.mixed_port -isnot [long] -and $nativeReport.mixed_port -isnot [int]) { throw 'Native startup report has no integer mixed port' }
    if ($nativeReport.mixed_port -lt 1 -or $nativeReport.mixed_port -gt 65535) { throw 'Native startup report has an invalid mixed port' }
    $mixedPort = [int]$nativeReport.mixed_port
    $evidence.mixed_port = $mixedPort
    foreach ($field in @('core_closed', 'proxy_disabled', 'listeners_closed')) {
        if ($nativeReport.cleanup.$field -isnot [bool] -or -not $nativeReport.cleanup.$field) { throw 'Native startup report did not confirm clean shutdown' }
    }
    $evidence.probe_report_passed = $true
    $stage = 'native_cleanup_verification'
    Update-OwnedProcesses
    $listeners = Get-LoopbackListeners $mixedPort
    $cores = @(Get-NativeProcesses | Where-Object { $_.Name -ieq 'FlClashCore.exe' })
    if (@(Get-OwnedRemaining).Count -ne 0 -or $cores.Count -ne 0 -or $listeners.tcp -ne 0 -or $listeners.udp -ne 0) { throw 'Native probe left processes or listeners behind' }
    $evidence.native_cleanup_verified = $true
} catch {
    Add-SupervisorFailure $stage $_
} finally {
    if ($owned.Count -ne 0) {
        try { Update-OwnedProcesses } catch { Add-SupervisorFailure 'owned_process_discovery' $_ }
        try {
            if (@(Get-OwnedRemaining).Count -ne 0) {
                $evidence.forced_cleanup_used = $true
                Stop-OwnedProcesses
            }
        } catch { Add-SupervisorFailure 'owned_process_cleanup' $_ }
    }
    if ($null -ne $proxySnapshot) {
        try {
            $proxySnapshot.Restore()
            $evidence.proxy_restore_completed = $true
        } catch { Add-SupervisorFailure 'proxy_restore' $_ }
        try {
            $evidence.proxy_matches_snapshot = $proxySnapshot.MatchesCurrent()
            if (-not $evidence.proxy_matches_snapshot) { Add-SupervisorFailure 'proxy_restore_verification' }
        } catch { Add-SupervisorFailure 'proxy_restore_verification' $_ }
    }
    try {
        $evidence.owned_processes_remaining = @(Get-OwnedRemaining).Count
        $evidence.core_processes_remaining = @(Get-NativeProcesses | Where-Object { $_.Name -ieq 'FlClashCore.exe' }).Count
        if ($owned.Count -ne 0 -and ($evidence.owned_processes_remaining -ne 0 -or $evidence.core_processes_remaining -ne 0)) { Add-SupervisorFailure 'remaining_processes' }
    } catch { Add-SupervisorFailure 'process_cleanup_verification' $_ }
    try {
        if ($mixedPort -eq 0 -and (Test-Path -LiteralPath $reportPath)) {
            $partialReport = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            if (($partialReport.mixed_port -is [int] -or $partialReport.mixed_port -is [long]) -and $partialReport.mixed_port -ge 1 -and $partialReport.mixed_port -le 65535) {
                $mixedPort = [int]$partialReport.mixed_port
                $evidence.mixed_port = $mixedPort
            }
        }
        if ($mixedPort -ne 0) {
            $listeners = Get-LoopbackListeners $mixedPort
            $evidence.tcp_loopback_listeners_remaining = $listeners.tcp
            $evidence.udp_loopback_listeners_remaining = $listeners.udp
            if ($listeners.tcp -ne 0 -or $listeners.udp -ne 0) { Add-SupervisorFailure 'remaining_listeners' }
        }
    } catch { Add-SupervisorFailure 'listener_cleanup_verification' $_ }
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process') }
    foreach ($process in $owned.Values) { $process.Dispose() }
    if ($failures.Count -eq 0 -and $evidence.native_cleanup_verified -and $evidence.proxy_matches_snapshot) { $evidence.status = 'passed' }
    $evidence.failures = @($failures.ToArray())
    $evidence.errors = @($failureDetails.ToArray())
    [IO.File]::WriteAllText($supervisorPath, ($evidence | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}
if ($evidence.status -cne 'passed') { throw 'Native startup verification failed; inspect supervisor-report.json and native probe artifacts' }
Write-Host 'Native startup probe passed; owned processes and listeners are gone, and WinINet proxy settings are restored'
