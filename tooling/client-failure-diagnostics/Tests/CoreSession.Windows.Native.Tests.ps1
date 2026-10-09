[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Host 'SKIP native Windows named-pipe process checks: Windows is required.'
    return
}

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'ClientProtocol.ps1')
if (-not ('FengWoDiagnosticCoreSession' -as [type])) {
    Add-FwDiagnosticType -Path (Join-Path $root 'ClientCoreSession.cs')
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('fengwo-windows-native-fixture-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Reflection;
using System.Text;
using System.Threading;

public static class __FIXTURE_CLASS__
{
    private static readonly bool NeverConnect = __NEVER_CONNECT__;
    public static int Main(string[] arguments)
    {
        string executable = Assembly.GetExecutingAssembly().Location;
        File.WriteAllText(Path.ChangeExtension(executable, ".pid"), Process.GetCurrentProcess().Id.ToString());
        if (arguments.Length != 1) return 2;
        if (NeverConnect) { Thread.Sleep(30000); return 0; }
        Console.Out.Write(new string('o', 180000));
        Console.Out.Flush();
        Console.Error.Write(new string('e', 180000));
        Console.Error.Flush();
        string address = arguments[0];
        string pipeName = address.Substring(address.LastIndexOf('\\') + 1);
        using (NamedPipeClientStream pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous))
        {
            pipe.Connect(5000);
            for (;;)
            {
                byte[] header = new byte[4];
                if (!ReadExact(pipe, header)) return 0;
                int length = BitConverter.ToInt32(header, 0);
                if (length < 0 || length > 1048576) return 3;
                byte[] body = new byte[length];
                if (!ReadExact(pipe, body)) return 0;
                string text = Encoding.UTF8.GetString(body);
                if (text == "stall") { Thread.Sleep(30000); return 0; }
                if (text == "exit-now") return 0;
                for (int index = 0; index < header.Length; index++) pipe.Write(header, index, 1);
                for (int index = 0; index < body.Length; index++) pipe.Write(body, index, 1);
                pipe.Flush();
            }
        }
    }
    private static bool ReadExact(Stream stream, byte[] buffer)
    {
        int offset = 0;
        while (offset < buffer.Length)
        {
            int count = stream.Read(buffer, offset, buffer.Length - offset);
            if (count == 0) return false;
            offset += count;
        }
        return true;
    }
}
'@

$script:nativePassed = 0
$script:nativeFailures = New-Object 'System.Collections.Generic.List[string]'
function Assert-NativeSession([bool]$Condition, [string]$Reason) {
    if (-not $Condition) { throw $Reason }
}
function Test-NativeSessionCase([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:nativePassed++; Write-Host ('PASS ' + $Name) }
    catch { $script:nativeFailures.Add($Name + ': ' + $_.Exception.Message); Write-Host ('FAIL ' + $Name) }
}
function New-NativeCoreFixture([bool]$NeverConnect) {
    $suffix = [Guid]::NewGuid().ToString('N')
    $path = Join-Path $temporary ('core-native-' + $suffix + '.exe')
    $value = 'false'
    if ($NeverConnect) { $value = 'true' }
    $definition = $source.Replace('__FIXTURE_CLASS__', ('FengWoNativeCoreFixture_' + $suffix)).Replace('__NEVER_CONNECT__', $value)
    $parameters = New-Object System.CodeDom.Compiler.CompilerParameters
    $parameters.CompilerOptions='/langversion:5'
    $parameters.GenerateExecutable=$true
    $parameters.GenerateInMemory=$false
    $parameters.OutputAssembly=$path
    [void]$parameters.ReferencedAssemblies.Add('System.dll')
    [void]$parameters.ReferencedAssemblies.Add('System.Core.dll')
    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    try {
        $result = $provider.CompileAssemblyFromSource($parameters, [string[]]@($definition))
        if ($result.Errors.HasErrors) {
            $codes = @($result.Errors | Where-Object {-not $_.IsWarning} | ForEach-Object {$_.ErrorNumber})
            throw ('NATIVE_FIXTURE_COMPILATION_FAILED: ' + ($codes -join ','))
        }
        if (-not [IO.File]::Exists($path)) { throw 'NATIVE_FIXTURE_EXECUTABLE_MISSING' }
    }
    finally { $provider.Dispose() }
    return $path
}

$guardSession = $null
$session = $null
try {
    $executable = New-NativeCoreFixture $false
    $neverConnect = New-NativeCoreFixture $true
    $guardSession = [FengWoDiagnosticCoreSession]::Start($executable, 10000)
    $guardProcessId = $guardSession.OwnedPid

    Test-NativeSessionCase 'Native child identity and frame roundtrip survive 180 KB stdout and stderr' {
        $session = [FengWoDiagnosticCoreSession]::Start($executable, 10000)
        $ownedProcessId = $session.OwnedPid
        try {
            Assert-NativeSession ($session.IsAlive -and $session.PeerIdentityVerified -and $guardSession.PeerIdentityVerified) 'Windows native peer PID was not verified'
            Assert-NativeSession ($ownedProcessId -gt 0 -and $ownedProcessId -ne $guardProcessId) 'Independent fixture processes were not created'
            $text = '{"id":"native-fixture","message":"' + [char]0x8702 + [char]0x7a9d + '"}'
            $session.SendFrame($text, 1000)
            Assert-NativeSession ($session.ReadFrame(1000) -ceq $text) 'Native fragmented frame did not roundtrip'
        }
        finally { $session.Dispose(); $session=$null }
        Assert-NativeSession ($null -eq (Get-Process -Id $ownedProcessId -ErrorAction SilentlyContinue)) 'Disposed native child still runs'
        $guardSession.SendFrame('guard-after-dispose', 1000)
        Assert-NativeSession ($guardSession.IsAlive -and $guardSession.ReadFrame(1000) -ceq 'guard-after-dispose') 'Disposal terminated another fixture process'
    }

    Test-NativeSessionCase 'Read timeout terminates only its owned stalled native child' {
        $session = [FengWoDiagnosticCoreSession]::Start($executable, 10000)
        $ownedProcessId = $session.OwnedPid
        try {
            Assert-NativeSession $session.PeerIdentityVerified 'Stall fixture peer PID was not verified'
            $session.SendFrame('stall', 1000)
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $errorText = ''
            try { [void]$session.ReadFrame(150) }
            catch { $errorText=$_.Exception.ToString() }
            Assert-NativeSession ($errorText -match 'TimeoutException' -and $watch.ElapsedMilliseconds -lt 6000 -and $session.IsDisposed) 'Native stalled read was not bounded and disposed'
            Assert-NativeSession ($null -eq (Get-Process -Id $ownedProcessId -ErrorAction SilentlyContinue)) 'Timed out native child still runs'
            $guardSession.SendFrame('guard-after-timeout', 1000)
            Assert-NativeSession ($guardSession.IsAlive -and $guardSession.ReadFrame(1000) -ceq 'guard-after-timeout') 'Timeout terminated another fixture process'
        }
        finally { $session.Dispose(); $session=$null }
    }

    Test-NativeSessionCase 'Startup timeout cleans up native child that never connects its pipe' {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $errorText = ''
        try { [void][FengWoDiagnosticCoreSession]::Start($neverConnect, 1000) }
        catch { $errorText=$_.Exception.ToString() }
        Assert-NativeSession ($errorText -match 'TimeoutException' -and $watch.ElapsedMilliseconds -lt 6000) 'Native startup connection timeout was not bounded'
        $pidPath = [IO.Path]::ChangeExtension($neverConnect, '.pid')
        Assert-NativeSession ([IO.File]::Exists($pidPath)) 'Native startup fixture did not record its PID'
        $ownedProcessId = [int][IO.File]::ReadAllText($pidPath)
        Assert-NativeSession ($null -eq (Get-Process -Id $ownedProcessId -ErrorAction SilentlyContinue)) 'Unconnected native child was not cleaned up'
        $guardSession.SendFrame('guard-after-startup-timeout', 1000)
        Assert-NativeSession ($guardSession.IsAlive -and $guardSession.ReadFrame(1000) -ceq 'guard-after-startup-timeout') 'Startup cleanup terminated another fixture process'
    }
}
finally {
    if ($null -ne $session) {$session.Dispose()}
    if ($null -ne $guardSession) {$guardSession.Dispose()}
    [IO.Directory]::Delete($temporary, $true)
}

Assert-NativeSession (-not [IO.Directory]::Exists($temporary)) 'Native fixture files were not deleted'
Write-Host ('RESULT native_windows_cases=' + $script:nativePassed + ' failed=' + $script:nativeFailures.Count)
foreach ($failure in $script:nativeFailures) {Write-Host $failure}
if ($script:nativeFailures.Count -gt 0) {exit 1}
