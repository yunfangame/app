using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace FengWoCoexistenceTests
{
    public sealed class ProxyRegistryValue
    {
        public string Path { get; set; }
        public string Name { get; set; }
        public bool Exists { get; set; }
        public string Kind { get; set; }
        public object Value { get; set; }
    }

    public sealed class ProxySnapshot
    {
        public uint Flags { get; set; }
        public string Server { get; set; }
        public string Bypass { get; set; }
        public string Pac { get; set; }
        public ProxyRegistryValue[] Registry { get; set; }
    }

    public sealed class ProxyRestoreResult
    {
        public bool Passed { get; set; }
        public string[] Errors { get; set; }
        public ProxySnapshot Actual { get; set; }
    }

    public sealed class ProxyFixture
    {
        private const string SettingsPath = "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";
        private const uint PerConnectionOption = 75;
        private readonly ProxySnapshot original;
        private bool mutated;

        [StructLayout(LayoutKind.Explicit)]
        private struct OptionValue
        {
            [FieldOffset(0)] public uint Number;
            [FieldOffset(0)] public IntPtr Text;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Option
        {
            public uint Kind;
            public OptionValue Value;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct OptionList
        {
            public uint Size;
            public IntPtr Connection;
            public uint Count;
            public uint Error;
            public IntPtr Options;
        }

        [DllImport("wininet.dll", EntryPoint = "InternetQueryOptionW", SetLastError = true)]
        private static extern bool Query(IntPtr handle, uint option, ref OptionList value, ref uint bytes);
        [DllImport("wininet.dll", EntryPoint = "InternetSetOptionW", SetLastError = true)]
        private static extern bool Set(IntPtr handle, uint option, ref OptionList value, uint bytes);
        [DllImport("wininet.dll", EntryPoint = "InternetSetOptionW", SetLastError = true)]
        private static extern bool Notify(IntPtr handle, uint option, IntPtr value, uint bytes);
        [DllImport("kernel32.dll")]
        private static extern IntPtr GlobalFree(IntPtr memory);

        public ProxyFixture(string architecture = "arm64")
        {
            string runnerArchitecture;
            if (architecture == "arm64") runnerArchitecture = "ARM64";
            else if (architecture == "x64") runnerArchitecture = "X64";
            else throw new ArgumentException("Unsupported native fixture architecture", "architecture");
            if (Environment.OSVersion.Platform != PlatformID.Win32NT ||
                Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true" ||
                !String.Equals(Environment.GetEnvironmentVariable("RUNNER_ARCH"), runnerArchitecture, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("An isolated native " + runnerArchitecture + " GitHub Actions Windows runner is required");
            original = Capture();
        }

        public ProxySnapshot Original { get { return original; } }

        private static OptionList Allocate(uint flagsKind)
        {
            int optionBytes = Marshal.SizeOf(typeof(Option));
            OptionList list = new OptionList {
                Size = (uint)Marshal.SizeOf(typeof(OptionList)), Count = 4,
                Options = Marshal.AllocHGlobal(optionBytes * 4)
            };
            uint[] kinds = { flagsKind, 2, 3, 4 };
            for (int index = 0; index < kinds.Length; index++)
                Marshal.StructureToPtr(new Option { Kind = kinds[index] }, IntPtr.Add(list.Options, index * optionBytes), false);
            return list;
        }

        private static Option ReadOption(OptionList list, int index)
        {
            return (Option)Marshal.PtrToStructure(IntPtr.Add(list.Options, index * Marshal.SizeOf(typeof(Option))), typeof(Option));
        }

        private static string ReadText(OptionList list, int index)
        {
            return Marshal.PtrToStringUni(ReadOption(list, index).Value.Text) ?? String.Empty;
        }

        private static void FreeQuery(OptionList list)
        {
            for (int index = 1; index < 4; index++)
            {
                IntPtr value = ReadOption(list, index).Value.Text;
                if (value != IntPtr.Zero) GlobalFree(value);
            }
            Marshal.FreeHGlobal(list.Options);
        }

        private static ProxyRegistryValue ReadRegistry(string path, string name)
        {
            using (RegistryKey root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
            using (RegistryKey key = root.OpenSubKey(path))
            {
                bool exists = key != null && Array.Exists(key.GetValueNames(), value => String.Equals(value, name, StringComparison.OrdinalIgnoreCase));
                return new ProxyRegistryValue {
                    Path = path, Name = name, Exists = exists,
                    Kind = exists ? key.GetValueKind(name).ToString() : null,
                    Value = exists ? key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) : null
                };
            }
        }

        public ProxySnapshot Capture()
        {
            OptionList list = Allocate(10);
            try
            {
                uint bytes = list.Size;
                if (!Query(IntPtr.Zero, PerConnectionOption, ref list, ref bytes))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot read native WinINet proxy snapshot");
                List<ProxyRegistryValue> values = new List<ProxyRegistryValue>();
                foreach (string name in new[] { "ProxyEnable", "ProxyServer", "ProxyOverride", "AutoConfigURL", "AutoDetect" })
                    values.Add(ReadRegistry(SettingsPath, name));
                foreach (string name in new[] { "DefaultConnectionSettings", "SavedLegacySettings" })
                    values.Add(ReadRegistry(SettingsPath + "\\Connections", name));
                return new ProxySnapshot {
                    Flags = ReadOption(list, 0).Value.Number,
                    Server = ReadText(list, 1), Bypass = ReadText(list, 2), Pac = ReadText(list, 3),
                    Registry = values.ToArray()
                };
            }
            finally { FreeQuery(list); }
        }

        private static void Refresh()
        {
            int firstError = 0;
            bool failed = false;
            if (!Notify(IntPtr.Zero, 39, IntPtr.Zero, 0)) { firstError = Marshal.GetLastWin32Error(); failed = true; }
            if (!Notify(IntPtr.Zero, 37, IntPtr.Zero, 0))
            {
                if (!failed) firstError = Marshal.GetLastWin32Error();
                failed = true;
            }
            if (failed) throw new Win32Exception(firstError, "Native proxy refresh failed");
        }

        private static void Apply(ProxySnapshot snapshot)
        {
            OptionList list = Allocate(1);
            List<IntPtr> strings = new List<IntPtr>();
            try
            {
                Option flags = ReadOption(list, 0);
                flags.Value.Number = snapshot.Flags;
                Marshal.StructureToPtr(flags, list.Options, false);
                string[] texts = { snapshot.Server, snapshot.Bypass, snapshot.Pac };
                for (int index = 1; index < 4; index++)
                {
                    Option value = ReadOption(list, index);
                    value.Value.Text = Marshal.StringToHGlobalUni(texts[index - 1] ?? String.Empty);
                    strings.Add(value.Value.Text);
                    Marshal.StructureToPtr(value, IntPtr.Add(list.Options, index * Marshal.SizeOf(typeof(Option))), false);
                }
                if (!Set(IntPtr.Zero, PerConnectionOption, ref list, list.Size))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot apply native WinINet proxy fixture");
                Refresh();
            }
            finally
            {
                foreach (IntPtr value in strings) Marshal.FreeHGlobal(value);
                Marshal.FreeHGlobal(list.Options);
            }
        }

        public ProxySnapshot SetDirect()
        {
            mutated = true;
            Apply(new ProxySnapshot { Flags = 1, Server = String.Empty, Bypass = String.Empty, Pac = String.Empty });
            ProxySnapshot actual = Capture();
            if ((actual.Flags & 2) != 0) throw new InvalidOperationException("Isolated direct baseline was not applied");
            return actual;
        }

        public ProxySnapshot SetForeign(int port)
        {
            if (port != 7890) throw new ArgumentOutOfRangeException("port");
            mutated = true;
            Apply(new ProxySnapshot { Flags = 3, Server = "127.0.0.1:7890", Bypass = "localhost;127.0.0.1;[::1];*.flclash-fixture.invalid;<local>", Pac = String.Empty });
            ProxySnapshot actual = Capture();
            if (actual.Flags != 3 || actual.Server != "127.0.0.1:7890" || actual.Pac != String.Empty)
                throw new InvalidOperationException("The synthetic same-port system proxy did not verify");
            ProxyRegistryValue enabled = actual.Registry[0];
            ProxyRegistryValue server = actual.Registry[1];
            if (!enabled.Exists || enabled.Kind != "DWord" || Convert.ToInt32(enabled.Value) != 1 ||
                !server.Exists || server.Kind != "String" || (string)server.Value != actual.Server)
                throw new InvalidOperationException("Native proxy and HKCU readback differ");
            return actual;
        }

        public static bool Same(ProxySnapshot left, ProxySnapshot right)
        {
            if (left == null || right == null || left.Flags != right.Flags || left.Server != right.Server ||
                left.Bypass != right.Bypass || left.Pac != right.Pac || left.Registry == null || right.Registry == null ||
                left.Registry.Length != right.Registry.Length) return false;
            for (int index = 0; index < left.Registry.Length; index++)
            {
                ProxyRegistryValue first = left.Registry[index], second = right.Registry[index];
                if (first.Path != second.Path || first.Name != second.Name || first.Exists != second.Exists || first.Kind != second.Kind ||
                    !StructuralComparisons.StructuralEqualityComparer.Equals(first.Value, second.Value)) return false;
            }
            return true;
        }

        private static void RestoreRegistry(ProxyRegistryValue value)
        {
            using (RegistryKey root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64))
            {
                if (value.Exists)
                {
                    using (RegistryKey key = root.CreateSubKey(value.Path))
                        key.SetValue(value.Name, value.Value, (RegistryValueKind)Enum.Parse(typeof(RegistryValueKind), value.Kind));
                }
                else
                {
                    using (RegistryKey key = root.OpenSubKey(value.Path, true))
                        if (key != null) key.DeleteValue(value.Name, false);
                }
            }
        }

        public ProxyRestoreResult Restore()
        {
            List<string> errors = new List<string>();
            if (mutated)
            {
                try { Apply(original); } catch (Exception error) { errors.Add(error.Message); }
                foreach (ProxyRegistryValue value in original.Registry)
                    try { RestoreRegistry(value); } catch (Exception error) { errors.Add(value.Path + "\\" + value.Name + ": " + error.Message); }
                try { Refresh(); } catch (Exception error) { errors.Add(error.Message); }
            }
            ProxySnapshot actual = null;
            try
            {
                actual = Capture();
                if (!Same(original, actual)) errors.Add("Original WinINet and typed HKCU fields did not fully restore");
            }
            catch (Exception error) { errors.Add(error.Message); }
            bool passed = errors.Count == 0;
            if (passed) mutated = false;
            return new ProxyRestoreResult { Passed = passed, Errors = errors.ToArray(), Actual = actual };
        }
    }
}
