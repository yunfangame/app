using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public sealed class FengWoDiagnosticCoreSession : IDisposable
{
    public const int MaximumFrameBytes = 64 * 1024 * 1024;
    private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);
    private readonly object readGate = new object();
    private readonly object writeGate = new object();
    private Stream transport;
    private Process process;
    private OutputDrain standardOutput;
    private OutputDrain standardError;
    private int disposed;

    public int OwnedPid { get; private set; }
    public bool PeerIdentityVerified { get; private set; }
    public bool IsDisposed { get { return Interlocked.CompareExchange(ref disposed, 0, 0) != 0; } }
    public bool IsAlive
    {
        get
        {
            if (IsDisposed || process == null) return false;
            try { return !process.HasExited; }
            catch (InvalidOperationException) { return false; }
        }
    }

    private FengWoDiagnosticCoreSession() { }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint clientProcessId);

    public static FengWoDiagnosticCoreSession Start(string executable, int timeoutMs)
    {
        ValidateTimeout(timeoutMs);
        if (String.IsNullOrWhiteSpace(executable)) throw new ArgumentException("An executable path is required", "executable");
        string fullPath = Path.GetFullPath(executable);
        if (!File.Exists(fullPath)) throw new FileNotFoundException("Diagnostic core executable was not found", fullPath);
        FengWoDiagnosticCoreSession session = new FengWoDiagnosticCoreSession();
        Stopwatch timer = Stopwatch.StartNew();
        try
        {
            string name = "FWDiag_" + Guid.NewGuid().ToString("N");
            NamedPipeServerStream pipe = new NamedPipeServerStream(name, PipeDirection.InOut, 1,
                PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 65536, 65536);
            session.transport = pipe;
            string address = "\\\\.\\pipe\\" + name;
            ProcessStartInfo startInfo = new ProcessStartInfo(fullPath, "\"" + address + "\"");
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.WorkingDirectory = Path.GetDirectoryName(fullPath);
            session.process = Process.Start(startInfo);
            if (session.process == null) throw new IOException("Diagnostic core did not start");
            session.OwnedPid = session.process.Id;
            session.standardOutput = new OutputDrain(session.process.StandardOutput.BaseStream);
            session.standardError = new OutputDrain(session.process.StandardError.BaseStream);
            session.standardOutput.Start();
            session.standardError.Start();
            using (Completion completion = new Completion())
            {
                pipe.BeginWaitForConnection(delegate(IAsyncResult pending)
                {
                    try { pipe.EndWaitForConnection(pending); completion.Complete(0, null); }
                    catch (Exception error) { completion.Complete(0, error); }
                }, null);
                completion.Wait(Remaining(timer, timeoutMs), "core pipe connection");
            }
            if (Environment.OSVersion.Platform == PlatformID.Win32NT)
            {
                uint peer;
                if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out peer))
                    throw new IOException("Unable to verify core pipe client", new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()));
                if (peer != (uint)session.OwnedPid) throw new IOException("Core pipe client process identity mismatch");
                session.PeerIdentityVerified = true;
            }
            if (!session.IsAlive) throw new IOException("Diagnostic core exited during startup");
            return session;
        }
        catch
        {
            session.Dispose();
            throw;
        }
    }

    public void SendFrame(string json, int timeoutMs)
    {
        ValidateTimeout(timeoutMs);
        if (json == null) throw new ArgumentNullException("json");
        Stopwatch timer = Stopwatch.StartNew();
        bool locked = false;
        try
        {
            locked = Monitor.TryEnter(writeGate, Remaining(timer, timeoutMs));
            if (!locked) throw new TimeoutException("Timeout waiting to send core frame");
            ThrowIfClosed();
            int length = StrictUtf8.GetByteCount(json);
            if (length > MaximumFrameBytes) throw new InvalidDataException("Core frame exceeds 64 MiB");
            byte[] data = StrictUtf8.GetBytes(json);
            byte[] header = new byte[] { (byte)length, (byte)(length >> 8), (byte)(length >> 16), (byte)(length >> 24) };
            Write(header, timer, timeoutMs);
            if (data.Length != 0) Write(data, timer, timeoutMs);
        }
        catch
        {
            Dispose();
            throw;
        }
        finally { if (locked) Monitor.Exit(writeGate); }
    }

    public string ReadFrame(int timeoutMs)
    {
        ValidateTimeout(timeoutMs);
        Stopwatch timer = Stopwatch.StartNew();
        bool locked = false;
        try
        {
            locked = Monitor.TryEnter(readGate, Remaining(timer, timeoutMs));
            if (!locked) throw new TimeoutException("Timeout waiting to read core frame");
            ThrowIfClosed();
            byte[] header = new byte[4];
            ReadExact(header, timer, timeoutMs);
            uint length = (uint)header[0] | ((uint)header[1] << 8) | ((uint)header[2] << 16) | ((uint)header[3] << 24);
            if (length > MaximumFrameBytes) throw new InvalidDataException("Core frame exceeds 64 MiB");
            byte[] data = new byte[(int)length];
            if (data.Length != 0) ReadExact(data, timer, timeoutMs);
            return StrictUtf8.GetString(data);
        }
        catch
        {
            Dispose();
            throw;
        }
        finally { if (locked) Monitor.Exit(readGate); }
    }

    private void ReadExact(byte[] data, Stopwatch timer, int timeoutMs)
    {
        int offset = 0;
        while (offset < data.Length)
        {
            ThrowIfClosed();
            int remaining = Remaining(timer, timeoutMs);
            if (remaining == 0) throw new TimeoutException("Timeout reading core frame");
            Stream active = transport;
            using (Completion completion = new Completion())
            {
                active.BeginRead(data, offset, data.Length - offset, delegate(IAsyncResult pending)
                {
                    try { completion.Complete(active.EndRead(pending), null); }
                    catch (Exception error) { completion.Complete(0, error); }
                }, null);
                int received = completion.Wait(Remaining(timer, timeoutMs), "core frame read");
                if (received == 0) throw new EndOfStreamException("Core pipe closed before the complete frame arrived");
                offset += received;
            }
        }
    }

    private void Write(byte[] data, Stopwatch timer, int timeoutMs)
    {
        ThrowIfClosed();
        if (Remaining(timer, timeoutMs) == 0) throw new TimeoutException("Timeout writing core frame");
        Stream active = transport;
        using (Completion completion = new Completion())
        {
            active.BeginWrite(data, 0, data.Length, delegate(IAsyncResult pending)
            {
                try { active.EndWrite(pending); completion.Complete(0, null); }
                catch (Exception error) { completion.Complete(0, error); }
            }, null);
            completion.Wait(Remaining(timer, timeoutMs), "core frame write");
        }
    }

    private void ThrowIfClosed()
    {
        if (IsDisposed || transport == null) throw new ObjectDisposedException("FengWoDiagnosticCoreSession");
    }

    private static int Remaining(Stopwatch timer, int timeoutMs)
    {
        long remaining = timeoutMs - timer.ElapsedMilliseconds;
        return remaining > 0 ? (int)remaining : 0;
    }

    private static void ValidateTimeout(int timeoutMs)
    {
        if (timeoutMs < 1 || timeoutMs > 120000) throw new ArgumentOutOfRangeException("timeoutMs", "Timeout must be between 1 and 120000 milliseconds");
    }

    private static void DisposeQuietly(IDisposable value)
    {
        if (value == null) return;
        try { value.Dispose(); }
        catch (Exception) { }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        DisposeQuietly(transport);
        if (process != null)
        {
            try
            {
                if (!process.WaitForExit(1500))
                {
                    process.Kill();
                    process.WaitForExit(1000);
                }
            }
            catch (Exception) { }
        }
        DisposeQuietly(standardOutput);
        DisposeQuietly(standardError);
        DisposeQuietly(process);
    }

    private sealed class Completion : IDisposable
    {
        private readonly object gate = new object();
        private ManualResetEvent signal = new ManualResetEvent(false);
        private bool completed;
        private int count;
        private Exception error;

        public void Complete(int value, Exception failure)
        {
            lock (gate)
            {
                if (completed) return;
                count = value;
                error = failure;
                completed = true;
                if (signal != null) signal.Set();
            }
        }

        public int Wait(int timeoutMs, string operation)
        {
            ManualResetEvent current;
            lock (gate) { current = signal; }
            if (current == null || !current.WaitOne(Math.Max(0, timeoutMs)))
                throw new TimeoutException("Timeout during " + operation);
            lock (gate)
            {
                if (error != null) throw error;
                return count;
            }
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

    private sealed class OutputDrain : IDisposable
    {
        private readonly Stream stream;
        private readonly byte[] buffer = new byte[8192];
        private int stopped;

        public OutputDrain(Stream stream) { this.stream = stream; }

        public void Start()
        {
            if (Interlocked.CompareExchange(ref stopped, 0, 0) != 0) return;
            try { stream.BeginRead(buffer, 0, buffer.Length, Received, null); }
            catch (Exception) { Dispose(); }
        }

        private void Received(IAsyncResult pending)
        {
            int count;
            try { count = stream.EndRead(pending); }
            catch (Exception) { Dispose(); return; }
            if (count == 0) { Dispose(); return; }
            ThreadPool.QueueUserWorkItem(delegate(object ignored) { Start(); });
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref stopped, 1) == 0) DisposeQuietly(stream);
        }
    }
}
