using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace FengWoNetworkCleanupTests
{
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
