param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$Installed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$publisher = '27e3e2e77a0c5f3428eeb95a35825d4cf0c8710e760e9c8cb12b447d39603252'
$root = (Resolve-Path -LiteralPath $Directory).Path
$coreHash = (Get-FileHash -LiteralPath (Join-Path $root 'FengWoCore.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
$coreManifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
if ($coreManifest.coreSha256 -cne $coreHash) { throw 'Core manifest must bind the signed Core file hash' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -cne 'fengwo-fully-signed-payload-v1' -or $manifest.passed -ne $true) { throw 'Invalid signed payload manifest' }
$expected = @{}
foreach ($row in $manifest.files) {
    if (-not $row.path.StartsWith('bundle/')) { continue }
    $name = $row.path.Substring(7)
    if ($Installed -and $name.StartsWith('prerequisites/')) {
        if ($name -cne 'prerequisites/fengwo_install_cleanup.ps1') { continue }
        $name = 'fengwo_install_cleanup.ps1'
    }
    if ($expected.ContainsKey($name)) { throw 'Duplicate payload manifest entry' }
    $expected[$name] = $row
}
$results = @()
$seen = @{}
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point in release payload' }
    $name = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
    $row = $expected[$name]
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($row) {
        if ($hash -cne $row.sha256) { throw ('Payload content changed: ' + $name) }
        $seen[$name] = $true
    }
    $stream = [IO.File]::OpenRead($file.FullName)
    try { $pe = $stream.ReadByte() -eq 0x4d -and $stream.ReadByte() -eq 0x5a } finally { $stream.Dispose() }
    $code = $pe -or $file.Extension -in @('.exe', '.dll', '.sys', '.ps1', '.ps1xml', '.psc1', '.psd1', '.psm1', '.cdxml', '.mof', '.js', '.bat', '.cmd', '.vbs')
    if ($name -ceq 'data/flutter_assets/packages/flutter_js/assets/js/fetch.js' -and -not $pe) {
        if ($hash -cne '466306adec694b9c09cfbc2702810a623396f23f51158e0fad47c513ddcf2317' -or -not $row -or $row.action -cne 'copied_unchanged') { throw 'Pinned embedded JavaScript asset changed' }
        $code = $false
    }
    if (-not $code) { continue }
    $uninstaller = $Installed -and $name -cmatch '^unins\d+\.exe$'
    if (-not $row -and -not $uninstaller) { throw ('Unexpected executable code: ' + $name) }
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) { throw ('Trusted timestamped signature missing: ' + $name + ' (' + $signature.Status + ')') }
    $certificateHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($signature.SignerCertificate.RawData)).ToLowerInvariant()
    if (($uninstaller -or $row.action -ceq 'ov_signed') -and $certificateHash -cne $publisher) { throw ('OV publisher changed: ' + $name) }
    $results += @{ path = $name; sha256 = $hash; status = [string]$signature.Status; publisher_certificate_sha256 = $certificateHash; subject = $signature.SignerCertificate.Subject; timestamp_subject = $signature.TimeStamperCertificate.Subject; installed_uninstaller = $uninstaller }
}
foreach ($name in $expected.Keys) {
    if (-not $seen.ContainsKey($name)) { throw ('Missing release payload file: ' + $name) }
}
if ($results.Count -lt 25) { throw 'Incomplete signed binary inventory' }
if ($Installed -and @($results | Where-Object installed_uninstaller).Count -ne 1) { throw 'Expected exactly one signed installed uninstaller' }
@{ passed = $true; installed = [bool]$Installed; count = $results.Count; files = $results; sac_enforcement_test_passed = $false } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
