param(
    [Parameter(Mandatory = $true)][string]$SdkDirectory,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

. (Join-Path $PSScriptRoot 'common.ps1')
$environment = Assert-FwArmRunner
if (Test-Path -LiteralPath $SdkDirectory) { throw 'The ARM64 Flutter SDK destination must be new' }
& git clone --depth 1 --branch 3.44.4 https://github.com/flutter/flutter.git $SdkDirectory
if ($LASTEXITCODE -ne 0) { throw 'Pinned Flutter checkout failed' }
$revision = (& git -C $SdkDirectory rev-parse HEAD).Trim()
if ($revision -cne 'ad70ec4617166f1c38e5d2bfd388af71fda14f06') { throw 'Unexpected Flutter 3.44.4 source revision' }
$engine = [IO.File]::ReadAllText((Join-Path $SdkDirectory 'bin/internal/engine.version')).Trim()
if ($engine -cne 'a10d8ac38de835021c8d2f920dbf50a920ccc030') { throw 'Unexpected pinned Flutter engine revision' }
$previousArchitecture = $env:PROCESSOR_ARCHITECTURE
try {
    $env:PROCESSOR_ARCHITECTURE = 'ARM64'
    & (Join-Path $SdkDirectory 'bin/flutter.bat') --version
    if ($LASTEXITCODE -ne 0) { throw 'Native Flutter bootstrap failed' }
} finally {
    $env:PROCESSOR_ARCHITECTURE = $previousArchitecture
}
$dart = Get-FwPeIdentity (Join-Path $SdkDirectory 'bin/cache/dart-sdk/bin/dart.exe')
if (-not $dart.arm64) { throw 'Flutter downloaded a non-ARM64 Dart SDK; refusing an x64 application build' }
$env:PATH = (Join-Path $SdkDirectory 'bin') + ';' + $env:PATH
& flutter config --enable-windows-desktop --no-analytics
if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows configuration failed' }
if ($env:GITHUB_PATH) { Add-Content -LiteralPath $env:GITHUB_PATH -Value (Join-Path $SdkDirectory 'bin') }
if ($env:GITHUB_ENV) {
    Add-Content -LiteralPath $env:GITHUB_ENV -Value ('FENGWO_ARM64_FLUTTER=' + $SdkDirectory)
    Add-Content -LiteralPath $env:GITHUB_ENV -Value 'PROCESSOR_ARCHITECTURE=ARM64'
}
Save-FwArmEvidence (Join-Path $EvidenceDirectory 'toolchain.json') ([ordered]@{ environment = $environment; flutter_version = '3.44.4'; flutter_revision = $revision; engine_revision = $engine; dart = $dart; source_bootstrap = $true })
