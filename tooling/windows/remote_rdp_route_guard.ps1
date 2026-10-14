$ErrorActionPreference = 'Stop'
$script:FengWoRdpRoutes = @()
$peers = @(Get-NetTCPConnection -LocalPort 3389 -State Established | Select-Object -ExpandProperty RemoteAddress -Unique)
if ($peers.Count -eq 0) { throw 'No established RDP connection was found' }
foreach ($peer in $peers) {
    if ($peer -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $peer -match '^127\.') { continue }
    $route = Find-NetRoute -RemoteIPAddress $peer | Where-Object { $_.DestinationPrefix } | Select-Object -First 1
    if ($null -eq $route) { throw 'Cannot determine the current RDP route' }
    $adapter = Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceIndex -eq $route.InterfaceIndex }
    if ($adapter.Name -match 'FengWo|Clash|Meta|TUN') { throw 'RDP is already using a tunnel route' }
    $prefix = $peer+'/32'
    $existing = @(Get-NetRoute -DestinationPrefix $prefix -ErrorAction SilentlyContinue)
    if ($existing.Count -eq 0) {
        $created = New-NetRoute -DestinationPrefix $prefix -InterfaceIndex $route.InterfaceIndex -NextHop $route.NextHop -RouteMetric 0 -PolicyStore ActiveStore
        $script:FengWoRdpRoutes += [ordered]@{ prefix=$prefix; index=$created.InterfaceIndex; nextHop=$created.NextHop }
    } elseif (@($existing | Where-Object { $_.InterfaceIndex -ne $route.InterfaceIndex }).Count -gt 0) {
        throw 'An existing RDP host route requires manual review'
    }
}
function Remove-FengWoRdpRouteGuard {
    foreach ($route in $script:FengWoRdpRoutes) {
        Get-NetRoute -DestinationPrefix $route.prefix -InterfaceIndex $route.index -NextHop $route.nextHop -PolicyStore ActiveStore -ErrorAction Stop | Remove-NetRoute -Confirm:$false
    }
    $script:FengWoRdpRoutes = @()
    Write-Output 'RDP_ROUTE_GUARD_REMOVED'
}
$script:FengWoRdpRoutes | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $script:AuditRoot 'rdp-route-guard.json')
Write-Output ('RDP_ROUTE_GUARD_READY NewRoutes='+$script:FengWoRdpRoutes.Count)
