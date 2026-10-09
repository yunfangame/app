param(
    [string]$SessionPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'ClientCoreSession.cs'),
    [switch]$Child,
    [string]$PipeAddress
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Child) {
    $pipeName = $PipeAddress.Substring($PipeAddress.LastIndexOf('\') + 1)
    $client = [IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [IO.Pipes.PipeDirection]::InOut)
    try {
        [Console]::Out.Write(('o' * 180000))
        [Console]::Error.Write(('e' * 180000))
        $client.Connect(5000)
        while ($true) {
            $header = [byte[]]::new(4)
            $offset = 0
            while ($offset -lt 4) {
                $count = $client.Read($header, $offset, 4 - $offset)
                if ($count -eq 0) { exit 0 }
                $offset += $count
            }
            $length = [BitConverter]::ToInt32($header, 0)
            if ($length -lt 0 -or $length -gt 1048576) { exit 2 }
            $data = [byte[]]::new($length)
            $offset = 0
            while ($offset -lt $length) {
                $count = $client.Read($data, $offset, $length - $offset)
                if ($count -eq 0) { exit 0 }
                $offset += $count
            }
            $request = [Text.Encoding]::UTF8.GetString($data)
            if ($request -eq 'exit-now') { exit 0 }
            if ($request -eq 'stall') { Start-Sleep -Seconds 30; exit 0 }
            if ($request -eq 'bad-length') {
                $client.Write([byte[]]@(255, 255, 255, 127), 0, 4)
                $client.Flush()
                Start-Sleep -Seconds 30
                exit 0
            }
            for ($index = 0; $index -lt 4; $index++) { $client.Write($header, $index, 1) }
            for ($index = 0; $index -lt $data.Length; $index++) { $client.Write($data, $index, 1) }
            $client.Flush()
        }
    }
    finally { $client.Dispose() }
    exit 0
}

Add-Type -Path $SessionPath -CompilerOptions '/langversion:5'
Add-Type -CompilerOptions '/langversion:5' -TypeDefinition @'
using System;
using System.IO;
using System.Threading;

public sealed class FengWoFrameFixtureStream : Stream
{
    private readonly MemoryStream input;
    private readonly MemoryStream output = new MemoryStream();
    private readonly bool blockRead;
    private readonly bool blockWrite;
    private volatile bool disposed;
    public bool Closed { get { return disposed; } }
    public byte[] Written { get { return output.ToArray(); } }

    public FengWoFrameFixtureStream(byte[] data, bool blockRead, bool blockWrite)
    {
        input = new MemoryStream(data);
        this.blockRead = blockRead;
        this.blockWrite = blockWrite;
    }

    public override int Read(byte[] buffer, int offset, int count)
    {
        while (blockRead && !disposed) Thread.Sleep(5);
        if (disposed) throw new ObjectDisposedException("fixture");
        return input.Read(buffer, offset, Math.Min(count, 2));
    }

    public override void Write(byte[] buffer, int offset, int count)
    {
        while (blockWrite && !disposed) Thread.Sleep(5);
        if (disposed) throw new ObjectDisposedException("fixture");
        output.Write(buffer, offset, count);
    }

    protected override void Dispose(bool disposing)
    {
        disposed = true;
        input.Dispose();
        output.Dispose();
        base.Dispose(disposing);
    }

    public override bool CanRead { get { return true; } }
    public override bool CanWrite { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override long Length { get { throw new NotSupportedException(); } }
    public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }
}
'@

$script:passed = 0
function Assert-Session([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}

function New-FixtureSession($Stream) {
    $session = [Activator]::CreateInstance([FengWoDiagnosticCoreSession], $true)
    [FengWoDiagnosticCoreSession].GetField('transport', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($session, $Stream)
    return $session
}

function Assert-ReadFailure([byte[]]$Bytes, [string]$Pattern, [string]$Name) {
    $stream = [FengWoFrameFixtureStream]::new($Bytes, $false, $false)
    $session = New-FixtureSession $stream
    $failure = ''
    try { $null = $session.ReadFrame(1000) }
    catch { $failure = $_.Exception.ToString() }
    finally { $session.Dispose() }
    Assert-Session ($failure -match $Pattern -and $stream.Closed -and $session.IsDisposed) $Name
}

$text = '{"id":"1","message":"' + [char]0x8702 + [char]0x7a9d + '"}'
$encoded = [Text.Encoding]::UTF8.GetBytes($text)
$frame = [byte[]]([BitConverter]::GetBytes([int]$encoded.Length) + $encoded)
$stream = [FengWoFrameFixtureStream]::new($frame, $false, $false)
$session = New-FixtureSession $stream
try {
    Assert-Session ($session.ReadFrame(1000) -ceq $text) 'partial reads reconstruct UTF-8 frame exactly'
    $session.SendFrame($text, 1000)
    Assert-Session ([Convert]::ToBase64String($stream.Written) -ceq [Convert]::ToBase64String($frame)) 'write uses byte length and little-endian header'
}
finally { $session.Dispose(); $session.Dispose() }
Assert-Session ($stream.Closed -and $session.IsDisposed) 'dispose closes transport and is idempotent'

Assert-ReadFailure ([byte[]]@(1, 0)) 'EndOfStreamException' 'short header closes session'
Assert-ReadFailure ([byte[]]@(5, 0, 0, 0, 97, 98)) 'EndOfStreamException' 'short body closes session'
Assert-ReadFailure ([byte[]]@(1, 0, 0, 4)) 'exceeds 64 MiB' 'oversized frame rejected before allocation'
Assert-ReadFailure ([byte[]]@(255, 255, 255, 255)) 'exceeds 64 MiB' 'unsigned length cannot wrap into negative allocation'
Assert-ReadFailure ([byte[]]@(2, 0, 0, 0, 195, 40)) 'DecoderFallbackException' 'malformed UTF-8 rejected'

foreach ($operation in @('read', 'write')) {
    $stream = [FengWoFrameFixtureStream]::new([byte[]]@(), $operation -eq 'read', $operation -eq 'write')
    $session = New-FixtureSession $stream
    $failure = ''
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($operation -eq 'read') { $null = $session.ReadFrame(120) }
        else { $session.SendFrame('{}', 120) }
    }
    catch { $failure = $_.Exception.ToString() }
    finally { $session.Dispose() }
    Assert-Session ($failure -match 'TimeoutException' -and $timer.ElapsedMilliseconds -lt 1500 -and $stream.Closed) "$operation timeout closes session within bound"
}

$isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $isWindowsHost) {
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('fengwo-core-session-test-' + [Guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($temporary)
    $wrapper = Join-Path $temporary 'core-fixture'
    $pwshPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $singleQuote = [string][char]39
    $escapedQuote = $singleQuote + [char]34 + $singleQuote + [char]34 + $singleQuote
    $quotedPwsh = $singleQuote + $pwshPath.Replace($singleQuote, $escapedQuote) + $singleQuote
    $quotedScript = $singleQuote + $PSCommandPath.Replace($singleQuote, $escapedQuote) + $singleQuote
    $shell = '#!/bin/sh' + "`nexec " + $quotedPwsh + ' -NoLogo -NoProfile -File ' + $quotedScript + ' -Child -PipeAddress "$1"' + "`n"
    [IO.File]::WriteAllText($wrapper, $shell, [Text.UTF8Encoding]::new($false))
    & /bin/chmod u+x $wrapper
    if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare local process fixture' }
    try {
        $session = [FengWoDiagnosticCoreSession]::Start($wrapper, 10000)
        $ownedProcessId = $session.OwnedPid
        try {
            Assert-Session ($session.IsAlive -and $ownedProcessId -gt 0 -and -not $session.PeerIdentityVerified) 'local child starts without claiming Windows PID verification'
            $session.SendFrame($text, 1000)
            Assert-Session ($session.ReadFrame(1000) -ceq $text) 'real named pipe roundtrip survives large discarded stdout and stderr'
        }
        finally { $session.Dispose() }
        Assert-Session ($null -eq (Get-Process -Id $ownedProcessId -ErrorAction SilentlyContinue)) 'closing pipe lets owned child exit'

        $guardSession = [FengWoDiagnosticCoreSession]::Start($wrapper, 10000)
        $session = $null
        try {
            $session = [FengWoDiagnosticCoreSession]::Start($wrapper, 10000)
            $ownedProcessId = $session.OwnedPid
            $session.SendFrame('stall', 1000)
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $failure = ''
            try { $null = $session.ReadFrame(120) }
            catch { $failure = $_.Exception.ToString() }
            Assert-Session ($failure -match 'TimeoutException' -and $timer.ElapsedMilliseconds -lt 4500) 'stalled child read timeout includes bounded cleanup'
            Assert-Session ($null -eq (Get-Process -Id $ownedProcessId -ErrorAction SilentlyContinue)) 'timeout terminates only owned unresponsive child'
            $guardSession.SendFrame('{}', 1000)
            Assert-Session ($guardSession.IsAlive -and $guardSession.ReadFrame(1000) -ceq '{}') 'one timed-out session leaves another child operational'
        }
        finally {
            if ($null -ne $session) { $session.Dispose() }
            $guardSession.Dispose()
        }

        $neverConnect = Join-Path $temporary 'never-connect'
        $pidFile = Join-Path $temporary 'started-pid'
        $quotedPidFile = $singleQuote + $pidFile.Replace($singleQuote, $escapedQuote) + $singleQuote
        $shell = '#!/bin/sh' + "`nprintf '%s' " + '"$$" > ' + $quotedPidFile + "`nexec /bin/sleep 30`n"
        [IO.File]::WriteAllText($neverConnect, $shell, [Text.UTF8Encoding]::new($false))
        & /bin/chmod u+x $neverConnect
        if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare startup timeout fixture' }
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $failure = ''
        try { $null = [FengWoDiagnosticCoreSession]::Start($neverConnect, 200) }
        catch { $failure = $_.Exception.ToString() }
        Assert-Session ($failure -match 'TimeoutException' -and $timer.ElapsedMilliseconds -lt 4500) 'startup pipe connection timeout is bounded'
        $ownedProcessId = [int][IO.File]::ReadAllText($pidFile)
        Assert-Session ($null -eq (Get-Process -Id $ownedProcessId -ErrorAction SilentlyContinue)) 'startup timeout recovers its unconnected child'
    }
    finally { [IO.Directory]::Delete($temporary, $true) }
}
else {
    Write-Host 'Process fixture skipped: Windows PID authentication needs a native Windows fixture executable.'
}

Write-Host ("All {0} core-session checks passed." -f $script:passed)
