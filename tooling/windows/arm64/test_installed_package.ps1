param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

. (Join-Path $PSScriptRoot 'common.ps1')
$environment = Assert-FwArmRunner
if (Get-Process -Name FengWo, FlClashCore -ErrorAction SilentlyContinue) { throw 'Another client is running; refusing the isolated installation fixture' }
$windowsTools = Split-Path -Parent $PSScriptRoot
$checks = New-Object 'Collections.Generic.List[object]'
$failure = $null
$process = $null
try {
    & (Join-Path $windowsTools 'test_installed_upgrade.ps1') -InstallerPath $InstallerPath -OutputDirectory (Join-Path $EvidenceDirectory 'overwrite')
    $results = Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'overwrite/upgrade-results.json') -Raw | ConvertFrom-Json
    foreach ($name in @('overwrite-valid-preferences', 'locked-preferences-and-retry', 'read-only-preferences', 'corrupt-preferences-valid-backup', 'corrupt-preferences-fresh-recovery', 'corrupt-config-schema-valid-backup')) {
        if (@($results | Where-Object { $_.case -ceq $name -and $_.passed }).Count -ne 1) { throw ('An installed overwrite regression was not verified: ' + $name) }
    }
    $checks.Add([ordered]@{ name = 'same-arm64-version-overwrite-and-six-preference-regressions'; passed = $true; verifies_old_x64_to_arm64_migration = $false })
    $installDirectory = Join-Path $env:RUNNER_TEMP 'fengwo-overwrite-test'
    $application = Join-Path $installDirectory 'FengWo.exe'
    if (-not (Get-FwPeIdentity $application).arm64) { throw 'The installed application is not ARM64' }
    $process = Start-Process -FilePath $application -WorkingDirectory $installDirectory -PassThru
    $processHandle = $process.Handle
    Assert-FwArmProcess $process.Id
    . (Join-Path $windowsTools '../verify_windows_title.ps1')
    $window = Assert-FengWoWindowTitle $process.Id
    if ($process.HasExited) { throw 'The installed native ARM64 application exited before its window was verified' }
    $checks.Add([ordered]@{ name = 'installed-native-arm64-process-and-current-window-title'; passed = $true })
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FengWoArm64WindowCapture {
    [StructLayout(LayoutKind.Sequential)]
    public struct Rectangle { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool GetWindowRect(IntPtr window, out Rectangle rectangle);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool PrintWindow(IntPtr window, IntPtr target, uint flags);
}
'@
    Start-Sleep -Seconds 3
    $rectangle = New-Object FengWoArm64WindowCapture+Rectangle
    if (-not [FengWoArm64WindowCapture]::GetWindowRect($window, [ref]$rectangle)) { throw 'The owned application window bounds could not be read' }
    $width = $rectangle.Right - $rectangle.Left
    $height = $rectangle.Bottom - $rectangle.Top
    if ($width -lt 1 -or $height -lt 1 -or $width -gt 4096 -or $height -gt 4096) { throw 'The owned application window has invalid capture bounds' }
    $bitmap = New-Object Drawing.Bitmap($width, $height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $captureMethod = 'PrintWindow'
    try {
        $target = $graphics.GetHdc()
        try { $printed = [FengWoArm64WindowCapture]::PrintWindow($window, $target, 2) } finally { $graphics.ReleaseHdc($target) }
        if (-not $printed) {
            $captureMethod = 'CopyFromScreen'
            $graphics.CopyFromScreen($rectangle.Left, $rectangle.Top, 0, 0, $bitmap.Size)
        }
        $bitmap.Save((Join-Path $EvidenceDirectory 'installed-arm64-login-window.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    $checks.Add([ordered]@{ name = 'installed-window-captured-for-visual-review'; passed = $true; capture_method = $captureMethod; pixels_require_visual_review = $true })
} catch { $failure = $_.Exception.Message } finally {
    if ($process) {
        try { if (-not $process.HasExited) { $process.Kill(); if (-not $process.WaitForExit(5000)) { throw 'Owned application did not exit' } } } catch { if (-not $failure) { $failure = $_.Exception.Message } }
        $process.Dispose()
    }
    Save-FwArmEvidence (Join-Path $EvidenceDirectory 'installation-verification.json') ([ordered]@{ passed = (-not $failure); failure = $failure; environment = $environment; checks = @($checks.ToArray()); synthetic_preferences_only = $true; real_customer_account_tested = $false })
}
if ($failure) { throw $failure }
