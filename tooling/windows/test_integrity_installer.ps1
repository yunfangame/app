param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$InnoCompiler
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The native installer integrity tests require Windows.'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
if (-not $InnoCompiler) {
    $InnoCompiler = @(
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Inno Setup 6\ISCC.exe'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $InnoCompiler) {
    $compilerCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($compilerCommand) { $InnoCompiler = $compilerCommand.Source }
}
if (-not $InnoCompiler -or -not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) {
    throw 'Inno Setup compiler was not found.'
}
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$template = [IO.File]::ReadAllText((Join-Path $repository 'windows\packaging\exe\inno_setup.iss'))
$source = [IO.File]::ReadAllText((Join-Path $repository 'windows\packaging\exe\install_integrity_code.iss'))
$dirPage = [regex]::Match($template, '(?m)^DisableDirPage=(.+)$').Groups[1].Value.Trim()
$previousDir = [regex]::Match($template, '(?m)^UsePreviousAppDir=(.+)$').Groups[1].Value.Trim()
if ($dirPage -cne 'no' -or $previousDir -cne 'yes') {
    throw 'Production upgrades must display the directory page and prefill the previous directory.'
}
if ($template -notmatch '(?s)function PrepareToInstall.*?EnsureFengWoInstallLocation.*?EnsureVcRuntime') {
    throw 'Production preparation must validate the directory before installing prerequisites or stopping the old app.'
}
if ($template -notmatch 'Check: CanLaunchInstalledFengWo;') {
    throw 'Production launch must be gated by the final executable integrity verification.'
}
$messages = @($template -split '\r?\n' | Where-Object { $_ -match '^InstallIntegrity\w+=' }) -join "`r`n"
if (-not $messages) { throw 'Production integrity messages are missing.' }
$fixtureAppId = 'FwIL' + [Guid]::NewGuid().ToString('N')
$caseRoot = Join-Path ([IO.Path]::GetTempPath()) ('FengWo-Installer-Integrity-' + $fixtureAppId)
[void][IO.Directory]::CreateDirectory($caseRoot)
$payload = Join-Path $caseRoot 'inert-payload.bin'
[IO.File]::WriteAllText($payload, 'FengWo isolated integrity fixture; never execute this file.')
$include = Join-Path $caseRoot 'production-integrity.iss'
$source = $source.Replace('procedure CurStepChanged(CurStep: TSetupStep);', 'procedure ProductionCurStepChanged(CurStep: TSetupStep);')
$source = $source.Replace('function NextButtonClick(CurPageID: Integer): Boolean;', 'function ProductionNextButtonClick(CurPageID: Integer): Boolean;')
[IO.File]::WriteAllText($include, $source, [Text.UTF8Encoding]::new($true))
$fixture = @"
[Setup]
AppId=$fixtureAppId
AppName=FengWo Isolated Integrity Fixture
AppVersion=1.0
DefaultDirName=$caseRoot\default
DisableWelcomePage=yes
DisableDirPage=$dirPage
UsePreviousAppDir=$previousDir
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
Uninstallable=yes
CreateUninstallRegKey=yes
OutputDir=$OutputDirectory
OutputBaseFilename=integrity-fixture
[CustomMessages]
$messages
[Files]
Source: "$payload"; DestDir: "{app}"; DestName: "FengWo.exe"; Flags: ignoreversion
[Code]
function CanLaunchAfterRuntime: Boolean;
begin
  Result := True;
end;
#include "$include"

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := ProductionNextButtonClick(CurPageID);
  if CurPageID = wpSelectDir then
    if not SaveStringToFile(ExpandConstant('{param:PAGEFILE|}'),
      Utf8Encode('directory-page-visited;allowed=' + IntToStr(Ord(Result)) + ';path=' + ExpandConstant('{app}')), False) then
      RaiseException('Directory page result could not be saved');
end;

procedure InitializeWizard;
begin
  if FwIntegrityValidateLabel('fixture', '') <> '' then RaiseException('An implicit Medium label was rejected');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;ME)') <> '' then RaiseException('A Medium label was rejected');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;S-1-16-8192)') <> '' then RaiseException('A numeric Medium label was rejected');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;HI)') <> '' then RaiseException('A High label was rejected');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;OICI;NW;;;LW)') = '' then RaiseException('A Low label was accepted');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;UN)') = '' then RaiseException('An Untrusted label was accepted');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;S-1-16-4096)') = '' then RaiseException('A numeric Low label was accepted');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;S-1-16-8191)') = '' then RaiseException('A sub-Medium label was accepted');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;UNKNOWN)') = '' then RaiseException('An unknown label was accepted');
  if FwIntegrityValidateLabel('fixture', 'S:(ML;;NW;;;LW') = '' then RaiseException('A malformed label was accepted');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := EnsureFengWoInstallLocation;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ExitCode: Integer;
