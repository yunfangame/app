[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Collect-Client.ps1') -LibraryOnly -NonInteractive -AllowNonWindows
$script:Passed=0;$script:Failed=New-Object 'System.Collections.Generic.List[string]'
function Assert-Report([bool]$Value,[string]$Reason) { if (-not $Value) { throw $Reason } }
function Case([string]$Name,[scriptblock]$Body) { try { & $Body;$script:Passed++;Write-Host ('PASS '+$Name) } catch { $script:Failed.Add($Name+': '+$_.Exception.Message);Write-Host ('FAIL '+$Name) } }
$node=[pscustomobject]@{Id='node-001';Type='vless';Server='192.0.2.1';Port=443;Position=1;Positions=@(1,3);Chain=$false;Dependency=''}
function Row([string]$Stage,[string]$Status,$Data) { return [pscustomobject]@{Time=[DateTime]::UtcNow.ToString('o');Target='node-001';Stage=$Stage;Status=$Status;Data=$Data} }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('fw-report-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
 Case 'Two different targets are required for complete success' {
  $rows=@((Row 'protocol.http' 'PASS' @{TargetId='client-target'}),(Row 'protocol.http' 'PASS' @{TargetId='client-target'}))
  Assert-Report ((Get-FwNodeConclusion $node $rows).Status -eq 'INFO') 'Duplicate target successes became two targets'
 }
 Case '407 temporary authentication error is not declared as failed node' {
  $rows=@((Row 'protocol.http' 'UNKNOWN' @{TargetId='client-target';Category='LOCAL_PROXY_AUTH_FAILURE';HttpStatus=407}))
  Assert-Report ((Get-FwNodeConclusion $node $rows).Status -eq 'UNKNOWN') 'Tool authentication failure became node failure'
 }
 Case 'TCP success plus EOF retains ambiguous origin' {
  $rows=@((Row 'protocol.http' 'FAIL' @{TargetId='client-target'}),(Row 'tcp' 'PASS' @{}),(Row 'protocol.core.error' 'INFO' @{Category='REMOTE_CLOSED'}))
  $result=Get-FwNodeConclusion $node $rows
  Assert-Report ($result.Cause.Contains('不能区分') -and -not $result.Cause.Contains('运营商已')) 'EOF was blamed on network or authorization without proof'
 }
 Case 'Explicit core authentication evidence outranks TCP reachability' {
  $rows=@((Row 'protocol.http' 'FAIL' @{TargetId='client-target'}),(Row 'tcp' 'PASS' @{}),(Row 'protocol.core.error' 'INFO' @{Category='AUTHENTICATION'}))
  Assert-Report ((Get-FwNodeConclusion $node $rows).Cause.Contains('明确的认证错误')) 'Authentication evidence was lost'
 }
 Case 'Batched actual core messages associate node and retain only error tokens' {
  $script:Events.Clear();$script:CoreWarnings.Clear()
  $reply=@{method='message';arguments=@(@{type='log';data=@{LogLevel=2;Payload='[TCP] dial node-002 127.0.0.1:50000 --> example.invalid:80 error: dial tcp 192.0.2.1:443: i/o timeout fixture-private-password=secret 11111111-2222-3333-4444-555555555555'}})}
  Add-FwCoreMessages $reply
  Assert-Report ($script:CoreWarnings.Count -eq 1 -and $script:CoreWarnings[0].NodeId -eq 'node-002' -and $script:CoreWarnings[0].Category -eq 'TIMEOUT') 'Core warning envelope failed'
  $safe=$script:CoreWarnings.ToArray() | ConvertTo-Json -Depth 8
  Assert-Report (-not $safe.Contains('fixture-private') -and -not $safe.Contains('11111111') -and $safe.Contains('i/o timeout')) 'Core arbitrary content leaked or all details dropped'
 }
 Case 'Safe error extraction never retains arbitrary TLS alert text' {
  $safe=@(Get-SafeCoreError 'remote error: tls: fixturesecret handshake failure password=fixture-private-password') -join '|'
  Assert-Report (-not $safe.Contains('fixture') -and $safe.Contains('handshake')) 'Arbitrary TLS text survived redaction'
 }
 Case 'HTML escapes evidence and shows recovered rather than active failure' {
  $script:ReportRoot=$fixture;$script:Events.Clear()
  $script:Observation=[pscustomobject]@{Findings=@([pscustomobject]@{Status='INFO';Code='API_REQUEST_TIMEOUT';Summary='以前失败';RecoveredLater=$true;RecoveryMeaning='同阶段后来成功';NextCheck='继续核验'})}
  $script:Account=$null
  Add-Result 'node-001' 'protocol.http' 'UNKNOWN' @{TargetId='client-target';Note='<script>fixture-no-execution</script>'}
  Write-FwClientReport @($node) 'partial'
  $html=[IO.File]::ReadAllText((Join-Path $fixture '检测报告.html'))
  Assert-Report (($html.Contains('&lt;script&gt;') -or $html.Contains('\u003cscript\u003e')) -and -not $html.Contains('<script>')) 'HTML evidence executes script'
  Assert-Report ($html.Contains('随后出现同阶段成功记录') -and $html.Contains('1, 3')) 'Recovered finding or identical-config aliases not shown'
 }
 Case 'All emitted files exclude internal raw node credentials and paths' {
  foreach ($name in @('检测报告.html','report.json','summary.txt','results.jsonl')) {
   $text=[IO.File]::ReadAllText((Join-Path $fixture $name))
   Assert-Report (-not $text.Contains('fixture-private-password') -and -not $text.Contains('11111111-2222')) 'Private data escaped into generated artifact'
  }
 }
} finally { $script:ReportRoot=$null;Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ('RESULT passed='+$script:Passed+' failed='+$script:Failed.Count)
foreach ($failure in $script:Failed) { Write-Host $failure }
if ($script:Failed.Count -gt 0) { exit 1 }
