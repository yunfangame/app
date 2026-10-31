param(
    [Parameter(Mandatory = $true)][string]$CorePath,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$binding = if ($Architecture -eq 'x64') {
    @{ offset = 58288320; bytes = 427552; sha256 = 'e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce' }
} else {
    @{ offset = 53395488; bytes = 222488; sha256 = 'f7ba89005544be9d85231a9e0d5f23b2d15b3311667e2dad0debd344918a3f80' }
}
$core = [IO.File]::ReadAllBytes($CorePath)
$dll = [byte[]]::new($binding.bytes)
[Array]::Copy($core, $binding.offset, $dll, 0, $binding.bytes)
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($dll)).ToLowerInvariant()
if ($hash -cne $binding.sha256) { throw 'The embedded Wintun binary differs from the published 1.1.1 dependency' }
$path = Join-Path $OutputDirectory 'embedded-wintun.dll'
[IO.File]::WriteAllBytes($path, $dll)
$signature = Get-AuthenticodeSignature -LiteralPath $path
if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) { throw 'The embedded Wintun DLL lacks a valid timestamped vendor signature' }
@{ passed = $true; architecture = $Architecture; core_sha256 = (Get-FileHash $CorePath).Hash.ToLowerInvariant(); embedded_sha256 = $hash; embedded_offset = $binding.offset; dependency = 'github.com/metacubex/sing-tun@v0.4.22'; signature_status = [string]$signature.Status; signer_subject = $signature.SignerCertificate.Subject; timestamp_subject = $signature.TimeStamperCertificate.Subject; vendor_signature_preserved = $true; sac_enforcement_test_passed = $false } | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'embedded-wintun-signature.json') -Encoding utf8NoBOM
