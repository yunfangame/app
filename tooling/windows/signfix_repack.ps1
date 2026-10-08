param(
  [Parameter(Mandatory = $true)][ValidateSet('prepare', 'helper', 'build', 'verify', 'capture')][string]$Stage,
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [string]$CaptureSource
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or -not $IsWindows) {
  throw 'Signing repair may run only in an isolated GitHub Actions Windows runner with PowerShell 7'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if ($Stage -eq 'capture') {
  if (-not $CaptureSource -or -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw 'Invalid capture request' }
  $source = Get-Item -LiteralPath $CaptureSource
  if ($source.Name -notmatch '^uninst\.e(32|64)\.tmp$' -or $source.Length -le 0) { throw 'Unexpected unsigned uninstaller name' }
  if (@(Get-ChildItem -LiteralPath $OutputDirectory -File).Count -ne 0) { throw 'Capture directory is not empty' }
  Copy-Item -LiteralPath $source.FullName -Destination (Join-Path $OutputDirectory $source.Name)
  exit 1
}

$RepositoryDirectory = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$WorkDirectory = Join-Path $env:RUNNER_TEMP ('fengwo-signfix-' + $Stage + '-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$null = New-Item -ItemType Directory -Path $WorkDirectory
$Version = '1.0.8+17'
$SourceCommit = '9a71d2e4bd155aa8f61af08ec081642cb71da84c'
$InputRelease = 'fengwo-signfix-inputs-20261008'
$ExpectedSignerSha256 = '27e3e2e77a0c5f3428eeb95a35825d4cf0c8710e760e9c8cb12b447d39603252'
$Limitation = 'GitHub Actions verifies package signatures and Windows behavior; it cannot prove acceptance by customer Smart App Control (VerifiedAndReputableDesktop), reputation services, or enterprise policies.'
$Limitation | Set-Content -LiteralPath (Join-Path $OutputDirectory 'verification-limits.txt') -Encoding utf8NoBOM
Write-Host $Limitation

function Invoke-Bounded {
  param([string]$Executable, [string[]]$Arguments, [string]$Name, [int]$TimeoutSeconds = 300, [string]$WorkingDirectory = $RepositoryDirectory, [int[]]$AllowedExitCodes = @(0))
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $Executable
  $start.WorkingDirectory = $WorkingDirectory
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $start
  $stdout = $null
  $stderr = $null
  try {
    if (-not $process.Start()) { throw "Unable to start $Name" }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      try { $process.Kill($true) } catch { }
      $null = $process.WaitForExit(5000)
      throw "$Name exceeded $TimeoutSeconds seconds"
    }
    $code = $process.ExitCode
    if ($AllowedExitCodes -notcontains $code) { throw "$Name exited with $code; see $Name logs" }
    return $code
  } finally {
    if ($stdout -and $stdout.Wait(5000)) { $stdout.Result | Set-Content -LiteralPath (Join-Path $OutputDirectory "$Name.stdout.log") -Encoding utf8NoBOM }
    if ($stderr -and $stderr.Wait(5000)) { $stderr.Result | Set-Content -LiteralPath (Join-Path $OutputDirectory "$Name.stderr.log") -Encoding utf8NoBOM }
    $process.Dispose()
  }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Json([object]$Value, [string]$Path) {
  $Value | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Expand-SafeZip([string]$Path, [string]$Destination) {
  $null = New-Item -ItemType Directory -Path $Destination
  $root = [IO.Path]::GetFullPath($Destination).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    if ($zip.Entries.Count -gt 2000) { throw 'Unexpected archive entry count' }
    [long]$total = 0
    foreach ($entry in $zip.Entries) {
      $name = $entry.FullName.Replace('\', '/')
      $total += $entry.Length
      if ($total -gt 2GB -or $name -match '(^/|:|(^|/)\.\.?(/|$))' -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Unsafe archive entry' }
      if (-not $seen.Add($name.TrimEnd('/'))) { throw 'Duplicate archive entry' }
      $target = [IO.Path]::GetFullPath((Join-Path $Destination $name))
      if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive entry escapes destination' }
      if ($name.EndsWith('/')) { $null = New-Item -ItemType Directory -Path $target -Force; continue }
      $null = New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
      $inputStream = $entry.Open()
      $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew)
      try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
    }
  } finally { $zip.Dispose() }
}

function Assert-Inventory([string]$Payload, [string]$InventoryPath) {
  $inventory = @(Get-Content -LiteralPath $InventoryPath -Raw | ConvertFrom-Json)
  $actual = @(Get-ChildItem -LiteralPath $Payload -File -Recurse)
  if ($inventory.Count -ne $actual.Count -or $inventory.Count -ne 85) { throw 'Payload must contain exactly the original 85 files' }
  $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in $inventory) {
    $path = [string]$entry.path
    if ($path -match '(^/|\\|:|(^|/)\.\.?(/|$))' -or -not $path -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid payload inventory entry' }
    if (-not $expected.TryAdd($path, $entry)) { throw 'Duplicate payload inventory entry' }
  }
  foreach ($file in $actual) {
    $path = [IO.Path]::GetRelativePath($Payload, $file.FullName).Replace('\', '/')
    if (-not $expected.ContainsKey($path)) { throw "Unexpected payload file: $path" }
    $entry = $expected[$path]
    if ($file.Length -ne $entry.bytes -or (Get-Sha256 $file.FullName) -cne $entry.sha256.ToLowerInvariant()) { throw "Payload hash mismatch: $path" }
  }
  return ,$inventory
}

function Get-Baseline {
  $directory = Join-Path $WorkDirectory 'baseline'
  $null = New-Item -ItemType Directory -Path $directory
  $null = Invoke-Bounded 'gh' @('run', 'download', '37602827410', '--name', 'fengwo-windows-amd64', '--dir', $directory) 'download-baseline' 300
  $pinnedHashes = @{
    'fengwo-windows-amd64-release-unsigned.zip' = '75071df1a50e40fe6d4d0a82d60289036bd9ab7130bd99ee497d6f617b04aa00'
    'fengwo-windows-amd64-setup.exe' = '9e9d374743fe9cb6ab60f13dad032ba7d4ab0afa38f90d3120c8e73a4b3528ba'
  }
  $sums = Get-Content -LiteralPath (Join-Path $directory 'SHA256SUMS')
  foreach ($name in @('fengwo-windows-amd64-release-unsigned.zip', 'fengwo-windows-amd64-setup.exe')) {
    $matching = @($sums | Where-Object { $_ -match ('^[a-fA-F0-9]{64}\s+' + [regex]::Escape($name) + '$') })
    if ($matching.Count -ne 1 -or (Get-Sha256 (Join-Path $directory $name)) -cne ($matching[0] -split '\s+')[0].ToLowerInvariant()) { throw "Baseline artifact hash mismatch: $name" }
    if ((Get-Sha256 (Join-Path $directory $name)) -cne $pinnedHashes[$name]) { throw "Original release artifact changed: $name" }
  }
  $payload = Join-Path $WorkDirectory 'baseline-payload'
  Expand-SafeZip (Join-Path $directory 'fengwo-windows-amd64-release-unsigned.zip') $payload
  $null = Assert-Inventory $payload (Join-Path $directory 'release-directory-files.json')
  Copy-Item -LiteralPath (Join-Path $directory 'release-directory-files.json') -Destination (Join-Path $OutputDirectory 'baseline-payload-sha256.json')
  return @{ directory = $directory; payload = $payload; installer = (Join-Path $directory 'fengwo-windows-amd64-setup.exe') }
}

function Get-InputBundle {
  $download = Join-Path $WorkDirectory 'input-download'
  $null = New-Item -ItemType Directory -Path $download
  $null = Invoke-Bounded 'gh' @('release', 'download', $InputRelease, '--pattern', 'input-bundle.zip', '--dir', $download) 'download-inputs' 300
  $directory = Join-Path $WorkDirectory 'inputs'
  Expand-SafeZip (Join-Path $download 'input-bundle.zip') $directory
  $null = Assert-Inventory (Join-Path $directory 'payload') (Join-Path $directory 'payload-sha256.json')
  Copy-Item -LiteralPath (Join-Path $directory 'payload-sha256.json') -Destination (Join-Path $OutputDirectory 'payload-sha256.json')
  return $directory
}

function Get-SignatureRecord([string]$Path, [string]$RelativePath) {
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  $certificateHash = $null
  if ($signature.SignerCertificate) { $certificateHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($signature.SignerCertificate.RawData)).ToLowerInvariant() }
  return [ordered]@{ path = $RelativePath; sha256 = (Get-Sha256 $Path); status = $signature.Status.ToString(); signer_sha256 = $certificateHash; timestamped = ($null -ne $signature.TimeStamperCertificate) }
}

function Assert-Signature([string]$Path, [switch]$Owned) {
  $record = Get-SignatureRecord $Path ([IO.Path]::GetFileName($Path))
  if ($record.status -cne 'Valid') { throw "Authenticode is $($record.status): $Path" }
  if ($Owned -and ($record.signer_sha256 -cne $ExpectedSignerSha256 -or -not $record.timestamped)) { throw "Expected timestamped publisher signature: $Path" }
  return $record
}

function Assert-CoreBinding([string]$Payload, [switch]$Helper) {
  $coreHash = Get-Sha256 (Join-Path $Payload 'FlClashCore.exe')
  $manifest = Get-Content -LiteralPath (Join-Path $Payload 'manifest.json') -Raw | ConvertFrom-Json
  if ($manifest.coreSha256 -cne $coreHash) { throw 'Core hash does not match manifest.json' }
  if ($Helper) {
    $binary = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $Payload 'FlClashHelperService.exe')))
    if (-not $binary.Contains($coreHash) -or -not $binary.Contains('FlClashCore.exe')) { throw 'Helper does not embed the signed Core hash and name' }
  }
  return $coreHash
}