begin
  if (CurStep = ssPostInstall) and (ExpandConstant('{param:POSTLOW|0}') = '1') then
  begin
    if not Exec(ExpandConstant('{sys}\icacls.exe'),
      '"' + ExpandConstant('{app}\FengWo.exe') + '" /setintegritylevel L',
      '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
      RaiseException('The isolated post-install Low fixture could not be created');
    if ExitCode <> 0 then RaiseException('The isolated post-install label assignment failed');
  end;
  ProductionCurStepChanged(CurStep);
  if CurStep = ssPostInstall then
  begin
    if not CanLaunchInstalledFengWo then RaiseException('Final launch verification did not pass');
    SaveStringToFile(ExpandConstant('{param:RESULTFILE|}'), 'verified', False);
  end;
end;
"@
$fixturePath = Join-Path $OutputDirectory 'integrity-fixture.iss'
[IO.File]::WriteAllText($fixturePath, $fixture, [Text.UTF8Encoding]::new($true))
& $InnoCompiler /Q $fixturePath | Write-Host
if ($LASTEXITCODE -ne 0) { throw 'The production integrity fixture did not compile.' }
$fixtureExe = Join-Path $OutputDirectory 'integrity-fixture.exe'
$results = [Collections.Generic.List[object]]::new()
$junctions = [Collections.Generic.List[string]]::new()
$denied = [Collections.Generic.List[string]]::new()
$completed = $false

function Get-SecuritySnapshot([string]$Path) {
    $result = @(& icacls.exe $Path 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Fixture permissions could not be inspected: $Path" }
    return $result
}

function Set-LowFixture([string]$Path, [bool]$Directory = $true) {
    $label = if ($Directory) { '(OI)(CI)L' } else { 'L' }
    & icacls.exe $Path /setintegritylevel $label | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "Low integrity fixture setup failed: $Path" }
    $snapshot = Get-SecuritySnapshot $Path
    if ($snapshot -notmatch '(?i)(Low Mandatory Level|S-1-16-4096)') {
        throw "The fixture does not have a Low label: $Path"
    }
}

function Invoke-Case([string]$Name, [string]$Target, [bool]$ExpectedSuccess, [string]$ExpectedCode = '', [bool]$PostLow = $false, [bool]$UsePreviousDirectory = $false) {
    $log = Join-Path $OutputDirectory ($Name + '.log')
    $resultFile = Join-Path $OutputDirectory ($Name + '.result')
    $pageFile = Join-Path $OutputDirectory ($Name + '-directory-page.result')
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $Target + '"'), ('/LOG="' + $log + '"'), ('/RESULTFILE="' + $resultFile + '"'), ('/PAGEFILE="' + $pageFile + '"'))
    if ($UsePreviousDirectory) { $arguments = @($arguments | Where-Object { -not $_.StartsWith('/DIR=') }) }
    if ($PostLow) { $arguments += '/POSTLOW=1' }
    $process = Start-Process -FilePath $fixtureExe -ArgumentList $arguments -PassThru
    $handle = $process.Handle
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force
        throw "The silent installer did not exit for case $Name"
    }
    $verified = Test-Path -LiteralPath $resultFile -PathType Leaf
    $logText = if (Test-Path -LiteralPath $log -PathType Leaf) { [IO.File]::ReadAllText($log) } else { '' }
    $diagnosticLines = @($logText -split '\r?\n' | Where-Object { $_.Contains('FENGWO_INSTALL_INTEGRITY ' + $ExpectedCode + ' path=') -and -not $_.Contains('path=fixture ') })
    $passed = if ($ExpectedSuccess) {
        $process.ExitCode -eq 0 -and $verified -and [IO.File]::ReadAllText($resultFile) -ceq 'verified'
    } else {
        $process.ExitCode -ne 0 -and -not $verified -and $diagnosticLines.Count -gt 0 -and $logText.Contains('INSTALL-INTEGRITY-' + $ExpectedCode)
    }
    $expectedPageAllowed = if (($ExpectedCode -eq 'Low' -and -not $PostLow) -or $ExpectedCode -eq 'Reparse') { 0 } else { 1 }
    $pageObserved = Test-Path -LiteralPath $pageFile -PathType Leaf
    $pageResult = if ($pageObserved) { [IO.File]::ReadAllText($pageFile) } else { '' }
    $pagePassed = $pageResult -ceq "directory-page-visited;allowed=$expectedPageAllowed;path=$Target"
    $passed = $passed -and $pagePassed
    $results.Add(@{ case=$Name; exit_code=$process.ExitCode; installed_verified=$verified; expected_success=$ExpectedSuccess; expected_code=$ExpectedCode; directory_page=$pageResult; directory_page_passed=$pagePassed; passed=$passed })
    if (-not $passed) {
        $logText -split '\r?\n' | Select-Object -Last 70 | Write-Host
        throw "The production integrity case failed: $Name (exit $($process.ExitCode))"
    }
    Write-Host "Installer integrity passed: $Name"
}

