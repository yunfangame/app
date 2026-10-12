. (Join-Path $PSScriptRoot '../arm64/common.ps1')

function Assert-FwNativeRunner {
    param([Parameter(Mandatory = $true)][ValidateSet('arm64')][string]$Architecture)
    return Assert-FwArmRunner
}

function Assert-FwNativeProcess {
    param([Parameter(Mandatory = $true)][int]$ProcessId, [Parameter(Mandatory = $true)][ValidateSet('arm64')][string]$Architecture)
    Assert-FwArmProcess -ProcessId $ProcessId
}
