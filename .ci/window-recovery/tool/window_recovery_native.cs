using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace FengWoWindowRecovery
{
    public sealed class Rect
    {
        public int Left { get; set; }
        public int Top { get; set; }
        public int Right { get; set; }
        public int Bottom { get; set; }
        public int Width { get { return (int)Math.Max(0L, Math.Min(Int32.MaxValue, (long)Right - Left)); } }
        public int Height { get { return (int)Math.Max(0L, Math.Min(Int32.MaxValue, (long)Bottom - Top)); } }
    }

    public sealed class MonitorSnapshot
    {
        public string Handle { get; set; }
        public string Device { get; set; }
        public bool Primary { get; set; }
        public Rect Bounds { get; set; }
        public Rect WorkArea { get; set; }
    }

    public sealed class ProcessSnapshot
    {
        public int ProcessId { get; set; }
        public int SessionId { get; set; }
        public string ProcessName { get; set; }
        public string Integrity { get; set; }
    }

    public sealed class WindowSnapshot
    {
        public string Handle { get; set; }
        public int ProcessId { get; set; }
        public int SessionId { get; set; }
        public string ProcessName { get; set; }
        public string ClassName { get; set; }
        public Rect Rect { get; set; }
        public Rect NormalRect { get; set; }
        public bool Visible { get; set; }
        public bool Minimized { get; set; }
        public bool Hung { get; set; }
        public string Integrity { get; set; }
        public int RectLastError { get; set; }
        public int PlacementLastError { get; set; }
        public bool? DwmCloaked { get; set; }
        public uint? DwmCloakFlags { get; set; }
        public int DwmQueryHResult { get; set; }
    }

    public sealed class DpiState
    {
        public string Requested { get; set; }
        public string PreviousContext { get; set; }
        public bool Applied { get; set; }
        public int ApplyLastError { get; set; }
        public bool Restored { get; set; }
        public int RestoreLastError { get; set; }
        public string Error { get; set; }
    }

    public sealed class NativeCall
    {
        public bool Attempted { get; set; }
        public bool Returned { get; set; }
        public int LastError { get; set; }
        public string Error { get; set; }
    }

    public sealed class SnapshotReport
    {
        public string Utc { get; set; }
        public int CurrentProcessId { get; set; }
        public int CurrentSessionId { get; set; }
        public string CurrentIntegrityLevel { get; set; }
        public DpiState Dpi { get; set; }
        public List<MonitorSnapshot> Monitors { get; set; }
        public List<ProcessSnapshot> Processes { get; set; }
        public List<WindowSnapshot> Windows { get; set; }
        public string[] Errors { get; set; }
    }

    public sealed class RecoveryAttempt
    {
        public string Utc { get; set; }
        public int ExpectedProcessId { get; set; }
        public string WindowHandle { get; set; }
        public WindowSnapshot Before { get; set; }
        public WindowSnapshot After { get; set; }
        public MonitorSnapshot PrimaryMonitor { get; set; }
        public Rect RequestedRect { get; set; }
        public DpiState Dpi { get; set; }
        public NativeCall ShowWindowAsync { get; set; }
        public NativeCall SetWindowPos { get; set; }
        public NativeCall SetForegroundWindow { get; set; }
        public string[] Errors { get; set; }
    }

    public static class NativeProbe
    {
        private const string TargetClass = "FLUTTER_RUNNER_WIN32_WINDOW";
        private const string TargetName = "FengWo.exe";

        public static SnapshotReport Capture()
        {
            List<string> errors = new List<string>();
            SnapshotReport result = new SnapshotReport
            {
                Utc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                CurrentProcessId = (int)GetCurrentProcessId(),
                Monitors = new List<MonitorSnapshot>(),
                Processes = new List<ProcessSnapshot>(),
                Windows = new List<WindowSnapshot>()
            };
            using (DpiScope dpi = new DpiScope())
            {
                result.Dpi = dpi.State;
                try
                {
                    result.CurrentSessionId = CurrentSessionId();
                    result.CurrentIntegrityLevel = GetIntegrityLevel(result.CurrentProcessId);
                    result.Monitors = CaptureMonitors(errors);
                    result.Processes = CaptureProcesses(result.CurrentSessionId, errors);
                    result.Windows = CaptureWindows(result.CurrentSessionId, errors);
                }
                catch (Exception exception)
                {
                    errors.Add("Capture: " + ErrorText(exception));
                }
            }
            result.Errors = errors.ToArray();
            return result;
        }

        public static RecoveryAttempt Recover(string windowHandle)
        {
            IntPtr handle = ParseHandle(windowHandle);
            uint pid;
            GetWindowThreadProcessId(handle, out pid);
            if (pid == 0 || pid > Int32.MaxValue) throw new InvalidOperationException("The window process is unavailable.");
            return Recover((int)pid, windowHandle);
        }

        public static RecoveryAttempt Recover(int processId, string windowHandle)
        {
            List<string> errors = new List<string>();
            RecoveryAttempt result = new RecoveryAttempt
            {
                Utc = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
                ExpectedProcessId = processId,
                WindowHandle = windowHandle,
                ShowWindowAsync = new NativeCall(),
                SetWindowPos = new NativeCall(),
                SetForegroundWindow = new NativeCall()
            };
            using (DpiScope dpi = new DpiScope())
            {
                result.Dpi = dpi.State;
                IntPtr handle = IntPtr.Zero;
                int sessionId = -1;
                try
                {
                    if (processId <= 0) throw new ArgumentOutOfRangeException("processId");
                    handle = ParseHandle(windowHandle);
                    sessionId = CurrentSessionId();
                    result.Before = ReadTarget(handle, processId, sessionId);
                    List<MonitorSnapshot> monitors = CaptureMonitors(errors);
                    foreach (MonitorSnapshot monitor in monitors)
                    {
                        if (monitor.Primary)
                        {
                            result.PrimaryMonitor = monitor;
                            break;
                        }
                    }
                    if (result.PrimaryMonitor == null) throw new InvalidOperationException("No active primary monitor was found.");
                    Rect area = result.PrimaryMonitor.WorkArea;
                    if (area == null || area.Width <= 0 || area.Height <= 0) throw new InvalidOperationException("The primary work area is invalid.");
                    Rect existing = result.Before.Minimized && result.Before.NormalRect != null ? result.Before.NormalRect : result.Before.Rect;
                    int width = Math.Min(area.Width, Math.Max(640, existing == null || existing.Width == 0 ? 960 : existing.Width));
                    int height = Math.Min(area.Height, Math.Max(480, existing == null || existing.Height == 0 ? 600 : existing.Height));
                    int left = area.Left + (area.Width - width) / 2;
                    int top = area.Top + (area.Height - height) / 2;
                    result.RequestedRect = new Rect { Left = left, Top = top, Right = left + width, Bottom = top + height };
                    ValidateTarget(handle, processId, sessionId);
                    SetLastError(0);
                    result.ShowWindowAsync.Attempted = true;
                    result.ShowWindowAsync.Returned = ShowWindowAsync(handle, 9);
                    result.ShowWindowAsync.LastError = Marshal.GetLastWin32Error();
                    ValidateTarget(handle, processId, sessionId);
                    SetLastError(0);
                    result.SetWindowPos.Attempted = true;
                    result.SetWindowPos.Returned = SetWindowPos(handle, IntPtr.Zero, left, top, width, height, 0x4000 | 0x0040 | 0x0200 | 0x0010);
                    result.SetWindowPos.LastError = Marshal.GetLastWin32Error();
                    ValidateTarget(handle, processId, sessionId);
                    if (IsHungAppWindow(handle))
                    {
                        result.SetForegroundWindow.Error = "Skipped because the target window is reported hung.";
                    }
                    else
                    {
                        SetLastError(0);
                        result.SetForegroundWindow.Attempted = true;
                        result.SetForegroundWindow.Returned = SetForegroundWindow(handle);
                        result.SetForegroundWindow.LastError = Marshal.GetLastWin32Error();
                    }
                }
                catch (Exception exception)
                {
                    errors.Add("Recover: " + ErrorText(exception));
                }
                if (handle != IntPtr.Zero && sessionId >= 0)
                {
                    try
                    {
                        result.After = ReadTarget(handle, processId, sessionId);
                    }
                    catch (Exception exception)
                    {
                        errors.Add("Immediate after snapshot: " + ErrorText(exception));
                    }
                }
            }
            result.Errors = errors.ToArray();
            return result;
        }

        private static List<ProcessSnapshot> CaptureProcesses(int sessionId, List<string> errors)
        {
            List<ProcessSnapshot> result = new List<ProcessSnapshot>();
            Process[] processes;
            try
            {
                processes = Process.GetProcessesByName("FengWo");
            }
            catch (Exception exception)
            {
                errors.Add("Process enumeration: " + ErrorText(exception));
                return result;
            }
            foreach (Process process in processes)
            {
                int pid = 0;
                try
                {
                    pid = process.Id;
                    if (process.SessionId != sessionId) continue;
                    string matchError;
                    if (!MatchesProcess((uint)pid, sessionId, out matchError))
                    {
                        if (matchError != null) errors.Add(matchError);
                        continue;
                    }
                    result.Add(new ProcessSnapshot { ProcessId = pid, SessionId = sessionId, ProcessName = TargetName, Integrity = GetIntegrityLevel(pid) });
                }
                catch (Exception exception)
                {
                    errors.Add("Process " + pid.ToString(CultureInfo.InvariantCulture) + ": " + ErrorText(exception));
                }
                finally
                {
                    process.Dispose();
                }
            }
            return result;
        }

        private static List<WindowSnapshot> CaptureWindows(int sessionId, List<string> errors)
        {
            List<WindowSnapshot> result = new List<WindowSnapshot>();
            EnumWindowsCallback callback = delegate(IntPtr handle, IntPtr parameter)
            {
                try
                {
                    uint pid;
                    GetWindowThreadProcessId(handle, out pid);
                    if (pid != 0 && pid <= Int32.MaxValue && MatchesClass(handle) && MatchesProcess(pid, sessionId))
                    {
                        result.Add(ReadTarget(handle, (int)pid, sessionId));
                    }
                }
                catch (Exception exception)
                {
                    errors.Add("Window " + FormatHandle(handle) + ": " + ErrorText(exception));
                }
                return true;
            };
            SetLastError(0);
            if (!EnumWindows(callback, IntPtr.Zero)) errors.Add("EnumWindows failed: " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
            return result;
        }

        private static List<MonitorSnapshot> CaptureMonitors(List<string> errors)
        {
            List<MonitorSnapshot> result = new List<MonitorSnapshot>();
            MonitorEnumCallback callback = delegate(IntPtr monitor, IntPtr deviceContext, ref NativeRect bounds, IntPtr parameter)
            {
                try
                {
                    MonitorInfo info = new MonitorInfo();
                    info.Size = Marshal.SizeOf(typeof(MonitorInfo));
                    SetLastError(0);
                    if (!GetMonitorInfoW(monitor, ref info))
                    {
                        errors.Add("GetMonitorInfo failed: " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        result.Add(new MonitorSnapshot { Handle = FormatHandle(monitor), Device = info.Device, Primary = (info.Flags & 1) != 0, Bounds = ToRect(info.Bounds), WorkArea = ToRect(info.WorkArea) });
                    }
                }
                catch (Exception exception)
                {
                    errors.Add("Monitor snapshot: " + ErrorText(exception));
                }
                return true;
            };
            SetLastError(0);
            if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero)) errors.Add("EnumDisplayMonitors failed: " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture));
            return result;
        }

        private static WindowSnapshot ReadTarget(IntPtr handle, int pid, int sessionId)
        {
            ValidateTarget(handle, pid, sessionId);
            WindowSnapshot result = new WindowSnapshot
            {
                Handle = FormatHandle(handle),
                ProcessId = pid,
                SessionId = sessionId,
                ProcessName = TargetName,
                ClassName = TargetClass,
                Visible = IsWindowVisible(handle),
                Minimized = IsIconic(handle),
                Hung = IsHungAppWindow(handle),
                Integrity = GetIntegrityLevel(pid),
                DwmQueryHResult = -1
            };
            NativeRect rect;
            SetLastError(0);
            if (GetWindowRect(handle, out rect)) result.Rect = ToRect(rect);
            else result.RectLastError = Marshal.GetLastWin32Error();
            WindowPlacement placement = new WindowPlacement();
            placement.Length = Marshal.SizeOf(typeof(WindowPlacement));
            SetLastError(0);
            if (GetWindowPlacement(handle, ref placement)) result.NormalRect = ToRect(placement.NormalPosition);
            else result.PlacementLastError = Marshal.GetLastWin32Error();
            try
            {
                uint cloak;
                result.DwmQueryHResult = DwmGetWindowAttribute(handle, 14, out cloak, 4);
                if (result.DwmQueryHResult == 0)
                {
                    result.DwmCloakFlags = cloak;
                    result.DwmCloaked = cloak != 0;
                }
            }
            catch (EntryPointNotFoundException) { }
            catch (DllNotFoundException) { }
            ValidateTarget(handle, pid, sessionId);
            return result;
        }

        private static void ValidateTarget(IntPtr handle, int expectedPid, int sessionId)
        {
            uint actualPid;
            GetWindowThreadProcessId(handle, out actualPid);
            if (expectedPid <= 0 || actualPid != (uint)expectedPid || !IsWindow(handle) || GetAncestor(handle, 2) != handle || !MatchesClass(handle))
            {
                throw new InvalidOperationException("The handle no longer identifies the specified FengWo Flutter window in the current session.");
            }
            string matchError;
            if (!MatchesProcess(actualPid, sessionId, out matchError))
            {
                throw new InvalidOperationException(matchError ?? "The process image or session no longer matches the recovery target.");
            }
        }

        private static bool MatchesClass(IntPtr handle)
        {
            StringBuilder name = new StringBuilder(256);
            return GetClassNameW(handle, name, name.Capacity) != 0 && String.Equals(name.ToString(), TargetClass, StringComparison.Ordinal);
        }

        private static bool MatchesProcess(uint pid, int sessionId)
        {
            string ignored;
            return MatchesProcess(pid, sessionId, out ignored);
        }

        private static bool MatchesProcess(uint pid, int sessionId, out string matchError)
        {
            matchError = null;
            uint processSession;
            SetLastError(0);
            if (!ProcessIdToSessionId(pid, out processSession))
            {
                matchError = "ProcessIdToSessionId failed for FengWo candidate " + pid.ToString(CultureInfo.InvariantCulture) + " (Win32 " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture) + ").";
                return false;
            }
            if (processSession != (uint)sessionId) return false;
            SetLastError(0);
            IntPtr process = OpenProcess(0x1000, false, pid);
            if (process == IntPtr.Zero)
            {
                matchError = "OpenProcess failed for FengWo candidate " + pid.ToString(CultureInfo.InvariantCulture) + " (Win32 " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture) + ").";
                return false;
            }
            try
            {
                StringBuilder image = new StringBuilder(32768);
                int size = image.Capacity;
                SetLastError(0);
                if (!QueryFullProcessImageNameW(process, 0, image, ref size))
                {
                    matchError = "QueryFullProcessImageName failed for FengWo candidate " + pid.ToString(CultureInfo.InvariantCulture) + " (Win32 " + Marshal.GetLastWin32Error().ToString(CultureInfo.InvariantCulture) + ").";
                    return false;
                }
                return String.Equals(Path.GetFileName(image.ToString()), TargetName, StringComparison.OrdinalIgnoreCase);
            }
            finally
            {
                CloseHandle(process);
            }
        }

        private static int CurrentSessionId()
        {
            uint sessionId;
            if (!ProcessIdToSessionId(GetCurrentProcessId(), out sessionId) || sessionId > Int32.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error(), "Current session is unavailable.");
            return (int)sessionId;
        }

        private static string GetIntegrityLevel(int pid)
        {
            IntPtr process = IntPtr.Zero;
            IntPtr token = IntPtr.Zero;
            IntPtr information = IntPtr.Zero;
            try
            {
                process = OpenProcess(0x1000, false, (uint)pid);
                if (process == IntPtr.Zero || !OpenProcessToken(process, 0x0008, out token)) return "unknown";
                int required;
                if (GetTokenInformation(token, 25, IntPtr.Zero, 0, out required) || Marshal.GetLastWin32Error() != 122 || required < IntPtr.Size + 4 || required > 65536) return "unknown";
                information = Marshal.AllocHGlobal(required);
                int returned;
                if (!GetTokenInformation(token, 25, information, required, out returned) || returned < IntPtr.Size + 4 || returned > required) return "unknown";
                IntPtr sid = Marshal.ReadIntPtr(information);
                long offset = sid.ToInt64() - information.ToInt64();
                if (sid == IntPtr.Zero || offset < 0 || offset > returned - 8) return "unknown";
                int count = Marshal.ReadByte(sid, 1);
                if (count == 0 || offset > returned - (8 + count * 4) || !IsValidSid(sid)) return "unknown";
                uint integrity = unchecked((uint)Marshal.ReadInt32(sid, 8 + (count - 1) * 4));
                if (integrity >= 0x5000) return "protected";
                if (integrity >= 0x4000) return "system";
                if (integrity >= 0x3000) return "high";
                if (integrity >= 0x2100) return "medium-plus";
                if (integrity >= 0x2000) return "medium";
                if (integrity >= 0x1000) return "low";
                return "untrusted";
            }
            catch (Exception) { return "unknown"; }
            finally
            {
                if (information != IntPtr.Zero) Marshal.FreeHGlobal(information);
                if (token != IntPtr.Zero) CloseHandle(token);
                if (process != IntPtr.Zero) CloseHandle(process);
            }
        }

        private static Rect ToRect(NativeRect value)
        {
            return new Rect { Left = value.Left, Top = value.Top, Right = value.Right, Bottom = value.Bottom };
        }

        private static string FormatHandle(IntPtr handle)
        {
            return "0x" + (IntPtr.Size == 8 ? unchecked((ulong)handle.ToInt64()).ToString("X16", CultureInfo.InvariantCulture) : unchecked((uint)handle.ToInt32()).ToString("X8", CultureInfo.InvariantCulture));
        }

        private static IntPtr ParseHandle(string text)
        {
            ulong value;
            if (String.IsNullOrEmpty(text) || !text.StartsWith("0x", StringComparison.OrdinalIgnoreCase) || !UInt64.TryParse(text.Substring(2), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out value) || value == 0 || (IntPtr.Size == 4 && value > UInt32.MaxValue)) throw new ArgumentException("A nonzero hexadecimal window handle is required.", "windowHandle");
            return IntPtr.Size == 8 ? new IntPtr(unchecked((long)value)) : new IntPtr(unchecked((int)(uint)value));
        }

        private static string ErrorText(Exception exception)
        {
            return exception.GetType().Name + ": " + exception.Message;
        }

        private sealed class DpiScope : IDisposable
        {
            internal readonly DpiState State = new DpiState { Requested = "per-monitor-v2" };
            private IntPtr previous;

            internal DpiScope()
            {
                try
                {
                    SetLastError(0);
                    previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
                    State.ApplyLastError = Marshal.GetLastWin32Error();
                    State.Applied = previous != IntPtr.Zero;
                    if (State.Applied) State.PreviousContext = FormatHandle(previous);
                }
                catch (Exception exception)
                {
                    State.Error = ErrorText(exception);
                }
            }

            public void Dispose()
            {
                if (!State.Applied) return;
                try
                {
                    SetLastError(0);
                    State.Restored = SetThreadDpiAwarenessContext(previous) != IntPtr.Zero;
                    State.RestoreLastError = Marshal.GetLastWin32Error();
                }
                catch (Exception exception)
                {
                    State.Error = ErrorText(exception);
                }
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect { internal int Left; internal int Top; internal int Right; internal int Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativePoint { internal int X; internal int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct WindowPlacement
        {
            internal int Length;
            internal uint Flags;
            internal uint ShowCommand;
            internal NativePoint MinPosition;
            internal NativePoint MaxPosition;
            internal NativeRect NormalPosition;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct MonitorInfo
        {
            internal int Size;
            internal NativeRect Bounds;
            internal NativeRect WorkArea;
            internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] internal string Device;
        }

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private delegate bool EnumWindowsCallback(IntPtr handle, IntPtr parameter);

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private delegate bool MonitorEnumCallback(IntPtr monitor, IntPtr deviceContext, ref NativeRect bounds, IntPtr parameter);

        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplayMonitors(IntPtr deviceContext, IntPtr clip, MonitorEnumCallback callback, IntPtr parameter);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMonitorInfoW(IntPtr monitor, ref MonitorInfo info);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern int GetClassNameW(IntPtr handle, StringBuilder name, int maximumLength);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr handle, out NativeRect rect);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowPlacement(IntPtr handle, ref WindowPlacement placement);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr handle);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr handle);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsHungAppWindow(IntPtr handle);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr handle);
        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr handle, uint flags);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindowAsync(IntPtr handle, int command);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr handle);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr handle, uint attribute, out uint value, uint size);
        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentProcessId();
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ProcessIdToSessionId(uint processId, out uint sessionId);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inheritHandle, uint processId);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, StringBuilder name, ref int size);
        [DllImport("kernel32.dll")]
        private static extern void SetLastError(uint error);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(IntPtr token, int informationClass, IntPtr information, int length, out int returnLength);
        [DllImport("advapi32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsValidSid(IntPtr sid);
    }
}
