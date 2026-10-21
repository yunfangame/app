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
$process = Start-Process -FilePath $shell -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$null = $process.Handle
while (-not $process.WaitForExit(30000)) {
    $length = if (Test-Path -LiteralPath $stdout) { (Get-Item -LiteralPath $stdout).Length } else { 0 }
    Write-Output ('Private step active; captured stdout bytes=' + $length)
}
$process.WaitForExit()
Write-Output ('Private build step completed; exit=' + $process.ExitCode + '; encrypted logs retained')
exit $process.ExitCode
