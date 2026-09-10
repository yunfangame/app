param(
    [string]$InnoCompiler
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'The native installer policy tests require Windows.'
}

if (-not $InnoCompiler) {
    $compilerCandidates = @(
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Inno Setup 6\ISCC.exe'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Inno Setup 6\ISCC.exe')
    )
    $InnoCompiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $InnoCompiler) {
        $compilerCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        if ($compilerCommand) { $InnoCompiler = $compilerCommand.Source }
    }
}
if (-not $InnoCompiler -or -not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) {
    throw 'Inno Setup compiler was not found. Supply -InnoCompiler with its full path.'
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$template = [IO.File]::ReadAllText((Join-Path $repositoryRoot 'windows\packaging\exe\inno_setup.iss'))
$runtimeSource = [IO.File]::ReadAllText((Join-Path $repositoryRoot 'windows\packaging\exe\vc_runtime_code.iss'))
$codeMatch = [regex]::Match($template, '(?ms)^\[Code\]\s*\r?\n(?<code>.*?)(?=^\[|\z)')
if (-not $codeMatch.Success) { throw 'The production installer Code section was not found.' }
$runtimeInclude = '#include "{{SOURCE_DIR}}\prerequisites\vc_runtime_code.iss"'
$productionCode = $codeMatch.Groups['code'].Value
if ([regex]::Matches($productionCode, [regex]::Escape($runtimeInclude)).Count -ne 1) {
    throw 'The production runtime include was not found exactly once.'
}
$productionCode = $productionCode.Replace($runtimeInclude, $runtimeSource)
if ($productionCode.Contains('{{') -or $productionCode -match '(?m)^#include') {
    throw 'The production Code section contains an unresolved template or include.'
}
$customMessages = @($template -split '\r?\n' | Where-Object { $_ -match '^(?:english\.)?VcRuntime\w+=' } | ForEach-Object { $_ -replace '^english\.', '' }) -join "`n"
if (-not $customMessages) { throw 'The production English runtime messages were not found.' }

$mockCode = $productionCode
$cleanupMocks = @{
    KillProcesses = 'procedure KillProcesses; begin TestKillCalls := TestKillCalls + 1; TestActions := TestActions + ''kill;''; end;'
    UnregisterHelperService = 'procedure UnregisterHelperService; begin TestUnregisterCalls := TestUnregisterCalls + 1; TestActions := TestActions + ''unregister;''; end;'
}
foreach ($entry in $cleanupMocks.GetEnumerator()) {
    $pattern = '(?ms)^procedure ' + [regex]::Escape($entry.Key) + ';\s*\r?\n.*?^end;'
    if ([regex]::Matches($mockCode, $pattern).Count -ne 1) {
        throw "Production cleanup procedure was not found exactly once: $($entry.Key)"
    }
    $mockCode = [regex]::Replace($mockCode, $pattern, $entry.Value)
}
$mockNames = @(
    'RegQueryDWordValue',
    'RegQueryStringValue',
    'GetVersionNumbersString',
    'ExtractTemporaryFile',
    'GetSHA256OfFile',
    'ForceDirectories',
    'Exec'
)
foreach ($name in $mockNames) {
    $mockCode = [regex]::Replace($mockCode, '\b' + $name + '\b', 'Mock' + $name)
}
foreach ($name in @('PrepareToInstall', 'InitializeUninstall', 'NeedRestart')) {
    $mockCode = [regex]::Replace($mockCode, '\b' + $name + '\b', 'Policy' + $name)
}
if ($mockCode -match '\b(?:Exec|ShellExec|ExecAsOriginalUser|ForceDirectories|ExtractTemporaryFile|RegWrite\w+|RegDelete\w+)\s*\(') {
    throw 'The native fixture contains an unmocked system mutation.'
}
$globalsMatch = [regex]::Match($mockCode, '(?ms)\A\s*(?<globals>var\s+.*?)(?=^function\s|^procedure\s)')
if (-not $globalsMatch.Success) { throw 'The production runtime global declarations were not found.' }
$productionGlobals = $globalsMatch.Groups['globals'].Value
$mockCode = $mockCode.Substring($globalsMatch.Length)

$mockSupport = @'
  TestRegistry64, TestRegistry32, TestExecLaunches, TestBecomesReady: Boolean;
  TestHashValid, TestExtractFails, TestHashThrows, TestLogWritable: Boolean;
  TestRegistryVersion, TestFileVersion, TestMissingFile, TestActions: String;
  TestParameters, TestInvariantFailure: String;
  TestExitCode, TestExecCalls, TestExtractCalls: Integer;
  TestKillCalls, TestUnregisterCalls, TestFileReadMask: Integer;

procedure Require(Condition: Boolean; Message: String);
begin
  if not Condition then
  begin
    TestInvariantFailure := Message;
    RaiseException(Message);
  end;
end;

function MockRegQueryDWordValue(RootKey: Integer; const Key, Name: String;
  var Value: Cardinal): Boolean;
begin
  Require(Key = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\{#VcRuntimeArchitecture}',
    'Registry check used the wrong architecture or key');
  Require(Name = 'Installed', 'Unexpected registry DWORD');
  Require((RootKey = HKLM64) or (RootKey = HKLM32), 'Registry view was not explicit');
  Value := 0;
  Result := ((RootKey = HKLM64) and TestRegistry64) or
    ((RootKey = HKLM32) and TestRegistry32);
  if Result then Value := 1;
end;

function MockRegQueryStringValue(RootKey: Integer; const Key, Name: String;
  var Value: String): Boolean;
begin
  Require(Key = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\{#VcRuntimeArchitecture}',
    'Registry version check used the wrong architecture or key');
  Require(Name = 'Version', 'Unexpected registry string');
  Require((RootKey = HKLM64) or (RootKey = HKLM32), 'Registry view was not explicit');
  Result := ((RootKey = HKLM64) and TestRegistry64) or
    ((RootKey = HKLM32) and TestRegistry32);
  Value := TestRegistryVersion;
end;

function MockGetVersionNumbersString(const Filename: String; var Version: String): Boolean;
var
  Name: String;
begin
  Name := ExtractFileName(Filename);
  Require(Filename = ExpandConstant('{sysnative}\') + Name,
    'Runtime DLL check did not use the native system directory');
  Require((Name = 'vcruntime140.dll') or (Name = 'vcruntime140_1.dll') or
    (Name = 'msvcp140.dll'), 'Unexpected runtime DLL check');
  if Name = 'vcruntime140.dll' then TestFileReadMask := TestFileReadMask or 1;
  if Name = 'vcruntime140_1.dll' then TestFileReadMask := TestFileReadMask or 2;
  if Name = 'msvcp140.dll' then TestFileReadMask := TestFileReadMask or 4;
  Version := TestFileVersion;
  Result := Name <> TestMissingFile;
end;

procedure MockExtractTemporaryFile(const Filename: String);
begin
  Require(Filename = 'vc_redist.exe', 'Unexpected prerequisite extraction');
  TestExtractCalls := TestExtractCalls + 1;
  TestActions := TestActions + 'extract;';
  if TestExtractFails then RaiseException('Fixture extraction failure');
end;

function MockGetSHA256OfFile(const Filename: String): String;
begin
  Require(Filename = ExpandConstant('{tmp}\vc_redist.exe'), 'Unexpected hash input');
  TestActions := TestActions + 'hash;';
  if TestHashThrows then RaiseException('Fixture hash read failure');
  if TestHashValid then Result := '{#VcRuntimeInstallerSHA256}'
    else Result := '0000000000000000000000000000000000000000000000000000000000000000';
end;

function MockForceDirectories(const Directory: String): Boolean;
begin
  Require(Directory = ExpandConstant('{commonappdata}\Fengwo\InstallerLogs'),
    'Unexpected prerequisite log directory');
  TestActions := TestActions + 'mkdir;';
  Result := TestLogWritable;
end;

function MockExec(const Filename, Parameters, WorkingDir: String;
  const ShowCmd: Integer; const Wait: TExecWait; var ResultCode: Integer): Boolean;
begin
  Require(Filename = ExpandConstant('{tmp}\vc_redist.exe'), 'Unexpected process execution');
  Require(WorkingDir = '', 'Unexpected prerequisite working directory');
  Require(ShowCmd = SW_HIDE, 'Prerequisite execution was not hidden');
  Require(Wait = ewWaitUntilTerminated, 'Prerequisite execution did not wait for termination');
  Require(Pos('/quiet /norestart', Parameters) > 0, 'Prerequisite execution may prompt or reboot');
  Require(Pos(' /log "', Parameters) > 0, 'Prerequisite execution omitted its log');
  Require(TestKillCalls = 0, 'Old processes stopped before prerequisite execution');
  Require(TestUnregisterCalls = 0, 'Old helper removed before prerequisite execution');
  Require(TestActions = 'extract;hash;mkdir;', 'Prerequisite execution bypassed integrity checks');
  TestExecCalls := TestExecCalls + 1;
  TestParameters := Parameters;
  TestActions := TestActions + 'exec;';
  ResultCode := TestExitCode;
  Result := TestExecLaunches;
  if Result and TestBecomesReady then
  begin
    TestRegistry64 := True;
    TestRegistryVersion := 'v{#VcRuntimeMinimumVersion}';
    TestFileVersion := '{#VcRuntimeMinimumVersion}';
    TestMissingFile := '';
  end;
end;
'@

$testDriver = @'
procedure InitializeWizard;
var
  Name, Message, ExpectedOperation, ResultPath: String;
  ExpectedSuccess, NeedsRestart, ExpectedRestart, ExpectedImmediateRestart: Boolean;
  ExpectedExecCalls, ExpectedExtractCalls: Integer;
begin
  Name := ExpandConstant('{param:CASE|}');
  TestRegistryVersion := 'v{#VcRuntimeMinimumVersion}';
  TestFileVersion := '{#VcRuntimeMinimumVersion}';
  TestExecLaunches := True;
  TestBecomesReady := True;
  TestHashValid := True;
  TestLogWritable := True;
  ExpectedSuccess := True;
  ExpectedRestart := False;
  ExpectedImmediateRestart := False;
  ExpectedExecCalls := 1;
  ExpectedExtractCalls := 1;
  ExpectedOperation := '/install';
  if Name = 'healthy' then
  begin
    TestRegistry64 := True;
    ExpectedExecCalls := 0;
    ExpectedExtractCalls := 0;
    ExpectedOperation := '';
  end
  else if Name = 'registry32' then
  begin
    TestRegistry32 := True;
    ExpectedExecCalls := 0;
    ExpectedExtractCalls := 0;
    ExpectedOperation := '';
  end
  else if Name = 'absent' then
    TestRegistry64 := False
  else if Name = 'outdated' then
  begin
    TestRegistry64 := True;
    TestRegistryVersion := 'v14.9.40000.0';
    TestFileVersion := '14.9.40000.0';
  end
  else if Name = 'missing-dll' then
  begin
    TestRegistry64 := True;
    TestMissingFile := 'vcruntime140_1.dll';
    ExpectedOperation := '/repair';
  end
  else if Name = 'outdated-dll' then
  begin
    TestRegistry64 := True;
    TestFileVersion := '14.39.33810.0';
    ExpectedOperation := '/repair';
  end
  else if Name = 'invalid-hash' then
  begin
    TestHashValid := False;
    ExpectedSuccess := False;
    ExpectedExecCalls := 0;
    ExpectedOperation := '';
  end
  else if Name = 'extraction-failure' then
  begin
    TestExtractFails := True;
    ExpectedSuccess := False;
    ExpectedExecCalls := 0;
    ExpectedOperation := '';
  end
  else if Name = 'hash-read-failure' then
  begin
    TestHashThrows := True;
    ExpectedSuccess := False;
    ExpectedExecCalls := 0;
    ExpectedOperation := '';
  end
  else if Name = 'log-directory-failure' then
  begin
    TestLogWritable := False;
    ExpectedSuccess := False;
    ExpectedExecCalls := 0;
    ExpectedOperation := '';
  end
  else if Name = 'exec-failure' then
  begin
    TestExecLaunches := False;
    TestExitCode := 5;
    ExpectedSuccess := False;
  end
  else if Name = 'installer-error' then
  begin
    TestExitCode := 1603;
    ExpectedSuccess := False;
  end
  else if Name = 'postcheck-failure' then
  begin
    TestBecomesReady := False;
    ExpectedSuccess := False;
  end
  else if Name = 'already-installed' then
    TestExitCode := 1638
  else if Name = 'already-installed-invalid' then
  begin
    TestExitCode := 1638;
    TestBecomesReady := False;
    ExpectedSuccess := False;
  end
  else if Name = 'already-installed-hresult' then
    TestExitCode := -2147023258
  else if Name = 'already-installed-hresult-invalid' then
  begin
    TestExitCode := -2147023258;
    TestBecomesReady := False;
    ExpectedSuccess := False;
  end
  else if Name = 'restart-required' then
  begin
    TestExitCode := 3010;
    TestBecomesReady := False;
    ExpectedRestart := True;
  end
  else if Name = 'restart-initiated' then
  begin
    TestExitCode := 1641;
    TestBecomesReady := False;
    ExpectedSuccess := False;
    ExpectedRestart := True;
    ExpectedImmediateRestart := True;
  end
  else
    RaiseException('Unknown native fixture case: ' + Name);

  Require(VcRuntimeVersionSufficient('v14.40.33810.0'), 'Exact runtime version was rejected');
  Require(VcRuntimeVersionSufficient('14.40.33811.0'), 'Newer runtime version was rejected');
  Require(not VcRuntimeVersionSufficient('14.9.40000.0'), 'Versions were compared lexically');
  Require(not VcRuntimeVersionSufficient('invalid'), 'Malformed runtime version was accepted');
  NeedsRestart := False;
  Message := PolicyPrepareToInstall(NeedsRestart);
  Require(TestInvariantFailure = '', Name + ': ' + TestInvariantFailure);
  Require((Message = '') = ExpectedSuccess, Name + ': incorrect preparation result: ' + Message);
  Require(TestExecCalls = ExpectedExecCalls, Name + ': incorrect prerequisite execution count');
  Require(TestExtractCalls = ExpectedExtractCalls, Name + ': incorrect prerequisite extraction count');
  if ExpectedOperation <> '' then
    Require(Pos(ExpectedOperation + ' /quiet /norestart', TestParameters) = 1,
      Name + ': incorrect installation operation: ' + TestParameters);
  if ExpectedSuccess then
  begin
    Require(TestUnregisterCalls = 1, Name + ': old helper cleanup did not run exactly once');
    Require(TestKillCalls = 1, Name + ': old process cleanup did not run exactly once');
    Require(Pos('unregister;kill;', TestActions) > 0, Name + ': cleanup order changed');
  end
  else
  begin
    Require(TestUnregisterCalls = 0, Name + ': failed preparation removed the old helper');
    Require(TestKillCalls = 0, Name + ': failed preparation stopped the old app');
  end;
  Require(PolicyNeedRestart = ExpectedRestart, Name + ': incorrect completion restart state');
  Require(CanLaunchAfterRuntime = (not ExpectedRestart), Name + ': incorrect launch availability');
  Require(NeedsRestart = ExpectedImmediateRestart, Name + ': incorrect immediate restart state');
  if ExpectedSuccess and not ExpectedRestart then
    Require(TestFileReadMask = 7, Name + ': a required runtime DLL was not checked');
  if Name = 'restart-initiated' then
  begin
    NeedsRestart := False;
    Message := PolicyPrepareToInstall(NeedsRestart);
    Require(Message <> '', 'Retry bypassed the initiated-restart block');
    Require(NeedsRestart, 'Retry lost the initiated-restart requirement');
    Require(TestExecCalls = 1, 'Retry executed a prerequisite during an initiated restart');
    Require((TestKillCalls = 0) and (TestUnregisterCalls = 0),
      'Retry changed the old app during an initiated restart');
  end;
  if Name = 'restart-required' then
  begin
    Message := EnsureVcRuntime(NeedsRestart);
    Require(Message = '', 'Retry rejected the completed prerequisite requiring restart');
    Require(TestExecCalls = 1, 'Retry installed the prerequisite twice');
    Require(PolicyNeedRestart and not CanLaunchAfterRuntime, 'Retry lost the completion restart state');
  end;
  ResultPath := ExpandConstant('{param:RESULTFILE|}');
  Require(ResultPath <> '', 'Fixture result path was not supplied');
  Require(SaveStringToFile(ResultPath, Name + #13#10, False), 'Fixture result could not be saved');
end;
'@

$mockCode = $productionGlobals + "`n" + $mockSupport + "`n" + $mockCode + "`n" + $testDriver
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('fengwo-vc-policy-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$payloadPath = Join-Path $fixtureRoot 'inert-payload.bin'
[IO.File]::WriteAllText($payloadPath, 'This native fixture never executes its prerequisite payload.')
$completed = $false

function Write-InnoFixture([string]$Name, [string]$Architecture, [string]$Code) {
    $script = @"
#define VcRuntimeArchitecture "$Architecture"
#define VcRuntimeMinimumVersion "14.40.33810.0"
#define VcRuntimeInstallerSHA256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
[Setup]
AppId=FengwoRuntimePolicyFixture
AppName=Fengwo Runtime Policy Fixture
AppVersion=1.0
DefaultDirName=$fixtureRoot\app
CreateAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
Uninstallable=no
CreateUninstallRegKey=no
OutputDir=$fixtureRoot
OutputBaseFilename=$Name
[CustomMessages]
$customMessages
[Files]
Source: "$payloadPath"; DestName: "vc_redist.exe"; Flags: dontcopy
[Code]
$Code
"@
    $scriptPath = Join-Path $fixtureRoot "$Name.iss"
    [IO.File]::WriteAllText($scriptPath, $script, [Text.UTF8Encoding]::new($true))
    & $InnoCompiler /Q $scriptPath | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "Native Inno fixture compilation failed: $Name" }
    return (Join-Path $fixtureRoot "$Name.exe")
}

try {
    foreach ($architecture in @('x64', 'arm64')) {
        [void](Write-InnoFixture "production-api-$architecture" $architecture $productionCode)
    }
    $fixtureInstaller = Write-InnoFixture 'runtime-policy' 'x64' $mockCode
    $cases = @(
        'healthy', 'registry32', 'absent', 'outdated', 'missing-dll', 'outdated-dll',
        'invalid-hash', 'extraction-failure', 'hash-read-failure', 'log-directory-failure',
        'exec-failure', 'installer-error', 'postcheck-failure', 'already-installed',
        'already-installed-invalid', 'already-installed-hresult',
        'already-installed-hresult-invalid', 'restart-required', 'restart-initiated'
    )
    foreach ($case in $cases) {
        $resultPath = Join-Path $fixtureRoot "$case.result"
        $logPath = Join-Path $fixtureRoot "$case.log"
        $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/CASE=$case", "/RESULTFILE=`"$resultPath`"", "/LOG=`"$logPath`"")
        $process = Start-Process -FilePath $fixtureInstaller -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            if (Test-Path -LiteralPath $logPath -PathType Leaf) { Get-Content -LiteralPath $logPath -Tail 60 | Write-Host }
            throw "Native runtime policy case failed: $case (exit $($process.ExitCode))"
        }
        if ([IO.File]::ReadAllText($resultPath).Trim() -cne $case) {
            throw "Native runtime policy case produced the wrong result: $case"
        }
        Write-Host "Native runtime policy passed: $case"
    }
    $completed = $true
    Write-Host "Native runtime policy verified: $($cases.Count) scenarios and production x64/arm64 API compilation."
}
finally {
    if ($completed) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
    else {
        Write-Host "Native fixture sources and logs retained at $fixtureRoot"
    }
}
