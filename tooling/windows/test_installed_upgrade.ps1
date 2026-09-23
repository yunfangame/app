param(
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [string]$PreviousInstallerPath,
  [string]$ExpectedPreviousVersion
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
  throw 'This test may only run in an isolated GitHub Actions Windows runner'
}
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
if ([bool]$PreviousInstallerPath -ne [bool]$ExpectedPreviousVersion) {
  throw 'PreviousInstallerPath and ExpectedPreviousVersion must be supplied together'
}
if ($PreviousInstallerPath) {
  $PreviousInstallerPath = (Resolve-Path -LiteralPath $PreviousInstallerPath).Path
}
$repositoryDirectory = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$versionLine = @(Select-String -LiteralPath (Join-Path $repositoryDirectory 'pubspec.yaml') -Pattern '^version:\s*(\S+)\s*$')
if ($versionLine.Count -ne 1) { throw 'Expected exactly one release version in pubspec.yaml' }
$expectedVersion = $versionLine[0].Matches[0].Groups[1].Value
$appIdLine = @(Select-String -LiteralPath (Join-Path $repositoryDirectory 'windows/packaging/exe/make_config.yaml') -Pattern '^app_id:\s*([A-Fa-f0-9-]+)\s*$')
if ($appIdLine.Count -ne 1) { throw 'Expected exactly one installer AppId' }
$expectedAppId = $appIdLine[0].Matches[0].Groups[1].Value
if ($PreviousInstallerPath -and [version]$ExpectedPreviousVersion -ge [version]$expectedVersion) {
  throw 'The baseline version must be older than the version being packaged'
}
$installDirectory = Join-Path $env:RUNNER_TEMP 'fengwo-overwrite-test'
$savedDirectory = Join-Path $env:RUNNER_TEMP ('fengwo-profile-before-upgrade-' + [Guid]::NewGuid())
$results = [System.Collections.Generic.List[object]]::new()
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Install-TestPackage([string]$PackagePath = $InstallerPath, [string]$Stage = 'overwrite') {
  $installerLog = Join-Path $OutputDirectory "$Stage-installer.log"
  $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installDirectory`"", '/TASKS=', "/LOG=`"$installerLog`"")
  $install = Start-Process -FilePath $PackagePath -ArgumentList $arguments -PassThru -Wait
  if ($install.ExitCode -ne 0) { throw "Installer exited with $($install.ExitCode)" }
}