function Assert-Payload([string]$Payload, [string]$Baseline, [switch]$AllowOldHelper) {
  $records = [Collections.Generic.List[object]]::new()
  $originalFiles = @(Get-ChildItem -LiteralPath $Baseline -File -Recurse)
  if (@(Get-ChildItem -LiteralPath $Payload -File -Recurse).Count -ne $originalFiles.Count) { throw 'Payload file set changed' }
  foreach ($original in $originalFiles) {
    $relative = [IO.Path]::GetRelativePath($Baseline, $original.FullName)
    $path = Join-Path $Payload $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing original payload file: $relative" }
    if ($relative -ieq 'FlClashHelperService.exe' -and $AllowOldHelper) {
      if ((Get-Sha256 $path) -cne (Get-Sha256 $original.FullName)) { throw 'Helper input must be the untouched original Helper for the helper stage' }
      continue
    }
    if ($original.Extension -in @('.exe', '.dll')) {
      $before = Get-SignatureRecord $original.FullName $relative
      if ($before.status -eq 'Valid') {
        if ((Get-Sha256 $path) -cne $before.sha256) { throw "Third-party signed binary changed: $relative" }
        $record = Assert-Signature $path
      } else {
        if ($before.status -ne 'NotSigned') { throw "Baseline signature is neither valid nor unsigned: $relative" }
        $record = Assert-Signature $path -Owned
      }
      $record.path = $relative.Replace('\', '/')
      $records.Add($record)
    } elseif ($relative -ine 'manifest.json' -and (Get-Sha256 $path) -cne (Get-Sha256 $original.FullName)) {
      throw "Non-signing payload content changed: $relative"
    }
  }
  $versionInfo = (Get-Item -LiteralPath (Join-Path $Payload 'FengWo.exe')).VersionInfo
  if ($versionInfo.ProductVersion -cne $Version -or $versionInfo.FileVersion -cne $Version -or $versionInfo.ProductName -cne '蜂窝加速器' -or $versionInfo.CompanyName -cne 'com.follow') { throw 'Payload application identity changed' }
  Write-Json @($records) (Join-Path $OutputDirectory 'payload-signatures.json')
  $null = Assert-CoreBinding $Payload -Helper:(-not $AllowOldHelper)
}

function Get-CompilerMetadata([string]$Iscc) {
  $directory = Split-Path $Iscc -Parent
  $files = @(Get-ChildItem -LiteralPath $directory -File -Recurse | Where-Object { $_.Extension -in @('.exe', '.dll', '.e32', '.e64', '.isl') } | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path = [IO.Path]::GetRelativePath($directory, $_.FullName).Replace('\', '/'); sha256 = (Get-Sha256 $_.FullName) }
  })
  return [ordered]@{
    compiler_version = (Get-Item -LiteralPath $Iscc).VersionInfo.FileVersion
    compiler_files = $files
    template_sha256 = (Get-Sha256 (Join-Path $RepositoryDirectory 'windows/packaging/exe/inno_setup.iss'))
    icon_sha256 = (Get-Sha256 (Join-Path $RepositoryDirectory 'windows/runner/resources/app_icon.ico'))
    language_sha256 = (Get-Sha256 (Join-Path $RepositoryDirectory 'windows/packaging/exe/ChineseSimplified.isl'))
    version = $Version
    architecture = 'x64'
  }
}

function Render-Installer([string]$Payload, [string]$Cache, [string]$Destination, [switch]$Capture) {
  $renderer = Join-Path $WorkDirectory 'render.py'
  @'
import json, pathlib, sys
import jinja2, yaml
root, payload, cache, destination, capture = sys.argv[1:]
root = pathlib.Path(root)
config = yaml.safe_load((root / 'windows/packaging/exe/make_config.yaml').read_text(encoding='utf-8-sig'))
version = yaml.safe_load((root / 'pubspec.yaml').read_text(encoding='utf-8-sig'))['version']
assert version == '1.0.8+17'
assert config['app_id'] == '728B3532-C74B-4870-9068-BE70FE12A3E6'
assert config['app_name'] == config['display_name'] == '蜂窝加速器'
assert config['executable_name'] == 'FengWo.exe' and config['privileges_required'] == 'admin'
locales = config['locales']
assert [locale['lang'] for locale in locales] == ['zh', 'en']
locales[0]['file'] = '"' + str(root / 'windows/packaging/exe/ChineseSimplified.isl') + '"'
locales[1]['file'] = None
values = dict(APP_ID=config['app_id'], APP_VERSION=version, DISPLAY_NAME=config['display_name'], PUBLISHER_NAME=config['publisher'], PUBLISHER_URL=config['publisher_url'], INSTALL_DIR_NAME=config.get('install_dir_name', '{autopf64}' + chr(92) + config['app_name']), OUTPUT_BASE_FILENAME='fengwo-windows-amd64-signfix-unsigned-setup', SETUP_ICON_FILE=str(root / pathlib.Path(config['setup_icon_file'].replace('\\', '/'))), PRIVILEGES_REQUIRED=config['privileges_required'], ARCH='x64', SOURCE_DIR=payload, EXECUTABLE_NAME=config['executable_name'], LOCALES=locales, CREATE_DESKTOP_ICON=config.get('create_desktop_icon'))
template = (root / 'windows/packaging/exe' / config['script_template']).read_text(encoding='utf-8-sig')
assert 'SignedUninstaller' not in template and 'SignTool=' not in template
rendered = jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True).from_string(template).render(values)
assert '{{' not in rendered and '{%' not in rendered
directives = '\nSignedUninstaller=yes\nSignedUninstallerDir=' + cache + '\n'
if capture == 'yes':
    directives += 'SignTool=Capture\n'
assert rendered.count('[Setup]') == 1
rendered = rendered.replace('[Setup]', '[Setup]' + directives, 1)
pathlib.Path(destination).write_text(rendered, encoding='utf-8-sig')
'@ | Set-Content -LiteralPath $renderer -Encoding utf8NoBOM
  $mode = if ($Capture) { 'yes' } else { 'no' }
  $null = Invoke-Bounded 'python' @($renderer, $RepositoryDirectory, $Payload, $Cache, $Destination, $mode) ('render-' + [IO.Path]::GetFileNameWithoutExtension($Destination)) 60
}

