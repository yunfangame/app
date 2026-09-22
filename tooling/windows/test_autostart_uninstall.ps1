param([Parameter(Mandatory = $true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') { throw 'Requires an isolated GitHub Actions Windows runner' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$template = Get-Content -LiteralPath (Join-Path $repository 'windows/packaging/exe/inno_setup.iss') -Raw
$pattern = '(?ms)^procedure RemoveOwnedAutoLaunch\(RootKey: Integer; Name: String\);\s*\r?\n.*?^end;\s*\r?\n\s*procedure CurUninstallStepChanged\(CurUninstallStep: TUninstallStep\);\s*\r?\n.*?^end;'
$match = [regex]::Match($template, $pattern)
if (-not $match.Success) { throw 'Production uninstall callbacks were not found' }
$production = $match.Value.Replace('procedure CurUninstallStepChanged(', 'procedure ProductionCurUninstallStepChanged(')
$fixture = @"
[Setup]
AppId=FengWo-Autostart-Isolated-Uninstall-Test
AppName=FengWo Autostart Isolated Test
AppVersion=1.0
DefaultDirName={tmp}\FengWo Uninstall Test
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=$OutputDirectory
OutputBaseFilename=fixture
UninstallDisplayName=FengWo Autostart Isolated Test
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
[Files]
Source: "{sys}\whoami.exe"; DestDir: "{app}"; DestName: "FengWo.exe"; Flags: external
[Code]
$production
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Value: String;
begin
  Log('fixture_callback_begin=' + IntToStr(Ord(CurUninstallStep)) + ' app=' + ExpandConstant('{app}'));
  if RegQueryStringValue(HKCU64, 'Software\Microsoft\Windows\CurrentVersion\Run', 'FengWo', Value) then Log('fixture_FengWo_before=' + Value);
  ProductionCurUninstallStepChanged(CurUninstallStep);
  if RegQueryStringValue(HKCU64, 'Software\Microsoft\Windows\CurrentVersion\Run', 'FengWo', Value) then Log('fixture_FengWo_after=' + Value);
  Log('fixture_callback_end=' + IntToStr(Ord(CurUninstallStep)));
end;
"@
$script = Join-Path $OutputDirectory 'fixture.iss'
[IO.File]::WriteAllText($script, $fixture, [Text.UTF8Encoding]::new($true))
$compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
& $compiler $script
if ($LASTEXITCODE -ne 0) { throw 'Native uninstall fixture compilation failed' }
$runPath = 'Software\Microsoft\Windows\CurrentVersion\Run'
$approvedPath = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$keys = @{}
$original = @()
foreach ($path in @($runPath, $approvedPath)) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
    $keys[$path] = $key
    foreach ($name in @('FengWo', 'FlClash')) {
        $exists = $key.GetValueNames() -contains $name
        $original += @{path=$path; name=$name; exists=$exists; value=$(if($exists){$key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null}); kind=$(if($exists){$key.GetValueKind($name)}else{$null})}
    }
}
$results = [Collections.Generic.List[object]]::new()
function Invoke-Fixture([string]$File, [string[]]$Arguments) {
    $process = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru
    $handle = $process.Handle
    if (-not $process.WaitForExit(45000)) { Stop-Process -Id $process.Id -Force; throw 'Fixture process timed out' }
    if ($process.ExitCode -ne 0) { throw "Fixture process failed: $($process.ExitCode)" }
}
try {
    foreach ($case in @('quoted-fengwo', 'unquoted-legacy')) {
        $directory = Join-Path $env:RUNNER_TEMP ('FengWo Uninstall ' + $case)
        $application = Join-Path $directory 'FengWo.exe'
        $ownName = if ($case -eq 'quoted-fengwo') { 'FengWo' } else { 'FlClash' }
        $foreignName = if ($case -eq 'quoted-fengwo') { 'FlClash' } else { 'FengWo' }
        $ownCommand = if ($case -eq 'quoted-fengwo') { '"' + $application + '"' } else { $application }
        $foreignCommand = '"C:\Another Installation\' + $foreignName + '.exe"'
        Invoke-Fixture (Join-Path $OutputDirectory 'fixture.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $directory + '"'))
        $keys[$runPath].SetValue($ownName, $ownCommand, [Microsoft.Win32.RegistryValueKind]::String)
        $keys[$approvedPath].SetValue($ownName, [byte[]](2,0,0,0,0,0,0,0,0,0,0,0), [Microsoft.Win32.RegistryValueKind]::Binary)
        $keys[$runPath].SetValue($foreignName, $foreignCommand, [Microsoft.Win32.RegistryValueKind]::String)
        $keys[$approvedPath].SetValue($foreignName, [byte[]](3,0,0,0,0,0,0,0,0,0,0,0), [Microsoft.Win32.RegistryValueKind]::Binary)
        $watch = [Diagnostics.Stopwatch]::StartNew()
        Invoke-Fixture (Join-Path $directory 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="' + (Join-Path $OutputDirectory ($case + '-uninstall.log')) + '"'))
        $atExit = @{elapsed_ms=$watch.ElapsedMilliseconds; own_run=$keys[$runPath].GetValue($ownName); own_approval=$keys[$approvedPath].GetValue($ownName); application_exists=(Test-Path -LiteralPath $application)}
        $complete = $false
        do {
            $complete = $keys[$runPath].GetValue($ownName) -eq $null -and $keys[$approvedPath].GetValue($ownName) -eq $null -and -not (Test-Path -LiteralPath $application)
            if ($complete) { break }
            Start-Sleep -Milliseconds 100
        } while ($watch.ElapsedMilliseconds -lt 15000)
        $foreignPreserved = $keys[$runPath].GetValue($foreignName) -ceq $foreignCommand -and ([byte[]]$keys[$approvedPath].GetValue($foreignName))[0] -eq 3
        $results.Add(@{case=$case; at_parent_exit=$atExit; elapsed_ms=$watch.ElapsedMilliseconds; completed=$complete; foreign_preserved=$foreignPreserved; final_run=$keys[$runPath].GetValue($ownName); final_approval=$keys[$approvedPath].GetValue($ownName)})
        if (-not $complete -or -not $foreignPreserved) { throw "Native production uninstall cleanup failed: $case" }
    }
} finally {
    $results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'uninstall-results.json') -Encoding utf8
    foreach ($item in $original) {
        $key = $keys[$item.path]
        if ($item.exists) { $key.SetValue($item.name, $item.value, $item.kind) } else { $key.DeleteValue($item.name, $false) }
    }
    foreach ($key in $keys.Values) { $key.Dispose() }
}
