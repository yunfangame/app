Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'prepare_arm64_javascript.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "fengwo-arm64-javascript-tests-$([Guid]::NewGuid().ToString('N'))"
[void][IO.Directory]::CreateDirectory($testRoot)
$script:passed = 0

function Assert-True {
  param([bool]$Value, [string]$Message)
  if (-not $Value) { throw $Message }
}

function Assert-Throws {
  param([scriptblock]$Action, [string]$Pattern)
  $failure = $null
  try { & $Action | Out-Null } catch { $failure = $_ }
  Assert-True ($null -ne $failure) "Expected failure: $Pattern"
  Assert-True ($failure.Exception.Message -match $Pattern) "Unexpected failure: $($failure.Exception.Message)"
}

function Test-Case {
  param([string]$Name, [scriptblock]$Action)
  & $Action
  $script:passed++
  Write-Host "PASS $Name"
}

function New-PackageFixture {
  param([string]$Name, [string]$Version = '0.8.7', [bool]$Relative = $false)
  $root = Join-Path $testRoot $Name
  $package = Join-Path $root 'package with spaces'
  [void][IO.Directory]::CreateDirectory((Join-Path $root '.dart_tool'))
  [void][IO.Directory]::CreateDirectory($package)
  [IO.File]::WriteAllText((Join-Path $package 'pubspec.yaml'), "name: flutter_js`nversion: $Version`n")
  $uri = if ($Relative) { '../package%20with%20spaces/' } else { [Uri]::new("$package/").AbsoluteUri }
  $config = @{ packages = @(@{ name = 'flutter_js'; rootUri = $uri }) } | ConvertTo-Json -Depth 4
  [IO.File]::WriteAllText((Join-Path $root '.dart_tool/package_config.json'), $config)
  return $root
}

function New-EngineSourceFixture {
  $functions = @('fabs', 'floor', 'ceil', 'sqrt', 'acos', 'asin', 'atan', 'atan2', 'cos', 'exp', 'log', 'sin', 'tan', 'trunc', 'cosh', 'sinh', 'tanh', 'acosh', 'asinh', 'atanh', 'expm1', 'log1p', 'log2', 'log10', 'cbrt')
  $source = "return _AddressOfReturnAddress();`nJSClassID JS_GetClassID(JSValueConst obj)`n{`n    if (JS_VALUE_GET_TAG(obj) != JS_TAG_OBJECT)`n        return NULL;`n    return p->class_id;`n}`nstatic const JSCFunctionListEntry js_math_funcs[] = {`n"
  foreach ($function in $functions) {
    $kind = if ($function -eq 'atan2') { 'f_f_f' } else { 'f_f' }
    $count = if ($function -eq 'atan2') { 2 } else { 1 }
    $source += "JS_CFUNC_SPECIAL_DEF(`"$function`", $count, $kind, $function ),`n"
  }
  return $source + '};'
}

function New-PeFixture {
  param([string]$Name, [uint16]$Machine)
  $path = Join-Path $testRoot $Name
  $stream = [IO.File]::Create($path)
  $writer = [IO.BinaryWriter]::new($stream)
  try {
    $stream.SetLength(96)
    $writer.Write([uint16]0x5A4D)
    $stream.Position = 0x3C
    $writer.Write([uint32]64)
    $stream.Position = 64
    $writer.Write([uint32]0x00004550)
    $writer.Write($Machine)
  } finally { $writer.Dispose() }
  return $path
}

