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
$shell = New-Object -ComObject WScript.Shell
$uninstallers = @(Get-ChildItem -LiteralPath $installed -File -Filter 'unins*.exe')
if ($uninstallers.Count -ne 1) { throw 'Expected one installed uninstaller' }
$programFolders = @([Environment]::GetFolderPath('CommonPrograms'), [Environment]::GetFolderPath('Programs')) | Sort-Object -Unique
$links = @($programFolders | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.lnk' -File })
$fileSystem = New-Object -ComObject Scripting.FileSystemObject
$expectedTargets = @($uninstallers[0].FullName, $fileSystem.GetFile($uninstallers[0].FullName).ShortPath)
$linkRows = @($links | ForEach-Object { @{ path = $_.FullName; target = $shell.CreateShortcut($_.FullName).TargetPath } })
@{ program_folders = $programFolders; expected_targets = $expectedTargets; shortcuts = $linkRows } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stage 'shortcut-targets.json') -Encoding utf8NoBOM
$uninstallLinks = @($linkRows | Where-Object { [Environment]::ExpandEnvironmentVariables($_.target).Trim('"') -iin $expectedTargets })
if ($uninstallLinks.Count -ne 1) { throw 'Signed uninstaller Start menu shortcut missing' }
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
if (Test-Path -LiteralPath $uninstallLinks[0].path) { throw 'Uninstall shortcut was not removed' }
@{ passed = $true; installer_sha256 = (Get-FileHash $candidate).Hash.ToLowerInvariant(); shortcut_verified = $true; signed_uninstall_passed = $true; user_data_preserved = $true; preserved_data_hashes = $dataHashes; sac_enforcement_test_passed = $false; publication_allowed = $false } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stage 'repack-acceptance.json') -Encoding utf8NoBOM
