using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

public sealed class FengWoIsolatedProxySnapshot : IDisposable
{
    [StructLayout(LayoutKind.Explicit)]
    private struct OptionValue
    {
        [FieldOffset(0)] public uint Number;
        [FieldOffset(0)] public IntPtr Text;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct NativeOption
    {
        public uint Option;
        public OptionValue Value;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct NativeList
    {
        public uint Size;
        public IntPtr Connection;
        public uint Count;
        public uint Error;
        public IntPtr Options;
    }
    private sealed class Settings
    {
        public uint Flags;
        public string Server;
        public string Bypass;
        public string Pac;
        public string Fingerprint()
        {
            using (var sha = SHA256.Create())
            {
                var value = Flags.ToString() + "\n" + Server + "\n" + Bypass + "\n" + Pac;
                return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-", "").ToLowerInvariant();
            }
        }
    }
    [DllImport("wininet.dll", EntryPoint="InternetQueryOptionA", SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)]
    private static extern bool Query(IntPtr handle, uint option, ref NativeList value, ref uint length);
    [DllImport("wininet.dll", EntryPoint="InternetSetOptionA", SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)]
    private static extern bool Set(IntPtr handle, uint option, ref NativeList value, uint length);
    [DllImport("wininet.dll", EntryPoint="InternetSetOptionW", SetLastError=true)]
    [return:MarshalAs(UnmanagedType.Bool)]
    private static extern bool Notify(IntPtr handle, uint option, IntPtr value, uint length);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GlobalFree(IntPtr value);

    private readonly Settings original;
    private bool restored;
    public string BeforeFingerprint { get; private set; }
    public string AfterFingerprint { get; private set; }
    public bool Restored { get { return restored; } }

    public FengWoIsolatedProxySnapshot()
    {
        if (Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true" || Environment.GetEnvironmentVariable("FENGWO_PROXY_MUTATING_TEST") != "1")
            throw new InvalidOperationException("ISOLATED_WINDOWS_CI_REQUIRED");
        original = Read();
        BeforeFingerprint = original.Fingerprint();
    }
    private static Settings Read()
    {
        int size = Marshal.SizeOf(typeof(NativeOption));
        IntPtr memory = Marshal.AllocHGlobal(size * 4);
        try
        {
            for (int i = 0; i < 4; i++)
            {
                var option = new NativeOption(); option.Option = (uint)(i + 1);
                Marshal.StructureToPtr(option, IntPtr.Add(memory, i * size), false);
            }
            var list = new NativeList(); list.Size = (uint)Marshal.SizeOf(typeof(NativeList)); list.Count = 4; list.Options = memory;
            uint length = list.Size;
            if (!Query(IntPtr.Zero, 75, ref list, ref length)) throw new Win32Exception(Marshal.GetLastWin32Error(), "WININET_SNAPSHOT_QUERY_FAILED");
            var values = new NativeOption[4];
            for (int i = 0; i < 4; i++) values[i] = (NativeOption)Marshal.PtrToStructure(IntPtr.Add(memory, i * size), typeof(NativeOption));
            return new Settings { Flags=values[0].Value.Number, Server=Marshal.PtrToStringAnsi(values[1].Value.Text) ?? "", Bypass=Marshal.PtrToStringAnsi(values[2].Value.Text) ?? "", Pac=Marshal.PtrToStringAnsi(values[3].Value.Text) ?? "" };
        }
        finally
        {
            for (int i = 1; i < 4; i++)
            {
                var value = (NativeOption)Marshal.PtrToStructure(IntPtr.Add(memory, i * size), typeof(NativeOption));
                if (value.Value.Text != IntPtr.Zero) GlobalFree(value.Value.Text);
            }
            Marshal.FreeHGlobal(memory);
        }
    }
    private static void Write(Settings settings)
    {
        int size = Marshal.SizeOf(typeof(NativeOption));
        IntPtr memory = Marshal.AllocHGlobal(size * 4);
        var strings = new IntPtr[3];
        try
        {
            strings[0] = Marshal.StringToHGlobalAnsi(settings.Server); strings[1] = Marshal.StringToHGlobalAnsi(settings.Bypass); strings[2] = Marshal.StringToHGlobalAnsi(settings.Pac);
            for (int i = 0; i < 4; i++)
            {
                var option = new NativeOption(); option.Option = (uint)(i + 1);
                if (i == 0) option.Value.Number = settings.Flags; else option.Value.Text = strings[i - 1];
                Marshal.StructureToPtr(option, IntPtr.Add(memory, i * size), false);
            }
            var list = new NativeList(); list.Size = (uint)Marshal.SizeOf(typeof(NativeList)); list.Count = 4; list.Options = memory;
            if (!Set(IntPtr.Zero, 75, ref list, list.Size)) throw new Win32Exception(Marshal.GetLastWin32Error(), "WININET_SNAPSHOT_RESTORE_FAILED");
            if (!Notify(IntPtr.Zero, 39, IntPtr.Zero, 0) || !Notify(IntPtr.Zero, 37, IntPtr.Zero, 0)) throw new Win32Exception(Marshal.GetLastWin32Error(), "WININET_SNAPSHOT_NOTIFY_FAILED");
        }
        finally
        {
            foreach (var value in strings) if (value != IntPtr.Zero) Marshal.FreeHGlobal(value);
            Marshal.FreeHGlobal(memory);
        }
    }
    public bool RestoreAndVerify()
    {
        Write(original);
        AfterFingerprint = Read().Fingerprint();
        restored = BeforeFingerprint == AfterFingerprint;
        return restored;
    }
    public void Dispose()
    {
        if (!restored) RestoreAndVerify();
    }
}
