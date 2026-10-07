param([Parameter(Mandatory = $true)][string]$EvidenceDirectory, [switch]$CompileOnly)

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
$pluginDirectory = Join-Path $repository 'plugins/window_ext/windows'
if ($CompileOnly) {
    $sourceHashes['window_ext_plugin.cpp'] = (Get-FileHash -LiteralPath (Join-Path $pluginDirectory 'window_ext_plugin.cpp') -Algorithm SHA256).Hash.ToLowerInvariant()
}
[ordered]@{ commit = $env:GITHUB_SHA; runtime = $PSVersionTable.PSVersion.ToString(); runner = $env:RUNNER_OS; synthetic_data_only = $true; source_hashes = $sourceHashes; uipi_window_scoped_structure_verified = $true } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'source.json') -Encoding UTF8
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($installation)) { throw 'MSVC installation unavailable' }
$developerCommand = Join-Path $installation 'Common7/Tools/VsDevCmd.bat'
$initialize = Join-Path $build 'initialize-msvc.cmd'
@('@echo off', ('call "' + $developerCommand + '" -no_logo -arch=x64 -host_arch=x64 >nul'), 'if errorlevel 1 exit /b 1', 'set Path', 'set INCLUDE', 'set LIB', 'set LIBPATH', 'exit /b 0') |
    Set-Content -LiteralPath $initialize -Encoding ASCII
$environment = & $env:ComSpec /d /c $initialize
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
    if ($CompileOnly) {
        $engineRevision = 'a10d8ac38de835021c8d2f920dbf50a920ccc030'
        $engineUrl = 'https://storage.googleapis.com/flutter_infra_release/flutter/' + $engineRevision + '/windows-x64-debug/windows-x64-flutter.zip'
        $wrapperUrl = 'https://storage.googleapis.com/flutter_infra_release/flutter/' + $engineRevision + '/windows-x64/flutter-cpp-client-wrapper.zip'
        $engineZip = Join-Path $build 'engine.zip'
        $wrapperZip = Join-Path $build 'wrapper.zip'
        Invoke-WebRequest -Uri $engineUrl -OutFile $engineZip
        Invoke-WebRequest -Uri $wrapperUrl -OutFile $wrapperZip
        $engineHash = (Get-FileHash -LiteralPath $engineZip -Algorithm SHA256).Hash.ToLowerInvariant()
        $wrapperHash = (Get-FileHash -LiteralPath $wrapperZip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($engineHash -ne '73815672368f2c3fa2e91b6ab9ab32f4abbc5f8820c39d3f2c5a129130dc13c1' -or
            $wrapperHash -ne 'e87298da5ab5a8795cd2a67561418a0fbd8fbe4877c79c7b819a17614aa8398d') {
            throw 'Pinned official Flutter header artifacts have unexpected bytes'
        }
        foreach ($archive in @($engineZip, $wrapperZip)) {
            $opened = [IO.Compression.ZipFile]::OpenRead($archive)
            try {
                foreach ($entry in $opened.Entries) {
                    if ($entry.FullName.EndsWith('.h')) {
                        $destination = Join-Path $build $entry.FullName
                        [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination))
                        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination)
                    }
                }
            } finally {
                $opened.Dispose()
            }
        }
        $registrant = Join-Path $build 'stub/flutter/generated_plugin_registrant.h'
        [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $registrant))
        @('#pragma once', '#include <flutter/plugin_registry.h>', 'void RegisterPlugins(flutter::PluginRegistry* registry);') |
            Set-Content -LiteralPath $registrant -Encoding ASCII
        $includes = @(('/I' + $build), ('/I' + (Join-Path $build 'cpp_client_wrapper/include')), ('/I' + (Join-Path $build 'stub')), ('/I' + $runnerDirectory), ('/I' + (Join-Path $pluginDirectory 'include')))
        $sources = @((Join-Path $pluginDirectory 'window_ext_plugin.cpp'), (Join-Path $pluginDirectory 'window_ext_plugin_c_api.cpp'))
        $sources += @('main.cpp', 'win32_window.cpp', 'flutter_window.cpp', 'utils.cpp', 'window_visibility.cpp') | ForEach-Object { Join-Path $runnerDirectory $_ }
        & cl.exe /nologo /c /std:c++17 /EHsc /W4 /WX /wd4100 /utf-8 /DUNICODE /D_UNICODE /DNOMINMAX /DFLUTTER_PLUGIN_IMPL /D_HAS_EXCEPTIONS=0 @includes @sources *> (Join-Path $EvidenceDirectory 'compile.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Production runner or window_ext plugin compilation failed' }
        [ordered]@{ passed = $true; compile_only = $true; object_count = @(Get-ChildItem -LiteralPath $build -Filter '*.obj').Count; production_translation_units = $sources; flutter_engine_revision = $engineRevision; official_engine_url = $engineUrl; official_engine_sha256 = $engineHash; official_wrapper_url = $wrapperUrl; official_wrapper_sha256 = $wrapperHash; official_dll_executed = $false; generated_registrant_stub = 'void RegisterPlugins(flutter::PluginRegistry* registry);'; flags = '/std:c++17 /EHsc /W4 /WX /wd4100 /utf-8 /D_HAS_EXCEPTIONS=0'; source_hashes = $sourceHashes } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'verification.json') -Encoding UTF8
        return
    }
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
