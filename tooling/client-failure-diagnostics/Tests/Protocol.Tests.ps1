[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'ClientProtocol.ps1')
Initialize-FwHttpProbe

Add-FwDiagnosticType -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public sealed class FengWoHttpProxyFixture : IDisposable
{
    private TcpListener listener;
    private Thread worker;
    private volatile bool stopping;
    private readonly string expected;
    private readonly int status;
    private readonly int stallMs;
    public int Port { get; private set; }
    public int AcceptedAuthenticatedRequests;
    public int UnauthenticatedRequests;
    public bool SawHead;
    public bool SawDiagnosticTarget;

    public FengWoHttpProxyFixture(string user, string password, int status, int stallMs)
    {
        expected = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(user + ":" + password));
        this.status = status;
        this.stallMs = stallMs;
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        worker = new Thread(Run);
        worker.IsBackground = true;
        worker.Start();
    }
    private void Run()
    {
        while (!stopping)
        {
            TcpClient client = null;
            try
            {
                client = listener.AcceptTcpClient();
                client.ReceiveTimeout = 2000;
                client.SendTimeout = 2000;
                using (NetworkStream stream = client.GetStream())
                {
                    StringBuilder headers = new StringBuilder();
                    int value;
                    while (headers.Length < 32768 && (value = stream.ReadByte()) != -1)
                    {
                        headers.Append((char)value);
                        if (headers.ToString().EndsWith("\r\n\r\n")) break;
                    }
                    string text = headers.ToString();
                    bool authenticated = text.IndexOf("Proxy-Authorization: " + expected, StringComparison.OrdinalIgnoreCase) >= 0;
                    SawHead = text.StartsWith("HEAD ");
                    SawDiagnosticTarget = text.IndexOf("example.invalid", StringComparison.OrdinalIgnoreCase) >= 0;
                    string response;
                    if (!authenticated)
                    {
                        Interlocked.Increment(ref UnauthenticatedRequests);
                        response = "HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=\"fixture\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    }
                    else
                    {
                        Interlocked.Increment(ref AcceptedAuthenticatedRequests);
                        if (stallMs > 0) Thread.Sleep(stallMs);
                        response = "HTTP/1.1 " + status.ToString() + " Fixture\r\nContent-Type: text/html\r\nContent-Length: 100000000\r\nLocation: http://private.invalid/fixture-location-secret\r\nConnection: close\r\n\r\nfixture-response-body-secret";
                    }
                    byte[] bytes = Encoding.ASCII.GetBytes(response);
                    stream.Write(bytes, 0, bytes.Length);
                }
            }
            catch { if (stopping) return; }
            finally { if (client != null) client.Close(); }
        }
    }
    public void Dispose()
    {
        stopping = true;
        listener.Stop();
        worker.Join(2500);
    }
}
'@

