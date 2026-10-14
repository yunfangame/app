param(
  [Parameter(Mandatory=$true)][string]$InstallerPath,
  [Parameter(Mandatory=$true)][string]$ExpectedHash
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This prepared candidate is x64 only' }
if (Get-Process FengWo -ErrorAction SilentlyContinue) { throw 'Exit the client before preparing the upgrade' }
$root = $script:AuditRoot
if (-not $root -or -not (Test-Path -LiteralPath $root)) { throw 'Initialize the audit directory first' }
if ($ExpectedHash -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid expected installer hash' }
$installer = (Get-Item -LiteralPath $InstallerPath).FullName
$hash = (Get-FileHash -Algorithm SHA256 $installer).Hash.ToLowerInvariant()
if ($hash -cne $ExpectedHash) { throw 'Candidate installer hash mismatch' }
$signature = Get-AuthenticodeSignature $installer
if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) { throw 'Candidate installer signature or timestamp is not trusted' }
$sha = [Security.Cryptography.SHA256]::Create()
try { $certificateHash = [BitConverter]::ToString($sha.ComputeHash($signature.SignerCertificate.RawData)).Replace('-','').ToLowerInvariant() }
finally { $sha.Dispose() }
if ($certificateHash -cne '27e3e2e77a0c5f3428eeb95a35825d4cf0c8710e760e9c8cb12b447d39603252') { throw 'Unexpected OV signing certificate' }
$source = Join-Path $env:APPDATA 'FengWo'
$backup = Join-Path ([Environment]::GetFolderPath('Desktop')) ('FengWo-Private-Profile-Backup-'+(Get-Date -Format yyyyMMdd-HHmmss))
Copy-Item -LiteralPath $source -Destination $backup -Recurse
$evidence = [ordered]@{ phase='candidate-prepared'; time=(Get-Date).ToString('o'); sha256=$hash; signature=$signature.Status.ToString(); signer=$signature.SignerCertificate.Subject; timestamp=$signature.TimeStamperCertificate.Subject; profile_backup_created=(Test-Path $backup); installed=$false }
$evidence | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $root 'candidate-prepared.json')
Write-Output ('CANDIDATE_READY SHA256='+$hash+' OV='+$signature.Status+' PROFILE_BACKUP=True')
$script:CandidateInstaller = $installer
$script:CandidateHash = $hash
