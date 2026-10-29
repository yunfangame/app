using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

public static class FengWoShellLinkFixture {
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW {
        [PreserveSig] int GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int capacity, IntPtr findData, uint flags);
        [PreserveSig] int GetIDList(out IntPtr idList);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SHGetPathFromIDListEx(IntPtr idList, StringBuilder path, uint capacity, uint flags);

    public static string ReadTarget(string filename) {
        object instance = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
        try {
            ((IPersistFile)instance).Load(filename, 0);
            var link = (IShellLinkW)instance;
            var path = new StringBuilder(32768);
            Marshal.ThrowExceptionForHR(link.GetPath(path, path.Capacity, IntPtr.Zero, 4));
            if (path.Length > 0) return path.ToString();
            IntPtr idList;
            Marshal.ThrowExceptionForHR(link.GetIDList(out idList));
            if (idList == IntPtr.Zero) return "";
            try {
                return SHGetPathFromIDListEx(idList, path, (uint)path.Capacity, 0) ? path.ToString() : "";
            } finally { Marshal.FreeCoTaskMem(idList); }
        } finally { Marshal.FinalReleaseComObject(instance); }
    }
}
