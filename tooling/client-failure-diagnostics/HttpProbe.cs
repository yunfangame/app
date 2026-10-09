using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;

public sealed class FengWoHttpProbeResult
{
    public string NodeId { get; set; }
    public string TargetId { get; set; }
    public bool HttpResponseReceived { get; set; }
    public int HttpStatus { get; set; }
    public string Category { get; set; }
    public string Stage { get; set; }
    public string WebExceptionStatus { get; set; }
    public string ContentClass { get; set; }
    public bool HasRedirectLocation { get; set; }
    public long ElapsedMilliseconds { get; set; }
}

public sealed class FengWoHttpProbe : IDisposable
{
    private readonly object gate = new object();
    private readonly Stopwatch watch = Stopwatch.StartNew();
    private readonly string nodeId;
    private readonly string targetId;
    private HttpWebRequest request;
    private readonly Timer deadline;
    private Task<FengWoHttpProbeResult> task;
    private bool deadlineExpired;
    private bool disposed;

    private FengWoHttpProbe(string nodeId, string targetId, string url, int port, string user, string password, int timeoutMs)
    {
        if (timeoutMs < 100 || timeoutMs > 120000) throw new ArgumentOutOfRangeException("timeoutMs");
        if (port < 1 || port > 65535) throw new ArgumentOutOfRangeException("port");
        if (String.IsNullOrEmpty(user) || String.IsNullOrEmpty(password)) throw new ArgumentException("Loopback authentication required");
        if (String.IsNullOrEmpty(nodeId) || String.IsNullOrEmpty(targetId)) throw new ArgumentException("Diagnostic identifiers required");
        Uri uri;
        if (!Uri.TryCreate(url, UriKind.Absolute, out uri) || (uri.Scheme != "http" && uri.Scheme != "https") || !String.IsNullOrEmpty(uri.UserInfo) || !String.IsNullOrEmpty(uri.Fragment))
            throw new ArgumentException("Safe HTTP target required");
        this.nodeId = nodeId;
        this.targetId = targetId;
        request = (HttpWebRequest)WebRequest.Create(uri);
        request.Method = "HEAD";
        request.AllowAutoRedirect = false;
        request.KeepAlive = false;
        request.Timeout = timeoutMs;
        request.ReadWriteTimeout = timeoutMs;
        request.MaximumResponseHeadersLength = 32;
        request.Credentials = null;
        request.UseDefaultCredentials = false;
        request.ConnectionGroupName = "FengWo-Diagnostic-" + Guid.NewGuid().ToString("N");
        request.UserAgent = "FengWo-Client-Diagnostics/3";
        WebProxy proxy = new WebProxy(new Uri("http://127.0.0.1:" + port.ToString()), false, new string[0]);
        proxy.Credentials = new NetworkCredential(user, password);
        request.Proxy = proxy;
        deadline = new Timer(AbortAtDeadline, null, timeoutMs, Timeout.Infinite);
        task = Task.Factory.StartNew<FengWoHttpProbeResult>(Execute, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
    }

    public static FengWoHttpProbe Start(string nodeId, string targetId, string url, int port, string user, string password, int timeoutMs)
    {
        return new FengWoHttpProbe(nodeId, targetId, url, port, user, password, timeoutMs);
    }

    public static int AllocateLoopbackPort()
    {
        TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        try
        {
            listener.Start();
            return ((IPEndPoint)listener.LocalEndpoint).Port;
        }
        finally { listener.Stop(); }
    }

    public bool IsCompleted { get { return task != null && task.IsCompleted; } }
    public FengWoHttpProbeResult Result
    {
        get
        {
            if (!IsCompleted) throw new InvalidOperationException("Probe has not completed");
            return task.GetAwaiter().GetResult();
        }
    }

    private void AbortAtDeadline(object state)
    {
        HttpWebRequest current;
        lock (gate)
        {
            if (disposed) return;
            deadlineExpired = true;
            current = request;
        }
        try { if (current != null) current.Abort(); } catch { }
    }

    private FengWoHttpProbeResult Execute()
    {
        FengWoHttpProbeResult result = new FengWoHttpProbeResult {
            NodeId = nodeId, TargetId = targetId, Category = "HTTP_REQUEST_FAILED", Stage = "protocol_or_target", WebExceptionStatus = "", ContentClass = "none"
        };
        HttpWebResponse response = null;
        try
        {
            lock (gate)
            {
                if (deadlineExpired || disposed) { result.Category = "REQUEST_DEADLINE"; return result; }
            }
            try { response = (HttpWebResponse)request.GetResponse(); }
            catch (WebException error)
            {
                result.WebExceptionStatus = error.Status.ToString();
                response = error.Response as HttpWebResponse;
                if (response == null)
                {
                    bool timedOut;
                    lock (gate) { timedOut = deadlineExpired; }
                    if (timedOut || error.Status == WebExceptionStatus.Timeout) result.Category = "REQUEST_DEADLINE";
                    else if (error.Status == WebExceptionStatus.ConnectFailure || error.Status == WebExceptionStatus.ProxyNameResolutionFailure) {
                        result.Category = "LOCAL_PROXY_UNREACHABLE"; result.Stage = "loopback_listener";
                    }
                    else if (error.Status == WebExceptionStatus.TrustFailure) {
                        result.Category = "TEST_TARGET_CERTIFICATE"; result.Stage = "test_target_tls";
                    }
                    else if (error.Status == WebExceptionStatus.SecureChannelFailure) {
                        result.Category = "TEST_TARGET_TLS"; result.Stage = "test_target_tls";
                    }
                    else if (error.Status == WebExceptionStatus.RequestCanceled) result.Category = "REQUEST_ABORTED";
                    else if (error.Status == WebExceptionStatus.ReceiveFailure || error.Status == WebExceptionStatus.ConnectionClosed || error.Status == WebExceptionStatus.SendFailure)
                        result.Category = "PROXY_OR_TARGET_CLOSED";
                    else if (error.Status == WebExceptionStatus.NameResolutionFailure) result.Category = "TEST_TARGET_NAME_RESOLUTION";
                    return result;
                }
            }
            if (response != null)
            {
                result.HttpResponseReceived = true;
                result.HttpStatus = (int)response.StatusCode;
                result.Category = "HTTP_RESPONSE";
                result.Stage = "test_target_http";
                if (result.HttpStatus == 407) { result.Category = "LOCAL_PROXY_AUTH_FAILURE"; result.Stage = "loopback_proxy_auth"; }
                else if (result.HttpStatus == 502 || result.HttpStatus == 503 || result.HttpStatus == 504) {
                    result.Category = "HTTP_GATEWAY_OR_TARGET_RESPONSE"; result.Stage = "gateway_or_test_target_http";
                }
                string contentType = response.ContentType ?? "";
                if (contentType.IndexOf("html", StringComparison.OrdinalIgnoreCase) >= 0) result.ContentClass = "html";
                else if (contentType.IndexOf("json", StringComparison.OrdinalIgnoreCase) >= 0) result.ContentClass = "json";
                else if (contentType.IndexOf("text", StringComparison.OrdinalIgnoreCase) >= 0) result.ContentClass = "text";
                else if (contentType.Length != 0) result.ContentClass = "other";
                result.HasRedirectLocation = !String.IsNullOrEmpty(response.Headers["Location"]);
            }
            return result;
        }
        catch
        {
            result.Category = "HTTP_PROBE_INTERNAL_ERROR";
            result.Stage = "collector_http";
            return result;
        }
        finally
        {
            result.ElapsedMilliseconds = watch.ElapsedMilliseconds;
            if (response != null) response.Close();
            try { request.Abort(); } catch { }
            try { deadline.Change(Timeout.Infinite, Timeout.Infinite); } catch (ObjectDisposedException) { }
        }
    }

    public void Dispose()
    {
        HttpWebRequest current;
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            current = request;
        }
        deadline.Dispose();
        try { if (current != null) current.Abort(); } catch { }
    }
}
