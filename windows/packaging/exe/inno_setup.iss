#include "{{SOURCE_DIR}}\prerequisites\vc_runtime.iss"
#if VcRuntimeArchitecture != "{{ARCH}}"
  #error "Visual C++ runtime architecture does not match the application"
#endif

[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableDirPage=no
UsePreviousAppDir=yes
SetupLogging=yes
UninstallLogging=yes
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}

[Code]
#include "{{SOURCE_DIR}}\prerequisites\vc_runtime_code.iss"

function HasFengWoPreviousInstallation: Boolean;
var
  Roots: TArrayOfInteger;
  I: Integer;
  Path, Key: String;
begin
  Result := False;
  Roots := [HKLM64, HKCU64, HKLM32, HKCU32];
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\0B31AA8F-C520-4E03-ACF1-FBE8B4EBA461_is1';
  for I := 0 to GetArrayLength(Roots) - 1 do
  begin
    if RegQueryStringValue(Roots[I], Key, 'Inno Setup: App Path', Path) and
      (Path <> '') then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure InitializeWizard;
var
  ScriptPath, PowerShellPath, OutputPath, Parameters, Path: String;
  Output: AnsiString;
  ResultCode: Integer;
begin
  if (ExpandConstant('{param:DIR|}') <> '') or
    (ExpandConstant('{param:LOADINF|}') <> '') or HasFengWoPreviousInstallation then Exit;
  ExtractTemporaryFile('fengwo_install_cleanup.ps1');
  ScriptPath := ExpandConstant('{tmp}\fengwo_install_cleanup.ps1');
  OutputPath := ExpandConstant('{tmp}\fengwo-legacy-install-path.txt');
  PowerShellPath := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    AddQuotes(ScriptPath) + ' -Operation discover -DiscoveryOutputPath ' + AddQuotes(OutputPath);
  if not Exec(PowerShellPath, Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Log('FengWo legacy installation discovery could not start: ' + IntToStr(ResultCode));
    Exit;
  end;
  if ResultCode <> 0 then
  begin
    Log('FengWo legacy installation discovery failed: ' + IntToStr(ResultCode));
    Exit;
  end;
  if LoadStringFromFile(OutputPath, Output) then
  begin
    Path := Utf8Decode(Output);
    if Path <> '' then WizardForm.DirEdit.Text := Path;
  end;
end;

function RunFengWoInstallCleanup(Operation: String): String;
var
  ScriptPath, PowerShellPath, Parameters: String;
  ResultCode: Integer;
  CleanupStarted: Boolean;
begin
  Result := '';
  if IsUninstaller then
    ScriptPath := ExpandConstant('{app}\fengwo_install_cleanup.ps1')
  else
  begin
    ExtractTemporaryFile('fengwo_install_cleanup.ps1');
    ScriptPath := ExpandConstant('{tmp}\fengwo_install_cleanup.ps1');
  end;
  if not FileExists(ScriptPath) then
  begin
    Result := CustomMessage('InstallOwnershipCleanupMissing');
    Exit;
  end;
  PowerShellPath := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    AddQuotes(ScriptPath) + ' -InstallDirectory ' + AddQuotes(ExpandConstant('{app}')) +
    ' -Operation ' + Operation;
  if not IsUninstaller then
    Parameters := Parameters + ' -OwnershipEvidencePath ' +
      AddQuotes(ExpandConstant('{tmp}\fengwo-install-ownership.json'));
  try
    CleanupStarted := ExecAndLogOutput(PowerShellPath, Parameters, '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode, nil);
  except
    Log('FengWo installation cleanup output capture failed: ' + Operation + ': ' + GetExceptionMessage);
    Result := FmtMessage(CustomMessage('InstallCleanupFailed'),
      [Operation, 'output_capture_failed', ExpandConstant('{log}')]);
    Exit;
  end;
  if not CleanupStarted then
  begin
    Log('FengWo installation cleanup could not start: ' + Operation + ' (' +
      IntToStr(ResultCode) + '): ' + SysErrorMessage(ResultCode));
    Result := FmtMessage(CustomMessage('InstallCleanupFailed'),
      [Operation, IntToStr(ResultCode), ExpandConstant('{log}')]);
    Exit;
  end;
  if ResultCode <> 0 then
  begin
    Log('FengWo path-scoped installation cleanup failed: ' + Operation + ' (' + IntToStr(ResultCode) + ')');
    if ResultCode = 41 then
      Result := FmtMessage(CustomMessage('InstallDirectoryConflict'),
        [ExpandConstant('{app}'), ExpandConstant('{autopf64}\FengWo')])
    else
      Result := FmtMessage(CustomMessage('InstallCleanupFailed'),
        [Operation, IntToStr(ResultCode), ExpandConstant('{log}')]);
  end;
end;

function FinalizeFengWoInstall: String;
begin
  Result := RunFengWoInstallCleanup('finalize');
end;

#include "{{SOURCE_DIR}}\prerequisites\install_integrity_code.iss"

function StopHelperService: String;
begin
  Result := RunFengWoInstallCleanup('stop');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := EnsureFengWoInstallLocation;
  if Result <> '' then Exit;
  Result := EnsureVcRuntime(NeedsRestart);
  if Result <> '' then Exit;
  Result := StopHelperService;
end;

function InitializeUninstall(): Boolean;
var
  Error: String;
begin
  Error := RunFengWoInstallCleanup('uninstall');
  Result := Error = '';
  if not Result then
  begin
    Log(Error);
    if not UninstallSilent then MsgBox(Error, mbError, MB_OK);
  end;
end;

procedure RemoveOwnedAutoLaunch(RootKey: Integer; Name: String);
var
  Command, Expected: String;
begin
  if not RegQueryStringValue(RootKey,
    'Software\Microsoft\Windows\CurrentVersion\Run', Name, Command) then Exit;
  Expected := ExpandConstant('{app}\FengWo.exe');
  if CompareText(RemoveQuotes(Trim(Command)), Expected) <> 0 then Exit;
  if RegDeleteValue(RootKey, 'Software\Microsoft\Windows\CurrentVersion\Run', Name) then
  begin
    RegDeleteValue(RootKey,
      'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', Name);
    RegDeleteValue(RootKey,
      'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32', Name);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  RemoveOwnedAutoLaunch(HKCU64, 'FengWo');
  RemoveOwnedAutoLaunch(HKCU64, 'FlClash');
  RemoveOwnedAutoLaunch(HKCU32, 'FengWo');
  RemoveOwnedAutoLaunch(HKCU32, 'FlClash');
end;

[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[CustomMessages]
InstallOwnershipCleanupMissing=The FengWo installation cleanup component is missing. Download the complete installer again.
InstallIntegrityLow=This installation location has a Low integrity security label and would prevent FengWo from saving settings. Go Back and choose a normal local application folder, such as Program Files. Existing user data is preserved.%nLocation: %1
InstallIntegrityReparse=This installation location uses a symbolic link or redirected folder. Go Back and choose a normal local application folder. Existing user data is preserved.%nLocation: %1
InstallIntegrityAccess=The installation location cannot be safely checked or written. Go Back and choose another local application folder, or check its permissions and free disk space. Existing user data is preserved.%nLocation: %1%nDetails: %2
InstallIntegrityPath=Choose a dedicated folder on a local drive rather than a drive root or a network path.%nLocation: %1
InstallDirectoryConflict=The FengWo identity of the application in this folder cannot be verified. Go Back and choose a separate folder, such as %2. The existing application will be preserved.%nLocation: %1
InstallCleanupFailed=Installation cleanup failed during %1 (code %2). Send the installation log to support to identify the cause.%nLog: %3
VcRuntimeInstalling=Installing Microsoft Visual C++ runtime. Please wait...
VcRuntimeInvalid=The bundled Visual C++ runtime is missing or damaged. Download the complete installer again.
VcRuntimeLogFailed=Unable to create the runtime installation log directory. Check administrator permissions and disk space.
VcRuntimeFailed=Visual C++ runtime installation failed (code %1). Installation cannot continue. Log: %2
VcRuntimeVerifyFailed=Visual C++ runtime verification failed. Repair the installed Microsoft Visual C++ runtime and run this installer again. Log: %1
VcRuntimeRestart=Windows must restart to finish installing the Visual C++ runtime. Restart and run this installer again.
{% for locale in LOCALES %}
{% if locale.lang == 'zh' %}
chineseSimplified.InstallOwnershipCleanupMissing=蜂窝安装清理组件缺失，请重新下载完整安装包。
chineseSimplified.InstallIntegrityLow=此安装位置带有 Low（低完整性）安全标签，会导致蜂窝无法保存配置。请返回上一步，更换为 Program Files 等正常的本地安装目录。原有用户数据会保留。%n位置：%1
chineseSimplified.InstallIntegrityReparse=此安装位置包含符号链接或重定向目录。请返回上一步，选择普通的本地安装目录。原有用户数据会保留。%n位置：%1
chineseSimplified.InstallIntegrityAccess=无法安全检查或写入此安装位置。请返回上一步，更换本地安装目录，或检查该目录权限及磁盘空间。原有用户数据会保留。%n位置：%1%n详情：%2
chineseSimplified.InstallIntegrityPath=请选择本地磁盘内独立的程序文件夹，不要选择磁盘根目录或网络路径。%n位置：%1
chineseSimplified.InstallDirectoryConflict=此目录中的应用无法确认属于蜂窝，不能安全覆盖。请返回上一步，选择独立的蜂窝目录，例如 %2。现有程序会保留。%n位置：%1
chineseSimplified.InstallCleanupFailed=安装清理失败，操作：%1，错误码：%2。请将安装日志发给客服确认具体原因。%n日志：%3
chineseSimplified.VcRuntimeInstalling=正在安装 Microsoft Visual C++ 运行库，请稍候……
chineseSimplified.VcRuntimeInvalid=安装包中的 Visual C++ 运行库缺失或损坏，请重新下载完整安装包。
chineseSimplified.VcRuntimeLogFailed=无法创建运行库安装日志目录，请检查管理员权限和磁盘空间。
chineseSimplified.VcRuntimeFailed=Visual C++ 运行库安装失败（错误码 %1），无法继续安装。日志：%2
chineseSimplified.VcRuntimeVerifyFailed=Visual C++ 运行库安装后验证失败，请修复系统中已安装的 Microsoft Visual C++ 运行库后重试。日志：%1
chineseSimplified.VcRuntimeRestart=需要重启 Windows 才能完成运行库安装，请重启后再次运行安装包。
{% endif %}
{% endfor %}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}
[Files]
Source: "{{SOURCE_DIR}}\prerequisites\fengwo_install_cleanup.ps1"; Flags: dontcopy
Source: "{{SOURCE_DIR}}\prerequisites\vc_redist.exe"; Flags: dontcopy
Source: "{{SOURCE_DIR}}\prerequisites\fengwo_install_cleanup.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Excludes: "prerequisites\*"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Check: CanLaunchInstalledFengWo; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