try {
    $normal = Join-Path $caseRoot 'normal\蜂窝加速器'
    Invoke-Case 'normal-new-chinese-path' $normal $true
    $normalAcl = Get-SecuritySnapshot $normal
    Invoke-Case 'normal-cover-upgrade' $normal $true '' $false $true
    if ((Get-SecuritySnapshot $normal) -cne $normalAcl) { throw 'The normal upgrade changed directory security.' }

    $lowParent = Join-Path $caseRoot 'low-parent'
    [void][IO.Directory]::CreateDirectory($lowParent)
    Set-LowFixture $lowParent
    $beforeLow = Get-SecuritySnapshot $lowParent
    $lowTarget = Join-Path $lowParent 'FengWo'
    Invoke-Case 'inherited-low-parent' $lowTarget $false 'Low'
    if (Test-Path -LiteralPath $lowTarget) { throw 'A rejected Low location was modified.' }
    if ((Get-SecuritySnapshot $lowParent) -cne $beforeLow) { throw 'The Low parent security was modified.' }

    $oldLow = Join-Path $caseRoot 'old-low-app'
    [void][IO.Directory]::CreateDirectory($oldLow)
    $oldExe = Join-Path $oldLow 'FengWo.exe'
    [IO.File]::WriteAllText($oldExe, 'old executable sentinel')
    Set-LowFixture $oldLow
    $oldHash = (Get-FileHash -LiteralPath $oldExe -Algorithm SHA256).Hash
    Invoke-Case 'existing-low-directory' $oldLow $false 'Low'
    if ((Get-FileHash -LiteralPath $oldExe -Algorithm SHA256).Hash -cne $oldHash) { throw 'A rejected old executable was overwritten.' }

    $lowExeDir = Join-Path $caseRoot 'only-exe-low'
    [void][IO.Directory]::CreateDirectory($lowExeDir)
    $lowExe = Join-Path $lowExeDir 'FengWo.exe'
    [IO.File]::WriteAllText($lowExe, 'old low executable sentinel')
    Set-LowFixture $lowExe $false
    $beforeExe = Get-SecuritySnapshot $lowExe
    Invoke-Case 'existing-low-executable' $lowExeDir $false 'Low'
    if ((Get-SecuritySnapshot $lowExe) -cne $beforeExe) { throw 'The existing Low executable security was modified.' }

    $outside = Join-Path $caseRoot 'outside-target'
    [void][IO.Directory]::CreateDirectory($outside)
    $outsideSentinel = Join-Path $outside 'user-data.sentinel'
    [IO.File]::WriteAllText($outsideSentinel, 'preserve external data and permissions')
    $outsideAcl = Get-SecuritySnapshot $outside
    $link = Join-Path $caseRoot 'redirected'
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    $junctions.Add($link)
    Invoke-Case 'reparse-target' (Join-Path $link 'FengWo') $false 'Reparse'
    if ([IO.File]::ReadAllText($outsideSentinel) -cne 'preserve external data and permissions' -or (Get-SecuritySnapshot $outside) -cne $outsideAcl -or (Test-Path -LiteralPath (Join-Path $outside 'FengWo'))) {
        throw 'The reparse target was modified.'
    }

    $denyDir = Join-Path $caseRoot 'deny-write'
    [void][IO.Directory]::CreateDirectory($denyDir)
    & icacls.exe $denyDir /deny '*S-1-1-0:(W)' | Write-Host
    if ($LASTEXITCODE -ne 0) { throw 'The denied-write fixture could not be created.' }
    $denied.Add($denyDir)
    Invoke-Case 'directory-write-denied' $denyDir $false 'Access'
    if (Test-Path -LiteralPath (Join-Path $denyDir 'FengWo.exe')) { throw 'The denied directory was modified.' }

    Invoke-Case 'post-install-low-executable' (Join-Path $caseRoot 'post-low') $false 'Low' $true
    $newNormal = Join-Path $caseRoot 'normal-recovery\FengWo'
    Invoke-Case 'choose-normal-after-low-rejection' $newNormal $true
    if ((Get-SecuritySnapshot $lowParent) -cne $beforeLow -or (Get-SecuritySnapshot $lowExe) -cne $beforeExe) {
        throw 'Choosing a new install directory altered the previous Low directory.'
    }
    $completed = $true
} finally {
    $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'integrity-results.json') -Encoding utf8
    foreach ($path in $denied) {
        & icacls.exe $path /remove:d '*S-1-1-0' | Write-Host
        if ($LASTEXITCODE -ne 0) { Write-Warning "Fixture deny cleanup failed: $path" }
    }
    foreach ($path in $junctions) {
        if ([IO.Directory]::Exists($path)) { [IO.Directory]::Delete($path) }
    }
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
        $hive = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $view)
        try {
            $hive.DeleteSubKeyTree(('Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $fixtureAppId + '_is1'), $false)
        } finally {
            $hive.Dispose()
        }
    }
    if ($completed) {
        Remove-Item -LiteralPath $caseRoot -Recurse -Force
    } else {
        Write-Host "Failed integrity fixture files retained: $caseRoot"
    }
}
Write-Host "Installer integrity verified: $($results.Count) native silent scenarios."
