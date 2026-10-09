$script:FwProtocolModuleRoot = $PSScriptRoot

function Initialize-FwHttpProbe {
    if (-not ('FengWoHttpProbe' -as [type])) {
        $options = @('/langversion:5')
        if ($PSVersionTable.PSVersion.Major -ge 7) { $options += '/nowarn:SYSLIB0014' }
        Add-Type -Path (Join-Path $script:FwProtocolModuleRoot 'HttpProbe.cs') -CompilerOptions $options
    }
}

function New-FwProtocolSecret {
    $bytes = New-Object byte[] 24
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($bytes); return [Convert]::ToBase64String($bytes) }
    finally { $random.Dispose() }
}

function Get-FwProtocolListenerConfiguration {
    param([Parameter(Mandatory=$true)][object[]]$Nodes)
    if ($Nodes.Count -lt 1 -or $Nodes.Count -gt 4) { throw 'PROTOCOL_BATCH_SIZE_INVALID' }
    Initialize-FwHttpProbe
    $listeners = New-Object 'System.Collections.Generic.List[object]'
    $bindings = New-Object 'System.Collections.Generic.List[object]'
    $ports = @{}
    foreach ($node in $Nodes) {
        $id = [string]$node.Id
        if ($id -notmatch '^node-[0-9]{3,6}$') { throw 'PROTOCOL_NODE_ID_INVALID' }
        if (@($bindings | Where-Object { $_.NodeId -eq $id }).Count -gt 0) { throw 'PROTOCOL_NODE_ID_DUPLICATE' }
        $port = 0
        for ($attempt = 0; $attempt -lt 16; $attempt++) {
            $candidate = [FengWoHttpProbe]::AllocateLoopbackPort()
            if (-not $ports.ContainsKey($candidate)) { $port = $candidate; $ports[$port] = $true; break }
        }
        if ($port -eq 0) { throw 'PROTOCOL_LOOPBACK_PORT_UNAVAILABLE' }
        $user = 'fw-diagnostic-' + [Guid]::NewGuid().ToString('N')
        $password = New-FwProtocolSecret
        $listeners.Add(@{type='mixed';name=('diagnostic-'+$id);listen='127.0.0.1';port=$port;proxy=$id;udp=$false;users=@(@{username=$user;password=$password})})
        $bindings.Add([pscustomobject]@{NodeId=$id;Port=$port;User=$user;Password=$password})
    }
    return [pscustomobject]@{Listeners=$listeners.ToArray();Bindings=$bindings.ToArray()}
}

function Invoke-FwHttpBatch {
    param(
        [Parameter(Mandatory=$true)][object[]]$Bindings,
        [Parameter(Mandatory=$true)][object[]]$Targets,
        [ValidateRange(100,120000)][int]$TimeoutMs = 5000,
        [scriptblock]$RpcPoll
    )
    if ($Bindings.Count -lt 1 -or $Bindings.Count -gt 4 -or $Targets.Count -lt 1 -or $Targets.Count -gt 2) { throw 'PROTOCOL_BATCH_SIZE_INVALID' }
    Initialize-FwHttpProbe
    foreach ($target in $Targets) {
        $pending = New-Object 'System.Collections.Generic.List[object]'
        try {
            foreach ($binding in $Bindings) {
                $probe = [FengWoHttpProbe]::Start([string]$binding.NodeId,[string]$target.Id,[string]$target.Url,[int]$binding.Port,[string]$binding.User,[string]$binding.Password,$TimeoutMs)
                $pending.Add($probe)
            }
            while (@($pending | Where-Object { -not $_.IsCompleted }).Count -gt 0) {
                if ($RpcPoll) { [void](& $RpcPoll ([string]$target.Id) @($Bindings | ForEach-Object { $_.NodeId })) }
                [Threading.Thread]::Sleep(100)
            }
            if ($RpcPoll) { [void](& $RpcPoll ([string]$target.Id) @($Bindings | ForEach-Object { $_.NodeId })) }
            foreach ($probe in $pending) { $probe.Result }
        }
        finally { foreach ($probe in $pending) { $probe.Dispose() } }
    }
}
