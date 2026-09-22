param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Requires disposable Windows CI' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC is required' }
$vcvars = "$installation\VC\Auxiliary\Build\vcvars64.bat"
& cmd.exe /c ('call "' + $vcvars + '" >nul && set') | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize MSVC environment' }
$source = (Resolve-Path "$PSScriptRoot/../../plugins/proxy/windows/test/proxy_winhttp_compatibility_test.cpp").Path
$helper = (Resolve-Path "$PSScriptRoot/../../plugins/proxy/windows/proxy_settings.h").Path
$binary = "$OutputDirectory/proxy_winhttp_compatibility_test.exe"
$inputFile = "$OutputDirectory/raw-bypass.txt"
$outputFile = "$OutputDirectory/normalized-bypass.txt"
$cases = Get-Content "$PSScriptRoot/chrome_proxy_cases.json" -Raw | ConvertFrom-Json
[IO.File]::WriteAllText($inputFile, ($cases.current -join ';'), [Text.UTF8Encoding]::new($false))
Push-Location $OutputDirectory
try {
    & cl.exe /nologo /std:c++17 /EHsc /utf-8 $source "/Fe:$binary" /link wininet.lib winhttp.lib 2>&1 | Tee-Object "$OutputDirectory/production-compile.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Production native regression failed to compile' }
    $env:FENGWO_PROXY_MUTATING_TEST = '1'
    & $binary $inputFile $outputFile 2>&1 | Tee-Object "$OutputDirectory/production-regression.txt"
    if ($LASTEXITCODE -ne 0) { throw 'Production native regression failed' }
    @{helper_sha256=(Get-FileHash $helper -Algorithm SHA256).Hash; source_sha256=(Get-FileHash $source -Algorithm SHA256).Hash; normalized_sha256=(Get-FileHash $outputFile -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content "$OutputDirectory/production-source.json"
} finally {
    Pop-Location
    Remove-Item $binary, "$OutputDirectory/proxy_winhttp_compatibility_test.obj" -Force -ErrorAction SilentlyContinue
}
