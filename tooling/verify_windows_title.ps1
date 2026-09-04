if (-not ('FengWoTitleTest' -as [type])) {
  Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FengWoTitleTest {
  private delegate bool EnumWindowCallback(IntPtr window, IntPtr parameter);
  [DllImport("user32.dll")]
  private static extern bool EnumWindows(EnumWindowCallback callback, IntPtr parameter);
  [DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
  private static extern int GetClassNameW(IntPtr window, StringBuilder name, int capacity);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
  private static extern int GetWindowTextW(IntPtr window, StringBuilder text, int capacity);
  public static IntPtr FindMainWindow(uint processId) {
    IntPtr result = IntPtr.Zero;
    EnumWindows((window, parameter) => {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner != processId) return true;
      var name = new StringBuilder(256);
      GetClassNameW(window, name, name.Capacity);
      if (name.ToString() != "FLUTTER_RUNNER_WIN32_WINDOW") return true;
      result = window;
      return false;
    }, IntPtr.Zero);
    return result;
  }
  public static string ReadTitle(IntPtr window) {
    var title = new StringBuilder(1024);
    GetWindowTextW(window, title, title.Capacity);
    return title.ToString();
  }
}
'@
}

function Assert-FengWoWindowTitle {
  param([Parameter(Mandatory = $true)][uint32]$ProcessId)
  $window = [IntPtr]::Zero
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    $window = [FengWoTitleTest]::FindMainWindow($ProcessId)
    if ($window -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 250
  }
  if ($window -eq [IntPtr]::Zero) {
    throw "No native main window found for process $ProcessId"
  }
  $expected = -join ([char[]](0x8702, 0x7a9d, 0x52a0, 0x901f, 0x5668))
  $actual = [FengWoTitleTest]::ReadTitle($window)
  $codeUnits = ($actual.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
  if ($actual -cne $expected) {
    throw "Incorrect taskbar/window title: '$actual' ($codeUnits)"
  }
  Write-Host "Verified native window title: $actual ($codeUnits)"
  return $window
}
