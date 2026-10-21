param([Parameter(Mandatory = $true)][string]$ScriptPath)
$ErrorActionPreference = 'Stop'
$directory = Join-Path $env:RUNNER_TEMP 'private-build-logs'
[void][IO.Directory]::CreateDirectory($directory)
$name = [IO.Path]::GetFileNameWithoutExtension($ScriptPath)
$stdout = Join-Path $directory ($name + '.stdout.txt')
$stderr = Join-Path $directory ($name + '.stderr.txt')
$child = Join-Path $directory ($name + '.private.ps1')
[IO.File]::WriteAllText($child, ('$ErrorActionPreference = ''Stop''' + [Environment]::NewLine + [IO.File]::ReadAllText($ScriptPath)), [Text.UTF8Encoding]::new($false))
$shell = (Get-Process -Id $PID).Path
$arguments = '-NoLogo -NoProfile -NonInteractive -File "' + $child + '"'
$process = Start-Process -FilePath $shell -ArgumentList $arguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Write-Output ('Private build step completed; exit=' + $process.ExitCode + '; encrypted logs retained')
exit $process.ExitCode
