var
  VcRuntimeRestartRequired: Boolean;
  VcRuntimeRestartInitiated: Boolean;

function VcRuntimeVersionSufficient(Version: String): Boolean;
var
  ActualVersion, MinimumVersion: Int64;
begin
  Result := False;
  if (Length(Version) > 0) and (Version[1] = 'v') then
    Delete(Version, 1, 1);
  if not StrToVersion(Version, ActualVersion) then Exit;
  if not StrToVersion('{#VcRuntimeMinimumVersion}', MinimumVersion) then Exit;
  Result := ComparePackedVersion(ActualVersion, MinimumVersion) >= 0;
end;

function VcRuntimeRegistryVersion(RootKey: Integer; var Version: String): Boolean;
var
  Installed: Cardinal;
  Key: String;
begin
  Key := 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\{#VcRuntimeArchitecture}';
  Result := RegQueryDWordValue(RootKey, Key, 'Installed', Installed) and
    (Installed = 1) and RegQueryStringValue(RootKey, Key, 'Version', Version);
end;

function VcRuntimeInstalledVersion(var Version: String): Boolean;
begin
  Result := VcRuntimeRegistryVersion(HKLM64, Version);
  if Result and VcRuntimeVersionSufficient(Version) then Exit;
  Result := VcRuntimeRegistryVersion(HKLM32, Version);
end;

function VcRuntimeFilesReady: Boolean;
var
  Names: TArrayOfString;
  I: Integer;
  Version: String;
begin
  Result := False;
  Names := ['vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll'];
  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    if not GetVersionNumbersString(ExpandConstant('{sysnative}\') + Names[I], Version) then Exit;
    if not VcRuntimeVersionSufficient(Version) then Exit;
  end;
  Result := True;
end;

function VcRuntimeReady: Boolean;
var
  Version: String;
begin
  Result := VcRuntimeInstalledVersion(Version) and
    VcRuntimeVersionSufficient(Version) and VcRuntimeFilesReady;
end;

function EnsureVcRuntime(var NeedsRestart: Boolean): String;
var
  InstallerPath, Parameters, InstalledVersion, LogPath: String;
  ResultCode: Integer;
begin
  Result := '';
  if VcRuntimeRestartInitiated then
  begin
    NeedsRestart := True;
    Result := CustomMessage('VcRuntimeRestart');
    Exit;
  end;
  if VcRuntimeRestartRequired or VcRuntimeReady then Exit;
  try
    ExtractTemporaryFile('vc_redist.exe');
    InstallerPath := ExpandConstant('{tmp}\vc_redist.exe');
    if CompareText(GetSHA256OfFile(InstallerPath), '{#VcRuntimeInstallerSHA256}') <> 0 then
    begin
      Result := CustomMessage('VcRuntimeInvalid');
      Exit;
    end;
    LogPath := ExpandConstant('{commonappdata}\Fengwo\InstallerLogs');
    if not ForceDirectories(LogPath) then
    begin
      Result := CustomMessage('VcRuntimeLogFailed');
      Exit;
    end;
    LogPath := LogPath + '\vc-runtime-' + GetDateTimeString('yyyymmdd-hhnnss', '-', ':') + '.log';
    Parameters := '/install /quiet /norestart';
    if VcRuntimeInstalledVersion(InstalledVersion) and
      VcRuntimeVersionSufficient(InstalledVersion) then
      Parameters := '/repair /quiet /norestart';
    Parameters := Parameters + ' /log "' + LogPath + '"';
    WizardForm.PreparingLabel.Caption := CustomMessage('VcRuntimeInstalling');
    Log('Preparing Microsoft Visual C++ runtime: ' + Parameters);
    if not Exec(InstallerPath, Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      Result := FmtMessage(CustomMessage('VcRuntimeFailed'), [IntToStr(ResultCode), LogPath]);
      Exit;
    end;
    Log('Microsoft Visual C++ runtime exit code: ' + IntToStr(ResultCode));
    if ResultCode = 3010 then
    begin
      VcRuntimeRestartRequired := True;
      Exit;
    end;
    if ResultCode = 1641 then
    begin
      VcRuntimeRestartRequired := True;
      VcRuntimeRestartInitiated := True;
      NeedsRestart := True;
      Result := CustomMessage('VcRuntimeRestart');
      Exit;
    end;
    if (ResultCode <> 0) and (ResultCode <> 1638) and
      (ResultCode <> -2147023258) then
    begin
      Result := FmtMessage(CustomMessage('VcRuntimeFailed'), [IntToStr(ResultCode), LogPath]);
      Exit;
    end;
    if not VcRuntimeReady then
      Result := FmtMessage(CustomMessage('VcRuntimeVerifyFailed'), [LogPath]);
  except
    Log('Microsoft Visual C++ runtime preparation failed: ' + GetExceptionMessage);
    Result := CustomMessage('VcRuntimeInvalid');
  end;
end;

function NeedRestart: Boolean;
begin
  Result := VcRuntimeRestartRequired;
end;

function CanLaunchAfterRuntime: Boolean;
begin
  Result := not VcRuntimeRestartRequired;
end;
