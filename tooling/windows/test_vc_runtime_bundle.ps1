Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) "fengwo-runtime-bundle-$([guid]::NewGuid().ToString('N'))"
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'prerequisites'))
. (Join-Path $PSScriptRoot 'verify_vc_runtime_bundle.ps1') -BundleDirectory $fixture -Architecture x64

function Get-VcRuntimeFileVersion {
  param([string]$Path)
  return [IO.File]::ReadAllText($Path) | ConvertFrom-Json
}

function Get-VcRuntimeSignature {
  param([string]$Path)
  $certificate = [pscustomobject]@{}
  $certificate | Add-Member -MemberType ScriptMethod -Name GetNameInfo -Value { 'Microsoft Corporation' }
  return [pscustomobject]@{ Status = 'Valid'; SignerCertificate = $certificate }
}

function Write-Fixture {
  $dll = @{ CompanyName = 'Microsoft Corporation'; FileVersion = '14.44.35211.0' } | ConvertTo-Json
  foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    [IO.File]::WriteAllText((Join-Path $fixture $name), $dll)
  }
  $installer = Join-Path $fixture 'prerequisites/vc_redist.exe'
  $metadata = @{
    CompanyName = 'Microsoft Corporation'
    ProductName = 'Microsoft Visual C++ v14 Redistributable (x64)'
    FileVersion = '14.50.35719.0'
    ProductVersion = '14.50.35719.0'
  } | ConvertTo-Json
  [IO.File]::WriteAllText($installer, $metadata)
  $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  $defines = "#define VcRuntimeArchitecture `"x64`"`n#define VcRuntimeMinimumVersion `"14.50.35719.0`"`n#define VcRuntimeInstallerSHA256 `"$hash`"`n"
  [IO.File]::WriteAllText((Join-Path $fixture 'prerequisites/vc_runtime.iss'), $defines)
  [IO.File]::WriteAllText((Join-Path $fixture 'prerequisites/vc_runtime_code.iss'), 'fixture')
}

function Assert-BundleRejected {
  param([string]$Pattern)
  $failure = $null
  try { Assert-VcRuntimeBundle -BundleDirectory $fixture -Architecture x64 | Out-Null } catch { $failure = $_ }
  if ($null -eq $failure -or $failure.Exception.Message -notmatch $Pattern) {
    throw "Expected bundle rejection matching $Pattern; got $failure"
  }
}

try {
  Write-Fixture
  Assert-VcRuntimeBundle -BundleDirectory $fixture -Architecture x64

  foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    Write-Fixture
    [IO.File]::Delete((Join-Path $fixture $name))
    Assert-BundleRejected 'Missing bundled runtime'
  }

  foreach ($change in @(
    @{ Old = '"x64"'; New = '"arm64"'; Expected = 'VcRuntimeArchitecture' },
    @{ Old = '14.50.35719.0'; New = '14.44.35211.0'; Expected = 'VcRuntimeMinimumVersion' },
    @{ Old = 'VcRuntimeInstallerSHA256'; New = 'WrongHash'; Expected = 'VcRuntimeInstallerSHA256' }
  )) {
    Write-Fixture
    $path = Join-Path $fixture 'prerequisites/vc_runtime.iss'
    [IO.File]::WriteAllText($path, [IO.File]::ReadAllText($path).Replace($change.Old, $change.New))
    Assert-BundleRejected $change.Expected
  }

  Write-Fixture
  $path = Join-Path $fixture 'vcruntime140.dll'
  [IO.File]::WriteAllText($path, [IO.File]::ReadAllText($path).Replace('14.44.35211.0', '14.51.0.0'))
  Assert-BundleRejected 'older than required'

  Write-Fixture
  $path = Join-Path $fixture 'prerequisites/vc_redist.exe'
  [IO.File]::AppendAllText($path, ' ')
  Assert-BundleRejected 'VcRuntimeInstallerSHA256'

  Write-Fixture
  [IO.File]::Delete((Join-Path $fixture 'prerequisites/vc_runtime_code.iss'))
  Assert-BundleRejected 'logic is missing'
  Write-Output 'VC++ runtime bundle verification tests passed'
} finally {
  [IO.Directory]::Delete($fixture, $true)
}
