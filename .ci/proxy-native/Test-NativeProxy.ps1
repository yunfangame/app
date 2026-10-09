[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory,[ValidateSet('Compile','Native')][string]$Mode='Compile')
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'ISOLATED_WINDOWS_CI_REQUIRED' }
$repository=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'FrozenSources.json') -Raw | ConvertFrom-Json
[void](New-Item -ItemType Directory -Force -Path $EvidenceDirectory)
$actual=@{}
foreach ($field in $manifest.Files.PSObject.Properties) {
    $file=Join-Path $repository $field.Name
    if ($field.Name -match '(^|[/\\])\.\.([/\\]|$)' -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'INVALID_FROZEN_SOURCE_PATH' }
    $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne $field.Value) { throw ('FROZEN_SOURCE_CHANGED '+$field.Name) }
    $actual[$field.Name]=$hash
}
[ordered]@{Commit=$env:GITHUB_SHA;Mode=$Mode;OS=[Environment]::OSVersion.VersionString;PowerShell=$PSVersionTable.PSVersion.ToString();SyntheticOnly=$true;FrozenSourceHashes=$actual} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory ($Mode+'-sources.json')) -Encoding utf8
$build=Join-Path $env:RUNNER_TEMP ('proxy-native-'+$Mode+'-'+[Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $build)
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC_NOT_AVAILABLE' }
$initialize=Join-Path $build 'initialize-msvc.cmd'
@('@echo off',('call "'+(Join-Path $installation 'Common7/Tools/VsDevCmd.bat')+'" -no_logo -arch=x64 -host_arch=x64 >nul'),'if errorlevel 1 exit /b 1','set Path','set INCLUDE','set LIB','set LIBPATH','exit /b 0') | Set-Content -LiteralPath $initialize -Encoding ascii
$environment=& $env:ComSpec /d /c $initialize
if ($LASTEXITCODE -ne 0) { throw 'MSVC_ENVIRONMENT_FAILED' }
foreach ($entry in $environment) { $index=$entry.IndexOf('=');if ($index -gt 0) { $name=$entry.Substring(0,$index);if ($name -in @('Path','INCLUDE','LIB','LIBPATH')) { [Environment]::SetEnvironmentVariable($name,$entry.Substring($index+1),'Process') } } }
Push-Location $build
try {
    if ($Mode -eq 'Compile') {
        $revision='a10d8ac38de835021c8d2f920dbf50a920ccc030'
        $archives=@(
            @{Name='engine';Url=('https://storage.googleapis.com/flutter_infra_release/flutter/'+$revision+'/windows-x64-debug/windows-x64-flutter.zip');Hash='73815672368f2c3fa2e91b6ab9ab32f4abbc5f8820c39d3f2c5a129130dc13c1'},
            @{Name='wrapper';Url=('https://storage.googleapis.com/flutter_infra_release/flutter/'+$revision+'/windows-x64/flutter-cpp-client-wrapper.zip');Hash='e87298da5ab5a8795cd2a67561418a0fbd8fbe4877c79c7b819a17614aa8398d'}
        )
        foreach ($archive in $archives) {
            $zip=Join-Path $build ($archive.Name+'.zip');Invoke-WebRequest -Uri $archive.Url -OutFile $zip
            if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $archive.Hash) { throw 'OFFICIAL_FLUTTER_HEADER_HASH_CHANGED' }
            $opened=[IO.Compression.ZipFile]::OpenRead($zip)
            try { foreach ($entry in $opened.Entries) { if ($entry.FullName.EndsWith('.h')) { $destination=[IO.Path]::GetFullPath((Join-Path $build $entry.FullName));if (-not $destination.StartsWith($build+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'ARCHIVE_PATH_INVALID' };[void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination));[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$destination) } } } finally { $opened.Dispose() }
        }
        $plugin=Join-Path $repository 'plugins/proxy/windows'
        & cl.exe /nologo /c /std:c++17 /EHsc /W4 /WX /wd4100 /utf-8 /DUNICODE /D_UNICODE /DNOMINMAX /DFLUTTER_PLUGIN_IMPL /D_HAS_EXCEPTIONS=0 ('/I'+$build) ('/I'+(Join-Path $build 'cpp_client_wrapper/include')) ('/I'+$plugin) ('/I'+(Join-Path $plugin 'include')) (Join-Path $plugin 'proxy_plugin.cpp') (Join-Path $plugin 'proxy_plugin_c_api.cpp') *> (Join-Path $EvidenceDirectory 'plugin-compile.log')
        if ($LASTEXITCODE -ne 0) { throw 'PRODUCTION_PROXY_TRANSLATION_UNITS_FAILED' }
        [ordered]@{Passed=$true;TranslationUnits=@('proxy_plugin.cpp','proxy_plugin_c_api.cpp');ObjectCount=@(Get-ChildItem -LiteralPath $build -Filter '*.obj').Count;OfficialFlutterRevision=$revision;OfficialHeaderArchives=$archives;FlutterDllExecuted=$false} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'plugin-compile-result.json') -Encoding utf8
        return
    }
    if ($env:FENGWO_PROXY_MUTATING_TEST -ne '1') { throw 'MUTATING_TEST_EXPLICIT_OPT_IN_REQUIRED' }
    Add-Type -Path (Join-Path $PSScriptRoot 'IsolatedProxySnapshot.cs')
    $results=New-Object 'System.Collections.Generic.List[object]'
    foreach ($test in @($manifest.NativeTests)) {
        $name=[string]$test.Name
        if ($name -notmatch '^[a-z0-9_-]+$') { throw 'INVALID_NATIVE_TEST_NAME' }
        $source=Join-Path $repository $test.Source
        if (-not $actual.ContainsKey([string]$test.Source)) { throw 'NATIVE_TEST_SOURCE_NOT_FROZEN' }
        $exe=Join-Path $build ($name+'.exe')
        & cl.exe /nologo /std:c++17 /EHsc /W4 /WX /utf-8 /DUNICODE /D_UNICODE /DNOMINMAX ('/I'+(Join-Path $repository 'plugins/proxy/windows')) $source ('/Fe:'+$exe) wininet.lib winhttp.lib rasapi32.lib advapi32.lib *> (Join-Path $EvidenceDirectory ($name+'-compile.log'))
        if ($LASTEXITCODE -ne 0) { throw ('NATIVE_TEST_COMPILE_FAILED '+$name) }
        $snapshot=New-Object FengWoIsolatedProxySnapshot
        $watch=[Diagnostics.Stopwatch]::StartNew();$process=$null;$timedOut=$false;$exitCode=-1;$restored=$false
        try {
            $arguments=@();if ($test.Arguments) { $arguments=@($test.Arguments) }
            $options=@{FilePath=$exe;PassThru=$true;RedirectStandardOutput=(Join-Path $EvidenceDirectory ($name+'-runtime.log'));RedirectStandardError=(Join-Path $EvidenceDirectory ($name+'-stderr.log'))}
            if ($arguments.Count -gt 0) { $options.ArgumentList=$arguments }
            $process=Start-Process @options
            [void]$process.Handle
            if (-not $process.WaitForExit(60000)) { $timedOut=$true;try { $process.Kill() } catch {};[void]$process.WaitForExit(5000);throw 'NATIVE_TEST_TIMED_OUT' }
            $exitCode=$process.ExitCode
            if ($exitCode -ne 0) { throw ('NATIVE_TEST_FAILED '+$name) }
        } finally {
            $watch.Stop()
            try { $restored=$snapshot.RestoreAndVerify() } finally { $snapshot.Dispose();if ($null -ne $process) { $process.Dispose() } }
            $record=[ordered]@{Name=$name;ExitCode=$exitCode;TimedOut=$timedOut;ElapsedMs=$watch.ElapsedMilliseconds;OriginalProxyRestored=$restored;BeforeFingerprint=$snapshot.BeforeFingerprint;AfterFingerprint=$snapshot.AfterFingerprint}
            $results.Add([pscustomobject]$record)
            $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory ($name+'-execution.json')) -Encoding utf8
            if (-not $restored) { throw 'ORIGINAL_WININET_PROXY_RESTORE_MISMATCH' }
        }
    }
    $results.ToArray() | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'native-results.json') -Encoding utf8
} finally { Pop-Location }
