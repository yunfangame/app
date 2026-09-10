param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('x64', 'arm64')]
  [string]$Architecture,
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$OutputDirectory,
  [string]$MinimumVersion = '14.0.0.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-VcRuntimeVersion {
  param([string]$Value)
  if ($Value -notmatch '^\s*(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:\s.*)?$') {
    throw "Invalid VC++ runtime version: $Value"
  }
  $revision = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
  $version = [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], $revision)
  if ($version.Major -ne 14 -or @($version.Major, $version.Minor, $version.Build, $version.Revision | Where-Object { $_ -gt 65535 }).Count -ne 0) {
    throw "Unsupported VC++ runtime version: $Value"
  }
  return $version
}

function Get-VcRuntimeSignature {
  param([string]$Path)
  return Get-AuthenticodeSignature -LiteralPath $Path
}

function Get-VcRuntimeFileVersion {
  param([string]$Path)
  return [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
}

function Get-VcRuntimeVisualStudioPaths {
  if ($env:OS -ne 'Windows_NT') { return @() }
  $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  if ([string]::IsNullOrWhiteSpace($programFiles)) { return @() }
  $vswhere = Join-Path $programFiles 'Microsoft Visual Studio/Installer/vswhere.exe'
  if (-not [IO.File]::Exists($vswhere)) { return @() }
  try {
    $installations = & $vswhere -all -products '*' -property installationPath
    if ($LASTEXITCODE -ne 0) { throw "vswhere exited with $LASTEXITCODE" }
    return @($installations | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  } catch {
    Write-Warning "Visual Studio runtime discovery failed; packaged DLL verification is required: $($_.Exception.Message)"
    return @()
  }
}

function Get-VcRuntimeBuildVersions {
  param([string]$Architecture)
  foreach ($installation in @(Get-VcRuntimeVisualStudioPaths)) {
    $pattern = Join-Path $installation "VC/Redist/MSVC/*/$Architecture/Microsoft.VC*.CRT/vcruntime140.dll"
    foreach ($library in @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)) {
      (Get-VcRuntimeFileVersion -Path $library.FullName).FileVersion
    }
  }
}

function Save-VcRuntimeDownload {
  param([string]$Uri, [string]$Path)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -TimeoutSec 180
}

function Get-ValidatedVcRuntime {
  param([string]$Path, [string]$Architecture, [version]$MinimumVersion)
  if (-not [IO.File]::Exists($Path) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
    throw 'VC++ runtime installer is missing or empty'
  }
  $signature = Get-VcRuntimeSignature -Path $Path
  if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
    throw "VC++ runtime signature is not valid: $($signature.Status)"
  }
  $signer = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
  if ($signer -cne 'Microsoft Corporation') {
    throw "VC++ runtime signer is not Microsoft Corporation: $signer"
  }
  $metadata = Get-VcRuntimeFileVersion -Path $Path
  if ($metadata.CompanyName -cne 'Microsoft Corporation' -or
      $metadata.ProductName -notmatch '^Microsoft Visual C\+\+ .+ Redistributable \((x64|ARM64)\)(?:\s+-\s+.*)?$') {
    throw 'Installer is not a Microsoft Visual C++ Redistributable'
  }
  if ($Matches[1] -ine $Architecture) {
    throw "VC++ runtime architecture does not match $Architecture"
  }
  $fileVersion = ConvertTo-VcRuntimeVersion -Value $metadata.FileVersion
  $productVersion = ConvertTo-VcRuntimeVersion -Value $metadata.ProductVersion
  if ($fileVersion -ne $productVersion) {
    throw 'VC++ runtime file and product versions disagree'
  }
  if ($fileVersion -lt $MinimumVersion) {
    throw "VC++ runtime $fileVersion is older than required $MinimumVersion"
  }
  return [pscustomobject]@{
    Version = $fileVersion.ToString(4)
    SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

function Publish-VcRuntimeFiles {
  param([string]$Installer, [string]$Metadata, [string]$OutputDirectory)
  $published = [Collections.Generic.List[object]]::new()
  try {
    foreach ($entry in @(
      @{ Source = $Installer; Name = 'vc_redist.exe' },
      @{ Source = $Metadata; Name = 'vc_runtime.iss' }
    )) {
      $destination = Join-Path $OutputDirectory $entry.Name
      $backup = $null
      if ([IO.File]::Exists($destination)) {
        $backup = "$destination.$([guid]::NewGuid().ToString('N')).bak"
        [IO.File]::Replace($entry.Source, $destination, $backup)
      } else {
        [IO.File]::Move($entry.Source, $destination)
      }
      $published.Add(@{ Destination = $destination; Backup = $backup })
    }
  } catch {
    for ($index = $published.Count - 1; $index -ge 0; $index--) {
      $entry = $published[$index]
      if ($null -ne $entry.Backup) {
        [IO.File]::Replace($entry.Backup, $entry.Destination, [System.Management.Automation.Language.NullString]::Value)
      } else {
        [IO.File]::Delete($entry.Destination)
      }
    }
    throw
  }
  foreach ($entry in $published) {
    if ($null -ne $entry.Backup) { [IO.File]::Delete($entry.Backup) }
  }
}

function Invoke-PrepareVcRuntime {
  param(
    [ValidateSet('x64', 'arm64')][string]$Architecture,
    [string]$OutputDirectory,
    [string]$MinimumVersion = '14.0.0.0'
  )
  $requiredVersion = ConvertTo-VcRuntimeVersion -Value $MinimumVersion
  $architectureName = $Architecture.ToLowerInvariant()
  foreach ($buildVersion in @(Get-VcRuntimeBuildVersions -Architecture $architectureName)) {
    $version = ConvertTo-VcRuntimeVersion -Value $buildVersion
    if ($version -gt $requiredVersion) { $requiredVersion = $version }
  }
  $outputPath = [IO.Path]::GetFullPath($OutputDirectory)
  [void][IO.Directory]::CreateDirectory($outputPath)
  $lockPath = Join-Path $outputPath '.prepare.lock'
  $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  $token = [guid]::NewGuid().ToString('N')
  $stagedInstaller = Join-Path $outputPath "$token.exe.tmp"
  $stagedMetadata = Join-Path $outputPath "$token.iss.tmp"
  try {
    $validated = $null
    $cachedInstaller = Join-Path $outputPath 'vc_redist.exe'
    if ([IO.File]::Exists($cachedInstaller)) {
      [IO.File]::Copy($cachedInstaller, $stagedInstaller)
      try {
        $validated = Get-ValidatedVcRuntime -Path $stagedInstaller -Architecture $architectureName -MinimumVersion $requiredVersion
      } catch {
        [IO.File]::Delete($stagedInstaller)
      }
    }
    if ($null -eq $validated) {
      Save-VcRuntimeDownload -Uri "https://aka.ms/vc14/vc_redist.$architectureName.exe" -Path $stagedInstaller
      $validated = Get-ValidatedVcRuntime -Path $stagedInstaller -Architecture $architectureName -MinimumVersion $requiredVersion
    }
    $defines = @(
      "#define VcRuntimeArchitecture `"$architectureName`"",
      "#define VcRuntimeMinimumVersion `"$($validated.Version)`"",
      "#define VcRuntimeInstallerSHA256 `"$($validated.SHA256)`""
    ) -join "`r`n"
    [IO.File]::WriteAllText($stagedMetadata, "$defines`r`n", [Text.UTF8Encoding]::new($false))
    Publish-VcRuntimeFiles -Installer $stagedInstaller -Metadata $stagedMetadata -OutputDirectory $outputPath
    return [pscustomobject]@{
      Architecture = $architectureName
      MinimumVersion = $validated.Version
      InstallerSHA256 = $validated.SHA256
      OutputDirectory = $outputPath
    }
  } finally {
    [IO.File]::Delete($stagedInstaller)
    [IO.File]::Delete($stagedMetadata)
    $lock.Dispose()
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  Invoke-PrepareVcRuntime -Architecture $Architecture -OutputDirectory $OutputDirectory -MinimumVersion $MinimumVersion
}
