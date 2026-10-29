param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$RequireEnforced
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
$client = $os.ProductType -eq 1 -and [version]$os.Version -ge [version]'10.0.22621'
$registry = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue
$state = if ($registry) { [int]$registry.VerifiedAndReputablePolicyState } else { -1 }
$policies = @()
$policyCommandSucceeded = $false
if (Get-Command citool.exe -ErrorAction SilentlyContinue) {
    $raw = & citool.exe -lp -json
    if ($LASTEXITCODE -eq 0) {
        $document = ($raw -join "`n") | ConvertFrom-Json
        $policyCommandSucceeded = $document.OperationResult -eq 0
        $policies = @($document.Policies | Where-Object { $_.FriendlyName -eq 'VerifiedAndReputableDesktop' -and $_.PolicyID.Trim('{}') -ieq '0283ac0f-fff1-49ae-ada1-8a933130cad6' })
    }
}
$enforced = $client -and $state -eq 1 -and $policyCommandSucceeded -and $policies.Count -eq 1 -and $policies[0].IsEnforced -eq $true -and $policies[0].IsAuthorized -eq $true -and $policies[0].PolicyOptions -contains 'Enabled:UMCI' -and $policies[0].PolicyOptions -notcontains 'Enabled:Audit Mode'
$receipt = @{ schema = 'fengwo-sac-enforcement-state-v1'; observed_at_utc = [DateTime]::UtcNow.ToString('o'); windows_version = $os.Version; windows_product_type = $os.ProductType; registry_state = $state; policy_command_succeeded = $policyCommandSucceeded; policies = $policies; enforced = $enforced; application_test_performed = $false; publication_allowed = $false }
$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
if ($RequireEnforced -and -not $enforced) { throw 'Smart App Control is not in verified enforcement mode; release acceptance is blocked' }
