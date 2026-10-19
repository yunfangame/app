using System;
using System.Net;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace FengWoProxyDiagnostics
{
    public sealed class Configuration
    {
        public uint Flags { get; set; }
        public string Server { get; set; }
        public string Bypass { get; set; }
        public string Pac { get; set; }
    }

    public sealed class QueryResult
    {
        public bool Success { get; set; }
        public int Error { get; set; }
        public int OptionError { get; set; }
        public Configuration Configuration { get; set; }
    }

    public sealed class RefreshResult
    {
        public int Option { get; set; }
        public bool Success { get; set; }
        public int Error { get; set; }
    }

    public sealed class HttpResult
    {
        public string Target { get; set; }
        public string Transport { get; set; }
        public bool ResponseReceived { get; set; }
        public int Status { get; set; }
        public string Error { get; set; }
    }

    public static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct OptionList
        {
            public int Size;
            public IntPtr Connection;
            public int Count;
            public int Error;
            public IntPtr Options;
        }

        [DllImport("wininet.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InternetQueryOptionW(IntPtr handle, uint option, ref OptionList list, ref int size);

        [DllImport("wininet.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InternetQueryOptionA(IntPtr handle, uint option, ref OptionList list, ref int size);

        [DllImport("wininet.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InternetSetOptionW(IntPtr handle, uint option, IntPtr buffer, uint length);

        [DllImport("kernel32.dll", ExactSpelling = true)]
        private static extern IntPtr GlobalFree(IntPtr memory);

        public static QueryResult Query(bool ansi, bool ui)
        {
            int stride = IntPtr.Size == 8 ? 16 : 12;
            int offset = IntPtr.Size == 8 ? 8 : 4;
            IntPtr options = Marshal.AllocHGlobal(stride * 4);
            for (int i = 0; i < stride * 4; i++) Marshal.WriteByte(options, i, 0);
            int[] kinds = new int[] { ui ? 10 : 1, 2, 3, 4 };
            for (int i = 0; i < kinds.Length; i++) Marshal.WriteInt32(options, stride * i, kinds[i]);
            OptionList list = new OptionList { Size = Marshal.SizeOf(typeof(OptionList)), Count = 4, Options = options };
            int size = list.Size;
            try
            {
                bool success = ansi ? InternetQueryOptionA(IntPtr.Zero, 75, ref list, ref size)
                                    : InternetQueryOptionW(IntPtr.Zero, 75, ref list, ref size);
                int error = success ? 0 : Marshal.GetLastWin32Error();
                QueryResult result = new QueryResult { Success = success, Error = error, OptionError = list.Error };
                if (success)
                {
                    string[] values = new string[3];
                    for (int i = 1; i < 4; i++)
                    {
                        IntPtr text = Marshal.ReadIntPtr(options, stride * i + offset);
                        values[i - 1] = text == IntPtr.Zero ? "" :
                            (ansi ? Marshal.PtrToStringAnsi(text) : Marshal.PtrToStringUni(text));
                    }
                    result.Configuration = new Configuration {
                        Flags = unchecked((uint)Marshal.ReadInt32(options, offset)),
                        Server = values[0], Bypass = values[1], Pac = values[2]
                    };
                }
                return result;
            }
            finally
            {
                for (int i = 1; i < 4; i++)
                {
                    IntPtr text = Marshal.ReadIntPtr(options, stride * i + offset);
                    if (text != IntPtr.Zero) GlobalFree(text);
                }
                Marshal.FreeHGlobal(options);
            }
        }

        public static RefreshResult Refresh(int option)
        {
            if (option != 95 && option != 39 && option != 37)
                throw new ArgumentOutOfRangeException("option");
            bool success = InternetSetOptionW(IntPtr.Zero, (uint)option, IntPtr.Zero, 0);
            return new RefreshResult { Option = option, Success = success, Error = success ? 0 : Marshal.GetLastWin32Error() };
        }

        public static HttpResult Probe(string target, bool direct)
        {
            if (target != "domestic" && target != "public") throw new ArgumentOutOfRangeException("target");
            Task<HttpResult> pending = Task.Run(() => ProbeCore(target, direct));
            if (pending.Wait(7500)) return pending.Result;
            return new HttpResult { Target = target, Transport = direct ? "no_explicit_http_proxy" : "dotnet_system_proxy", Error = "TotalBudgetExceeded" };
        }

        private static HttpResult ProbeCore(string target, bool direct)
        {
            string url;
            if (target == "domestic") url = "https://www.baidu.com/";
            else if (target == "public") url = "https://www.microsoft.com/";
            else throw new ArgumentOutOfRangeException("target");
            HttpResult result = new HttpResult { Target = target, Transport = direct ? "no_explicit_http_proxy" : "dotnet_system_proxy" };
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
            request.Method = "HEAD";
            request.AllowAutoRedirect = false;
            request.Timeout = 5000;
            request.ReadWriteTimeout = 5000;
            request.UseDefaultCredentials = false;
            request.Credentials = null;
            request.PreAuthenticate = false;
            request.CookieContainer = null;
            request.KeepAlive = false;
            request.Proxy = direct ? null : WebRequest.GetSystemWebProxy();
            if (request.Proxy != null) request.Proxy.Credentials = null;
            try
            {
                IAsyncResult pending = request.BeginGetResponse(null, null);
                using (WaitHandle wait = pending.AsyncWaitHandle)
                {
                    if (!wait.WaitOne(6000))
                    {
                        request.Abort();
                        result.Error = "Timeout";
                        return result;
                    }
                    using (HttpWebResponse response = (HttpWebResponse)request.EndGetResponse(pending))
                    {
                        result.ResponseReceived = true;
                        result.Status = (int)response.StatusCode;
                    }
                }
            }
            catch (WebException error)
            {
                using (HttpWebResponse response = error.Response as HttpWebResponse)
                {
                    result.Error = error.Status.ToString();
                    if (response != null) { result.ResponseReceived = true; result.Status = (int)response.StatusCode; }
                }
            }
            catch (Exception error)
            {
                result.Error = error.GetType().Name;
            }
            return result;
        }
    }
}