function Assert-Cache([string]$Directory) {
  $files = @(Get-ChildItem -LiteralPath $Directory -File | Where-Object { $_.Name -match '^uninst-.+\.e(32|64)$' })
  if ($files.Count -ne 1) { throw 'Expected exactly one named Inno uninstaller cache file' }
  return $files[0]
}

try {
  if (-not $env:GH_REPO -or -not $env:GH_TOKEN) { throw 'GitHub repository and token must be passed through the environment' }
  $null = Invoke-Bounded 'git' @('diff', '--exit-code', $SourceCommit, '--', 'services/helper', 'pubspec.yaml', 'windows/packaging/exe', 'windows/runner/resources/app_icon.ico', 'tooling/windows/test_installed_upgrade.ps1', 'tooling/verify_windows_title.ps1') 'check-original-sources' 30
  if (-not (Select-String -LiteralPath (Join-Path $RepositoryDirectory 'pubspec.yaml') -Pattern '^version: 1\.0\.8\+17$')) { throw 'Only the original 1.0.8+17 payload is supported' }
  $baseline = Get-Baseline
  if ($Stage -in @('prepare', 'build')) {
    $null = Invoke-Bounded 'python' @('-m', 'pip', 'install', '--disable-pip-version-check', 'Jinja2==3.1.6', 'PyYAML==6.0.2') 'template-dependencies' 180
    $iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
    if (-not (Test-Path -LiteralPath $iscc -PathType Leaf)) { throw 'Inno Setup 6 is missing' }
    $compiler = Get-CompilerMetadata $iscc
  }
  switch ($Stage) {
    'prepare' {
      $captureCache = Join-Path $WorkDirectory 'capture-cache'
      $captured = Join-Path $OutputDirectory 'capture-tmp'
      $cache = Join-Path $OutputDirectory 'signed-uninstaller'
      $null = New-Item -ItemType Directory -Path $captureCache, $captured, $cache
      $captureScript = Join-Path $WorkDirectory 'capture.iss'
      Render-Installer $baseline.payload $captureCache $captureScript -Capture
      $pwsh = (Get-Process -Id $PID).Path
      $callback = '$q' + $pwsh + '$q -NoProfile -NonInteractive -File $q' + $PSCommandPath + '$q -Stage capture -OutputDirectory $q' + $captured + '$q -CaptureSource $f'
      $captureExit = Invoke-Bounded $iscc @('/Qp', "/SCapture=$callback", $captureScript) 'capture-uninstaller' 600 $WorkDirectory @(2)
      $capturedFiles = @(Get-ChildItem -LiteralPath $captured -File)
      if ($capturedFiles.Count -ne 1 -or $capturedFiles[0].Name -notmatch '^uninst\.e(32|64)\.tmp$') { throw 'Capture did not produce exactly one unsigned uninstaller' }
      $canonicalScript = Join-Path $WorkDirectory 'canonical.iss'
      Render-Installer $baseline.payload $cache $canonicalScript
      $null = Invoke-Bounded $iscc @('/Qp', $canonicalScript) 'name-uninstaller-cache' 600 $WorkDirectory @(2)
      $cacheFile = Assert-Cache $cache
      $log = (Get-Content -LiteralPath (Join-Path $OutputDirectory 'name-uninstaller-cache.stdout.log') -Raw) + (Get-Content -LiteralPath (Join-Path $OutputDirectory 'name-uninstaller-cache.stderr.log') -Raw)
      if ($log -notmatch 'Signed uninstaller mode is enabled' -or (Get-Sha256 $cacheFile.FullName) -cne (Get-Sha256 $capturedFiles[0].FullName)) { throw 'Expected unsigned-cache compiler stop or matching capture bytes was not observed' }
      if ((Get-AuthenticodeSignature -LiteralPath $cacheFile.FullName).Status -ne 'NotSigned') { throw 'Prepare must produce an unsigned uninstaller' }
      $compiler['cache_name'] = $cacheFile.Name
      $compiler['unsigned_uninstaller_sha256'] = Get-Sha256 $cacheFile.FullName
      Write-Json $compiler (Join-Path $cache 'compiler-metadata.json')
      Copy-Item -LiteralPath $canonicalScript -Destination (Join-Path $OutputDirectory 'rendered-installer.iss')
      Write-Host "Prepared unsigned uninstaller: $($cacheFile.Name). Sign it without renaming and preserve compiler-metadata.json."
    }
    'helper' {
      $inputs = Get-InputBundle
      $payload = Join-Path $inputs 'payload'
      Assert-Payload $payload $baseline.payload -AllowOldHelper
      $hash = Assert-CoreBinding $payload
      $env:CORE_SHA256 = $hash
      $env:CORE_NAME = 'FlClashCore.exe'
      $helperSource = Join-Path $RepositoryDirectory 'services/helper'
      $null = Invoke-Bounded 'rustc' @('-vV') 'rust-version' 30
      $hostDescription = Get-Content -LiteralPath (Join-Path $OutputDirectory 'rust-version.stdout.log') -Raw
      if ($hostDescription -notmatch '(?m)^host: x86_64-pc-windows-msvc\s*$') { throw 'Helper must use the original default x64 MSVC target' }
      $null = Invoke-Bounded 'cargo' @('test', '--locked', '--features', 'windows-service', '--release') 'helper-tests' 900 $helperSource
      $null = Invoke-Bounded 'cargo' @('build', '--locked', '--features', 'windows-service', '--release') 'helper-build' 900 $helperSource
      $helper = Join-Path $OutputDirectory 'FlClashHelperService.exe'
      Copy-Item -LiteralPath (Join-Path $helperSource 'target/release/helper.exe') -Destination $helper
      $bytes = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($helper))
      if (-not $bytes.Contains($hash) -or -not $bytes.Contains('FlClashCore.exe')) { throw 'Rebuilt Helper does not embed the signed Core identity' }
      if ((Get-AuthenticodeSignature -LiteralPath $helper).Status -ne 'NotSigned') { throw 'Helper must be unsigned before offline signing' }
      Write-Json ([ordered]@{ core_name = 'FlClashCore.exe'; core_sha256 = $hash; helper_unsigned_sha256 = (Get-Sha256 $helper); source_commit = $SourceCommit; version = $Version }) (Join-Path $OutputDirectory 'expected-hash.json')
    }
    'build' {
      $inputs = Get-InputBundle
      $payload = Join-Path $inputs 'payload'
      Assert-Payload $payload $baseline.payload
      $cache = Join-Path $inputs 'signed-uninstaller'
      $cacheFile = Assert-Cache $cache
      $metadata = Get-Content -LiteralPath (Join-Path $cache 'compiler-metadata.json') -Raw | ConvertFrom-Json -AsHashtable
      foreach ($key in $compiler.Keys) {
        if (($compiler[$key] | ConvertTo-Json -Depth 10 -Compress) -cne ($metadata[$key] | ConvertTo-Json -Depth 10 -Compress)) { throw "Prepare/build compiler identity mismatch: $key" }
      }
      if ($metadata.cache_name -cne $cacheFile.Name) { throw 'Signed uninstaller cache was renamed' }
      $uninstallerSignature = Assert-Signature $cacheFile.FullName -Owned
      Write-Json $uninstallerSignature (Join-Path $OutputDirectory 'uninstaller-signature.json')
      $iss = Join-Path $WorkDirectory 'signfix.iss'
      Render-Installer $payload $cache $iss
      if (Select-String -LiteralPath $iss -Pattern '^SignTool=') { throw 'Offline repack must not invoke a SignTool' }
      $before = Get-Sha256 $cacheFile.FullName
      $null = Invoke-Bounded $iscc @('/Qp', $iss) 'repack-installer' 900 $WorkDirectory
      if ((Get-Sha256 $cacheFile.FullName) -cne $before) { throw 'Compiler changed the signed uninstaller cache' }
      $null = Assert-Inventory $payload (Join-Path $inputs 'payload-sha256.json')
      $setup = Join-Path $WorkDirectory 'fengwo-windows-amd64-signfix-unsigned-setup.exe'
      if ((Get-AuthenticodeSignature -LiteralPath $setup).Status -ne 'NotSigned') { throw 'Expected unsigned setup for offline signing' }
      Copy-Item -LiteralPath $setup -Destination $OutputDirectory
      Copy-Item -LiteralPath $cache -Destination (Join-Path $OutputDirectory 'signed-uninstaller') -Recurse
      Copy-Item -LiteralPath $iss -Destination (Join-Path $OutputDirectory 'rendered-installer.iss')
      Write-Json ([ordered]@{ version = $Version; setup_sha256 = (Get-Sha256 $setup); signed_uninstaller_sha256 = $before; core_sha256 = (Assert-CoreBinding $payload -Helper) }) (Join-Path $OutputDirectory 'build-evidence.json')
    }
    'verify' {
      $inputs = Get-InputBundle
      $payload = Join-Path $inputs 'payload'
      Assert-Payload $payload $baseline.payload
      $download = Join-Path $WorkDirectory 'final'
      $null = New-Item -ItemType Directory -Path $download
      $null = Invoke-Bounded 'gh' @('release', 'download', $InputRelease, '--pattern', 'final-setup.exe', '--dir', $download) 'download-final-setup' 300
      $setup = Join-Path $download 'final-setup.exe'
      Write-Json (Assert-Signature $setup -Owned) (Join-Path $OutputDirectory 'setup-signature.json')
      $upgradeOutput = Join-Path $OutputDirectory 'upgrade'
      $null = Invoke-Bounded 'pwsh' @('-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'test_installed_upgrade.ps1'), '-InstallerPath', $setup, '-PreviousInstallerPath', $baseline.installer, '-ExpectedPreviousVersion', $Version, '-OutputDirectory', $upgradeOutput) 'same-version-upgrade' 1200
      $installed = Join-Path $env:RUNNER_TEMP 'fengwo-overwrite-test'
      $records = @(Get-ChildItem -LiteralPath $installed -File -Recurse | Where-Object { $_.Extension -in @('.exe', '.dll') } | ForEach-Object {
        $record = Assert-Signature $_.FullName
        $record.path = [IO.Path]::GetRelativePath($installed, $_.FullName).Replace('\', '/')
        $record
      })
      Write-Json $records (Join-Path $OutputDirectory 'installed-signatures.json')
      foreach ($entry in @(Get-Content -LiteralPath (Join-Path $inputs 'payload-sha256.json') -Raw | ConvertFrom-Json)) {
        if ($entry.path.StartsWith('prerequisites/')) { continue }
        if ((Get-Sha256 (Join-Path $installed $entry.path)) -cne $entry.sha256) { throw "Installed file differs from signed input: $($entry.path)" }
      }
      $uninstallers = @(Get-ChildItem -LiteralPath $installed -File -Filter 'unins*.exe')
      if ($uninstallers.Count -ne 1) { throw 'Expected exactly one installed uninstaller' }
      $null = Assert-Signature $uninstallers[0].FullName -Owned
      $uninstallerCache = Assert-Cache (Join-Path $inputs 'signed-uninstaller')
      if ((Get-Sha256 $uninstallers[0].FullName) -cne (Get-Sha256 $uninstallerCache.FullName)) { throw 'Installed uninstaller differs from the signed cache' }
      $null = Assert-CoreBinding $installed -Helper
      $loadScript = Join-Path $WorkDirectory 'load-rust-api.ps1'
      @'
param([string]$Directory)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class RustApiLoad { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags); [DllImport("kernel32.dll", SetLastError=true)] public static extern bool FreeLibrary(IntPtr module); }'
$path = Join-Path $Directory 'rust_api.dll'
$module = [RustApiLoad]::LoadLibraryExW($path, [IntPtr]::Zero, 0x00001100)
if ($module -eq [IntPtr]::Zero) { throw "rust_api LoadLibrary failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
if (-not [RustApiLoad]::FreeLibrary($module)) { throw 'rust_api FreeLibrary failed' }
Write-Output 'Installed rust_api.dll loaded and unloaded successfully'
'@ | Set-Content -LiteralPath $loadScript -Encoding utf8NoBOM
      $null = Invoke-Bounded 'pwsh' @('-NoProfile', '-NonInteractive', '-File', $loadScript, '-Directory', $installed) 'installed-rust-api-load' 60
      Write-Json ([ordered]@{ version = $Version; setup_sha256 = (Get-Sha256 $setup); installed_pe_count = $records.Count; core_sha256 = (Assert-CoreBinding $installed -Helper); same_version_upgrade = $true; rust_api_load_library = $true; limitation = $Limitation }) (Join-Path $OutputDirectory 'verification.json')
    }
  }
  Write-Json ([ordered]@{ stage = $Stage; passed = $true; version = $Version; source_commit = $SourceCommit; completed_utc = [DateTime]::UtcNow.ToString('o') }) (Join-Path $OutputDirectory 'stage-result.json')
} catch {
  Write-Json ([ordered]@{ stage = $Stage; passed = $false; version = $Version; error = $_.Exception.Message; completed_utc = [DateTime]::UtcNow.ToString('o') }) (Join-Path $OutputDirectory 'stage-result.json')
  throw
}
