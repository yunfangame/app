param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$CmakePath = 'cmake',
  [string]$Generator = 'Visual Studio 17 2022',
  [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FengwoJavascriptPackagePath {
  param([string]$Root)
  $configPath = Join-Path $Root '.dart_tool/package_config.json'
  if (-not (Test-Path -LiteralPath $configPath)) { throw 'Run flutter pub get before preparing the ARM64 JavaScript bridge' }
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $packages = @($config.packages | Where-Object { $_.name -eq 'flutter_js' })
  if ($packages.Count -ne 1) { throw 'Exactly one flutter_js package must be resolved' }
  $packageUri = $null
  $rootUri = [string]$packages[0].rootUri
  if ([Uri]::TryCreate($rootUri, [UriKind]::Absolute, [ref]$packageUri)) {
    if (-not $packageUri.IsFile) { throw 'flutter_js must resolve to a local package directory' }
    $packagePath = $packageUri.LocalPath
  } else {
    $relativePath = [Uri]::UnescapeDataString($rootUri)
    $packagePath = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $configPath) $relativePath))
  }
  $pubspec = Get-Content -LiteralPath (Join-Path $packagePath 'pubspec.yaml') -Raw
  if ($pubspec -notmatch '(?m)^version:\s*0\.8\.7\s*$') { throw 'The ARM64 bridge is pinned to flutter_js 0.8.7' }
  return $packagePath
}

function Assert-FengwoJavascriptPinnedHash {
  param([string]$Path, [string]$Expected)
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected) { throw "Pinned JavaScript source hash mismatch: $([IO.Path]::GetFileName($Path))" }
}

function Save-FengwoJavascriptSource {
  param([string]$Uri, [string]$Path, [string]$Hash)
  if (Test-Path -LiteralPath $Path) {
    Assert-FengwoJavascriptPinnedHash -Path $Path -Expected $Hash
    return
  }
  $temporaryPath = "$Path.download"
  try {
    Invoke-WebRequest -Uri $Uri -OutFile $temporaryPath -UseBasicParsing -TimeoutSec 120
    Assert-FengwoJavascriptPinnedHash -Path $temporaryPath -Expected $Hash
    Move-Item -LiteralPath $temporaryPath -Destination $Path
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
  }
}

function Read-FengwoJavascriptPeMachine {
  param([string]$Path)
  $stream = [IO.File]::OpenRead($Path)
  $reader = [IO.BinaryReader]::new($stream)
  try {
    if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw 'Invalid JavaScript PE file' }
    $stream.Position = 0x3C
    $offset = $reader.ReadUInt32()
    if ($offset -lt 64 -or $offset + 24 -gt $stream.Length) { throw 'Invalid JavaScript PE header offset' }
    $stream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x00004550) { throw 'Invalid JavaScript PE signature' }
    return $reader.ReadUInt16()
  } finally {
    $reader.Dispose()
  }
}

function Get-FengwoJavascriptOverrideContent {
  return "dependency_overrides:`n  flutter_js:`n    path: '.dart_tool/windows_arm64_javascript/flutter_js'`n"
}

function Assert-FengwoJavascriptOverrideAvailable {
  param([string]$Root)
  $overridePath = Join-Path $Root 'pubspec_overrides.yaml'
  if (Test-Path -LiteralPath $overridePath) {
    $existing = (Get-Content -LiteralPath $overridePath -Raw).Replace("`r`n", "`n")
    if ($existing -ne (Get-FengwoJavascriptOverrideContent)) { throw 'Existing pubspec_overrides.yaml must be preserved; use a separate build worktree' }
  }
}

