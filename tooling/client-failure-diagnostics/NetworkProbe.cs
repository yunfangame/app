using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

public class FengWoResolveResult
{
    public string[] Addresses { get; set; }
    public string Error { get; set; }

    public FengWoResolveResult()
    {
        Addresses = new string[0];
        Error = String.Empty;
    }
}

public sealed class FengWoDnsResult : FengWoResolveResult
{
    public bool Truncated { get; set; }
    public int Rcode { get; set; }

    public FengWoDnsResult()
    {
        Rcode = -1;
    }
}

public class FengWoTcpResult
{
    public bool Success { get; set; }
    public long Milliseconds { get; set; }
    public string Error { get; set; }

    public FengWoTcpResult()
    {
        Error = String.Empty;
    }
}

public sealed class FengWoTlsResult : FengWoTcpResult
{
    public bool CertificateValid { get; set; }
    public string PolicyErrors { get; set; }
    public string Protocol { get; set; }

    public FengWoTlsResult()
    {
        PolicyErrors = "NotEvaluated";
        Protocol = String.Empty;
    }
}

public static class FengWoNetworkProbe
{
    private sealed class Completion : IDisposable
    {
        private readonly object gate = new object();
        private ManualResetEvent signal = new ManualResetEvent(false);
        private bool completed;
        private object value;
        private Exception error;

        public void Complete(object result, Exception failure)
        {
            lock (gate)
            {
                if (completed) return;
                completed = true;
                value = result;
                error = failure;
                if (signal != null) signal.Set();
            }
        }

        public bool Wait(int timeoutMs)
        {
            ManualResetEvent current;
            lock (gate)
            {
                if (completed) return true;
                current = signal;
            }
            return current != null && current.WaitOne(Math.Max(0, timeoutMs));
        }

        public object Value
        {
            get { lock (gate) { return value; } }
        }

        public Exception Error
        {
            get { lock (gate) { return error; } }
        }

        public void Dispose()
        {
            lock (gate)
            {
                if (signal == null) return;
                signal.Close();
                signal = null;
            }
        }
    }

    private sealed class DnsRecord
    {
        public string Name;
        public string Address;
    }

    private sealed class CertificateState
    {
        private readonly object gate = new object();
        private bool valid;
        private string policy = "NotEvaluated";

        public bool Check(X509Certificate certificate, SslPolicyErrors errors)
        {
            lock (gate)
            {
                policy = errors.ToString();
                valid = certificate != null && errors == SslPolicyErrors.None;
                return valid;
            }
        }

        public void CopyTo(FengWoTlsResult result)
        {
            lock (gate)
            {
                result.CertificateValid = valid;
                result.PolicyErrors = policy;
            }
        }
    }

    public static FengWoResolveResult ResolveSystem(string host, int timeoutMs)
    {
        FengWoResolveResult result = new FengWoResolveResult();
        try
        {
            ValidateTimeout(timeoutMs);
            IPAddress literal;
            if (IPAddress.TryParse(host, out literal))
            {
                result.Addresses = new string[] { literal.ToString() };
                return result;
            }
            string name = NormalizeHost(host);
            using (Completion completion = new Completion())
            {
                Dns.BeginGetHostAddresses(name, delegate(IAsyncResult pending)
                {
                    try { completion.Complete(Dns.EndGetHostAddresses(pending), null); }
                    catch (Exception error) { completion.Complete(null, error); }
                }, null);
                if (!completion.Wait(timeoutMs))
                {
                    result.Error = "Timeout during system DNS lookup";
                    return result;
                }
                if (completion.Error != null) throw completion.Error;
                IPAddress[] addresses = (IPAddress[])completion.Value;
                List<string> values = new List<string>();
                foreach (IPAddress address in addresses)
                {
                    string value = address.ToString();
                    if (!values.Contains(value)) values.Add(value);
                }
                result.Addresses = values.ToArray();
            }
        }
        catch (Exception error) { result.Error = Describe(error); }
        return result;
    }

    public static FengWoDnsResult QueryDns(string host, string serverIP, string typeAorAAAA, int timeoutMs)
    {
        return QueryDnsAtPort(host, serverIP, typeAorAAAA, timeoutMs, 53);
    }

