using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace FengWoRealWindowsTests {
    public sealed class ProbeResponse {
        public int Status;
        public string Body;
    }
    public sealed class ForcedProxy : IWebProxy {
        private readonly Uri address;
        public ForcedProxy(int port) { address = new Uri("http://127.0.0.1:" + port); }
        public ICredentials Credentials { get; set; }
        public Uri GetProxy(Uri destination) { return address; }
        public bool IsBypassed(Uri destination) { return false; }
    }
    public static class HttpProbe {
        public static ProbeResponse Get(string url, string caseName, int timeoutSeconds, int proxyPort) {
            using (var handler = new HttpClientHandler { UseProxy = true, Proxy = new ForcedProxy(proxyPort) })
            using (var client = new HttpClient(handler))
            using (var request = new HttpRequestMessage(HttpMethod.Get, url)) {
                client.Timeout = TimeSpan.FromSeconds(timeoutSeconds);
                request.Headers.Add("X-FengWo-Chain-Case", caseName);
                using (var response = client.SendAsync(request).GetAwaiter().GetResult()) {
                    return new ProbeResponse { Status = (int)response.StatusCode, Body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult() };
                }
            }
        }
    }
    public sealed class CorePipe : IDisposable {
        private readonly NamedPipeServerStream pipe;
        private readonly Task connection;
        public readonly string SessionId;
        public readonly string Address;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint processId);

        public CorePipe(string product) {
            if (product != "FengWo" && product != "FlClash") throw new ArgumentException("Unknown isolated Core product");
            SessionId = Guid.NewGuid().ToString("N");
            string name = product + "Core_" + SessionId;
            Address = @"\\.\pipe\" + name;
            pipe = new NamedPipeServerStream(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
            connection = Task.Factory.FromAsync(pipe.BeginWaitForConnection, pipe.EndWaitForConnection, null);
        }

        public uint Accept(int expectedPid, int timeoutMilliseconds) {
            if (!connection.Wait(timeoutMilliseconds)) throw new TimeoutException("Owned Core did not connect to its named pipe");
            uint processId;
            if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out processId)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            if (processId != expectedPid) throw new InvalidOperationException("Named pipe peer is not the owned Core process");
            return processId;
        }

        public void Send(string json) {
            byte[] payload = Encoding.UTF8.GetBytes(json);
            byte[] prefix = BitConverter.GetBytes((uint)payload.Length);
            pipe.Write(prefix, 0, prefix.Length);
            pipe.Write(payload, 0, payload.Length);
            pipe.Flush();
        }

        private byte[] ReadExact(int length, Stopwatch watch, int timeoutMilliseconds) {
            byte[] data = new byte[length];
            int offset = 0;
            while (offset < data.Length) {
                int remaining = timeoutMilliseconds - (int)watch.ElapsedMilliseconds;
                if (remaining <= 0) throw new TimeoutException("Owned Core frame timed out");
                Task<int> read = pipe.ReadAsync(data, offset, data.Length - offset);
                if (!read.Wait(remaining)) throw new TimeoutException("Owned Core frame timed out");
                if (read.Result <= 0) throw new EndOfStreamException("Owned Core closed the pipe");
                offset += read.Result;
            }
            return data;
        }

        public string Receive(int timeoutMilliseconds) {
            Stopwatch watch = Stopwatch.StartNew();
            byte[] prefix = ReadExact(4, watch, timeoutMilliseconds);
            uint length = BitConverter.ToUInt32(prefix, 0);
            if (length > 4 * 1024 * 1024) throw new InvalidDataException("Core fixture response exceeds its bound");
            return Encoding.UTF8.GetString(ReadExact((int)length, watch, timeoutMilliseconds));
        }

        public void Dispose() {
            pipe.Dispose();
        }
    }

}

namespace FengWoRealWindowsTests {
    public sealed class WindowRecord {
        public long Handle;
        public string ClassName;
        public string Title;
        public bool Visible;
        public int Width;
        public int Height;
    }
    public static class Windows {
        private delegate bool Callback(IntPtr window, IntPtr parameter);
        [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] private static extern bool EnumWindows(Callback callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)] private static extern int GetClassNameW(IntPtr window, StringBuilder name, int capacity);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)] private static extern int GetWindowTextW(IntPtr window, StringBuilder name, int capacity);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool PostMessageW(IntPtr window, uint message, IntPtr first, IntPtr second);
        public static WindowRecord[] Snapshot(int pid) {
            var records = new System.Collections.Generic.List<WindowRecord>();
            EnumWindows((window, parameter) => {
                uint owner; GetWindowThreadProcessId(window, out owner);
                if (owner != pid) return true;
                var className = new StringBuilder(256);
                GetClassNameW(window, className, className.Capacity);
                if (className.ToString() != "FLUTTER_RUNNER_WIN32_WINDOW" && className.ToString() != "FENGWO_RUNNER_WIN32_WINDOW") return true;
                var title = new StringBuilder(512); GetWindowTextW(window, title, title.Capacity);
                Rect rect; if (!GetWindowRect(window, out rect)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                records.Add(new WindowRecord {Handle=window.ToInt64(),ClassName=className.ToString(),Title=title.ToString(),Visible=IsWindowVisible(window),Width=rect.Right-rect.Left,Height=rect.Bottom-rect.Top});
                return true;
            }, IntPtr.Zero);
            return records.ToArray();
        }
        public static bool Close(int pid, long handle) {
            uint owner; GetWindowThreadProcessId(new IntPtr(handle), out owner);
            return owner == pid && PostMessageW(new IntPtr(handle), 0x10, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
