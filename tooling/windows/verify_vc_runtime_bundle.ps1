param(
  [Parameter(Mandatory = $true)]
  [string]$BundleDirectory,
  [Parameter(Mandatory = $true)]
  [ValidateSet('x64', 'arm64')]
  [string]$Architecture
)

. (Join-Path $PSScriptRoot 'prepare_vc_runtime.ps1') -Architecture $Architecture -OutputDirectory $BundleDirectory

function Assert-VcRuntimeBundle {
  param([string]$BundleDirectory, [string]$Architecture)
  $minimumVersion = [version]'14.0.0.0'
  foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
    $path = Join-Path $BundleDirectory $name
    if (-not [IO.File]::Exists($path)) { throw "Missing bundled runtime: $name" }
    $metadata = Get-VcRuntimeFileVersion -Path $path
    $version = ConvertTo-VcRuntimeVersion -Value $metadata.FileVersion
    if ($metadata.CompanyName -cne 'Microsoft Corporation') { throw "Invalid runtime publisher: $name" }
    if ($version -gt $minimumVersion) { $minimumVersion = $version }
  }
  $prerequisites = Join-Path $BundleDirectory 'prerequisites'
  $validated = Get-ValidatedVcRuntime -Path (Join-Path $prerequisites 'vc_redist.exe') -Architecture $Architecture -MinimumVersion $minimumVersion
  $include = [IO.File]::ReadAllText((Join-Path $prerequisites 'vc_runtime.iss'))
  foreach ($definition in @{
    VcRuntimeArchitecture = $Architecture
    VcRuntimeMinimumVersion = $validated.Version
    VcRuntimeInstallerSHA256 = $validated.SHA256
  }.GetEnumerator()) {
    $pattern = '(?m)^#define ' + [regex]::Escape($definition.Key) + ' "' + [regex]::Escape($definition.Value) + '"\r?$'
    if ([regex]::Matches($include, $pattern).Count -ne 1) {
      throw "VC++ runtime metadata mismatch: $($definition.Key)"
    }
  }
  if (-not [IO.File]::Exists((Join-Path $prerequisites 'vc_runtime_code.iss'))) {
    throw 'VC++ installer prerequisite logic is missing'
  }
  Write-Output "VC++ runtime bundle verified ($Architecture, $($validated.Version))"
}

if ($MyInvocation.InvocationName -ne '.') {
  Assert-VcRuntimeBundle -BundleDirectory $BundleDirectory -Architecture $Architecture
}
