using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.IO;
using System.Security.Cryptography;

namespace FengWoNetworkCleanupTests
{
    public static class SystemInternetProbe
    {
        [DllImport("wininet.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr InternetOpenW(string agent, uint accessType, string proxy, string bypass, uint flags);
        [DllImport("wininet.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr InternetOpenUrlW(IntPtr session, string url, string headers, uint headerLength, uint flags, UIntPtr context);
        [DllImport("wininet.dll", SetLastError = true)]
        private static extern bool InternetSetOptionW(IntPtr handle, uint option, ref uint value, uint bytes);
        [DllImport("wininet.dll", SetLastError = true)]
        private static extern bool HttpQueryInfoW(IntPtr handle, uint info, ref uint value, ref uint bytes, ref uint index);
        [DllImport("wininet.dll", SetLastError = true)]
        private static extern bool InternetReadFile(IntPtr handle, byte[] buffer, uint capacity, out uint bytes);
        [DllImport("wininet.dll")]
        private static extern bool InternetCloseHandle(IntPtr handle);

        public sealed class Response
        {
            public uint Status { get; set; }
            public long Bytes { get; set; }
            public string Sha256 { get; set; }
        }

        public static Response Fetch(string url)
        {
            if (new Uri(url).Scheme != "https") throw new ArgumentException("HTTPS is required", "url");
            IntPtr session = InternetOpenW("FengWo-native-cleanup-acceptance", 0, null, null, 0);
            if (session == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                uint timeout = 20000;
                foreach (uint option in new uint[] { 2, 5, 6 })
                    if (!InternetSetOptionW(session, option, ref timeout, 4)) throw new Win32Exception(Marshal.GetLastWin32Error());
                IntPtr request = InternetOpenUrlW(session, url, null, 0, 0x80000000u | 0x04000000u | 0x00080000u | 0x00000200u, UIntPtr.Zero);
                if (request == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                try {
                    uint status = 0, length = 4, index = 0;
                    if (!HttpQueryInfoW(request, 19u | 0x20000000u, ref status, ref length, ref index)) throw new Win32Exception(Marshal.GetLastWin32Error());
                    using (MemoryStream body = new MemoryStream()) {
                        byte[] buffer = new byte[8192];
                        uint count;
                        do {
                            if (!InternetReadFile(request, buffer, (uint)buffer.Length, out count)) throw new Win32Exception(Marshal.GetLastWin32Error());
                            body.Write(buffer, 0, (int)count);
                            if (body.Length > 1024 * 1024) throw new InvalidOperationException("Unexpected network probe payload size");
                        } while (count != 0);
                        using (SHA256 sha = SHA256.Create())
                            return new Response { Status = status, Bytes = body.Length, Sha256 = BitConverter.ToString(sha.ComputeHash(body.ToArray())).Replace("-", "").ToLowerInvariant() };
                    }
                } finally { InternetCloseHandle(request); }
            } finally { InternetCloseHandle(session); }
        }
    }

    public static class TrayCommand
    {
        private delegate bool EnumCallback(IntPtr window, IntPtr parameter);
        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumCallback callback, IntPtr parameter);
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr window, StringBuilder name, int count);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindow(string className, string title);
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
        [DllImport("user32.dll")]
        private static extern int GetMenuItemCount(IntPtr menu);
        [DllImport("user32.dll")]
        private static extern uint GetMenuItemID(IntPtr menu, int position);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetMenuString(IntPtr menu, uint item, StringBuilder text, int count, uint flags);

        public static string Exit(int processId)
        {
            IntPtr owned = IntPtr.Zero;
            EnumWindows((window, _) => {
                uint pid;
                GetWindowThreadProcessId(window, out pid);
                StringBuilder name = new StringBuilder(256);
                GetClassName(window, name, name.Capacity);
                if (pid == processId && name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") { owned = window; return false; }
                return true;
            }, IntPtr.Zero);
            if (owned == IntPtr.Zero) throw new InvalidOperationException("Owned Flutter window not found");
            if (!PostMessage(owned, 0x401, IntPtr.Zero, new IntPtr(0x205)))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr menu = IntPtr.Zero;
            for (int attempt = 0; attempt < 100; attempt++) {
                IntPtr popup = FindWindow("#32768", null);
                uint pid;
                GetWindowThreadProcessId(popup, out pid);
                if (pid == processId) menu = SendMessage(popup, 0x1e1, IntPtr.Zero, IntPtr.Zero);
                if (menu != IntPtr.Zero) break;
                Thread.Sleep(100);
            }
            if (menu == IntPtr.Zero) throw new InvalidOperationException("Native tray context menu did not open");
            int last = GetMenuItemCount(menu) - 1;
            StringBuilder label = new StringBuilder(256);
            GetMenuString(menu, (uint)last, label, label.Capacity, 0x400);
            string value = label.ToString();
            if (value != "Exit" && value != "exit" && value != "\u9000\u51fa")
                throw new InvalidOperationException("Last native tray item is not Exit: " + value);
            uint id = GetMenuItemID(menu, last);
            SendMessage(owned, 0x1f, IntPtr.Zero, IntPtr.Zero);
            if (!PostMessage(owned, 0x111, new IntPtr(id), IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return value;
        }
    }
}
