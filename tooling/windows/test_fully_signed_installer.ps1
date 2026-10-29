param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
)

$ErrorActionPreference = 'Stop'

$filename = if ($Architecture -eq 'arm64') { 'fengwo-windows-arm64-setup.exe' } else { 'fengwo-windows-amd64-setup.exe' }
$candidate = Join-Path $stage $filename
$baseline = Join-Path $env:RUNNER_TEMP 'published-111.exe'
$inputs = Get-Content .github/release/windows-full-sign-input.json -Raw | ConvertFrom-Json
Invoke-WebRequest -Uri ('https://zryc.oss-cn-beijing.aliyuncs.com/releases/desktop-1.1.1/desktop-111-20261029-040924-60d125e4/' + $filename) -OutFile $baseline
if ((Get-FileHash $baseline).Hash.ToLowerInvariant() -cne $inputs.($Architecture).published_sha256) { throw 'Published baseline hash changed' }
& ./tooling/windows/test_installed_upgrade.ps1 -InstallerPath $candidate -PreviousInstallerPath $baseline -ExpectedPreviousVersion '1.1.1' -OutputDirectory (Join-Path $stage 'upgrade')
$installed = Join-Path $env:RUNNER_TEMP 'fengwo-overwrite-test'
& ./tooling/windows/verify_embedded_wintun.ps1 -CorePath (Join-Path $installed 'FengWoCore.exe') -Architecture $Architecture -OutputDirectory $stage
& ./tooling/windows/verify_release_signatures.ps1 -Directory $installed -ManifestPath (Join-Path $stage 'signed-payload.json') -OutputPath (Join-Path $stage 'installed-signatures.json') -Installed
$links = @(Get-ChildItem ([Environment]::GetFolderPath('CommonPrograms')) -Recurse -Filter '*.lnk' | Where-Object { $_.Name -like '*蜂窝*' })
$shell = New-Object -ComObject WScript.Shell
$uninstallLinks = @($links | Where-Object { $shell.CreateShortcut($_.FullName).TargetPath -ieq (Join-Path $installed 'unins000.exe') })
if ($uninstallLinks.Count -ne 1) { throw 'Signed uninstaller Start menu shortcut missing' }
$sentinel = Join-Path $env:APPDATA 'FengWo/蜂窝加速器/full-sign-uninstall-preserve.txt'
New-Item -ItemType Directory -Force (Split-Path $sentinel) | Out-Null
[IO.File]::WriteAllText($sentinel, 'preserve-user-data')
$uninstall = Start-Process -FilePath (Join-Path $installed 'unins000.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="' + (Join-Path $stage 'uninstall.log') + '"')) -Wait -PassThru
if ($uninstall.ExitCode -ne 0 -or (Test-Path (Join-Path $installed 'FengWo.exe'))) { throw 'Signed uninstaller did not remove the installed application' }
if ((Get-Content $sentinel -Raw) -cne 'preserve-user-data') { throw 'User data was removed by uninstall' }
@{ passed = $true; installer_sha256 = (Get-FileHash $candidate).Hash.ToLowerInvariant(); shortcut_verified = $true; signed_uninstall_passed = $true; user_data_preserved = $true; sac_enforcement_test_passed = $false; publication_allowed = $false } | ConvertTo-Json | Set-Content (Join-Path $stage 'repack-acceptance.json') -Encoding utf8NoBOM