$script:passed = 0
$script:failures = New-Object 'System.Collections.Generic.List[string]'
function Assert-Protocol([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-ProtocolCase([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:passed++; Write-Host ('PASS ' + $Name) }
    catch { $script:failures.Add($Name + ': ' + $_.Exception.GetType().Name + ' ' + $_.Exception.Message); Write-Host ('FAIL ' + $Name) }
}
function Get-FixtureBinding($Fixture,[string]$Id='node-001',[string]$Password='fixture-loopback-pass') {
    return [pscustomobject]@{NodeId=$Id;Port=$Fixture.Port;User='fixture-loopback-user';Password=$Password}
}
$target = [pscustomobject]@{Id='client-target';Url='http://example.invalid/generate_204?fixture-query-secret=abc'}

Test-ProtocolCase 'Listeners bind only loopback require random users and force each node independently' {
    $configuration = Get-FwProtocolListenerConfiguration @([pscustomobject]@{Id='node-001'},[pscustomobject]@{Id='node-002'},[pscustomobject]@{Id='node-003'},[pscustomobject]@{Id='node-004'})
    Assert-Protocol ($configuration.Listeners.Count -eq 4 -and $configuration.Bindings.Count -eq 4) 'Four listeners were not configured'
    $passwords = @($configuration.Bindings | ForEach-Object {$_.Password} | Select-Object -Unique)
    Assert-Protocol ($passwords.Count -eq 4) 'Loopback credentials were reused'
    foreach ($listener in $configuration.Listeners) {
        Assert-Protocol ($listener.type -eq 'mixed' -and $listener.listen -eq '127.0.0.1' -and -not $listener.udp -and $listener.users.Count -eq 1) 'Listener scope or authentication incorrect'
        $binding = @($configuration.Bindings | Where-Object {$_.NodeId -eq $listener.proxy})[0]
        Assert-Protocol ($binding.Port -eq $listener.port -and $binding.Password -eq $listener.users[0].password) 'Listener points to the wrong node'
    }
}

Test-ProtocolCase 'Unsafe diagnostic node identifiers and oversized batches are rejected' {
    foreach ($nodes in @(
        @([pscustomobject]@{Id='original-private-node'}),
        @([pscustomobject]@{Id='node-001'},[pscustomobject]@{Id='node-001'}),
        @([pscustomobject]@{Id='node-001'},[pscustomobject]@{Id='node-002'},[pscustomobject]@{Id='node-003'},[pscustomobject]@{Id='node-004'},[pscustomobject]@{Id='node-005'})
    )) {
        $rejected = $false
        try { [void](Get-FwProtocolListenerConfiguration $nodes) } catch { $rejected=$true }
        Assert-Protocol $rejected 'Invalid configuration was accepted'
    }
}

Test-ProtocolCase 'Explicit authenticated proxy handles HEAD without target DNS and without body or redirect leakage' {
    $fixture = New-Object FengWoHttpProxyFixture('fixture-loopback-user','fixture-loopback-pass',204,0)
    try {
        $rows = @(Invoke-FwHttpBatch @(Get-FixtureBinding $fixture) @($target) -TimeoutMs 2000)
        Assert-Protocol ($rows.Count -eq 1 -and $rows[0].HttpResponseReceived -and $rows[0].HttpStatus -eq 204 -and $rows[0].Category -eq 'HTTP_RESPONSE') 'HTTP response was not recorded'
        Assert-Protocol ($fixture.AcceptedAuthenticatedRequests -eq 1 -and $fixture.SawHead -and $fixture.SawDiagnosticTarget) 'Request bypassed explicit authenticated proxy'
        $safe = $rows | ConvertTo-Json -Depth 8 -Compress
        foreach ($value in @('fixture-loopback','fixture-query-secret','fixture-response-body-secret','fixture-location-secret','example.invalid')) {
            Assert-Protocol (-not $safe.Contains($value)) 'Probe leaked private request or response data'
        }
        Assert-Protocol ($rows[0].HasRedirectLocation -and $rows[0].ContentClass -eq 'html') 'Header class summary was lost'
    }
    finally { $fixture.Dispose() }
}

Test-ProtocolCase 'HTTP non2xx response is visible and is not diagnosed as blocked TCP' {
    $fixture = New-Object FengWoHttpProxyFixture('fixture-loopback-user','fixture-loopback-pass',404,0)
    try {
        $row = @(Invoke-FwHttpBatch @(Get-FixtureBinding $fixture) @($target) -TimeoutMs 2000)[0]
        Assert-Protocol ($row.HttpResponseReceived -and $row.HttpStatus -eq 404 -and $row.Category -eq 'HTTP_RESPONSE') 'HTTP 404 was treated as transport failure'
    }
    finally { $fixture.Dispose() }
}

Test-ProtocolCase 'Local proxy auth rejection is separate from remote node authentication' {
    $fixture = New-Object FengWoHttpProxyFixture('fixture-loopback-user','fixture-loopback-pass',204,0)
    try {
        $row = @(Invoke-FwHttpBatch @(Get-FixtureBinding $fixture 'node-001' 'wrong-fixture-pass') @($target) -TimeoutMs 2000)[0]
        Assert-Protocol ($row.HttpStatus -eq 407 -and $row.Category -eq 'LOCAL_PROXY_AUTH_FAILURE' -and $fixture.AcceptedAuthenticatedRequests -eq 0) 'Local proxy rejection misclassified'
    }
    finally { $fixture.Dispose() }
}

Test-ProtocolCase 'Request deadlines abort stalled requests and expose no error text' {
    $fixture = New-Object FengWoHttpProxyFixture('fixture-loopback-user','fixture-loopback-pass',204,1400)
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $row = @(Invoke-FwHttpBatch @(Get-FixtureBinding $fixture) @($target) -TimeoutMs 300)[0]
        Assert-Protocol ($row.Category -eq 'REQUEST_DEADLINE' -and -not $row.HttpResponseReceived -and $watch.ElapsedMilliseconds -lt 1300) 'Deadline did not bound stalled proxy request'
    }
    finally { $fixture.Dispose() }
}

Test-ProtocolCase 'Multiple independent nodes and targets remain correctly attributed with RPC polling' {
    $fixtures = @()
    try {
        $bindings = @()
        for ($i=0;$i -lt 4;$i++) {
            $fixture = New-Object FengWoHttpProxyFixture('fixture-loopback-user','fixture-loopback-pass',(200+$i),0)
            $fixtures += $fixture
            $bindings += Get-FixtureBinding $fixture ('node-{0:D3}' -f ($i+1))
        }
        $script:polls=0
        $targets = @($target,[pscustomobject]@{Id='alternate-target';Url='http://example.invalid/second-probe'})
        $rows = @(Invoke-FwHttpBatch $bindings $targets -TimeoutMs 2500 -RpcPoll {$script:polls++;'discard-this-private-rpc-output'})
        Assert-Protocol ($rows.Count -eq 8 -and $script:polls -ge 2) 'Batch or poll outputs were incorrect'
        for ($i=0;$i -lt 4;$i++) {
            $nodeRows = @($rows | Where-Object {$_.NodeId -eq ('node-{0:D3}' -f ($i+1))})
            Assert-Protocol ($nodeRows.Count -eq 2 -and $nodeRows[0].HttpStatus -eq (200+$i) -and $nodeRows[1].HttpStatus -eq (200+$i)) 'Concurrent request routed through another node'
        }
    }
    finally { foreach ($fixture in $fixtures) {$fixture.Dispose()} }
}

Write-Host ('RESULT passed=' + $script:passed + ' failed=' + $script:failures.Count)
foreach ($failure in $script:failures) {Write-Host $failure}
if ($script:failures.Count -gt 0) {exit 1}
