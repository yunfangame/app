using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace FengWoStartupDiagnostics
{
    [Serializable]
    public sealed class PeMetadata
    {
        public ushort Machine { get; set; }
        public string Architecture { get; set; }
        public bool IsDll { get; set; }
        public string[] Imports { get; set; }
        public bool Valid { get; set; }
        public string[] Errors { get; set; }

        public PeMetadata()
        {
            Architecture = "unknown";
            Imports = new string[0];
            Errors = new string[0];
        }
    }

    [Serializable]
    public sealed class WindowRect
    {
        public int Left { get; set; }
        public int Top { get; set; }
        public int Right { get; set; }
        public int Bottom { get; set; }
        public int Width { get { return (int)Math.Max(0L, Math.Min(Int32.MaxValue, (long)Right - Left)); } }
        public int Height { get { return (int)Math.Max(0L, Math.Min(Int32.MaxValue, (long)Bottom - Top)); } }
    }

    [Serializable]
    public sealed class WindowSnapshot
    {
        public string Handle { get; set; }
        public string Title { get; set; }
        public bool Visible { get; set; }
        public bool Minimized { get; set; }
        public WindowRect Rect { get; set; }
    }

    public static class NativeProbe
    {
        private const long MaximumPeLength = 256L * 1024L * 1024L;

        public static PeMetadata ReadPe(string path)
        {
            PeMetadata result = new PeMetadata();
            List<string> errors = new List<string>();
            List<string> imports = new List<string>();
            try
            {
                byte[] data;
                using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    long snapshotLength = stream.Length;
                    if (snapshotLength < 64 || snapshotLength >= MaximumPeLength)
                    {
                        throw new InvalidDataException("PE file length must be at least 64 bytes and less than 256 MiB.");
                    }
                    data = new byte[(int)snapshotLength];
                    int offset = 0;
                    while (offset < data.Length)
                    {
                        int count = stream.Read(data, offset, data.Length - offset);
                        if (count == 0)
                        {
                            throw new EndOfStreamException("PE file changed or ended while being read.");
                        }
                        offset += count;
                    }
                }
                new PeReader(data).Read(result, imports, errors);
            }
            catch (Exception exception)
            {
                errors.Add(exception.Message);
            }
            imports.Sort(StringComparer.OrdinalIgnoreCase);
            result.Imports = imports.ToArray();
            result.Errors = errors.ToArray();
            result.Valid = errors.Count == 0;
            return result;
        }

        public static List<WindowSnapshot> SnapshotWindows(int pid)
        {
            if (pid <= 0)
            {
                throw new ArgumentOutOfRangeException("pid");
            }
            List<WindowSnapshot> windows = new List<WindowSnapshot>();
            Exception callbackError = null;
            EnumWindowsCallback callback = delegate(IntPtr handle, IntPtr parameter)
            {
                try
                {
                    uint windowPid;
                    GetWindowThreadProcessId(handle, out windowPid);
                    if (windowPid != (uint)pid)
                    {
                        return true;
                    }
                    int titleLength = Math.Max(0, Math.Min(32767, GetWindowTextLengthW(handle)));
                    StringBuilder title = new StringBuilder(titleLength + 1);
                    GetWindowTextW(handle, title, title.Capacity);
                    NativeRect nativeRect;
                    WindowRect rect = null;
                    if (GetWindowRect(handle, out nativeRect))
                    {
                        rect = new WindowRect
                        {
                            Left = nativeRect.Left,
                            Top = nativeRect.Top,
                            Right = nativeRect.Right,
                            Bottom = nativeRect.Bottom
                        };
                    }
                    windows.Add(new WindowSnapshot
                    {
                        Handle = "0x" + (IntPtr.Size == 8 ? unchecked((ulong)handle.ToInt64()).ToString("X16") : unchecked((uint)handle.ToInt32()).ToString("X8")),
                        Title = title.ToString(),
                        Visible = IsWindowVisible(handle),
                        Minimized = IsIconic(handle),
                        Rect = rect
                    });
                    return true;
                }
                catch (Exception exception)
                {
                    callbackError = exception;
                    return false;
                }
            };
            bool succeeded = EnumWindows(callback, IntPtr.Zero);
            if (callbackError != null)
            {
                throw new InvalidOperationException("Window snapshot failed.", callbackError);
            }
            if (!succeeded)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to enumerate top-level windows.");
            }
            return windows;
        }

        public static string GetIntegrityLevel(int pid)
        {
            IntPtr process = IntPtr.Zero;
            IntPtr token = IntPtr.Zero;
            IntPtr information = IntPtr.Zero;
            try
            {
                if (pid <= 0)
                {
                    return "unknown";
                }
                process = OpenProcess(0x1000, false, (uint)pid);
                if (process == IntPtr.Zero || !OpenProcessToken(process, 0x0008, out token))
                {
                    return "unknown";
                }
                int requiredLength;
                bool queried = GetTokenInformation(token, 25, IntPtr.Zero, 0, out requiredLength);
                if (queried || Marshal.GetLastWin32Error() != 122 || requiredLength < IntPtr.Size + 4 || requiredLength > 65536)
                {
                    return "unknown";
                }
                information = Marshal.AllocHGlobal(requiredLength);
                int returnedLength;
                if (!GetTokenInformation(token, 25, information, requiredLength, out returnedLength) || returnedLength < IntPtr.Size + 4 || returnedLength > requiredLength)
                {
                    return "unknown";
                }
                IntPtr sid = Marshal.ReadIntPtr(information);
                long sidOffset = sid.ToInt64() - information.ToInt64();
                if (sid == IntPtr.Zero || sidOffset < 0 || sidOffset > returnedLength - 8)
                {
                    return "unknown";
                }
                int subAuthorityCount = Marshal.ReadByte(sid, 1);
                int sidLength = 8 + subAuthorityCount * 4;
                if (subAuthorityCount == 0 || sidOffset > returnedLength - sidLength || !IsValidSid(sid))
                {
                    return "unknown";
                }
                uint integrity = unchecked((uint)Marshal.ReadInt32(sid, 8 + (subAuthorityCount - 1) * 4));
                if (integrity >= 0x5000) return "protected";
                if (integrity >= 0x4000) return "system";
                if (integrity >= 0x3000) return "high";
                if (integrity >= 0x2100) return "medium-plus";
                if (integrity >= 0x2000) return "medium";
                if (integrity >= 0x1000) return "low";
                return "untrusted";
            }
            catch (Exception)
            {
                return "unknown";
            }
            finally
            {
                if (information != IntPtr.Zero) Marshal.FreeHGlobal(information);
                if (token != IntPtr.Zero) CloseHandle(token);
                if (process != IntPtr.Zero) CloseHandle(process);
            }
        }

        private sealed class PeReader
        {
            private readonly byte[] data;
            private readonly List<PeSection> sections = new List<PeSection>();
            private uint headerSize;
            private ulong imageBase;

            internal PeReader(byte[] bytes)
            {
                data = bytes;
            }

            internal void Read(PeMetadata metadata, List<string> imports, List<string> errors)
            {
                if (ReadUInt16(0) != 0x5A4D)
                {
                    throw new InvalidDataException("DOS MZ signature is missing.");
                }
                uint peOffsetValue = ReadUInt32(60);
                RequireRange(peOffsetValue, 24);
                if (peOffsetValue < 64)
                {
                    throw new InvalidDataException("PE header overlaps the DOS header.");
                }
                int peOffset = (int)peOffsetValue;
                if (ReadUInt32(peOffset) != 0x00004550)
                {
                    throw new InvalidDataException("PE signature is missing.");
                }
                metadata.Machine = ReadUInt16(peOffset + 4);
                metadata.Architecture = metadata.Machine == 0x014C ? "x86" : metadata.Machine == 0x8664 ? "x64" : metadata.Machine == 0xAA64 ? "arm64" : "unknown";
                metadata.IsDll = (ReadUInt16(peOffset + 22) & 0x2000) != 0;
                int sectionCount = ReadUInt16(peOffset + 6);
                int optionalSize = ReadUInt16(peOffset + 20);
                if (sectionCount > 96)
                {
                    throw new InvalidDataException("PE section count exceeds the Windows image limit.");
                }
                int optionalOffset = peOffset + 24;
                RequireRange(optionalOffset, optionalSize);
                if (optionalSize < 2) throw new InvalidDataException("PE optional header is truncated.");
                ushort magic = ReadUInt16(optionalOffset);
                int directoryOffset;
                int directoryCountOffset;
                if (magic == 0x010B)
                {
                    directoryOffset = 96;
                    directoryCountOffset = 92;
                    if (optionalSize < directoryOffset) throw new InvalidDataException("PE32 optional header is truncated.");
                    imageBase = ReadUInt32(optionalOffset + 28);
                }
                else if (magic == 0x020B)
                {
                    directoryOffset = 112;
                    directoryCountOffset = 108;
                    if (optionalSize < directoryOffset) throw new InvalidDataException("PE32+ optional header is truncated.");
                    imageBase = ReadUInt64(optionalOffset + 24);
                }
                else
                {
                    throw new InvalidDataException("PE optional header magic is unsupported.");
                }
                if ((metadata.Machine == 0x014C && magic != 0x010B) || ((metadata.Machine == 0x8664 || metadata.Machine == 0xAA64) && magic != 0x020B))
                {
                    throw new InvalidDataException("PE machine and optional header architecture disagree.");
                }
                headerSize = ReadUInt32(optionalOffset + 60);
                uint directoryCount = ReadUInt32(optionalOffset + directoryCountOffset);
                if ((ulong)directoryCount * 8UL > (ulong)(optionalSize - directoryOffset))
                {
                    throw new InvalidDataException("PE data directories exceed the optional header.");
                }
                int sectionTable = optionalOffset + optionalSize;
                RequireRange(sectionTable, sectionCount * 40);
                if (headerSize < (ulong)sectionTable + (ulong)sectionCount * 40UL || headerSize > data.Length)
                {
                    throw new InvalidDataException("PE SizeOfHeaders is outside the file or header tables.");
                }
                for (int index = 0; index < sectionCount; index++)
                {
                    int offset = sectionTable + index * 40;
                    PeSection section = new PeSection
                    {
                        VirtualSize = ReadUInt32(offset + 8),
                        VirtualAddress = ReadUInt32(offset + 12),
                        RawSize = ReadUInt32(offset + 16),
                        RawOffset = ReadUInt32(offset + 20)
                    };
                    if (section.RawSize != 0) RequireRange(section.RawOffset, section.RawSize);
                    if ((ulong)section.VirtualAddress + Math.Max(section.VirtualSize, section.RawSize) > 0x100000000UL)
                    {
                        throw new InvalidDataException("PE section virtual range overflows an RVA.");
                    }
                    sections.Add(section);
                }
                HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                if (directoryCount > 1)
                {
                    ReadImportDirectory(optionalOffset + directoryOffset + 8, false, imports, seen, errors);
                }
                if (directoryCount > 13)
                {
                    ReadImportDirectory(optionalOffset + directoryOffset + 13 * 8, true, imports, seen, errors);
                }
            }

            private void ReadImportDirectory(int directory, bool delayed, List<string> imports, HashSet<string> seen, List<string> errors)
            {
                try
                {
                    uint address = ReadUInt32(directory);
                    uint size = ReadUInt32(directory + 4);
                    if (address == 0)
                    {
                        if (size != 0) throw new InvalidDataException("Directory size is set without an RVA.");
                        return;
                    }
                    int descriptorSize = delayed ? 32 : 20;
                    MappedRange mapped = MapRva(address, descriptorSize);
                    if (size > mapped.Available)
                    {
                        throw new InvalidDataException("Directory size exceeds its file-backed RVA range.");
                    }
                    int limit = size == 0 ? mapped.Available : (int)size;
                    int descriptors = 0;
                    for (int offset = 0; offset <= limit - descriptorSize; offset += descriptorSize)
                    {
                        if (++descriptors > 4096) throw new InvalidDataException("Import descriptor count exceeds the safety limit.");
                        int position = mapped.Offset + offset;
                        bool terminator = true;
                        for (int entry = 0; entry < descriptorSize; entry += 4)
                        {
                            if (ReadUInt32(position + entry) != 0) terminator = false;
                        }
                        if (terminator) return;
                        uint nameAddress = ReadUInt32(position + (delayed ? 4 : 12));
                        if (delayed && (ReadUInt32(position) & 1) == 0)
                        {
                            if ((ulong)nameAddress < imageBase || (ulong)nameAddress - imageBase > UInt32.MaxValue)
                            {
                                throw new InvalidDataException("Delay-import name VA cannot be converted to an RVA.");
                            }
                            nameAddress = (uint)((ulong)nameAddress - imageBase);
                        }
                        if (nameAddress == 0) throw new InvalidDataException("Import descriptor has no DLL name RVA.");
                        string name = ReadDllName(nameAddress);
                        if (seen.Add(name)) imports.Add(name);
                    }
                    throw new InvalidDataException("Import descriptor terminator is missing or truncated.");
                }
                catch (Exception exception)
                {
                    errors.Add((delayed ? "Delay-import directory: " : "Import directory: ") + exception.Message);
                }
            }

            private string ReadDllName(uint address)
            {
                MappedRange mapped = MapRva(address, 1);
                int limit = Math.Min(mapped.Available, 4096);
                for (int length = 0; length < limit; length++)
                {
                    byte value = data[mapped.Offset + length];
                    if (value == 0)
                    {
                        if (length == 0) throw new InvalidDataException("Import DLL name is empty.");
                        return Encoding.ASCII.GetString(data, mapped.Offset, length);
                    }
                    if (value < 32 || value > 126) throw new InvalidDataException("Import DLL name contains a non-ASCII or control byte.");
                }
                throw new InvalidDataException("Import DLL name is not terminated within its file-backed range or safety limit.");
            }

            private MappedRange MapRva(uint address, int length)
            {
                if ((ulong)address + (ulong)length > 0x100000000UL)
                {
                    throw new InvalidDataException("RVA range overflows.");
                }
                if (address < headerSize)
                {
                    if ((ulong)address + (ulong)length > headerSize) throw new InvalidDataException("RVA crosses the file headers.");
                    RequireRange(address, length);
                    return new MappedRange((int)address, (int)(headerSize - address));
                }
                PeSection matched = null;
                ulong delta = 0;
                foreach (PeSection section in sections)
                {
                    ulong span = Math.Max(section.VirtualSize, section.RawSize);
                    if ((ulong)address >= section.VirtualAddress && (ulong)address - section.VirtualAddress < span)
                    {
                        if (matched != null) throw new InvalidDataException("RVA belongs to overlapping PE sections.");
                        matched = section;
                        delta = (ulong)address - section.VirtualAddress;
                    }
                }
                if (matched == null || delta + (ulong)length > matched.RawSize)
                {
                    throw new InvalidDataException("RVA is outside a file-backed PE section.");
                }
                ulong offset = (ulong)matched.RawOffset + delta;
                RequireRange((long)offset, length);
                return new MappedRange((int)offset, (int)((ulong)matched.RawSize - delta));
            }

            private void RequireRange(long offset, long length)
            {
                if (offset < 0 || length < 0 || offset > data.Length || length > data.Length - offset)
                {
                    throw new InvalidDataException("PE read range is outside the file.");
                }
            }

            private ushort ReadUInt16(int offset)
            {
                RequireRange(offset, 2);
                return (ushort)(data[offset] | (data[offset + 1] << 8));
            }

            private uint ReadUInt32(int offset)
            {
                RequireRange(offset, 4);
                return (uint)data[offset] | ((uint)data[offset + 1] << 8) | ((uint)data[offset + 2] << 16) | ((uint)data[offset + 3] << 24);
            }

            private ulong ReadUInt64(int offset)
            {
                RequireRange(offset, 8);
                return ReadUInt32(offset) | ((ulong)ReadUInt32(offset + 4) << 32);
            }
        }

        private sealed class PeSection
        {
            internal uint VirtualSize;
            internal uint VirtualAddress;
            internal uint RawSize;
            internal uint RawOffset;
        }

        private struct MappedRange
        {
            internal readonly int Offset;
            internal readonly int Available;

            internal MappedRange(int offset, int available)
            {
                Offset = offset;
                Available = available;
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect
        {
            internal int Left;
            internal int Top;
            internal int Right;
            internal int Bottom;
        }

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        private delegate bool EnumWindowsCallback(IntPtr handle, IntPtr parameter);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern int GetWindowTextLengthW(IntPtr handle);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern int GetWindowTextW(IntPtr handle, StringBuilder text, int maximumLength);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr handle, out NativeRect rect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr handle);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inheritHandle, uint processId);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);

        [DllImport("advapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTokenInformation(IntPtr token, int informationClass, IntPtr information, int length, out int returnLength);

        [DllImport("advapi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsValidSid(IntPtr sid);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }
}
