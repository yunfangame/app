param(
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows') {
  throw 'This test may only run in an isolated GitHub Actions Windows runner'
}
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$installDirectory = Join-Path $env:RUNNER_TEMP 'fengwo-overwrite-test'
$savedDirectory = Join-Path $env:RUNNER_TEMP ('fengwo-profile-before-upgrade-' + [Guid]::NewGuid())
$results = [System.Collections.Generic.List[object]]::new()
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

function Install-TestPackage {
  $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$installDirectory", '/TASKS=')
  $install = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -PassThru -Wait
  if ($install.ExitCode -ne 0) { throw "Installer exited with $($install.ExitCode)" }
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

function Assert-Startup([string]$Case, [bool]$ExpectFailure = $false, [string]$DiagnosticCode = '') {
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
      $roots = @($events | Where-Object {
        $_.event -eq 'tls.trust.initialized' -and $_.fields.supplemental_roots -eq 2
      })
      if ($roots.Count -eq 0) { throw "$Case did not load both TLS roots" }
      [void](Assert-FengWoWindowTitle -ProcessId $process.Id)
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
Install-TestPackage
$applicationPath = Join-Path $installDirectory 'FengWo.exe'
$application = Get-Item -LiteralPath $applicationPath
if ($application.VersionInfo.CompanyName -cne 'com.follow' -or $application.VersionInfo.ProductName -cne '蜂窝加速器') {
  throw 'Unexpected application identity; refusing to modify the test profile'
}
$profileDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) (Join-Path $application.VersionInfo.CompanyName $application.VersionInfo.ProductName)
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
try {
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
  if (Test-Path -LiteralPath $profileDirectory) { Remove-Item -LiteralPath $profileDirectory -Recurse -Force }
  if (Test-Path -LiteralPath $savedDirectory) { Move-Item -LiteralPath $savedDirectory -Destination $profileDirectory }
}
