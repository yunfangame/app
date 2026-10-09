function Convert-FwHtml($Value) {
    return [Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-FwNodeConclusion($Node,$Rows) {
    $http=@($Rows | Where-Object { $_.Stage -eq 'protocol.http' })
    $passed=@($http | Where-Object { $_.Status -eq 'PASS' } | Group-Object { Get-Field $_.Data 'TargetId' } | ForEach-Object { $_.Group[0] })
    $tcp=@($Rows | Where-Object { $_.Stage -eq 'tcp' })
    $tcpPassed=@($tcp | Where-Object { $_.Status -eq 'PASS' })
    $warnings=@($Rows | Where-Object { $_.Stage -eq 'protocol.core.error' })
    $categories=@($warnings | ForEach-Object { [string](Get-Field $_.Data 'Category') } | Sort-Object -Unique)
    $status='UNKNOWN';$cause='检测未完成，暂不能定位。';$next='查看该节点的逐项记录和检测完成状态。'
    if ($Node.Chain -or (Get-Field $Node 'Dependency' '')) {
        $cause='节点依赖代理链或外部证书文件；本次未重放这些依赖。';$next='在原客户端重现，核对代理链及证书文件。'
    } elseif ($passed.Count -ge 2) {
        $status='PASS';$cause='两个目标的协议请求均有有效响应。';$next='若客户端仍超时，核对客户端 DNS、配置生效与日志中的内部通信异常。'
    } elseif ($passed.Count -gt 0) {
        $status='INFO';$cause='至少一个目标可达，另一个异常或未完成；节点并非完全不通。';$next='比较目标状态、出口 DNS 与另一个运营商的同节点结果。'
    } elseif ($categories -contains 'AUTHENTICATION') {
        $status='FAIL';$cause='内核记录了明确的认证错误。';$next='核对套餐有效性、订阅是否最新和服务端该用户授权；不归因为线路阻断。'
    } elseif ($categories -contains 'CERTIFICATE') {
        $status='FAIL';$cause='节点连接中出现证书校验错误。';$next='核对系统时间、节点证书及 SNI；HTTPS 测速目标证书问题另行记录。'
    } elseif ($categories -contains 'DNS') {
        $status='FAIL';$cause='内核记录了域名解析失败。';$next='比较系统 DNS 与两组公共 DNS，并核对节点域名。'
    } elseif ($http.Count -gt 0 -and $tcp.Count -gt 0 -and $tcpPassed.Count -eq 0) {
        $status='FAIL';$cause='协议请求失败，所测入口 TCP 也未连接成功。';$next='核对服务端监听、端口和路由；换运营商复测才可进一步区分本地线路问题。'
    } elseif ($categories -contains 'REMOTE_CLOSED') {
        $status='FAIL';$cause='连接被关闭或复位；仅凭 EOF/复位不能区分认证拒绝、服务器故障和中途干扰。';$next='结合服务端同时间日志，并用另一条运营商线路运行同一工具对照。'
    } elseif ($categories -contains 'HANDSHAKE') {
        $status='FAIL';$cause='协议握手未成功。';$next='核对协议参数、服务端日志和同节点跨线路结果。'
    } elseif ($http.Count -gt 0 -and @($http | Where-Object { $_.Status -eq 'FAIL' }).Count -eq 0) {
        $cause='仅取得工具监听或目标 HTTP 异常，不能据此判定节点故障。';$next='检查该次临时监听及目标状态；原客户端仍需单独核验。'
    } elseif ($http.Count -gt 0) {
        $status='FAIL';$cause='协议请求未通过，现有证据尚不能确定最终原因。';$next='核对请求耗时、内核错误词和服务端授权；TCP/TLS 成功也不代表代理认证成功。'
    }
    return [pscustomobject]@{NodeId=$Node.Id;Status=$status;Cause=$cause;NextCheck=$next;HttpTests=$http.Count;PassedTargets=$passed.Count;TcpTests=$tcp.Count;TcpPassed=$tcpPassed.Count;CoreCategories=$categories}
}

function Write-FwClientReport($Nodes,[string]$Completion) {
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $html=New-Object Text.StringBuilder
    [void]$html.Append('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>蜂窝客户端检测报告</title><style>body{font:15px/1.7 system-ui,sans-serif;background:#f2f6ff;color:#1c2b44;margin:0}main{max-width:1200px;margin:30px auto;padding:24px;background:white;border-radius:18px}h1,h2{color:#0959d9}h2{margin-top:30px}p{margin:8px 0}.notice{background:#fff4dc;padding:15px;border-radius:10px}.pass{color:#087b49}.fail{color:#bd3030}.unknown,.info{color:#805514}table{border-collapse:collapse;width:100%;font-size:14px}th,td{border:1px solid #dce5f5;padding:10px;vertical-align:top;word-break:break-word}th{background:#eef4ff;text-align:left}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f7f9fd;border:1px solid #e2e8f4;padding:12px}summary{cursor:pointer;color:#0959d9}small{color:#526781}@media(max-width:700px){main{margin:0;border-radius:0;padding:14px}.scroll{overflow:auto}table{min-width:680px}}</style><main>')
    $time=(Get-Date).ToString('o')
    $lines.Add('蜂窝客户端全面诊断 V3');$lines.Add('时间：'+$time);$lines.Add('完成状态：'+$Completion)
    [void]$html.Append('<h1>蜂窝客户端全面诊断 V3</h1><p>检测时间：'+(Convert-FwHtml $time)+' · 完成状态：'+(Convert-FwHtml $Completion)+'</p>')
    $limitations='这是本机客户端与独立内核的观测结果。单份报告不能确认运营商阻断。独立内核保留节点认证和传输参数，使用系统 DNS，不重放原客户端 TUN、DNS 缓存和分流规则；本机其他 VPN/TUN 路由仍可能影响结果。'
    $lines.Add($limitations)
    [void]$html.Append('<p class="notice">'+(Convert-FwHtml $limitations)+'</p>')
    $findings=@();if ($script:Observation) { $findings=@(Get-Field $script:Observation 'Findings' @()) }
    [void]$html.Append('<h2>账号与客户端现象</h2>')
    if ($script:Account -and (Get-Field $script:Account 'account_match') -eq 'MATCHED') {
        $remaining=Get-Field $script:Account 'remaining_bytes' $null
        $accountLine='当前账号缓存引用：'+[string](Get-Field $script:Account 'account_ref')+'；缓存最后核验时间：'+[string](Get-Field $script:Account 'verified_at')+'；缓存到期时间 UTC：'+[string](Get-Field $script:Account 'expires_at_utc')
        if ($null -ne $remaining) { $accountLine+='；缓存剩余流量：'+[Math]::Round(([double]$remaining/1GB),2)+' GB' }
        $lines.Add($accountLine);[void]$html.Append('<p>'+(Convert-FwHtml $accountLine)+'</p><p class="notice">账号数据来自匹配当前账号的本地缓存，不是本次服务端实时查询。可能已经续费或重置；不能用缓存直接确认当前套餐已过期。</p>')
    } else {
        $lines.Add('未读取到可确认属于当前账号的缓存套餐数据。');[void]$html.Append('<p>未读取到可确认属于当前账号的缓存套餐数据；套餐实时状态未知。</p>')
    }
    if ($findings.Count -eq 0) { [void]$html.Append('<p>本次观察未形成明确客户端归因，详见历史日志与各节点测试。</p>') }
    foreach ($finding in $findings) {
        $recovery='';if ((Get-Field $finding 'RecoveredLater' $false) -eq $true) { $recovery='；随后出现同阶段成功记录。'+[string](Get-Field $finding 'RecoveryMeaning') }
        $line=[string](Get-Field $finding 'Status')+' | '+[string](Get-Field $finding 'Code')+' | '+[string](Get-Field $finding 'Summary')+$recovery+' | '+[string](Get-Field $finding 'NextCheck')
        $lines.Add($line);[void]$html.Append('<p><b>'+(Convert-FwHtml (Get-Field $finding 'Status'))+' · '+(Convert-FwHtml (Get-Field $finding 'Summary'))+'</b> '+(Convert-FwHtml $recovery)+' '+(Convert-FwHtml (Get-Field $finding 'NextCheck'))+'</p>')
    }
    $timeline=@($script:Events | Where-Object { $_.Stage -eq 'client.logs' } | Select-Object -Last 1)
    if ($timeline.Count -gt 0) {
        $historical=@((Get-Field $timeline[0].Data 'Rows' @()) | Where-Object { $_.event -match '\.(failed|failure|timed_out|timeout)$' -or (Get-Field $_.fields 'subscription_v2_code') -eq 'subscription_unavailable' } | Select-Object -Last 8)
        if ($historical.Count -gt 0) {
            [void]$html.Append('<h3>最近历史失败记录</h3><p>以下记录可能发生在本次检测之前，只说明记录时间发生过异常，不直接代表现在仍然失败。</p>')
            foreach ($event in $historical) {
                $code=[string](Get-Field $event.fields 'subscription_v2_code' (Get-Field $event.fields 'error_code' ''))
                $description=$event.event+' · '+$code
                if ($code -eq 'subscription_unavailable') { $description+='：服务端曾拒绝提供订阅，需核对套餐有效性和订阅权限。' }
                $line='历史 '+$event.timestamp+' | '+$description
                $lines.Add($line);[void]$html.Append('<p>'+(Convert-FwHtml $line)+'</p>')
            }
        }
    }
    $selection=@($script:Events | Where-Object { $_.Stage -eq 'sample' } | Select-Object -Last 1)
    if ($selection.Count -gt 0) { $selectionText=$selection[0].Data | ConvertTo-Json -Compress -Depth 6;$lines.Add('节点覆盖：'+$selectionText);[void]$html.Append('<p>节点覆盖：<small>'+(Convert-FwHtml $selectionText)+'</small></p>') }
    [void]$html.Append('<h2>逐节点结论</h2><p>节点编号为报告编号；“配置第几项”用于对应客户端配置列表。HTTP 耗时为本次请求耗时，不等同于客户端显示的 RTT。</p><div class="scroll"><table><tr><th>节点 / 协议 / 配置位置</th><th>入口</th><th>结果与依据</th><th>下一步</th></tr>')
    $conclusions=New-Object 'System.Collections.Generic.List[object]'
    foreach ($node in $Nodes) {
        $rows=@($script:Events | Where-Object { $_.Target -eq $node.Id })
        $conclusion=Get-FwNodeConclusion $node $rows;$conclusions.Add($conclusion)
        $positions=@(Get-Field $node 'Positions' @($node.Position)) -join ', '
        $label=('{0} | {1} | 配置第 {2} 项' -f $node.Id,$node.Type,$positions)
        $endpoint=$node.Server+':'+$node.Port
        $evidence=('HTTP {0}/{1} 次通过；入口 TCP {2}/{3} 次通过；内核错误类别：{4}' -f $conclusion.PassedTargets,$conclusion.HttpTests,$conclusion.TcpPassed,$conclusion.TcpTests,($conclusion.CoreCategories -join ','))
        $lines.Add('');$lines.Add($label+' | '+$endpoint);$lines.Add($conclusion.Status+'：'+$conclusion.Cause);$lines.Add($evidence);$lines.Add('建议：'+$conclusion.NextCheck)
        [void]$html.Append('<tr><td>'+(Convert-FwHtml $label)+'</td><td>'+(Convert-FwHtml $endpoint)+'</td><td class="'+$conclusion.Status.ToLowerInvariant()+'">'+(Convert-FwHtml $conclusion.Cause)+'<br><small>'+(Convert-FwHtml $evidence)+'</small></td><td>'+(Convert-FwHtml $conclusion.NextCheck)+'</td></tr>')
    }
    [void]$html.Append('</table></div><h2>逐项证据</h2><p>包含进程、监听端口归属、客户端事件时间线、DNS/TCP/TLS/协议请求、请求耗时和可识别内核错误词。未读取到的字段不会视为正常。</p>')
    foreach ($group in @($script:Events | Group-Object Target)) {
        [void]$html.Append('<details><summary>'+(Convert-FwHtml $group.Name)+' · '+$group.Count+' 条记录</summary>')
        foreach ($row in $group.Group) {
            $data=$row.Data | ConvertTo-Json -Depth 16
            $line=[string]$row.Stage+' | '+[string]$row.Status+' | '+($row.Data | ConvertTo-Json -Depth 16 -Compress)
            $lines.Add($line)
            [void]$html.Append('<p><b>'+(Convert-FwHtml $row.Stage)+'</b> · '+(Convert-FwHtml $row.Status)+'</p><pre>'+(Convert-FwHtml $data)+'</pre>')
        }
        [void]$html.Append('</details>')
    }
    $footer='报告不包含账号明文、登录密码、设备私钥、订阅地址、节点密码/UUID、原始配置和数据库。节点入口域名/IP、端口、SNI 及脱敏系统网络信息会保留供排查。'
    $lines.Add('');$lines.Add($footer)
    [void]$html.Append('<h2>对照检测</h2><p>如果多种协议在本线路失败，仍需先排除套餐授权、服务端入口和出口故障。使用同一电脑、同一账号和同一版本，换另一家运营商热点再运行一次；两份报告配合服务端同时间日志，才能进一步判断线路或协议干扰。</p><small>'+(Convert-FwHtml $footer)+'</small></main></html>')
    [IO.File]::WriteAllLines((Join-Path $script:ReportRoot 'summary.txt'),$lines.ToArray(),$script:Utf8)
    [IO.File]::WriteAllText((Join-Path $script:ReportRoot '检测报告.html'),$html.ToString(),$script:Utf8)
    $report=@{Version='3.0';Completion=$Completion;Time=$time;Account=$script:Account;Observation=$script:Observation;Nodes=$conclusions.ToArray();Results=@($script:Events.ToArray());CoreErrorCategories=$script:CoreLogCounts;CoreWarnings=$script:CoreWarnings.ToArray();CoreWarningCoverage=@{Retained=$script:CoreWarnings.Count;Dropped=$script:CoreWarningsDropped};AttributionBoundary='LOCAL_EVIDENCE_NOT_ISP_BLOCK_CONFIRMATION'}
    [IO.File]::WriteAllText((Join-Path $script:ReportRoot 'report.json'),($report | ConvertTo-Json -Depth 24),$script:Utf8)
}