function ConvertTo-FengwoJavascriptMsvcSource {
  param([string]$Source)
  $stackReturn = 'return _AddressOfReturnAddress();'
  if ([regex]::Matches($Source, [regex]::Escape($stackReturn)).Count -ne 1) { throw 'Unexpected QuickJS stack pointer source contract' }
  $Source = $Source.Replace($stackReturn, 'return (uintptr_t)_AddressOfReturnAddress();')
  $classReturn = '(?s)(JSClassID JS_GetClassID\(JSValueConst obj\)\s*\{.*?if \(JS_VALUE_GET_TAG\(obj\) != JS_TAG_OBJECT\)\s*)return NULL;'
  if ([regex]::Matches($Source, $classReturn).Count -ne 1) { throw 'Unexpected QuickJS class identifier source contract' }
  $Source = [regex]::Replace($Source, $classReturn, '${1}return 0;')
  $mathPattern = '(?s)static const JSCFunctionListEntry js_math_funcs\[\] = \{.*?\n\};'
  $mathMatches = [regex]::Matches($Source, $mathPattern)
  if ($mathMatches.Count -ne 1) { throw 'Unexpected QuickJS Math source contract' }
  $mathTable = $mathMatches[0].Value
  $functions = @('fabs', 'floor', 'ceil', 'sqrt', 'acos', 'asin', 'atan', 'atan2', 'cos', 'exp', 'log', 'sin', 'tan', 'trunc', 'cosh', 'sinh', 'tanh', 'acosh', 'asinh', 'atanh', 'expm1', 'log1p', 'log2', 'log10', 'cbrt')
  $wrappers = [Collections.Generic.List[string]]::new()
  foreach ($function in $functions) {
    $entry = '(JS_CFUNC_SPECIAL_DEF\("[a-z0-9]+",\s*[12],\s*(f_f(?:_f)?),\s*)' + $function + '(\s*\))'
    $matches = [regex]::Matches($mathTable, $entry)
    if ($matches.Count -ne 1) { throw "Unexpected QuickJS Math function source contract: $function" }
    $parameters = if ($matches[0].Groups[2].Value -eq 'f_f_f') { 'double a, double b' } else { 'double a' }
    $arguments = if ($matches[0].Groups[2].Value -eq 'f_f_f') { 'a, b' } else { 'a' }
    $wrappers.Add("static double fengwo_math_${function}($parameters) { return ${function}($arguments); }")
    $mathTable = [regex]::Replace($mathTable, $entry, ('${1}fengwo_math_' + $function + '${3}'))
  }
  $replacement = ($wrappers -join "`n") + "`n`n" + $mathTable
  return $Source.Replace($mathMatches[0].Value, $replacement)
}

function Update-FengwoJavascriptMsvcCompatibility {
  param([string]$EngineDirectory)
  $sourcePath = Join-Path $EngineDirectory 'quickjs.c'
  Assert-FengwoJavascriptPinnedHash -Path $sourcePath -Expected '9dcf97180ca4d1f74cef4825c13c2a261b7809bf0157944d294dbbd3e0fefbdf'
  $source = Get-Content -LiteralPath $sourcePath -Raw
  [IO.File]::WriteAllText($sourcePath, (ConvertTo-FengwoJavascriptMsvcSource -Source $source), [Text.UTF8Encoding]::new($false))
}

function Invoke-FengwoJavascriptCmake {
  param([string]$Executable, [string[]]$Arguments)
  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) { throw "ARM64 JavaScript CMake failed with exit code $LASTEXITCODE" }
}