    private static FengWoDnsResult QueryDnsAtPort(string host, string serverIP, string typeAorAAAA, int timeoutMs, int serverPort)
    {
        FengWoDnsResult result = new FengWoDnsResult();
        Stopwatch timer = Stopwatch.StartNew();
        Socket socket = null;
        try
        {
            ValidateTimeout(timeoutMs);
            ValidatePort(serverPort);
            string name = NormalizeHost(host);
            IPAddress server = ParseAddress(serverIP);
            int type;
            if (String.Equals(typeAorAAAA, "A", StringComparison.OrdinalIgnoreCase)) type = 1;
            else if (String.Equals(typeAorAAAA, "AAAA", StringComparison.OrdinalIgnoreCase)) type = 28;
            else throw new ArgumentException("DNS type must be A or AAAA");
            byte[] random = new byte[2];
            using (RandomNumberGenerator generator = RandomNumberGenerator.Create()) generator.GetBytes(random);
            int id = (random[0] << 8) | random[1];
            byte[] query = BuildQuery(name, type, id);
            socket = new Socket(server.AddressFamily, SocketType.Dgram, ProtocolType.Udp);
            socket.Connect(new IPEndPoint(server, serverPort));
            socket.SendTimeout = Math.Max(1, Remaining(timer, timeoutMs));
            socket.Send(query);
            byte[] response = new byte[65535];
            for (int attempts = 0; attempts < 8; attempts++)
            {
                int remaining = Remaining(timer, timeoutMs);
                if (remaining == 0) break;
                socket.ReceiveTimeout = remaining;
                int received;
                try { received = socket.Receive(response); }
                catch (SocketException error)
                {
                    if (error.SocketErrorCode == SocketError.TimedOut || error.SocketErrorCode == SocketError.WouldBlock) break;
                    throw;
                }
                if (ParseDnsResponse(response, received, name, type, id, result)) return result;
            }
            result.Error = "Timeout or no matching DNS response";
        }
        catch (Exception error) { result.Error = Describe(error); }
        finally
        {
            DisposeQuietly(socket);
            timer.Stop();
        }
        return result;
    }

    public static FengWoTcpResult ProbeTcp(string ip, int port, int timeoutMs)
    {
        FengWoTcpResult result = new FengWoTcpResult();
        Stopwatch timer = Stopwatch.StartNew();
        TcpClient client = null;
        try
        {
            ValidateTimeout(timeoutMs);
            ValidatePort(port);
            IPAddress address = ParseAddress(ip);
            client = new TcpClient(address.AddressFamily);
            Connect(client, address, port, timer, timeoutMs);
            result.Success = true;
        }
        catch (Exception error) { result.Error = Describe(error); }
        finally
        {
            DisposeQuietly(client);
            timer.Stop();
            result.Milliseconds = timer.ElapsedMilliseconds;
        }
        return result;
    }

