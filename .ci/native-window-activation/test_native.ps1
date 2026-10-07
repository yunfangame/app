param([Parameter(Mandatory = $true)][string]$EvidenceDirectory)

$ErrorActionPreference = 'Stop'
[void](New-Item -ItemType Directory -Force -Path $EvidenceDirectory)
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runnerDirectory = Join-Path $repository 'windows/runner'
$build = Join-Path $env:RUNNER_TEMP ('native-window-build-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $build)
$sourceHashes = [ordered]@{}
foreach ($name in @('window_visibility.h', 'window_visibility.cpp', 'win32_window.h', 'win32_window.cpp', 'flutter_window.cpp', 'main.cpp', 'CMakeLists.txt')) {
    $file = Join-Path $runnerDirectory $name
    $sourceHashes[$name] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
}
$visibilitySource = Get-Content -LiteralPath (Join-Path $runnerDirectory 'window_visibility.cpp') -Raw
if ([regex]::Matches($visibilitySource, 'ChangeWindowMessageFilterEx\s*\(').Count -ne 1 -or
    $visibilitySource -notmatch '(?s)ChangeWindowMessageFilterEx\s*\(\s*window\s*,\s*activation\s*,\s*MSGFLT_ALLOW\s*,\s*nullptr\s*\)' -or
    $visibilitySource -match 'ChangeWindowMessageFilter\s*\(') {
    throw 'UIPI must allow only the dedicated registered message on its target window'
}
[ordered]@{ commit = $env:GITHUB_SHA; runtime = $PSVersionTable.PSVersion.ToString(); runner = $env:RUNNER_OS; synthetic_data_only = $true; source_hashes = $sourceHashes; uipi_window_scoped_structure_verified = $true } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'source.json') -Encoding UTF8
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($installation)) { throw 'MSVC installation unavailable' }
$developerCommand = Join-Path $installation 'Common7/Tools/VsDevCmd.bat'
$environment = & $env:ComSpec /d /s /c ('""' + $developerCommand + '" -no_logo -arch=x64 -host_arch=x64 >nul && set"')
if ($LASTEXITCODE -ne 0) { throw 'MSVC developer environment initialization failed' }
foreach ($entry in $environment) {
    $split = $entry.IndexOf('=')
    if ($split -gt 0) {
        $name = $entry.Substring(0, $split)
        if ($name -in @('Path', 'INCLUDE', 'LIB', 'LIBPATH')) {
            [Environment]::SetEnvironmentVariable($name, $entry.Substring($split + 1), 'Process')
        }
    }
}
$executable = Join-Path $build 'native-window-tests.exe'
Push-Location $build
try {
    & cl.exe /nologo /std:c++17 /EHsc /W4 /WX /utf-8 /DUNICODE /D_UNICODE /DNOMINMAX ('/I' + $runnerDirectory) (Join-Path $runnerDirectory 'window_visibility.cpp') (Join-Path $PSScriptRoot 'native_window_tests.cpp') ('/Fe:' + $executable) user32.lib gdi32.lib dwmapi.lib advapi32.lib *> (Join-Path $EvidenceDirectory 'build.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Production window visibility module or native test compilation failed' }
    $process = Start-Process -FilePath $executable -ArgumentList ('"' + (Join-Path $EvidenceDirectory 'verification.json') + '"') -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory 'runtime.txt') -RedirectStandardError (Join-Path $EvidenceDirectory 'stderr.txt')
    try {
        $processHandle = $process.Handle
        if (-not $process.WaitForExit(60000)) {
            try { $process.Kill() } catch { }
            throw 'Native verification exceeded the 60 second limit'
        }
        if ($null -eq $process.ExitCode -or $process.ExitCode -ne 0) { throw 'Production window visibility native verification failed' }
    } finally {
        $process.Dispose()
    }
} finally {
    Pop-Location
}
