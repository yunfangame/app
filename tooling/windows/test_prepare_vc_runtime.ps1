Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) "flclash-vc-runtime-tests-$([guid]::NewGuid().ToString('N'))"
[void][IO.Directory]::CreateDirectory($testDirectory)
. (Join-Path $PSScriptRoot 'prepare_vc_runtime.ps1') -Architecture x64 -OutputDirectory $testDirectory

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-Throws {
  param([scriptblock]$Action, [string]$Pattern)
  $failure = $null
  try { & $Action | Out-Null } catch { $failure = $_ }
  Assert-True ($null -ne $failure) "Expected failure matching: $Pattern"
  Assert-True ($failure.Exception.Message -match $Pattern) "Unexpected failure: $($failure.Exception.Message)"
}

function Reset-Fixture {
  $script:downloadCount = 0
  $script:downloadFailure = $false
  $script:signatureStatus = 'Valid'
  $script:signerName = 'Microsoft Corporation'
  $script:companyName = 'Microsoft Corporation'
  $script:productName = 'Microsoft Visual C++ v14 Redistributable (x64) - 14.50.35719'
  $script:fileVersion = '14.50.35719.0'
  $script:productVersion = '14.50.35719.0'
  $script:lastUri = $null
  $script:vsDirectories = @()
}

function Get-VcRuntimeVisualStudioPaths {
  return $script:vsDirectories
}

function Get-VcRuntimeSignature {
  param([string]$Path)
  $status = if ([IO.File]::ReadAllText($Path) -eq 'corrupt') { 'HashMismatch' } else { $script:signatureStatus }
  $certificate = [pscustomobject]@{}
  $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { return $script:signerName }
  return [pscustomobject]@{ Status = $status; SignerCertificate = $certificate }
}

function Get-VcRuntimeFileVersion {
  param([string]$Path)
  return [IO.File]::ReadAllText($Path) | ConvertFrom-Json
}

function Save-VcRuntimeDownload {
  param([string]$Uri, [string]$Path)
  $script:downloadCount++
  $script:lastUri = $Uri
  $metadata = [pscustomobject]@{
    CompanyName = $script:companyName
    ProductName = $script:productName
    FileVersion = $script:fileVersion
    ProductVersion = $script:productVersion
  } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($Path, $metadata)
  if ($script:downloadFailure) { throw 'Simulated download failure' }
}

function Invoke-Fixture {
  param([string]$Name, [string]$Architecture = 'x64', [string]$MinimumVersion = '14.0.0.0')
  return Invoke-PrepareVcRuntime -Architecture $Architecture -OutputDirectory (Join-Path $testDirectory $Name) -MinimumVersion $MinimumVersion
}