function Invoke-FengwoArm64JavascriptPreparation {
  param([string]$Root, [string]$Cmake, [string]$CmakeGenerator, [string]$BuildConfiguration)
  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Prepare the JavaScript bridge on a Windows ARM64 build host' }
  if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'Arm64') { throw 'Prepare the JavaScript bridge on a Windows ARM64 build host' }
  $Root = (Resolve-Path -LiteralPath $Root).Path
  Assert-FengwoJavascriptOverrideAvailable -Root $Root
  $packageSource = Get-FengwoJavascriptPackagePath -Root $Root
  $work = Join-Path $Root '.dart_tool/windows_arm64_javascript'
  [void][IO.Directory]::CreateDirectory($work)
  $bridgeCommit = '7204d9bf1afbe0550d51d7decdcce398b2c22e1a'
  $bridgeHash = '6e5f956aa041fba013a9a1186c92c9bb01c43ab1624874431749042a4a746361'
  $runtimeCommit = '0f72f7409ff610b33b0e09bd9460213f0e487bf0'
  $runtimeHash = 'b9d91789171b3b60a8fc724afa5b7517deaf0933c65f7369ff9b2fcd1e39e79b'
  $bridgeArchive = Join-Path $work 'quickjs-c-bridge.zip'
  $runtimeArchive = Join-Path $work 'android-js-runtimes.zip'
  Save-FengwoJavascriptSource -Uri "https://codeload.github.com/abner/quickjs-c-bridge/zip/$bridgeCommit" -Path $bridgeArchive -Hash $bridgeHash
  Save-FengwoJavascriptSource -Uri "https://codeload.github.com/fast-development/android-js-runtimes/zip/$runtimeCommit" -Path $runtimeArchive -Hash $runtimeHash
  $sources = Join-Path $work 'sources'
  if (Test-Path -LiteralPath $sources) { Remove-Item -LiteralPath $sources -Recurse -Force }
  Expand-Archive -LiteralPath $bridgeArchive -DestinationPath $sources
  Expand-Archive -LiteralPath $runtimeArchive -DestinationPath $sources
  $bridgeSource = Join-Path $sources "quickjs-c-bridge-$bridgeCommit"
  $runtimeSource = Join-Path $sources "android-js-runtimes-$runtimeCommit"
  $runtimeCpp = Join-Path $runtimeSource 'quickjs/src/main/c/quickjs_runtime.cpp'
  Update-FengwoJavascriptMsvcCompatibility -EngineDirectory (Join-Path $bridgeSource 'cxx/quickjs')
  $ffiSource = Get-Content -LiteralPath (Join-Path $packageSource 'lib/quickjs/ffi.dart') -Raw
  $symbolPattern = '>\(\s*[''"]([A-Za-z_][A-Za-z0-9_]*)[''"]\s*\)'
  $symbols = @([regex]::Matches($ffiSource, $symbolPattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if ($symbols.Count -ne 55) { throw 'Unexpected flutter_js 0.8.7 FFI export contract' }
  $symbolFile = Join-Path $work 'required_symbols.txt'
  [IO.File]::WriteAllLines($symbolFile, [string[]]$symbols, [Text.UTF8Encoding]::new($false))
  $build = Join-Path $work 'build'
  $cmakeSource = Join-Path $Root 'tooling/windows/quickjs_bridge'
  Invoke-FengwoJavascriptCmake -Executable $Cmake -Arguments @('-S', $cmakeSource, '-B', $build, '-G', $CmakeGenerator, '-A', 'ARM64', "-DQUICKJS_SOURCE_DIR=$(Join-Path $bridgeSource 'cxx/quickjs')", "-DQUICKJS_RUNTIME_SOURCE=$runtimeCpp", "-DQUICKJS_REQUIRED_SYMBOLS=$symbolFile")
  Invoke-FengwoJavascriptCmake -Executable $Cmake -Arguments @('--build', $build, '--config', $BuildConfiguration, '--parallel')
  $library = Join-Path $build "$BuildConfiguration/quickjs_c_bridge.dll"
  if ((Read-FengwoJavascriptPeMachine -Path $library) -ne 0xAA64) { throw 'JavaScript bridge is not native Windows ARM64' }
  $ctest = Join-Path (Split-Path -Parent (Get-Command $Cmake -ErrorAction Stop).Source) 'ctest.exe'
  & $ctest --test-dir $build -C $BuildConfiguration --output-on-failure --timeout 15
  if ($LASTEXITCODE -ne 0) { throw 'ARM64 JavaScript native ABI/evaluation smoke failed' }
  $packageCopy = Join-Path $work 'flutter_js'
  if ([IO.Path]::GetFullPath($packageSource).TrimEnd('\', '/') -ne [IO.Path]::GetFullPath($packageCopy).TrimEnd('\', '/')) {
    if (Test-Path -LiteralPath $packageCopy) { Remove-Item -LiteralPath $packageCopy -Recurse -Force }
    Copy-Item -LiteralPath $packageSource -Destination $packageCopy -Recurse
  }
  Copy-Item -LiteralPath $library -Destination (Join-Path $packageCopy 'windows/shared/quickjs_c_bridge.dll') -Force
  $engineText = Get-Content -LiteralPath (Join-Path $bridgeSource 'cxx/quickjs/quickjs.c') -Raw
  $engineLicense = [regex]::Match($engineText, '(?s)^/\*(.*?)\*/').Groups[1].Value -replace '(?m)^\s*\* ?', ''
  if ($engineLicense -notmatch 'Permission is hereby granted') { throw 'QuickJS engine license is missing' }
  $runtimeLicense = Get-Content -LiteralPath (Join-Path $runtimeSource 'LICENSE') -Raw
  $licensePath = Join-Path $packageCopy 'LICENSE'
  $pluginLicense = Get-Content -LiteralPath $licensePath -Raw
  $licenseMarker = 'FengWo Windows ARM64 JavaScript source notices'
  if (-not $pluginLicense.Contains($licenseMarker)) {
    [IO.File]::WriteAllText($licensePath, "$pluginLicense`n`n$licenseMarker`n`n$engineLicense`n`n$runtimeLicense", [Text.UTF8Encoding]::new($false))
  }
  $manifest = [ordered]@{
    flutter_js = '0.8.7'
    bridge_source_commit = $bridgeCommit
    bridge_source_sha256 = $bridgeHash
    runtime_source_commit = $runtimeCommit
    runtime_source_sha256 = $runtimeHash
    msvc_compatibility_revision = 1
    compiled_engine_source_sha256 = (Get-FileHash -LiteralPath (Join-Path $bridgeSource 'cxx/quickjs/quickjs.c') -Algorithm SHA256).Hash.ToLowerInvariant()
    machine = 'ARM64'
    required_ffi_exports = $symbols.Count
    bridge_sha256 = (Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant()
    native_smoke = 'passed'
  } | ConvertTo-Json
  [IO.File]::WriteAllText((Join-Path $work 'manifest.json'), $manifest, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $Root 'pubspec_overrides.yaml'), (Get-FengwoJavascriptOverrideContent), [Text.UTF8Encoding]::new($false))
  Write-Host 'Native ARM64 JavaScript bridge prepared and verified. Run flutter pub get again before building.'
}

if ($MyInvocation.InvocationName -ne '.') {
  Invoke-FengwoArm64JavascriptPreparation -Root $ProjectRoot -Cmake $CmakePath -CmakeGenerator $Generator -BuildConfiguration $Configuration
}
