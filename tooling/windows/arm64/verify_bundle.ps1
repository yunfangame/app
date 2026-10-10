param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [string]$ExpectedVersion = '1.0.8'
)

. (Join-Path $PSScriptRoot 'common.ps1')
$environment = Assert-FwArmRunner
$bundle = (Resolve-Path -LiteralPath $BundleDirectory).Path
$binaries = New-Object 'Collections.Generic.List[object]'
$excludedBootstrappers = New-Object 'Collections.Generic.List[object]'
$managedArchitectureIndependent = New-Object 'Collections.Generic.List[object]'
$failure = $null

function Get-FwAnyCpuIdentity {
    param([string]$Path)
    $identity = Get-FwPeIdentity $Path
    if ($identity.machine -cne '0x014c') { throw 'The designated managed utility has an unexpected PE machine' }
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        $stream.Position = 0x3c
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset + 6
        $sectionCount = $reader.ReadUInt16()
        $stream.Position = $peOffset + 20
        $optionalSize = $reader.ReadUInt16()
        $optionalOffset = $peOffset + 24
        $stream.Position = $optionalOffset
        if ($reader.ReadUInt16() -ne 0x10b -or $optionalSize -lt 216) { throw 'The designated managed utility is not a complete PE32 image' }
        $stream.Position = $optionalOffset + 92
        if ($reader.ReadUInt32() -lt 15) { throw 'The designated managed utility has no CLR directory' }
        $stream.Position = $optionalOffset + 96 + 14 * 8
        $clrRva = $reader.ReadUInt32()
        $clrSize = $reader.ReadUInt32()
        if ($clrRva -eq 0 -or $clrSize -lt 72) { throw 'The designated managed utility has no valid CLR header' }
        $clrOffset = $null
        $sectionTable = $optionalOffset + $optionalSize
        if ($sectionCount -eq 0 -or $sectionTable + $sectionCount * 40 -gt $stream.Length) { throw 'The designated managed utility has an invalid section table' }
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $stream.Position = $sectionTable + $index * 40 + 8
            $virtualSize = $reader.ReadUInt32()
            $virtualAddress = $reader.ReadUInt32()
            $rawSize = $reader.ReadUInt32()
            $rawOffset = $reader.ReadUInt32()
            if ($clrRva -ge $virtualAddress -and $clrRva -lt [long]$virtualAddress + [Math]::Max($virtualSize, $rawSize)) {
                $delta = [long]$clrRva - $virtualAddress
                if ($delta + 72 -gt $rawSize -or [long]$rawOffset + $delta + 72 -gt $stream.Length) { throw 'The designated managed utility CLR header is outside its section' }
                $clrOffset = [long]$rawOffset + $delta
                break
            }
        }
        if ($null -eq $clrOffset) { throw 'The designated managed utility CLR header could not be mapped' }
        $stream.Position = $clrOffset
        if ($reader.ReadUInt32() -lt 72) { throw 'The designated managed utility CLR header is truncated' }
        $stream.Position = $clrOffset + 16
        $flags = $reader.ReadUInt32()
        if ($flags -ne 1) { throw 'The designated utility is not pure AnyCPU IL without 32-bit requirements' }
        $identity.path = 'EnableLoopback.exe'
        $identity.clr_flags = ('0x{0:x8}' -f $flags)
        $identity.il_only = $true
        $identity.requires_32bit = $false
        $identity.prefers_32bit = $false
        $identity.actual_managed_runtime_execution_verified = $false
        return $identity
    } finally { $reader.Dispose(); $stream.Dispose() }
}

try {
    foreach ($name in @('FengWo.exe', 'FlClashCore.exe', 'FlClashHelperService.exe', 'flutter_windows.dll', 'rust_api.dll', 'wifi_ssid_plugin.dll', 'quickjs_c_bridge.dll', 'manifest.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bundle $name) -PathType Leaf)) { throw ('Required ARM64 bundle file is missing: ' + $name) }
    }
    $application = Get-Item -LiteralPath (Join-Path $bundle 'FengWo.exe')
    if ($application.VersionInfo.ProductVersion -cne $ExpectedVersion -or $application.VersionInfo.FileVersion -cne $ExpectedVersion -or $application.VersionInfo.ProductName -cne '蜂窝加速器') { throw 'The application version or product identity is incorrect' }
    $manifest = Get-Content -LiteralPath (Join-Path $bundle 'manifest.json') -Raw | ConvertFrom-Json
    $core = Get-FwPeIdentity (Join-Path $bundle 'FlClashCore.exe')
    if ($manifest.coreSha256 -cne $core.sha256) { throw 'The packaged Core hash is not the manifest hash' }
    foreach ($file in @(Get-ChildItem -LiteralPath $bundle -File -Recurse)) {
        $relative = $file.FullName.Substring($bundle.Length).TrimStart('\', '/')
        if ($relative -ceq 'EnableLoopback.exe') {
            $managedArchitectureIndependent.Add((Get-FwAnyCpuIdentity $file.FullName))
            continue
        }
        if ($relative -ieq 'prerequisites\vc_redist.exe') {
            $excludedBootstrappers.Add((Get-FwPeIdentity $file.FullName))
            continue
        }
        if ($file.Extension -notin @('.exe', '.dll', '.sys', '.so')) { continue }
        $header = [IO.File]::OpenRead($file.FullName)
        try { $isPe = ($header.Length -ge 2 -and $header.ReadByte() -eq 0x4d -and $header.ReadByte() -eq 0x5a) } finally { $header.Dispose() }
        if (-not $isPe) {
            if ($file.Extension -ne '.so') { throw ('Native executable is not a PE image: ' + $relative) }
            continue
        }
        $identity = Get-FwPeIdentity $file.FullName
        $identity.path = $relative
        $binaries.Add($identity)
        if (-not $identity.arm64) { throw ('Non-ARM64 native payload: ' + $relative + ' (' + $identity.machine + ')') }
    }
    if ($binaries.Count -lt 8) { throw 'The native bundle inspection was incomplete' }
    $installer = Get-FwPeIdentity $InstallerPath
    $signature = Get-AuthenticodeSignature -LiteralPath $InstallerPath
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'package.json') ([ordered]@{ version = $ExpectedVersion; architecture = 'arm64'; installer = $installer; installer_bootstrapper_is_application_architecture_proof = $false; authenticode_status = $signature.Status.ToString(); payload = @($binaries.ToArray()); separate_runtime_bootstrappers = @($excludedBootstrappers.ToArray()); managed_architecture_independent = @($managedArchitectureIndependent.ToArray()); core_manifest_sha256 = $manifest.coreSha256 })
} catch {
    $failure = $_.Exception.Message
} finally {
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'bundle-verification.json') ([ordered]@{ passed = ($null -eq $failure); failure = $failure; environment = $environment; native_payload_count = $binaries.Count; payload = @($binaries.ToArray()); separate_runtime_bootstrappers = @($excludedBootstrappers.ToArray()); managed_architecture_independent = @($managedArchitectureIndependent.ToArray()) })
}
if ($failure) { throw $failure }