function Read-InstalledIdentity([string]$ExpectedVersion) {
  $application = Get-Item -LiteralPath (Join-Path $installDirectory 'FengWo.exe')
  if ($application.VersionInfo.CompanyName -cne 'com.follow' -or $application.VersionInfo.ProductName -cne '蜂窝加速器') {
    throw 'Unexpected application identity; refusing to modify the test profile'
  }
  if ($application.VersionInfo.ProductVersion -cne $ExpectedVersion -or $application.VersionInfo.FileVersion -cne $ExpectedVersion) {
    throw "Installed version does not match $ExpectedVersion"
  }
  $registrations = @()
  foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($key in @(Get-ChildItem -LiteralPath $root)) {
      $entry = Get-ItemProperty -LiteralPath $key.PSPath
      $location = [string]$entry.InstallLocation
      if (-not $location) { $location = [string]$entry.'Inno Setup: App Path' }
      if ($location -and $location.TrimEnd('\', '/') -ieq $installDirectory.TrimEnd('\', '/')) {
        $registrations += $entry
      }
    }
  }
  if ($registrations.Count -ne 1) { throw "Expected one registration for the test installation, found $($registrations.Count)" }
  $registration = $registrations[0]
  $appId = $registration.PSChildName -replace '_is1$', ''
  if ($appId.Trim('{', '}') -ine $expectedAppId -or $registration.DisplayVersion -cne $ExpectedVersion) {
    throw 'Installed AppId or registered version does not match the package identity'
  }
  return [ordered]@{
    version = $application.VersionInfo.ProductVersion
    file_version = $application.VersionInfo.FileVersion
    company = $application.VersionInfo.CompanyName
    product = $application.VersionInfo.ProductName
    app_id = $appId
    registration = $registration.PSPath
    install_directory = $installDirectory
    executable_sha256 = (Get-FileHash -LiteralPath $application.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

function Stop-TestApplication {
  $processes = @(Get-Process FengWo, FlClashCore -ErrorAction SilentlyContinue)
  foreach ($process in $processes) {
    $process | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not $process.WaitForExit(5000)) { throw 'Test application did not exit' }
  }
}

function Write-TestPreferences([string]$Content, [string]$Backup = '') {
  Stop-TestApplication
  if (Test-Path -LiteralPath $profileDirectory) {
    Remove-Item -LiteralPath $profileDirectory -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
  [System.IO.File]::WriteAllText($preferencesPath, $Content, [System.Text.UTF8Encoding]::new($false))
  if ($Backup) {
    [System.IO.File]::WriteAllText("$preferencesPath.bak", $Backup, [System.Text.UTF8Encoding]::new($false))
  }
}

function Read-StartupEvents {
  if (-not (Test-Path -LiteralPath $eventsPath)) { return @() }
  return @(Get-Content -LiteralPath $eventsPath | ForEach-Object {
    try { $_ | ConvertFrom-Json } catch {}
  })
}

function Assert-Startup([string]$Case, [bool]$ExpectFailure = $false, [string]$DiagnosticCode = '', [bool]$RequireSupplementalRoots = $true, [bool]$RequireCurrentWindowTitle = $true) {
  if (Test-Path -LiteralPath $eventsPath) { Remove-Item -LiteralPath $eventsPath -Force }
  $process = Start-Process -FilePath $applicationPath -PassThru
  try {
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
      $events = @(Read-StartupEvents)
      $ready = @($events | Where-Object { $_.event -eq 'startup.ready' })
      $failed = @($events | Where-Object { $_.event -eq 'startup.failed' })
      if ($ready.Count -gt 0 -or $failed.Count -gt 0) { break }
      if ($process.HasExited) { throw "$Case exited before startup completed: $($process.ExitCode)" }
      Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($ExpectFailure) {
      if ($failed.Count -eq 0 -or $ready.Count -gt 0) { throw "$Case did not preserve the startup failure" }
      $diagnostic = @($events | Where-Object {
        $_.event -eq 'preferences.failed' -and $_.fields.diagnostic_code -eq $DiagnosticCode
      })
      if ($diagnostic.Count -eq 0) { throw "$Case did not record $DiagnosticCode" }
    } else {
      if ($ready.Count -eq 0 -or $failed.Count -gt 0) { throw "$Case did not reach the application first frame" }
      if ($RequireSupplementalRoots) {
        $roots = @($events | Where-Object {
          $_.event -eq 'tls.trust.initialized' -and $_.fields.supplemental_roots -eq 2
        })
        if ($roots.Count -eq 0) { throw "$Case did not load both TLS roots" }
      }
      if ($RequireCurrentWindowTitle) {
        [void](Assert-FengWoWindowTitle -ProcessId $process.Id)
      } else {
        $window = [IntPtr]::Zero
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
          $window = [FengWoTitleTest]::FindMainWindow($process.Id)
          if ($window -ne [IntPtr]::Zero) { break }
          Start-Sleep -Milliseconds 250
        }
        if ($window -eq [IntPtr]::Zero) { throw "$Case did not display its application window" }
      }
    }
  } finally {
    Stop-TestApplication
    if (Test-Path -LiteralPath $eventsPath) {
      Copy-Item -LiteralPath $eventsPath -Destination (Join-Path $OutputDirectory "$Case.jsonl") -Force
    }
  }
}

function Assert-PreservedPreferences {
  $saved = Get-Content -LiteralPath $preferencesPath -Raw | ConvertFrom-Json
  if ($saved.'flutter.upgrade_test_sentinel' -cne $sentinel) { throw 'Upgrade discarded the saved preference sentinel' }
  $config = $saved.'flutter.config' | ConvertFrom-Json
  if (@($config.excludeSSIDs) -notcontains 'FengWo CI WiFi') { throw 'Upgrade discarded the saved application setting' }
}

function Assert-Archived([string]$Damaged) {
  $archives = @(Get-ChildItem -LiteralPath $profileDirectory -Filter '*.recovery-*' -File)
  $matched = @($archives | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -ceq $Damaged })
  if ($matched.Count -eq 0) { throw 'Damaged preferences were not preserved before recovery' }
}

Stop-TestApplication
if ($PreviousInstallerPath) {
  Install-TestPackage -PackagePath $PreviousInstallerPath -Stage 'baseline-previous'
  $initialIdentity = Read-InstalledIdentity -ExpectedVersion $ExpectedPreviousVersion
} else {
  Install-TestPackage -Stage 'initial'
  $initialIdentity = Read-InstalledIdentity -ExpectedVersion $expectedVersion
}
$applicationPath = Join-Path $installDirectory 'FengWo.exe'
$profileDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) (Join-Path $initialIdentity.company $initialIdentity.product)
$preferencesPath = Join-Path $profileDirectory 'shared_preferences.json'
$eventsPath = Join-Path $profileDirectory 'diagnostics/events.jsonl'
. (Join-Path $PSScriptRoot '../verify_windows_title.ps1')
if (Test-Path -LiteralPath $profileDirectory) {
  Move-Item -LiteralPath $profileDirectory -Destination $savedDirectory
}
$sentinel = [Guid]::NewGuid().ToString()
$valid = @{
  'flutter.version' = 1
  'flutter.upgrade_test_sentinel' = $sentinel
  'flutter.xboard.email' = 'upgrade-test@example.invalid'
  'flutter.xboard.auto_login' = $false
  'flutter.config' = (@{
    appSettingProps = @{ locale = 'en'; autoRun = $false }
    excludeSSIDs = @('FengWo CI WiFi')
  } | ConvertTo-Json -Depth 10 -Compress)
} | ConvertTo-Json -Depth 10 -Compress
$damaged = '{"flutter.config":'
$lock = $null
$baselineEvidence = $null
try {
  if ($PreviousInstallerPath) {
    $baselineCase = "baseline-$ExpectedPreviousVersion-to-$expectedVersion"
    $baselineResult = @{ case = $baselineCase; passed = $false }
    $results.Add($baselineResult)
    $baselineEvidence = [ordered]@{
      case = $baselineCase
      passed = $false
      stage = 'previous-startup'
      previous_installer_sha256 = (Get-FileHash -LiteralPath $PreviousInstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
      installer_sha256 = (Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash.ToLowerInvariant()
      previous_identity = $initialIdentity
    }
    Write-TestPreferences -Content $valid
    Assert-Startup -Case "$baselineCase-previous-startup" -RequireSupplementalRoots $false -RequireCurrentWindowTitle $false
    Assert-PreservedPreferences
    $databasePath = Join-Path $profileDirectory 'database.sqlite'
    if (-not (Test-Path -LiteralPath $databasePath) -or (Get-Item -LiteralPath $databasePath).Length -eq 0) {
      throw 'The baseline application did not generate its real database'
    }
    $profileFiles = @('shared_preferences.json', 'database.sqlite', 'database.sqlite-wal', 'database.sqlite-shm')
    $beforeFiles = [ordered]@{}
    foreach ($name in $profileFiles) {
      $path = Join-Path $profileDirectory $name
      if (Test-Path -LiteralPath $path) {
        $beforeFiles[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
      }
    }
    $baselineEvidence['before_install_files'] = $beforeFiles
    Copy-Item -LiteralPath $preferencesPath -Destination (Join-Path $OutputDirectory "$baselineCase-previous-preferences.json") -Force
    $baselineEvidence['stage'] = 'overwrite-install'
    Install-TestPackage -Stage "$baselineCase-upgrade"
    $currentIdentity = Read-InstalledIdentity -ExpectedVersion $expectedVersion
    foreach ($field in @('app_id', 'registration', 'install_directory', 'company', 'product')) {
      if ($currentIdentity[$field] -cne $initialIdentity[$field]) { throw "Upgrade changed installation identity field: $field" }
    }
    $baselineEvidence['current_identity'] = $currentIdentity
    foreach ($name in $beforeFiles.Keys) {
      $path = Join-Path $profileDirectory $name
      if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $beforeFiles[$name]) {
        throw "Overwrite installer changed the existing profile file: $name"
      }
    }
    Assert-PreservedPreferences
    $baselineEvidence['installer_preserved_profile_files'] = $true
    $baselineEvidence['stage'] = 'upgraded-startup'
    Assert-Startup -Case "$baselineCase-upgraded-startup"
    Assert-PreservedPreferences
    if (-not (Test-Path -LiteralPath $databasePath) -or (Get-Item -LiteralPath $databasePath).Length -eq 0) {
      throw 'The upgraded application did not retain the baseline database'
    }
    Copy-Item -LiteralPath $preferencesPath -Destination (Join-Path $OutputDirectory "$baselineCase-upgraded-preferences.json") -Force
    $baselineEvidence['upgraded_database_sha256'] = (Get-FileHash -LiteralPath $databasePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $baselineEvidence['preferences_preserved_after_startup'] = $true
    $baselineEvidence['stage'] = 'complete'
    $baselineEvidence['passed'] = $true
    $baselineResult.passed = $true
  }

  Write-TestPreferences -Content $valid
  Install-TestPackage
  Assert-PreservedPreferences
  Assert-Startup -Case 'overwrite-valid-preferences'
  Assert-PreservedPreferences
  $results.Add(@{ case = 'overwrite-valid-preferences'; passed = $true })

  Write-TestPreferences -Content $valid
  $lock = [System.IO.File]::Open($preferencesPath, 'Open', 'ReadWrite', 'None')
  try {
    Assert-Startup -Case 'locked-preferences' -ExpectFailure $true -DiagnosticCode 'PREF-LOCKED'
  } finally {
    $lock.Dispose()
    $lock = $null
  }
  Assert-PreservedPreferences
  Assert-Startup -Case 'unlocked-preferences-retry'
  Assert-PreservedPreferences
  $results.Add(@{ case = 'locked-preferences-and-retry'; passed = $true })

  Write-TestPreferences -Content $damaged -Backup $valid
  (Get-Item -LiteralPath $preferencesPath).IsReadOnly = $true
  try {
    Assert-Startup -Case 'read-only-preferences' -ExpectFailure $true -DiagnosticCode 'PREF-ACCESS'
    if ((Get-Content -LiteralPath $preferencesPath -Raw) -cne $damaged) { throw 'Read-only failure modified the original data' }
    if ((Get-Content -LiteralPath "$preferencesPath.bak" -Raw) -cne $valid) { throw 'Read-only failure modified the backup' }
  } finally {
    (Get-Item -LiteralPath $preferencesPath).IsReadOnly = $false
  }
  $results.Add(@{ case = 'read-only-preferences'; passed = $true })

  Assert-Startup -Case 'corrupt-preferences-valid-backup'
  Assert-PreservedPreferences
  Assert-Archived -Damaged $damaged
  $results.Add(@{ case = 'corrupt-preferences-valid-backup'; passed = $true })

  Write-TestPreferences -Content $damaged
  Assert-Startup -Case 'corrupt-preferences-fresh-recovery'
  Assert-Archived -Damaged $damaged
  $fresh = Get-Content -LiteralPath $preferencesPath -Raw | ConvertFrom-Json
  if ($fresh.'flutter.upgrade_test_sentinel') { throw 'Fresh recovery unexpectedly reused a stale backup' }
  $results.Add(@{ case = 'corrupt-preferences-fresh-recovery'; passed = $true })

  $innerDamaged = @{ 'flutter.version' = 1; 'flutter.config' = '{"currentProfileId":"broken"}' } | ConvertTo-Json -Compress
  Write-TestPreferences -Content $innerDamaged -Backup $valid
  Assert-Startup -Case 'corrupt-config-schema-valid-backup'
  Assert-PreservedPreferences
  Assert-Archived -Damaged $innerDamaged
  $results.Add(@{ case = 'corrupt-config-schema-valid-backup'; passed = $true })
} finally {
  if ($lock) { $lock.Dispose() }
  Stop-TestApplication
  $results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'upgrade-results.json') -Encoding utf8NoBOM
  if ($baselineEvidence) {
    $baselineEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory ($baselineEvidence.case + '-evidence.json')) -Encoding utf8NoBOM
  }
  if (Test-Path -LiteralPath $profileDirectory) { Remove-Item -LiteralPath $profileDirectory -Recurse -Force }
  if (Test-Path -LiteralPath $savedDirectory) { Move-Item -LiteralPath $savedDirectory -Destination $profileDirectory }
}
