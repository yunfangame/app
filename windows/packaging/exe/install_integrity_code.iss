type
  TFwIntegrityAclSize = record
    AceCount, BytesInUse, BytesFree: Cardinal;
  end;

var
  FengWoInstalledIntegrityVerified: Boolean;
  FengWoIntegrityVerificationFailed: Boolean;

function FwIntegrityAttributes(Path: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function FwIntegritySecurity(Path: String; ObjectType, Information: Cardinal;
  var Owner, Group, Dacl, Sacl, Descriptor: THandle): Cardinal;
  external 'GetNamedSecurityInfoW@advapi32.dll stdcall';
function FwIntegrityAclSize(Acl: THandle; var Information: TFwIntegrityAclSize;
  InformationSize, InformationClass: Cardinal): Integer;
  external 'GetAclInformation@advapi32.dll stdcall';
function FwIntegritySecurityText(Descriptor: THandle; Revision, Information: Cardinal;
  var Text: THandle; var Length: Cardinal): Integer;
  external 'ConvertSecurityDescriptorToStringSecurityDescriptorW@advapi32.dll stdcall';
function FwIntegrityTextLength(Text: THandle): Integer;
  external 'lstrlenW@kernel32.dll stdcall';
function FwIntegrityCopyText(Destination: String; Source: THandle; Count: Integer): THandle;
  external 'lstrcpynW@kernel32.dll stdcall';
function FwIntegrityFree(Memory: THandle): THandle;
  external 'LocalFree@kernel32.dll stdcall';
function FwIntegrityTempFile(Directory, Prefix: String; Unique: Cardinal;
  Filename: String): Cardinal;
  external 'GetTempFileNameW@kernel32.dll stdcall';

function FwIntegrityFailure(Code, Path, Detail: String): String;
begin
  Log('FENGWO_INSTALL_INTEGRITY ' + Code + ' path=' + Path + ' detail=' + Detail +
    ' [INSTALL-INTEGRITY-' + Code + ']');
  Result := FmtMessage(CustomMessage('InstallIntegrity' + Code), [Path, Detail]) +
    Chr(13) + Chr(10) + '[INSTALL-INTEGRITY-' + Code + ']';
end;

function FwIntegrityReadLabel(Path: String; var LabelText: String): String;
var
  Owner, Group, Dacl, Sacl, Descriptor, Text: THandle;
  ErrorCode, TextSize: Cardinal;
  AclSize: TFwIntegrityAclSize;
  Length: Integer;
begin
  Result := '';
  LabelText := '';
  Descriptor := 0;
  ErrorCode := FwIntegritySecurity(Path, 1, $10, Owner, Group, Dacl, Sacl, Descriptor);
  if ErrorCode <> 0 then
  begin
    Result := FwIntegrityFailure('Access', Path, IntToStr(ErrorCode));
    Exit;
  end;
  try
    AclSize.AceCount := 0;
    if Sacl <> 0 then
    begin
      if FwIntegrityAclSize(Sacl, AclSize, 12, 2) = 0 then
      begin
        Result := FwIntegrityFailure('Access', Path, IntToStr(DLLGetLastError));
        Exit;
      end;
    end;
    Text := 0;
    if FwIntegritySecurityText(Descriptor, 1, $10, Text, TextSize) = 0 then
    begin
      Result := FwIntegrityFailure('Access', Path, IntToStr(DLLGetLastError));
      Exit;
    end;
    try
      if Text = 0 then
      begin
        Result := FwIntegrityFailure('Access', Path, 'missing security descriptor text');
        Exit;
      end;
      Length := FwIntegrityTextLength(Text);
      if (Length < 0) or (Length > 65535) then
      begin
        Result := FwIntegrityFailure('Access', Path, 'invalid label length');
        Exit;
      end;
      SetLength(LabelText, Length + 1);
      FwIntegrityCopyText(LabelText, Text, Length + 1);
      SetLength(LabelText, Length);
      if (AclSize.AceCount > 0) and (Pos('(ML;', Uppercase(LabelText)) = 0) then
        Result := FwIntegrityFailure('Access', Path, 'mandatory label conversion omitted its ACE');
    finally
      if Text <> 0 then FwIntegrityFree(Text);
    end;
  finally
    if Descriptor <> 0 then FwIntegrityFree(Descriptor);
  end;
end;

function FwIntegrityValidateLabel(Path, LabelText: String): String;
var
  Remaining, Ace, Sid: String;
  Start, Finish, Separator, Rid: Integer;
begin
  Result := '';
  Remaining := Uppercase(LabelText);
  Start := Pos('(ML;', Remaining);
  while Start > 0 do
  begin
    Remaining := Copy(Remaining, Start + 4, Length(Remaining));
    Finish := Pos(')', Remaining);
    if Finish = 0 then
    begin
      Result := FwIntegrityFailure('Access', Path, 'invalid mandatory label');
      Exit;
    end;
    Ace := Copy(Remaining, 1, Finish - 1);
    Sid := Ace;
    Separator := Pos(';', Sid);
    while Separator > 0 do
    begin
      Sid := Copy(Sid, Separator + 1, Length(Sid));
      Separator := Pos(';', Sid);
    end;
    Rid := -1;
    if Sid = 'UN' then Rid := 0
    else if Sid = 'LW' then Rid := 4096
    else if Sid = 'ME' then Rid := 8192
    else if Sid = 'MP' then Rid := 8448
    else if Sid = 'HI' then Rid := 12288
    else if Sid = 'SI' then Rid := 16384
    else if Pos('S-1-16-', Sid) = 1 then
      Rid := StrToIntDef(Copy(Sid, 8, Length(Sid)), -1);
    if Rid < 0 then
    begin
      Result := FwIntegrityFailure('Access', Path, 'unknown mandatory label: ' + Sid);
      Exit;
    end;
    if Rid < 8192 then
    begin
      Result := FwIntegrityFailure('Low', Path, Sid);
      Exit;
    end;
    Remaining := Copy(Remaining, Finish + 1, Length(Remaining));
    Start := Pos('(ML;', Remaining);
  end;
  Log('FENGWO_INSTALL_INTEGRITY accepted path=' + Path + ' label=' + LabelText);
end;

function FwIntegrityCheckLabel(Path: String): String;
var
  LabelText: String;
begin
  Result := FwIntegrityReadLabel(Path, LabelText);
  if Result = '' then Result := FwIntegrityValidateLabel(Path, LabelText);
end;

function FwIntegrityExistingParent(Path: String; var Existing: String): String;
var
  Cursor, Parent: String;
  Attributes, ErrorCode: Cardinal;
begin
  Result := '';
  Existing := '';
  Cursor := RemoveBackslashUnlessRoot(Path);
  while Cursor <> '' do
  begin
    Attributes := FwIntegrityAttributes(Cursor);
    if Attributes = $FFFFFFFF then
    begin
      ErrorCode := DLLGetLastError;
      if (ErrorCode <> 2) and (ErrorCode <> 3) then
      begin
        Result := FwIntegrityFailure('Access', Cursor, IntToStr(ErrorCode));
        Exit;
      end;
    end
    else
    begin
      if (Attributes and $400) <> 0 then
      begin
        Result := FwIntegrityFailure('Reparse', Cursor, 'reparse point');
        Exit;
      end;
      if (Attributes and $10) = 0 then
      begin
        Result := FwIntegrityFailure('Access', Cursor, 'not a directory');
        Exit;
      end;
      if Existing = '' then Existing := Cursor;
    end;
    Parent := RemoveBackslashUnlessRoot(ExtractFileDir(Cursor));
    if CompareText(Parent, Cursor) = 0 then Break;
    Cursor := Parent;
  end;
  if Existing = '' then
    Result := FwIntegrityFailure('Access', Path, 'parent directory not found');
end;

function FwIntegrityProbeDirectory(Path: String): String;
var
  Probe: String;
  Terminator: Integer;
begin
  Result := '';
  SetLength(Probe, 260);
  if FwIntegrityTempFile(Path, 'fwi', 0, Probe) = 0 then
  begin
    Result := FwIntegrityFailure('Access', Path, IntToStr(DLLGetLastError));
    Exit;
  end;
  Terminator := Pos(#0, Probe);
  if Terminator > 0 then SetLength(Probe, Terminator - 1);
  if not DeleteFile(Probe) then
    Result := FwIntegrityFailure('Access', Path, IntToStr(DLLGetLastError));
end;

function CheckFengWoInstallLocation(RequireExecutable, ProbeWrite: Boolean): String;
var
  Target, Existing, Executable: String;
  Attributes, ErrorCode: Cardinal;
begin
  Target := ExpandFileName(ExpandConstant('{app}'));
  if (Length(Target) <= 3) or (Copy(Target, 2, 2) <> ':\') or
    (Pos(':', Copy(Target, 3, Length(Target))) > 0) then
  begin
    Result := FwIntegrityFailure('Path', Target, 'local application directory required');
    Exit;
  end;
  Result := FwIntegrityExistingParent(Target, Existing);
  if Result <> '' then Exit;
  Result := FwIntegrityCheckLabel(Existing);
  if Result <> '' then Exit;
  Executable := AddBackslash(Target) + 'FengWo.exe';
  Attributes := FwIntegrityAttributes(Executable);
  if Attributes = $FFFFFFFF then
  begin
    ErrorCode := DLLGetLastError;
    if RequireExecutable or ((ErrorCode <> 2) and (ErrorCode <> 3)) then
    begin
      Result := FwIntegrityFailure('Access', Executable, IntToStr(ErrorCode));
      Exit;
    end;
  end
  else
  begin
    if (Attributes and $400) <> 0 then
      Result := FwIntegrityFailure('Reparse', Executable, 'reparse point')
    else if (Attributes and $10) <> 0 then
      Result := FwIntegrityFailure('Access', Executable, 'not a file')
    else
      Result := FwIntegrityCheckLabel(Executable);
    if Result <> '' then Exit;
  end;
  if ProbeWrite then Result := FwIntegrityProbeDirectory(Existing);
end;

function EnsureFengWoInstallLocation: String;
begin
  Result := CheckFengWoInstallLocation(False, True);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Error: String;
begin
  Result := True;
  if CurPageID <> wpSelectDir then Exit;
  Error := CheckFengWoInstallLocation(False, False);
  Result := Error = '';
  if not Result and not WizardSilent then MsgBox(Error, mbError, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Error: String;
begin
  if CurStep <> ssPostInstall then Exit;
  FengWoInstalledIntegrityVerified := False;
  FengWoIntegrityVerificationFailed := True;
  Error := CheckFengWoInstallLocation(True, False);
  if Error <> '' then RaiseException(Error);
  FengWoInstalledIntegrityVerified := True;
  FengWoIntegrityVerificationFailed := False;
end;

function CanLaunchInstalledFengWo: Boolean;
begin
  Result := FengWoInstalledIntegrityVerified and CanLaunchAfterRuntime;
  if Result then
  begin
    Result := CheckFengWoInstallLocation(True, False) = '';
    if not Result then
    begin
      FengWoInstalledIntegrityVerified := False;
      FengWoIntegrityVerificationFailed := True;
    end;
  end;
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := 0;
  if FengWoIntegrityVerificationFailed then
  begin
    Log('FENGWO_INSTALL_INTEGRITY final verification did not pass; exit code 74');
    Result := 74;
  end;
end;
