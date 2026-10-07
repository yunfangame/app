using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace SyntheticRecoveryFixture
{
    public sealed class WindowState
    {
        public long Handle { get; set; }
        public uint ProcessId { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
        public bool Minimized { get; set; }
        public bool Hung { get; set; }
        public bool? DwmCloaked { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Right { get; set; }
        public int Bottom { get; set; }
    }

    public static class Program
    {
        private delegate IntPtr WindowProc(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
        private static readonly WindowProc Procedure = ProcessMessage;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WindowClass
        {
            public uint Size;
            public uint Style;
            public WindowProc Procedure;
            public int ClassExtra;
            public int WindowExtra;
            public IntPtr Instance;
            public IntPtr Icon;
            public IntPtr Cursor;
            public IntPtr Background;
            public string MenuName;
            public string ClassName;
            public IntPtr SmallIcon;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandleW(string name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern ushort RegisterClassExW(ref WindowClass windowClass);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateWindowExW(uint extendedStyle, string className, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
        [DllImport("user32.dll")]
        private static extern IntPtr DefWindowProcW(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr handle, int command);
        [DllImport("user32.dll")]
        private static extern bool UpdateWindow(IntPtr handle);
        [DllImport("user32.dll")]
        private static extern int GetMessageW(IntPtr message, IntPtr window, uint minimum, uint maximum);
        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(IntPtr message);
        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessageW(IntPtr message);
        [DllImport("user32.dll")]
        private static extern void PostQuitMessage(int code);
        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr handle, out NativeRect rectangle);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassNameW(IntPtr handle, StringBuilder name, int maximum);
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr handle);
        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr handle);
        [DllImport("user32.dll")]
        private static extern bool IsHungAppWindow(IntPtr handle);
        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr handle, uint attribute, out uint value, int size);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool SystemParametersInfoW(uint action, uint parameter, out NativeRect rectangle, uint flags);

        private static IntPtr ProcessMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam)
        {
            if (message == 2)
            {
                PostQuitMessage(0);
                return IntPtr.Zero;
            }
            return DefWindowProcW(handle, message, wParam, lParam);
        }

        public static WindowState Describe(long handle)
        {
            IntPtr window = new IntPtr(handle);
            NativeRect rectangle;
            if (!GetWindowRect(window, out rectangle)) throw new InvalidOperationException("Synthetic window rectangle is unavailable");
            StringBuilder name = new StringBuilder(256);
            GetClassNameW(window, name, name.Capacity);
            uint processId;
            GetWindowThreadProcessId(window, out processId);
            uint cloaked;
            int cloakResult = DwmGetWindowAttribute(window, 14, out cloaked, 4);
            return new WindowState
            {
                Handle = handle,
                ProcessId = processId,
                ClassName = name.ToString(),
                Visible = IsWindowVisible(window),
                Minimized = IsIconic(window),
                Hung = IsHungAppWindow(window),
                DwmCloaked = cloakResult == 0 ? (bool?)(cloaked != 0) : null,
                Left = rectangle.Left,
                Top = rectangle.Top,
                Right = rectangle.Right,
                Bottom = rectangle.Bottom
            };
        }

        public static WindowState PrimaryWorkArea()
        {
            NativeRect rectangle;
            if (!SystemParametersInfoW(0x0030, 0, out rectangle, 0)) throw new InvalidOperationException("Primary work area is unavailable");
            return new WindowState { Left = rectangle.Left, Top = rectangle.Top, Right = rectangle.Right, Bottom = rectangle.Bottom };
        }

        public static void SetState(long handle, string state)
        {
            IntPtr window = new IntPtr(handle);
            ShowWindow(window, state == "hidden" ? 0 : state == "minimized" ? 6 : 5);
        }

        [STAThread]
        public static int Main(string[] arguments)
        {
            if (arguments.Length != 3) return 2;
            string className = arguments[0];
            string state = arguments[1];
            IntPtr instance = GetModuleHandleW(null);
            WindowClass windowClass = new WindowClass { Size = (uint)Marshal.SizeOf(typeof(WindowClass)), Procedure = Procedure, Instance = instance, Background = new IntPtr(6), ClassName = className };
            if (RegisterClassExW(ref windowClass) == 0) return 3;
            int x = state == "offscreen" ? GetSystemMetrics(0) + 20000 : 100;
            int y = state == "offscreen" ? GetSystemMetrics(1) + 20000 : 100;
            IntPtr window = CreateWindowExW(0, className, "Synthetic recovery fixture", 0x00CF0000, x, y, 520, 360, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
            if (window == IntPtr.Zero) return 4;
            ShowWindow(window, state == "hidden" ? 0 : state == "minimized" ? 6 : 5);
            UpdateWindow(window);
            File.WriteAllText(arguments[2], "{\"pid\":" + Process.GetCurrentProcess().Id + ",\"handle\":" + window.ToInt64() + "}", new UTF8Encoding(true));
            IntPtr message = Marshal.AllocHGlobal(64);
            try
            {
                while (GetMessageW(message, IntPtr.Zero, 0, 0) > 0)
                {
                    TranslateMessage(message);
                    DispatchMessageW(message);
                }
            }
            finally
            {
                Marshal.FreeHGlobal(message);
            }
            return 0;
        }
    }
}