    public static FengWoTlsResult ProbeTls(string ip, int port, string sni, int timeoutMs, bool tls12Only)
    {
        FengWoTlsResult result = new FengWoTlsResult();
        Stopwatch timer = Stopwatch.StartNew();
        TcpClient client = null;
        SslStream stream = null;
        CertificateState validation = new CertificateState();
        try
        {
            ValidateTimeout(timeoutMs);
            ValidatePort(port);
            IPAddress address = ParseAddress(ip);
            IPAddress literalName;
            string target = IPAddress.TryParse(sni, out literalName) ? literalName.ToString() : NormalizeHost(sni);
            client = new TcpClient(address.AddressFamily);
            Connect(client, address, port, timer, timeoutMs);
            client.NoDelay = true;
            stream = new SslStream(client.GetStream(), false,
                delegate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors)
                {
                    return validation.Check(certificate, errors);
                });
            using (Completion completion = new Completion())
            {
                SslStream active = stream;
                SslProtocols protocols = tls12Only ? SslProtocols.Tls12 : SslProtocols.None;
                active.BeginAuthenticateAsClient(target, new X509CertificateCollection(), protocols, true,
                    delegate(IAsyncResult pending)
                    {
                        try
                        {
                            active.EndAuthenticateAsClient(pending);
                            completion.Complete(null, null);
                        }
                        catch (Exception error) { completion.Complete(null, error); }
                    }, null);
                if (!completion.Wait(Remaining(timer, timeoutMs))) throw new TimeoutException("Timeout during TLS handshake");
                if (completion.Error != null) throw completion.Error;
                result.Protocol = active.SslProtocol.ToString();
                validation.CopyTo(result);
                result.Success = active.IsAuthenticated && active.IsEncrypted && result.CertificateValid;
                if (!result.Success) result.Error = "TLS authentication or certificate validation failed";
            }
        }
        catch (Exception error) { result.Error = Describe(error); }
        finally
        {
            DisposeQuietly(stream);
            DisposeQuietly(client);
            validation.CopyTo(result);
            timer.Stop();
            result.Milliseconds = timer.ElapsedMilliseconds;
        }
        return result;
    }

    private static void Connect(TcpClient client, IPAddress address, int port, Stopwatch timer, int timeoutMs)
    {
        using (Completion completion = new Completion())
        {
            client.BeginConnect(address, port, delegate(IAsyncResult pending)
            {
                try
                {
                    client.EndConnect(pending);
                    completion.Complete(null, null);
                }
                catch (Exception error) { completion.Complete(null, error); }
            }, null);
            if (!completion.Wait(Remaining(timer, timeoutMs))) throw new TimeoutException("Timeout during TCP connect");
            if (completion.Error != null) throw completion.Error;
        }
    }

    private static int Remaining(Stopwatch timer, int timeoutMs)
    {
        long remaining = timeoutMs - timer.ElapsedMilliseconds;
        return remaining > 0 ? (int)remaining : 0;
    }

    private static void DisposeQuietly(IDisposable value)
    {
        if (value == null) return;
        try { value.Dispose(); }
        catch (Exception) { }
    }

    private static void ValidateTimeout(int timeoutMs)
    {
        if (timeoutMs < 1 || timeoutMs > 120000) throw new ArgumentOutOfRangeException("timeoutMs", "Timeout must be between 1 and 120000 milliseconds");
    }

    private static void ValidatePort(int port)
    {
        if (port < 1 || port > 65535) throw new ArgumentOutOfRangeException("port", "Port must be between 1 and 65535");
    }

    private static IPAddress ParseAddress(string value)
    {
        IPAddress address;
        if (!IPAddress.TryParse(value, out address)) throw new ArgumentException("A numeric IP address is required");
        return address;
    }

    private static string NormalizeHost(string host)
    {
        if (String.IsNullOrWhiteSpace(host)) throw new ArgumentException("A hostname is required");
        string name = new IdnMapping().GetAscii(host.Trim().TrimEnd('.')).ToLowerInvariant();
        if (name.Length == 0 || name.Length > 253) throw new ArgumentException("Invalid hostname length");
        foreach (string label in name.Split('.'))
        {
            if (label.Length == 0 || label.Length > 63) throw new ArgumentException("Invalid DNS label length");
            foreach (char value in label)
            {
                if (!((value >= 'a' && value <= 'z') || (value >= '0' && value <= '9') || value == '-' || value == '_')) throw new ArgumentException("Invalid DNS hostname");
            }
        }
        return name;
    }

    private static string Describe(Exception error)
    {
        Exception cause = error.GetBaseException();
        SocketException socket = cause as SocketException;
        if (socket != null) return "Socket: " + socket.SocketErrorCode.ToString();
        string message = cause.GetType().Name + ": " + cause.Message;
        message = message.Replace('\r', ' ').Replace('\n', ' ');
        return message.Length <= 500 ? message : message.Substring(0, 500);
    }

    private static void AddU16(List<byte> bytes, int value)
    {
        bytes.Add((byte)(value >> 8));
        bytes.Add((byte)value);
    }

    private static byte[] BuildQuery(string name, int type, int id)
    {
        List<byte> bytes = new List<byte>();
        AddU16(bytes, id);
        AddU16(bytes, 0x0100);
        AddU16(bytes, 1);
        AddU16(bytes, 0);
        AddU16(bytes, 0);
        AddU16(bytes, 0);
        foreach (string label in name.Split('.'))
        {
            byte[] encoded = Encoding.ASCII.GetBytes(label);
            bytes.Add((byte)encoded.Length);
            bytes.AddRange(encoded);
        }
        bytes.Add(0);
        AddU16(bytes, type);
        AddU16(bytes, 1);
        return bytes.ToArray();
    }

    private static int ReadU16(byte[] bytes, int length, ref int offset)
    {
        Check(length, offset, 2);
        int value = (bytes[offset] << 8) | bytes[offset + 1];
        offset += 2;
        return value;
    }

    private static void Check(int length, int offset, int count)
    {
        if (offset < 0 || count < 0 || offset > length - count) throw new FormatException("Malformed DNS response");
    }

    private static string ReadName(byte[] bytes, int length, ref int offset)
    {
        int cursor = offset;
        int next = -1;
        int total = 0;
        HashSet<int> visited = new HashSet<int>();
        List<string> labels = new List<string>();
        while (true)
        {
            Check(length, cursor, 1);
            if (!visited.Add(cursor) || visited.Count > 256) throw new FormatException("Invalid DNS compression pointer");
            int size = bytes[cursor++];
            if (size == 0)
            {
                offset = next >= 0 ? next : cursor;
                return String.Join(".", labels.ToArray()).ToLowerInvariant();
            }
            if ((size & 0xc0) == 0xc0)
            {
                Check(length, cursor, 1);
                if (next < 0) next = cursor + 1;
                cursor = ((size & 63) << 8) | bytes[cursor];
                continue;
            }
            if (size > 63) throw new FormatException("Invalid DNS label");
            Check(length, cursor, size);
            total += size + 1;
            if (total > 254) throw new FormatException("DNS name too long");
            labels.Add(Encoding.ASCII.GetString(bytes, cursor, size));
            cursor += size;
        }
    }

    private static bool ParseDnsResponse(byte[] bytes, int length, string name, int type, int id, FengWoDnsResult result)
    {
        if (length < 12) return false;
        int offset = 0;
        if (ReadU16(bytes, length, ref offset) != id) return false;
        int flags = ReadU16(bytes, length, ref offset);
        int questions = ReadU16(bytes, length, ref offset);
        int answers = ReadU16(bytes, length, ref offset);
        offset += 4;
        if ((flags & 0x8000) == 0 || (flags & 0x7800) != 0 || questions != 1) return false;
        if (ReadName(bytes, length, ref offset) != name || ReadU16(bytes, length, ref offset) != type || ReadU16(bytes, length, ref offset) != 1) return false;
        result.Truncated = (flags & 0x0200) != 0;
        result.Rcode = flags & 15;
        if (result.Truncated)
        {
            result.Error = "Truncated DNS response (TCP retry required)";
            return true;
        }
        if (result.Rcode != 0)
        {
            result.Error = "DNS RCODE " + result.Rcode.ToString(CultureInfo.InvariantCulture);
            return true;
        }
        if (answers > 512) throw new FormatException("Too many DNS answers");
        Dictionary<string, string> aliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        List<DnsRecord> records = new List<DnsRecord>();
        for (int i = 0; i < answers; i++)
        {
            string owner = ReadName(bytes, length, ref offset);
            int recordType = ReadU16(bytes, length, ref offset);
            int recordClass = ReadU16(bytes, length, ref offset);
            Check(length, offset, 4);
            offset += 4;
            int dataLength = ReadU16(bytes, length, ref offset);
            Check(length, offset, dataLength);
            int end = offset + dataLength;
            if (recordClass == 1 && recordType == 5)
            {
                aliases[owner] = ReadName(bytes, length, ref offset);
                if (offset != end) throw new FormatException("Invalid DNS alias length");
            }
            else if (recordClass == 1 && recordType == type && ((type == 1 && dataLength == 4) || (type == 28 && dataLength == 16)))
            {
                byte[] address = new byte[dataLength];
                Buffer.BlockCopy(bytes, offset, address, 0, dataLength);
                records.Add(new DnsRecord { Name = owner, Address = new IPAddress(address).ToString() });
            }
            offset = end;
        }
        HashSet<string> owners = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        owners.Add(name);
        string current = name;
        for (int i = 0; i < 32 && aliases.ContainsKey(current); i++)
        {
            current = aliases[current];
            if (!owners.Add(current)) throw new FormatException("DNS alias loop");
        }
        List<string> addresses = new List<string>();
        foreach (DnsRecord record in records)
        {
            if (owners.Contains(record.Name) && !addresses.Contains(record.Address)) addresses.Add(record.Address);
        }
        result.Addresses = addresses.ToArray();
        return true;
    }
}
