$ErrorActionPreference = 'Stop'

function Save-FwArmEvidence {
    param([string]$Path, [object]$Value)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 15), (New-Object Text.UTF8Encoding($false)))
}

function Get-FwPeIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)
    $file = Get-Item -LiteralPath $Path
    $stream = [IO.File]::OpenRead($file.FullName)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw ('Invalid DOS image: ' + $file.Name) }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        if ($offset -gt ($stream.Length - 24)) { throw ('Invalid PE offset: ' + $file.Name) }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw ('Invalid PE signature: ' + $file.Name) }
        $machine = $reader.ReadUInt16()
        return [ordered]@{ path = $file.FullName; machine = ('0x{0:x4}' -f $machine); arm64 = ($machine -eq 0xaa64); sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); bytes = $file.Length }
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Assert-FwArmRunner {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or $env:RUNNER_ARCH -ine 'ARM64') { throw 'An isolated native ARM64 GitHub Actions Windows runner is required' }
    if (-not ('FengWoArm64Environment' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class FengWoArm64Environment {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool IsWow64Process2(IntPtr process, out ushort processMachine, out ushort nativeMachine);
    public static ushort[] Machines(int pid) {
        using (Process process = Process.GetProcessById(pid)) {
            ushort current, native;
            if (!IsWow64Process2(process.Handle, out current, out native)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            return new ushort[] {current, native};
        }
    }
}
'@
    }
    $machines = [FengWoArm64Environment]::Machines($PID)
    if ($machines[1] -ne 0xaa64) { throw 'The Windows kernel does not report ARM64 hardware' }
    return [ordered]@{ os = [Environment]::OSVersion.VersionString; os_native_machine = ('0x{0:x4}' -f $machines[1]); powershell_process_machine = ('0x{0:x4}' -f $machines[0]); powershell = $PSVersionTable.PSVersion.ToString(); runner_arch = $env:RUNNER_ARCH; runner_image = $env:ImageOS; image_version = $env:ImageVersion; commit = $env:GITHUB_SHA }
}

function Assert-FwArmProcess {
    param([int]$ProcessId)
    $machines = [FengWoArm64Environment]::Machines($ProcessId)
    if ($machines[0] -ne 0 -or $machines[1] -ne 0xaa64) { throw 'The tested process is emulated or is not on native ARM64 Windows' }
}
