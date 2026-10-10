param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$Generator = 'Ninja',
  [string]$CmakePath = 'cmake',
  [string]$EvidenceDirectory = (Join-Path ([IO.Path]::GetTempPath()) "fengwo-webview-coroutines-$([Guid]::NewGuid().ToString('N'))")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$projectCmake = Get-Content -LiteralPath (Join-Path $ProjectRoot 'windows/CMakeLists.txt') -Raw
$pattern = '(?s)if\(MSVC AND FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64" AND TARGET webview_all_windows_plugin\).*?\nendif\(\)'
$matches = [regex]::Matches($projectCmake, $pattern)
if ($matches.Count -ne 1) { throw 'Exactly one scoped WebView ARM64 coroutine configuration is required' }
$configuration = $matches[0].Value
$cppPath = (Join-Path $PSScriptRoot 'standard_coroutines_check.cpp').Replace('\', '/')
$cases = @(
  @{ name = 'arm64_msvc'; platform = 'windows-arm64'; msvc = 'TRUE'; present = $true; expected = '20' },
  @{ name = 'x64_msvc'; platform = 'windows-x64'; msvc = 'TRUE'; present = $true; expected = '17' },
  @{ name = 'arm64_other_compiler'; platform = 'windows-arm64'; msvc = 'FALSE'; present = $true; expected = '17' },
  @{ name = 'arm64_without_webview'; platform = 'windows-arm64'; msvc = 'TRUE'; present = $false; expected = 'absent' }
)
$results = [Collections.Generic.List[object]]::new()
foreach ($case in $cases) {
  $source = Join-Path $EvidenceDirectory $case.name
  $build = Join-Path $source 'build'
  [void][IO.Directory]::CreateDirectory($source)
  [IO.File]::WriteAllText((Join-Path $source 'other.cpp'), 'int other() { return 17; }', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $source 'minimal.cpp'), 'int main() { return 0; }', [Text.UTF8Encoding]::new($false))
  $pluginSource = if ($case.name -eq 'arm64_msvc') { $cppPath } else { 'minimal.cpp' }
  $plugin = if ($case.present) {
    "add_executable(webview_all_windows_plugin `"$pluginSource`")`nset_target_properties(webview_all_windows_plugin PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)`ntarget_compile_features(webview_all_windows_plugin PRIVATE cxx_std_17)`nif(WIN32)`n  target_link_libraries(webview_all_windows_plugin PRIVATE runtimeobject)`nendif()`n"
  } else { '' }
  $cmake = @'
cmake_minimum_required(VERSION 3.15)
project(webview_coroutine_scope LANGUAGES CXX)
add_library(other_plugin STATIC other.cpp)
set_target_properties(other_plugin PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
'@ + "`n$plugin" + "set(MSVC $($case.msvc))`nset(FLUTTER_TARGET_PLATFORM `"$($case.platform)`")`n$configuration`n" + @'
get_target_property(other_standard other_plugin CXX_STANDARD)
if(NOT other_standard EQUAL 17)
  message(FATAL_ERROR "The WebView configuration changed an unrelated plugin")
endif()
if(TARGET webview_all_windows_plugin)
  get_target_property(webview_standard webview_all_windows_plugin CXX_STANDARD)
else()
  set(webview_standard "absent")
endif()
'@ + "`nif(NOT webview_standard STREQUAL `"$($case.expected)`")`n  message(FATAL_ERROR `"Unexpected WebView standard: `${webview_standard}`")`nendif()`n" + @'
if(webview_standard STREQUAL "20")
  get_target_property(required webview_all_windows_plugin CXX_STANDARD_REQUIRED)
  get_target_property(extensions webview_all_windows_plugin CXX_EXTENSIONS)
  if(NOT required OR extensions)
    message(FATAL_ERROR "Standard coroutines must be required without language extensions")
  endif()
endif()
file(WRITE "${CMAKE_BINARY_DIR}/scope.txt" "webview_standard=${webview_standard}\nother_standard=${other_standard}\n")
'@
  [IO.File]::WriteAllText((Join-Path $source 'CMakeLists.txt'), $cmake, [Text.UTF8Encoding]::new($false))
  $arguments = @('-S', $source, '-B', $build, '-G', $Generator, '-DCMAKE_BUILD_TYPE=Release')
  if ($Generator -match '^Visual Studio ') { $arguments += @('-A', 'ARM64') }
  & $CmakePath @arguments 2>&1 | Tee-Object -FilePath (Join-Path $source 'configure.log')
  if ($LASTEXITCODE -ne 0) { throw "WebView coroutine scope configuration failed: $($case.name)" }
  if ($case.name -eq 'arm64_msvc') {
    & $CmakePath --build $build --config Release --target webview_all_windows_plugin 2>&1 | Tee-Object -FilePath (Join-Path $source 'build.log')
    if ($LASTEXITCODE -ne 0) { throw 'The actual compiler/SDK cannot build standard coroutines' }
    $suffix = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { '.exe' } else { '' }
    $executable = if ($Generator -match '^Visual Studio ') { Join-Path $build "Release/webview_all_windows_plugin$suffix" } else { Join-Path $build "webview_all_windows_plugin$suffix" }
    $start = [Diagnostics.ProcessStartInfo]::new($executable)
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    try {
      if (-not $process.WaitForExit(15000)) {
        $process.Kill()
        throw 'The standard coroutine smoke exceeded 15 seconds'
      }
      if ($process.ExitCode -ne 0) { throw "The standard coroutine smoke failed with exit code $($process.ExitCode)" }
    } finally { $process.Dispose() }
  }
  $results.Add([ordered]@{ name = $case.name; webview_standard = $case.expected; unrelated_standard = '17'; passed = $true })
  Write-Host "PASS WebView coroutine configuration $($case.name)"
}
$evidence = [ordered]@{
  project_cmake_sha256 = (Get-FileHash -LiteralPath (Join-Path $ProjectRoot 'windows/CMakeLists.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
  check_source_sha256 = (Get-FileHash -LiteralPath $cppPath -Algorithm SHA256).Hash.ToLowerInvariant()
  generator = $Generator
  host = [Runtime.InteropServices.RuntimeInformation]::OSDescription
  process_architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
  standard_coroutine_compile_and_run = 'passed'
  cppwinrt_compile_and_run = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'passed' } else { 'requires_windows_arm64' }
  cases = $results.ToArray()
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'summary.json'), $evidence, [Text.UTF8Encoding]::new($false))
Write-Host '4 WebView configuration checks and the standard coroutine smoke passed'