try {
  Test-Case 'absolute package URI handles spaces' {
    $root = New-PackageFixture -Name 'absolute'
    Assert-True ((Get-FengwoJavascriptPackagePath -Root $root).TrimEnd([char[]]'\/') -eq (Join-Path $root 'package with spaces')) 'Wrong absolute package path'
  }
  Test-Case 'relative package URI handles escaped spaces' {
    $root = New-PackageFixture -Name 'relative' -Relative $true
    Assert-True ((Get-FengwoJavascriptPackagePath -Root $root).TrimEnd([char[]]'\/') -eq (Join-Path $root 'package with spaces')) 'Wrong relative package path'
  }
  Test-Case 'missing pub get is actionable' {
    Assert-Throws { Get-FengwoJavascriptPackagePath -Root $testRoot } 'Run flutter pub get'
  }
  Test-Case 'different plugin version is rejected' {
    $root = New-PackageFixture -Name 'version' -Version '0.8.8'
    Assert-Throws { Get-FengwoJavascriptPackagePath -Root $root } 'pinned to flutter_js 0.8.7'
  }
  Test-Case 'duplicate plugin resolution is rejected' {
    $root = New-PackageFixture -Name 'duplicate'
    $path = Join-Path $root '.dart_tool/package_config.json'
    $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $config.packages = @($config.packages[0], $config.packages[0])
    [IO.File]::WriteAllText($path, ($config | ConvertTo-Json -Depth 4))
    Assert-Throws { Get-FengwoJavascriptPackagePath -Root $root } 'Exactly one'
  }
  Test-Case 'non-file package URI is rejected' {
    $root = New-PackageFixture -Name 'remote'
    $path = Join-Path $root '.dart_tool/package_config.json'
    $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $config.packages[0].rootUri = 'https://example.invalid/plugin/'
    [IO.File]::WriteAllText($path, ($config | ConvertTo-Json -Depth 4))
    Assert-Throws { Get-FengwoJavascriptPackagePath -Root $root } 'local package directory'
  }
  Test-Case 'pinned source hash accepts exact content' {
    $path = Join-Path $testRoot 'source.zip'
    [IO.File]::WriteAllText($path, 'pinned source')
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-FengwoJavascriptPinnedHash -Path $path -Expected $hash
  }
  Test-Case 'pinned source hash rejects changed content' {
    Assert-Throws { Assert-FengwoJavascriptPinnedHash -Path (Join-Path $testRoot 'source.zip') -Expected ('0' * 64) } 'hash mismatch'
  }
  Test-Case 'ARM64 PE machine is read correctly' {
    $path = New-PeFixture -Name 'arm64.dll' -Machine 0xAA64
    Assert-True ((Read-FengwoJavascriptPeMachine -Path $path) -eq 0xAA64) 'Wrong ARM64 machine'
  }
  Test-Case 'x64 PE machine remains distinguishable' {
    $path = New-PeFixture -Name 'x64.dll' -Machine 0x8664
    Assert-True ((Read-FengwoJavascriptPeMachine -Path $path) -eq 0x8664) 'Wrong x64 machine'
  }
  Test-Case 'truncated PE is rejected' {
    $path = Join-Path $testRoot 'short.dll'
    [IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))
    Assert-Throws { Read-FengwoJavascriptPeMachine -Path $path } 'Invalid JavaScript PE file'
  }
  Test-Case 'out of bounds PE header is rejected' {
    $path = New-PeFixture -Name 'offset.dll' -Machine 0xAA64
    $bytes = [IO.File]::ReadAllBytes($path)
    [BitConverter]::GetBytes([uint32]4096).CopyTo($bytes, 0x3C)
    [IO.File]::WriteAllBytes($path, $bytes)
    Assert-Throws { Read-FengwoJavascriptPeMachine -Path $path } 'header offset'
  }
  Test-Case 'new override is allowed' {
    Assert-FengwoJavascriptOverrideAvailable -Root $testRoot
  }
  Test-Case 'own override is idempotent with CRLF' {
    [IO.File]::WriteAllText((Join-Path $testRoot 'pubspec_overrides.yaml'), ((Get-FengwoJavascriptOverrideContent).Replace("`n", "`r`n")))
    Assert-FengwoJavascriptOverrideAvailable -Root $testRoot
  }
  Test-Case 'unrelated overrides are preserved' {
    $path = Join-Path $testRoot 'pubspec_overrides.yaml'
    [IO.File]::WriteAllText($path, "dependency_overrides:`n  other: 1.0.0`n")
    Assert-Throws { Assert-FengwoJavascriptOverrideAvailable -Root $testRoot } 'must be preserved'
    Assert-True ((Get-Content -LiteralPath $path -Raw).Contains('other: 1.0.0')) 'Original override was changed'
  }
  Test-Case 'MSVC compatibility preserves integer and function pointer types' {
    $converted = ConvertTo-FengwoJavascriptMsvcSource -Source (New-EngineSourceFixture)
    Assert-True ($converted.Contains('return (uintptr_t)_AddressOfReturnAddress();')) 'Stack pointer conversion is missing'
    Assert-True ($converted.Contains('return 0;')) 'Class identifier zero is missing'
    Assert-True ($converted.Contains('static double fengwo_math_atan2(double a, double b) { return atan2(a, b); }')) 'Binary Math wrapper changes its signature'
    Assert-True ($converted.Contains('static double fengwo_math_floor(double a) { return floor(a); }')) 'Unary Math wrapper changes its signature'
    Assert-True ([regex]::Matches($converted, 'static double fengwo_math_').Count -eq 25) 'Math wrapper count changed'
    Assert-True ($converted.Contains('f_f_f, fengwo_math_atan2')) 'Math table still uses imported binary function pointer'
  }
  Test-Case 'MSVC compatibility rejects an unexpected Math entry' {
    $source = (New-EngineSourceFixture).Replace('f_f, floor )', 'f_f, different_floor )')
    Assert-Throws { ConvertTo-FengwoJavascriptMsvcSource -Source $source } 'source contract: floor'
  }
  Test-Case 'MSVC compatibility rejects duplicate stack pointer source' {
    $source = (New-EngineSourceFixture) + "`nreturn _AddressOfReturnAddress();"
    Assert-Throws { ConvertTo-FengwoJavascriptMsvcSource -Source $source } 'stack pointer source contract'
  }
  Test-Case 'MSVC compatibility requires the pinned engine source hash' {
    $engine = Join-Path $testRoot 'unexpected-engine'
    [void][IO.Directory]::CreateDirectory($engine)
    $path = Join-Path $engine 'quickjs.c'
    [IO.File]::WriteAllText($path, (New-EngineSourceFixture))
    Assert-Throws { Update-FengwoJavascriptMsvcCompatibility -EngineDirectory $engine } 'hash mismatch'
    Assert-True ((Get-Content -LiteralPath $path -Raw) -eq (New-EngineSourceFixture)) 'Rejected engine source was modified'
  }
  Write-Host "$script:passed ARM64 JavaScript preparation checks passed"
} finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
