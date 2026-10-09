[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
$collector=Join-Path (Split-Path -Parent $PSScriptRoot) 'Collect-Client.ps1'
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($collector,[ref]$tokens,[ref]$errors)
if ($errors.Count -ne 0) { throw 'Client collector syntax errors' }
. $collector -LibraryOnly -NonInteractive -AllowNonWindows -MaxSeconds 90 -MaxNodes 7
$script:Passed=0
$script:Failures=New-Object 'System.Collections.Generic.List[string]'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('fengwo-client-logic-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)

function Assert-True([bool]$Value,[string]$Reason) { if (-not $Value) { throw $Reason } }
function Run-Case([string]$Name,[scriptblock]$Body) {
    try { & $Body;$script:Passed++;Write-Host ('PASS '+$Name) }
    catch { $script:Failures.Add($Name+': '+$_.Exception.Message);Write-Host ('FAIL '+$Name) }
}
function New-LogicProxy([string]$Name='fixture-private-name',[string]$Uuid='fixture-private-uuid',[string]$Path='/fixture-private-ws-path') {
    return [pscustomobject]@{name=$Name;type='vless';server='192.0.2.1';port=443;uuid=$Uuid;network='ws';tls=$true;servername='sni.example';'ws-opts'=[pscustomobject]@{path=$Path;headers=[pscustomobject]@{Host='ws.example'}}}
}

try {
    Run-Case 'Library import retains outer noninteractive and runtime parameters' {
        Assert-True ([bool]$LibraryOnly -and [bool]$NonInteractive -and [bool]$AllowNonWindows -and $MaxSeconds -eq 90 -and $MaxNodes -eq 7) 'Dot-source changed outer parameters'
        Assert-True ($null -eq $script:ReportRoot -and $script:Events.Count -eq 0) 'Library import executed diagnostic main logic'
    }
    Run-Case 'Candidates reject incomplete node endpoints and retain internal credentials only' {
        $raw=[pscustomobject]@{proxies=@((New-LogicProxy),[pscustomobject]@{type='vless';server='bad/path';port=443},[pscustomobject]@{type='vless';server='example.invalid';port=0},[pscustomobject]@{type='direct';name='DIRECT'})}
        $nodes=@(Get-NodeCandidates $raw 'active-config')
        Assert-True ($nodes.Count -eq 1 -and $nodes[0].Raw.uuid -eq 'fixture-private-uuid' -and $nodes[0].Position -eq 1) 'Valid node parameters lost or invalid endpoints accepted'
    }
    Run-Case 'Same endpoint with different credentials or transport paths remains distinguishable' {
        $raw=[pscustomobject]@{proxies=@((New-LogicProxy 'fixture-private-name-a' 'fixture-private-uuid-a' '/fixture-private-path-a'),(New-LogicProxy 'fixture-private-name-b' 'fixture-private-uuid-b' '/fixture-private-path-a'),(New-LogicProxy 'fixture-private-name-c' 'fixture-private-uuid-a' '/fixture-private-path-b'))}
        $nodes=@(Select-DiagnosticNodes @(Get-NodeCandidates $raw 'active-config') 12)
        Assert-True ($nodes.Count -eq 3) 'Different real protocol configurations were collapsed by endpoint-only deduplication'
    }
    Run-Case 'Node selection limit and generated report identifiers are bounded' {
        $raw=@();for($i=1;$i -le 20;$i++){ $proxy=New-LogicProxy;$proxy.server='192.0.2.'+$i;$raw+=$proxy }
        $nodes=@(Select-DiagnosticNodes @(Get-NodeCandidates ([pscustomobject]@{proxies=$raw}) 'active-config') 5)
        Assert-True ($nodes.Count -eq 5) 'Node selection limit changed'
        Assert-True ($nodes[0].Id -eq 'node-001' -and $nodes[4].Id -eq 'node-005') 'Report identifiers contain original names'
    }
    Run-Case 'Isolated configuration disables inbound host state and excludes chain dependencies' {
        $plain=New-LogicProxy
        $chain=New-LogicProxy 'fixture-chain';$chain.server='192.0.2.2';$chain | Add-Member -NotePropertyName 'dialer-proxy' -NotePropertyValue 'fixture-private-chain'
        $nodes=@(Select-DiagnosticNodes @(Get-NodeCandidates ([pscustomobject]@{proxies=@($plain,$chain)}) 'active-config') 12)
        $original=[pscustomobject]@{ipv6=$true;'unified-delay'=$true;'mixed-port'=7890;tun=@{enable=$true};dns=@{enable=$true;listen='0.0.0.0:53'};'external-controller'='0.0.0.0:9090';'proxy-providers'=@{remote=@{url='https://fixture.invalid/sub?token=fixture-private-token'}};hosts=@{'example.invalid'='192.0.2.8'}}
        $isolated=New-IsolatedConfiguration $nodes $original
        foreach($key in @('mixed-port','port','socks-port','redir-port','tproxy-port')) { Assert-True ($isolated[$key] -eq 0) 'Isolated core exposes a listener' }
        foreach($key in @('external-controller','external-controller-tls','external-controller-pipe','external-controller-unix','external-ui','external-ui-url','external-doh-server')) { Assert-True ($isolated[$key] -eq '') 'Isolated core exposes controller or remote UI loader' }
        Assert-True (-not $isolated.tun.enable -and -not $isolated.tun.'auto-route' -and -not $isolated.ntp.'write-to-system' -and -not $isolated.iptables.enable) 'Isolated configuration can modify host networking'
        Assert-True ($isolated.'proxy-providers'.Count -eq 0 -and $isolated.'rule-providers'.Count -eq 0 -and $isolated.proxies.Count -eq 1) 'Remote subscriptions or un-replayed chain leaked into test config'
        Assert-True ($isolated.proxies[0].name -eq 'node-001' -and $isolated.proxies[0].uuid -eq 'fixture-private-uuid' -and $plain.name -eq 'fixture-private-name') 'Isolation mutated source node or changed authentication'
    }
    Run-Case 'Reality and UDP-only protocols are classified without ordinary TLS assumptions' {
        $proxy=New-LogicProxy;$proxy | Add-Member -NotePropertyName 'reality-opts' -NotePropertyValue @{ 'public-key'='fixture-private-key';'short-id'='fixture-private-shortid' }
        $nodes=@(Select-DiagnosticNodes @(Get-NodeCandidates ([pscustomobject]@{proxies=@($proxy)}) 'active-config') 2)
        $target=Get-EndpointTarget $nodes[0]
        Assert-True ($target.Security -eq 'reality') 'Reality was interpreted as ordinary TLS'
        foreach($type in @('hysteria','hysteria2','tuic')) {
            $proxy=New-LogicProxy;$proxy.type=$type
            $node=@(Get-NodeCandidates ([pscustomobject]@{proxies=@($proxy)}) 'active-config')[0];$node.Id='node-001'
            $target=Get-EndpointTarget $node
            Assert-True ($target.UdpOnly -and $target.Transport -eq 'quic') 'QUIC node would reach TCP probe'
        }
    }
    Run-Case 'DNS summary excludes resolver URL credentials and private paths' {
        $original=@{dns=@{enable=$true;'enhanced-mode'='fake-ip';nameserver=@('https://fixture-private-user:fixture-private-pass@dns.example/private-path?token=fixture-private-token','223.5.5.5','https://dns.example/private-path-two#fixture-private-fragment')}}
        $safe=Get-SafeDnsSummary $original | ConvertTo-Json -Compress -Depth 10
        foreach($secret in @('fixture-private','private-path','token=')) { Assert-True (-not $safe.Contains($secret)) 'Resolver credentials leaked into DNS summary' }
    }
    Run-Case 'Summary JSON and text omit raw node credentials names and WS paths' {
        $script:ReportRoot=$fixture;$script:Events.Clear()
        $proxy=New-LogicProxy
        $nodes=@(Select-DiagnosticNodes @(Get-NodeCandidates ([pscustomobject]@{proxies=@($proxy)}) 'active-config') 2)
        Add-Result $nodes[0].Id 'target' 'INFO' (Get-SafeTarget (Get-EndpointTarget $nodes[0]))
        Add-Result $nodes[0].Id 'client.core.delay' 'PASS' @{Target='client-target';ClientDelayValue=32;RequestMilliseconds=20;Reason='PROTOCOL_REQUEST_COMPLETED'}
        Write-ClientSummary $nodes 'fixture-completed'
        foreach($name in @('summary.txt','report.json','results.jsonl')) {
            $text=[IO.File]::ReadAllText((Join-Path $fixture $name))
            foreach($private in @('fixture-private','uuid','password','Raw','ws-opts')) { Assert-True (-not $text.Contains($private)) 'Private node data escaped into report' }
        }
    }
    Run-Case 'One completed target does not claim that both targets passed' {
        $script:ReportRoot=$fixture;$script:Events.Clear()
        $nodes=@(Select-DiagnosticNodes @(Get-NodeCandidates ([pscustomobject]@{proxies=@((New-LogicProxy))}) 'active-config') 2)
        Add-Result $nodes[0].Id 'client.core.delay' 'PASS' @{Target='client-target';ClientDelayValue=32;RequestMilliseconds=20;Reason='PROTOCOL_REQUEST_COMPLETED'}
        Write-ClientSummary $nodes 'partial'
        $text=[IO.File]::ReadAllText((Join-Path $fixture 'summary.txt'))
        Assert-True (-not $text.Contains('两个测速目标的协议请求均通过')) 'Partial single-target result was overstated as two successful targets'
    }
} finally {
    $script:ReportRoot=$null
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('RESULT passed='+$script:Passed+' failed='+$script:Failures.Count)
foreach($failure in $script:Failures) { Write-Host $failure }
if ($script:Failures.Count -gt 0) { exit 1 }
