$ErrorActionPreference = 'Stop'
if (-not (Test-Path $script:AuditRoot)) { throw 'The owned audit directory is missing' }
$events = @(Get-ChildItem (Join-Path $env:APPDATA 'FengWo') -Filter events.jsonl -Recurse -ErrorAction SilentlyContinue)
if ($events.Count -eq 1) { Copy-Item -LiteralPath $events[0].FullName -Destination (Join-Path $script:AuditRoot 'client-events.jsonl') }
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
$files = @(Get-ChildItem -LiteralPath $script:AuditRoot -File | Where-Object { $_.Extension -in @('.json','.jsonl','.log','.txt') })
if ($files.Count -eq 0) { throw 'No scoped diagnostic records were found' }
$zip = Join-Path ([Environment]::GetFolderPath('Desktop')) ('FengWo-Audit-Export-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.zip')
Compress-Archive -LiteralPath $files.FullName -DestinationPath $zip
$zipHash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLowerInvariant()
Set-Clipboard ('FENGWO_AUDIT_ZIP_V1:'+[Convert]::ToBase64String([IO.File]::ReadAllBytes($zip)))
Write-Output ('AUDIT_EXPORT_READY Files='+$files.Count+' ZIP_BYTES='+(Get-Item $zip).Length+' SHA256='+$zipHash)
Start-Transcript -Path (Join-Path $script:AuditRoot 'transcript.txt') -Append | Out-Null
