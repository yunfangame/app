using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace FengWoArm64Tests {
    public sealed class CorePipe : IDisposable {
        private readonly NamedPipeServerStream pipe;
        private readonly Task connection;
        public readonly string SessionId;
        public readonly string Address;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint processId);

        public CorePipe() {
            SessionId = Guid.NewGuid().ToString("N");
            string name = "FlClashCore_" + SessionId;
            Address = @"\\.\pipe\" + name;
            pipe = new NamedPipeServerStream(name, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
            connection = Task.Factory.FromAsync(pipe.BeginWaitForConnection, pipe.EndWaitForConnection, null);
        }

        public uint Accept(int expectedPid, int timeoutMilliseconds) {
            if (!connection.Wait(timeoutMilliseconds)) throw new TimeoutException("Owned Core did not connect to its named pipe");
            uint processId;
            if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle.DangerousGetHandle(), out processId)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            if (processId != expectedPid) throw new InvalidOperationException("Named pipe peer is not the owned Core process");
            return processId;
        }

        public void Send(string json) {
            byte[] payload = Encoding.UTF8.GetBytes(json);
            byte[] prefix = BitConverter.GetBytes((uint)payload.Length);
            pipe.Write(prefix, 0, prefix.Length);
            pipe.Write(payload, 0, payload.Length);
            pipe.Flush();
        }

        private byte[] ReadExact(int length, Stopwatch watch, int timeoutMilliseconds) {
            byte[] data = new byte[length];
            int offset = 0;
            while (offset < data.Length) {
                int remaining = timeoutMilliseconds - (int)watch.ElapsedMilliseconds;
                if (remaining <= 0) throw new TimeoutException("Owned Core frame timed out");
                Task<int> read = pipe.ReadAsync(data, offset, data.Length - offset);
                if (!read.Wait(remaining)) throw new TimeoutException("Owned Core frame timed out");
                if (read.Result <= 0) throw new EndOfStreamException("Owned Core closed the pipe");
                offset += read.Result;
            }
            return data;
        }

        public string Receive(int timeoutMilliseconds) {
            Stopwatch watch = Stopwatch.StartNew();
            byte[] prefix = ReadExact(4, watch, timeoutMilliseconds);
            uint length = BitConverter.ToUInt32(prefix, 0);
            if (length > 4 * 1024 * 1024) throw new InvalidDataException("Core fixture response exceeds its bound");
            return Encoding.UTF8.GetString(ReadExact((int)length, watch, timeoutMilliseconds));
        }

        public void Dispose() {
            pipe.Dispose();
        }
    }

    public sealed class LoopbackHttp : IDisposable {
        private readonly TcpListener listener;
        private readonly Thread worker;
        private volatile bool stopping;
        public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }

        public LoopbackHttp() {
            listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            worker = new Thread(Run);
            worker.IsBackground = true;
            worker.Start();
        }

        private void Run() {
            while (!stopping) {
                try {
                    using (TcpClient client = listener.AcceptTcpClient()) {
                        client.ReceiveTimeout = 5000;
                        client.SendTimeout = 5000;
                        using (NetworkStream stream = client.GetStream()) {
                            byte[] request = new byte[16384];
                            int length = 0;
                            while (length < request.Length) {
                                int value = stream.ReadByte();
                                if (value < 0) break;
                                request[length++] = (byte)value;
                                if (length >= 4 && request[length - 4] == 13 && request[length - 3] == 10 && request[length - 2] == 13 && request[length - 1] == 10) break;
                            }
                            byte[] response = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Length: 24\r\nConnection: close\r\n\r\nFENGWO_ARM64_LOOPBACK_OK");
                            stream.Write(response, 0, response.Length);
                        }
                    }
                } catch (SocketException) {
                    if (!stopping) Thread.Sleep(10);
                } catch (IOException) {
                    if (!stopping) Thread.Sleep(10);
                } catch (ObjectDisposedException) {
                    break;
                }
            }
        }

        public void Dispose() {
            stopping = true;
            listener.Stop();
            worker.Join(5000);
        }
    }
}
