param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
)

$ErrorActionPreference = 'Stop'

$filename = if ($Architecture -eq 'arm64') { 'fengwo-windows-arm64-setup.exe' } else { 'fengwo-windows-amd64-setup.exe' }
$candidate = Join-Path $stage $filename
$baseline = Join-Path $env:RUNNER_TEMP 'published-111.exe'
$inputs = Get-Content .github/release/windows-full-sign-input.json -Raw | ConvertFrom-Json
$baselineUrl = if ($Architecture -eq 'x64') {
    'https://zryc.oss-cn-beijing.aliyuncs.com/releases/desktop-1.1.1/desktop-111-20261029-165155-221f75d8/fengwo-windows-amd64-setup.exe'
} else {
    'https://zryc.oss-cn-beijing.aliyuncs.com/releases/desktop-1.1.1/desktop-111-20261029-040924-60d125e4/' + $filename
}
Invoke-WebRequest -Uri $baselineUrl -OutFile $baseline
if ((Get-FileHash $baseline).Hash.ToLowerInvariant() -cne $inputs.($Architecture).published_sha256) { throw 'Published baseline hash changed' }
& ./tooling/windows/test_installed_upgrade.ps1 -InstallerPath $candidate -PreviousInstallerPath $baseline -ExpectedPreviousVersion '1.1.1' -OutputDirectory (Join-Path $stage 'upgrade')
$installed = Join-Path $env:RUNNER_TEMP 'fengwo-overwrite-test'
& ./tooling/windows/verify_embedded_wintun.ps1 -CorePath (Join-Path $installed 'FengWoCore.exe') -Architecture $Architecture -OutputDirectory $stage
& ./tooling/windows/verify_release_signatures.ps1 -Directory $installed -ManifestPath (Join-Path $stage 'signed-payload.json') -OutputPath (Join-Path $stage 'installed-signatures.json') -Installed
Add-Type -Path (Join-Path $PSScriptRoot 'shell_link_fixture.cs')
$shell = New-Object -ComObject WScript.Shell
$uninstallers = @(Get-ChildItem -LiteralPath $installed -File -Filter 'unins*.exe')
if ($uninstallers.Count -ne 1) { throw 'Expected one installed uninstaller' }
$registrationPaths = @(@(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\0B31AA8F-C520-4E03-ACF1-FBE8B4EBA461_is1',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\0B31AA8F-C520-4E03-ACF1-FBE8B4EBA461_is1'
) | Where-Object { Test-Path -LiteralPath $_ })
if (@($registrationPaths).Count -ne 1) { throw 'Expected one machine-wide uninstall registration' }
$registration = Get-ItemProperty -LiteralPath $registrationPaths[0]
$expectedUninstallCommand = '"' + $uninstallers[0].FullName + '" /LOG'
@{ path = $registrationPaths[0]; name = $registration.DisplayName; version = $registration.DisplayVersion; uninstall_string = $registration.UninstallString; expected_uninstall_string = $expectedUninstallCommand } | ConvertTo-Json | Set-Content (Join-Path $stage 'uninstall-registration.json') -Encoding utf8NoBOM
if (-not ([string]$registration.DisplayName).StartsWith('蜂窝加速器') -or $registration.DisplayVersion -cne '1.1.1' -or $registration.UninstallString -ine $expectedUninstallCommand) { throw 'Windows Settings uninstall registration is invalid' }

$programFolders = @([Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Programs')) | Sort-Object -Unique
$links = @($programFolders | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.lnk' -File })
$fileSystem = New-Object -ComObject Scripting.FileSystemObject
$expectedTargets = @($uninstallers[0].FullName, $fileSystem.GetFile($uninstallers[0].FullName).ShortPath)
$linkRows = @($links | ForEach-Object {
    $nativeTarget = ''
    $nativeError = ''
    try { $nativeTarget = [FengWoShellLinkFixture]::ReadTarget($_.FullName) } catch { $nativeError = $_.Exception.Message }
    @{ path = $_.FullName; target = $nativeTarget; wsh_target = $shell.CreateShortcut($_.FullName).TargetPath; native_error = $nativeError }
})
@{ program_folders = $programFolders; expected_targets = $expectedTargets; shortcuts = $linkRows } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stage 'shortcut-targets.json') -Encoding utf8NoBOM
$uninstallLinks = @($linkRows | Where-Object { [Environment]::ExpandEnvironmentVariables($_.target).Trim('"') -iin $expectedTargets })
$shortcutEvidence = Join-Path $stage 'shortcuts'
New-Item -ItemType Directory -Force $shortcutEvidence | Out-Null
$links | Where-Object { $_.Name -like '*蜂窝*' } | Copy-Item -Destination $shortcutEvidence
if ($uninstallLinks.Count -ne 1) { throw 'Signed uninstaller Start menu shortcut missing' }
& ./tooling/windows/test_signed_core_runtime.ps1 -BundleDirectory $installed -EvidenceDirectory (Join-Path $stage 'runtime') -Architecture $Architecture
$sentinel = Join-Path $env:APPDATA 'FengWo/蜂窝加速器/full-sign-uninstall-preserve.txt'
New-Item -ItemType Directory -Force (Split-Path $sentinel) | Out-Null
[IO.File]::WriteAllText($sentinel, 'preserve-user-data')
$preferences = Join-Path (Split-Path $sentinel) 'shared_preferences.json'
$database = Join-Path (Split-Path $sentinel) 'database.sqlite'
[IO.File]::WriteAllText($preferences, '{"flutter.full_sign_uninstall_test":"preserve"}')
python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('CREATE TABLE IF NOT EXISTS full_sign_uninstall_test (value TEXT)'); c.execute('INSERT INTO full_sign_uninstall_test VALUES (?)', ('preserve',)); c.commit(); c.close()" $database
if ($LASTEXITCODE -ne 0) { throw 'Uninstall database fixture creation failed' }
$dataHashes = @{}
foreach ($path in @($preferences, $database, $sentinel)) { $dataHashes[$path] = (Get-FileHash $path).Hash }
$uninstall = Start-Process -FilePath $uninstallers[0].FullName -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="' + (Join-Path $stage 'uninstall.log') + '"')) -Wait -PassThru
if ($uninstall.ExitCode -ne 0 -or (Test-Path (Join-Path $installed 'FengWo.exe'))) { throw 'Signed uninstaller did not remove the installed application' }
if ((Get-Content $sentinel -Raw) -cne 'preserve-user-data') { throw 'User data was removed by uninstall' }
foreach ($path in $dataHashes.Keys) { if ((Get-FileHash $path).Hash -cne $dataHashes[$path]) { throw 'User preferences or database changed during uninstall' } }
if (Test-Path -LiteralPath $registrationPaths[0]) { throw 'Windows Settings uninstall registration was not removed' }
if (Test-Path -LiteralPath $uninstallLinks[0].path) { throw 'Uninstall shortcut was not removed' }
& ./tooling/windows/test_helper_service_repair.ps1 -InstallerPath $candidate -OutputDirectory (Join-Path $stage 'helper-repair')
@{ passed = $true; installer_sha256 = (Get-FileHash $candidate).Hash.ToLowerInvariant(); shortcut_verified = $true; uninstall_registration_verified = $true; runtime_verified = $true; helper_repair_verified = $true; signed_uninstall_passed = $true; user_data_preserved = $true; preserved_data_hashes = $dataHashes; sac_enforcement_test_passed = $false; publication_allowed = $false } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stage 'repack-acceptance.json') -Encoding utf8NoBOM
