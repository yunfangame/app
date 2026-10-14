$ErrorActionPreference = 'Stop'
$script:AuditRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FengWo-Disconnect-Audit-20261014'
New-Item -ItemType Directory -Force -Path $script:AuditRoot | Out-Null
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
Set-Content -Encoding UTF8 (Join-Path $script:AuditRoot 'transcript.txt') 'Audit initialization; configuration payloads are intentionally excluded.'
Start-Transcript -Path (Join-Path $script:AuditRoot 'transcript.txt') -Append | Out-Null
Add-Type -AssemblyName System.Web.Extensions
$script:JsonParser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$script:JsonParser.MaxJsonLength = 16777216
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class DisconnectAudit {
  [StructLayout(LayoutKind.Explicit)] struct Value { [FieldOffset(0)] public uint Number; [FieldOffset(0)] public IntPtr Text; }
  [StructLayout(LayoutKind.Sequential)] struct Option { public uint Kind; public Value Value; }
  [StructLayout(LayoutKind.Sequential)] struct List { public uint Size; public IntPtr Connection; public uint Count; public uint Error; public IntPtr Options; }
  [DllImport("wininet.dll", EntryPoint="InternetQueryOptionW", SetLastError=true)] static extern bool Query(IntPtr h,uint option,ref List list,ref uint bytes);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr p);
  public sealed class Snapshot { public uint Flags; public string Server; public string Bypass; public string Pac; }
  public static Snapshot Capture() {
    int size=Marshal.SizeOf(typeof(Option));
    List list=new List { Size=(uint)Marshal.SizeOf(typeof(List)),Count=4,Options=Marshal.AllocHGlobal(size*4) };
    uint[] kinds={10,2,3,4};
    for(int i=0;i<4;i++) Marshal.StructureToPtr(new Option { Kind=kinds[i] },IntPtr.Add(list.Options,size*i),false);
    try {
      uint bytes=list.Size;
      if(!Query(IntPtr.Zero,75,ref list,ref bytes)) throw new Win32Exception(Marshal.GetLastWin32Error());
      Option flags=(Option)Marshal.PtrToStructure(list.Options,typeof(Option));
      string[] values=new string[3];
      for(int i=1;i<4;i++) {
        Option o=(Option)Marshal.PtrToStructure(IntPtr.Add(list.Options,size*i),typeof(Option));
        values[i-1]=Marshal.PtrToStringUni(o.Value.Text)??String.Empty;
      }
      return new Snapshot { Flags=flags.Value.Number,Server=values[0],Bypass=values[1],Pac=values[2] };
    } finally {
      for(int i=1;i<4;i++) {
        Option o=(Option)Marshal.PtrToStructure(IntPtr.Add(list.Options,size*i),typeof(Option));
        if(o.Value.Text!=IntPtr.Zero) GlobalFree(o.Value.Text);
      }
      Marshal.FreeHGlobal(list.Options);
    }
  }
}
'@
function Save-FengWoAudit([string]$Phase) {
  if ($Phase -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid phase' }
  $preferences = $null
  $files = @(Get-ChildItem (Join-Path $env:APPDATA 'FengWo') -Filter shared_preferences.json -Recurse -ErrorAction SilentlyContinue)
  foreach ($file in $files) {
    try { $values = $script:JsonParser.DeserializeObject([IO.File]::ReadAllText($file.FullName)) }
    catch { throw 'Cannot parse preferences; configuration contents omitted' }
    $config = $values['flutter.config']
    if ($config -is [string]) { $config = $script:JsonParser.DeserializeObject($config) }
    if ($null -ne $config) {
      $preferences = [ordered]@{ currentProfileId=$config.currentProfileId; mode=$config.patchClashConfig.mode; network=$config.networkProps; tun=$config.patchClashConfig.tun; selectedMap=$config.selectedMap }
    }
  }
  $proxy = [DisconnectAudit]::Capture()
  $probe = [ordered]@{ url='https://house.zryc.tech/fengwoupdate.json'; selectedProxy=$null; status=$null; bytes=$null; error=$null }
  try {
    $uri = [Uri]$probe.url
    $request = [Net.HttpWebRequest]::Create($uri)
    $request.Proxy = [Net.WebRequest]::GetSystemWebProxy()
    $probe.selectedProxy = $request.Proxy.GetProxy($uri).AbsoluteUri
    $request.Timeout = 15000
    $response = $request.GetResponse()
    try {
      $memory = New-Object IO.MemoryStream
      $response.GetResponseStream().CopyTo($memory)
      $probe.status = [int]$response.StatusCode
      $probe.bytes = $memory.Length
    } finally { $response.Dispose() }
  } catch { $probe.error=$_.Exception.Message }
  $app = Get-Process FengWo -ErrorAction SilentlyContinue
  $snapshot = [ordered]@{
    phase=$Phase; time=(Get-Date).ToString('o'); version=$(if($app){(Get-Item $app.Path).VersionInfo.ProductVersion});
    proxy=$proxy; preferences=$preferences;
    adapters=@(Get-NetAdapter -IncludeHidden | Select-Object Name,InterfaceDescription,Status,InterfaceIndex);
    routes=@(Get-NetRoute | Select-Object InterfaceIndex,DestinationPrefix,NextHop,RouteMetric);
    dns=@(Get-DnsClientServerAddress | Select-Object InterfaceIndex,AddressFamily,ServerAddresses);
    listeners=@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -eq '127.0.0.1' } | Select-Object LocalPort,OwningProcess);
    internet=$probe
  }
  $snapshot | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 (Join-Path $script:AuditRoot ($Phase+'.json'))
  Write-Output ('AUDIT '+$Phase+' ProxyFlags='+$proxy.Flags+' Server='+$proxy.Server+' HTTP='+$probe.status+' Bytes='+$probe.bytes+' Error='+$probe.error)
}
Save-FengWoAudit 'baseline-109-disconnected'
