using System;
using System.ComponentModel;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;

public static class ChromeNetworkProbe {
    [StructLayout(LayoutKind.Sequential)]
    public struct InternetOption { public uint Option; public IntPtr Value; }
    [StructLayout(LayoutKind.Sequential)]
    public struct InternetOptionList { public uint Size; public IntPtr Connection; public uint Count; public uint Error; public IntPtr Options; }
    [DllImport("wininet.dll", EntryPoint="InternetSetOptionW", SetLastError=true)]
    static extern bool InternetSetOption(IntPtr handle, uint option, IntPtr buffer, uint length);
    [DllImport("wininet.dll", EntryPoint="InternetSetOptionA", SetLastError=true)]
    static extern bool InternetSetOptionAnsi(IntPtr handle, uint option, IntPtr buffer, uint length);
    [DllImport("winhttp.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr WinHttpOpen(string agent, uint access, string proxy, string bypass, uint flags);
    [DllImport("winhttp.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr WinHttpConnect(IntPtr session, string server, ushort port, uint reserved);
    [DllImport("winhttp.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr WinHttpOpenRequest(IntPtr connection, string verb, string path, string version, string referer, IntPtr accept, uint flags);
    [DllImport("winhttp.dll", SetLastError=true)]
    static extern bool WinHttpSetTimeouts(IntPtr handle, int resolve, int connect, int send, int receive);
    [DllImport("winhttp.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WinHttpSendRequest(IntPtr handle, string headers, uint headersLength, IntPtr optional, uint optionalLength, uint totalLength, IntPtr context);
    [DllImport("winhttp.dll", SetLastError=true)]
    static extern bool WinHttpReceiveResponse(IntPtr handle, IntPtr reserved);
    [DllImport("winhttp.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool WinHttpQueryHeaders(IntPtr handle, uint level, string name, out uint value, ref uint length, IntPtr index);
    [DllImport("winhttp.dll", SetLastError=true)]
    static extern bool WinHttpCloseHandle(IntPtr handle);
    delegate void StatusCallback(IntPtr handle, IntPtr context, uint status, IntPtr information, uint informationLength);
    [DllImport("winhttp.dll", SetLastError=true)]
    static extern IntPtr WinHttpSetStatusCallback(IntPtr handle, StatusCallback callback, uint flags, IntPtr reserved);
    sealed class Pending {
        public ManualResetEvent Sent=new ManualResetEvent(false);
        public ManualResetEvent Headers=new ManualResetEvent(false);
        public int Error;
    }
    static readonly ConcurrentDictionary<IntPtr, Pending> pending=new ConcurrentDictionary<IntPtr, Pending>();
    static readonly StatusCallback callback=OnStatus;
    static void OnStatus(IntPtr handle, IntPtr context, uint status, IntPtr information, uint length) {
        Pending state;
        if(!pending.TryGetValue(handle, out state)) return;
        if(status==0x00400000) state.Sent.Set();
        if(status==0x00020000) state.Headers.Set();
        if(status==0x00200000) {
            state.Error=Marshal.ReadInt32(information, IntPtr.Size);
            state.Sent.Set(); state.Headers.Set();
        }
    }
    public sealed class Result {
        public string url;
        public uint access;
        public string proxy;
        public string stage;
        public int error;
        public string hresult;
        public uint status;
        public double elapsed_ms;
    }
    public static void SetProxy(string proxy, string bypassValue) {
        if(String.IsNullOrEmpty(proxy)) proxy=null;
        int size = Marshal.SizeOf(typeof(InternetOption));
        IntPtr options = Marshal.AllocHGlobal(size * 3);
        IntPtr server = Marshal.StringToHGlobalUni(proxy ?? "");
        IntPtr bypass = Marshal.StringToHGlobalUni(bypassValue ?? "");
        IntPtr listPointer = IntPtr.Zero;
        try {
            Marshal.StructureToPtr(new InternetOption {Option=1, Value=new IntPtr(proxy == null ? 1 : 3)}, options, false);
            Marshal.StructureToPtr(new InternetOption {Option=2, Value=server}, IntPtr.Add(options, size), false);
            Marshal.StructureToPtr(new InternetOption {Option=3, Value=bypass}, IntPtr.Add(options, size*2), false);
            var list = new InternetOptionList {Size=(uint)Marshal.SizeOf(typeof(InternetOptionList)), Count=3, Options=options};
            listPointer = Marshal.AllocHGlobal((int)list.Size);
            Marshal.StructureToPtr(list, listPointer, false);
            if (!InternetSetOption(IntPtr.Zero, 75, listPointer, list.Size)) {
                int error=Marshal.GetLastWin32Error();
                if(error!=87) throw new Win32Exception(error);
                Marshal.FreeHGlobal(server); Marshal.FreeHGlobal(bypass);
                server=Marshal.StringToHGlobalAnsi(proxy ?? ""); bypass=Marshal.StringToHGlobalAnsi(bypassValue ?? "");
                Marshal.StructureToPtr(new InternetOption {Option=2, Value=server}, IntPtr.Add(options, size), false);
                Marshal.StructureToPtr(new InternetOption {Option=3, Value=bypass}, IntPtr.Add(options, size*2), false);
                if(!InternetSetOptionAnsi(IntPtr.Zero, 75, listPointer, list.Size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
            InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
        } finally {
            if(listPointer != IntPtr.Zero) Marshal.FreeHGlobal(listPointer);
            Marshal.FreeHGlobal(options); Marshal.FreeHGlobal(server); Marshal.FreeHGlobal(bypass);
        }
    }
    public static Result Get(string url, uint access, string proxy) {
        if(String.IsNullOrEmpty(proxy)) proxy=null;
        var result = new Result {url=url, access=access, proxy=proxy};
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var state=new Pending();
        IntPtr session=IntPtr.Zero, connection=IntPtr.Zero, request=IntPtr.Zero;
        try {
            result.stage="open";
            session=WinHttpOpen("FengWoChromeNetworkProbe/1.0", access, proxy, null, 0x10000000);
            if(session == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            if(WinHttpSetStatusCallback(session, callback, 0x00620000, IntPtr.Zero)==new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            WinHttpSetTimeouts(session, 8000, 8000, 8000, 8000);
            var uri=new Uri(url);
            result.stage="connect";
            connection=WinHttpConnect(session, uri.Host, (ushort)uri.Port, 0);
            if(connection == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            result.stage="request";
            request=WinHttpOpenRequest(connection, "GET", uri.PathAndQuery, null, null, IntPtr.Zero, uri.Scheme=="https" ? 0x800000u : 0);
            if(request == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            pending[request]=state;
            result.stage="send";
            const string headers="Range: bytes=0-1023\r\n";
            if(!WinHttpSendRequest(request, headers, (uint)headers.Length, IntPtr.Zero, 0, 0, IntPtr.Zero)) {
                int error=Marshal.GetLastWin32Error();
                if(error!=997) throw new Win32Exception(error);
            }
            if(!state.Sent.WaitOne(15000)) throw new Win32Exception(12002);
            if(state.Error!=0) throw new Win32Exception(state.Error);
            result.stage="receive";
            if(!WinHttpReceiveResponse(request, IntPtr.Zero)) {
                int error=Marshal.GetLastWin32Error();
                if(error!=997) throw new Win32Exception(error);
            }
            if(!state.Headers.WaitOne(15000)) throw new Win32Exception(12002);
            if(state.Error!=0) throw new Win32Exception(state.Error);
            result.stage="headers";
            uint size=4, status;
            if(!WinHttpQueryHeaders(request, 19u|0x20000000u, null, out status, ref size, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
            result.status=status;
            result.stage="response";
        } catch(Win32Exception error) {
            result.error=error.NativeErrorCode;
            result.hresult="0x" + (0x80070000u | (uint)error.NativeErrorCode).ToString("x8");
        } finally {
            if(request!=IntPtr.Zero) WinHttpCloseHandle(request);
            if(connection!=IntPtr.Zero) WinHttpCloseHandle(connection);
            if(session!=IntPtr.Zero) WinHttpCloseHandle(session);
            Pending removed;
            pending.TryRemove(request, out removed);
            result.elapsed_ms=clock.Elapsed.TotalMilliseconds;
        }
        return result;
    }
}