try {
  Reset-Fixture
  $result = Invoke-Fixture -Name 'success' -MinimumVersion '14.44.35211.0'
  $installer = Join-Path $result.OutputDirectory 'vc_redist.exe'
  $metadata = [IO.File]::ReadAllText((Join-Path $result.OutputDirectory 'vc_runtime.iss'))
  $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  Assert-True ($script:lastUri -ceq 'https://aka.ms/vc14/vc_redist.x64.exe') 'Incorrect official download URI'
  Assert-True ($result.MinimumVersion -ceq '14.50.35719.0') 'Minimum version was not derived from the validated installer'
  Assert-True ($metadata.Contains('#define VcRuntimeArchitecture "x64"')) 'Architecture define missing'
  Assert-True ($metadata.Contains('#define VcRuntimeMinimumVersion "14.50.35719.0"')) 'Version define missing'
  Assert-True ($metadata.Contains("#define VcRuntimeInstallerSHA256 `"$hash`"")) 'SHA256 does not match the installer'
  [IO.File]::WriteAllText((Join-Path $result.OutputDirectory 'vc_runtime.iss'), 'stale metadata')
  Invoke-Fixture -Name 'success' | Out-Null
  Assert-True ($script:downloadCount -eq 1) 'Valid cache unexpectedly downloaded again'
  Assert-True ([IO.File]::ReadAllText((Join-Path $result.OutputDirectory 'vc_runtime.iss')) -ceq $metadata) 'Cached metadata was not regenerated'

  [IO.File]::WriteAllText($installer, 'corrupt')
  Invoke-Fixture -Name 'success' | Out-Null
  Assert-True ($script:downloadCount -eq 2) 'Corrupt cached installer was trusted'
  Assert-True ((Get-VcRuntimeFileVersion -Path $installer).FileVersion -ceq '14.50.35719.0') 'Corrupt cache was not replaced'

  Reset-Fixture
  $script:productName = 'Microsoft Visual C++ 2015-2022 Redistributable (ARM64) - 14.44.35211'
  $script:fileVersion = '14.44.35211'
  $script:productVersion = '14.44.35211.0'
  $result = Invoke-Fixture -Name 'arm64' -Architecture arm64
  Assert-True ($result.Architecture -ceq 'arm64') 'ARM64 output architecture incorrect'
  Assert-True ($script:lastUri -ceq 'https://aka.ms/vc14/vc_redist.arm64.exe') 'Incorrect ARM64 download URI'
  Assert-True ($result.MinimumVersion -ceq '14.44.35211.0') 'Three-component version was not normalized'

  foreach ($case in @(
    @{ Name = 'unsigned'; Property = 'signatureStatus'; Value = 'NotSigned'; Pattern = 'signature is not valid' },
    @{ Name = 'untrusted'; Property = 'signatureStatus'; Value = 'NotTrusted'; Pattern = 'signature is not valid' },
    @{ Name = 'wrong-signer'; Property = 'signerName'; Value = 'Example Corporation'; Pattern = 'signer is not Microsoft' },
    @{ Name = 'wrong-company'; Property = 'companyName'; Value = 'Example Corporation'; Pattern = 'not a Microsoft Visual' },
    @{ Name = 'wrong-product'; Property = 'productName'; Value = 'Microsoft Edge'; Pattern = 'not a Microsoft Visual' },
    @{ Name = 'wrong-arch'; Property = 'productName'; Value = 'Microsoft Visual C++ v14 Redistributable (ARM64) - 14.50.35719'; Pattern = 'architecture does not match' },
    @{ Name = 'invalid-version'; Property = 'fileVersion'; Value = 'unknown'; Pattern = 'Invalid VC\+\+ runtime version' },
    @{ Name = 'mismatched-version'; Property = 'productVersion'; Value = '14.44.35211.0'; Pattern = 'versions disagree' },
    @{ Name = 'download-failure'; Property = 'downloadFailure'; Value = $true; Pattern = 'Simulated download failure' }
  )) {
    Reset-Fixture
    Set-Variable -Name $case.Property -Value $case.Value -Scope Script
    Assert-Throws { Invoke-Fixture -Name $case.Name } $case.Pattern
    $caseDirectory = Join-Path $testDirectory $case.Name
    Assert-True (-not [IO.File]::Exists((Join-Path $caseDirectory 'vc_redist.exe'))) "Failed case published an installer: $($case.Name)"
    Assert-True (-not [IO.File]::Exists((Join-Path $caseDirectory 'vc_runtime.iss'))) "Failed case published metadata: $($case.Name)"
    Assert-True (@(Get-ChildItem -LiteralPath $caseDirectory -Filter '*.tmp').Count -eq 0) "Failed case leaked partial downloads: $($case.Name)"
  }

  Reset-Fixture
  Assert-Throws { Invoke-Fixture -Name 'too-old' -MinimumVersion '14.51.0.0' } 'older than required'
  Assert-Throws { Invoke-Fixture -Name 'bad-minimum' -MinimumVersion '14.50' } 'Invalid VC\+\+ runtime version'
  Assert-Throws { Invoke-Fixture -Name 'wrong-major' -MinimumVersion '15.0.0.0' } 'Unsupported VC\+\+ runtime version'
  Assert-Throws { Invoke-Fixture -Name 'unsupported-arch' -Architecture x86 } 'ValidateSet|validation|argument'

  Reset-Fixture
  $result = Invoke-Fixture -Name 'existing'
  $existingInstaller = Join-Path $result.OutputDirectory 'vc_redist.exe'
  $existingMetadata = Join-Path $result.OutputDirectory 'vc_runtime.iss'
  $originalInstaller = [IO.File]::ReadAllText($existingInstaller)
  $originalMetadata = [IO.File]::ReadAllText($existingMetadata)
  $script:downloadFailure = $true
  Assert-Throws { Invoke-Fixture -Name 'existing' -MinimumVersion '14.51.0.0' } 'Simulated download failure'
  Assert-True ([IO.File]::ReadAllText($existingInstaller) -ceq $originalInstaller) 'Failed update changed the existing installer'
  Assert-True ([IO.File]::ReadAllText($existingMetadata) -ceq $originalMetadata) 'Failed update changed the existing metadata'

  $script:downloadFailure = $false
  $script:fileVersion = '14.51.100.0'
  $script:productVersion = '14.51.100.0'
  $result = Invoke-Fixture -Name 'existing' -MinimumVersion '14.51.0.0'
  Assert-True ($result.MinimumVersion -ceq '14.51.100.0') 'Required version update failed'
  Assert-True ($script:downloadCount -eq 3) 'Outdated cached installer was not replaced by a new download'

  Reset-Fixture
  Invoke-Fixture -Name 'vs-update' | Out-Null
  $script:vsDirectories = @(Join-Path $testDirectory 'visual-studio')
  $localRuntime = Join-Path $script:vsDirectories[0] 'VC/Redist/MSVC/14.51.100/x64/Microsoft.VC143.CRT/vcruntime140.dll'
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($localRuntime))
  [IO.File]::WriteAllText($localRuntime, '{"FileVersion":"14.51.100.0"}')
  $armRuntime = Join-Path $script:vsDirectories[0] 'VC/Redist/MSVC/14.51.100/arm64/Microsoft.VC143.CRT/vcruntime140.dll'
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($armRuntime))
  [IO.File]::WriteAllText($armRuntime, '{"FileVersion":"14.52.0.0"}')
  Assert-Throws { Invoke-Fixture -Name 'vs-update' } 'older than required 14.51.100.0'
  $script:fileVersion = '14.51.100.0'
  $script:productVersion = '14.51.100.0'
  $result = Invoke-Fixture -Name 'vs-update'
  Assert-True ($result.MinimumVersion -ceq '14.51.100.0') 'Visual Studio runtime version was ignored'
  Assert-True ($script:downloadCount -eq 3) 'Visual Studio update did not refresh the cached runtime'
  Assert-Throws { Invoke-Fixture -Name 'vs-explicit-minimum' -MinimumVersion '14.52.1.0' } 'older than required 14.52.1.0'
  $script:productName = 'Microsoft Visual C++ v14 Redistributable (ARM64) - 14.51.100'
  Assert-Throws { Invoke-Fixture -Name 'vs-arm64' -Architecture arm64 } 'older than required 14.52.0.0'

  $rollbackDirectory = Join-Path $testDirectory 'rollback'
  [void][IO.Directory]::CreateDirectory($rollbackDirectory)
  $rollbackInstaller = Join-Path $rollbackDirectory 'vc_redist.exe'
  [IO.File]::WriteAllText($rollbackInstaller, 'previous installer')
  [void][IO.Directory]::CreateDirectory((Join-Path $rollbackDirectory 'vc_runtime.iss'))
  $stagedInstaller = Join-Path $rollbackDirectory 'staged.exe'
  $stagedMetadata = Join-Path $rollbackDirectory 'staged.iss'
  [IO.File]::WriteAllText($stagedInstaller, 'replacement installer')
  [IO.File]::WriteAllText($stagedMetadata, 'replacement metadata')
  Assert-Throws { Publish-VcRuntimeFiles -Installer $stagedInstaller -Metadata $stagedMetadata -OutputDirectory $rollbackDirectory } '.+'
  Assert-True ([IO.File]::ReadAllText($rollbackInstaller) -ceq 'previous installer') 'Failed publish did not restore the previous installer'

  Write-Output 'VC++ runtime preparation tests passed'
} finally {
  if ([IO.Directory]::Exists($testDirectory)) {
    [IO.Directory]::Delete($testDirectory, $true)
  }
}
