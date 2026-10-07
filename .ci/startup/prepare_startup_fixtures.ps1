param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The .NET Framework C# compiler was not found' }
[void](New-Item -ItemType Directory -Force -Path $OutputDirectory)

foreach ($kind in @('window', 'headless', 'exit', 'dllmissing', 'badimage')) {
    $directory = Join-Path $OutputDirectory $kind
    [void](New-Item -ItemType Directory -Force -Path $directory)
    $sourcePath = Join-Path $directory 'FengWo.cs'
    $source = @"
using System;
using System.Threading;
using System.Windows.Forms;
public static class Program
{
    [STAThread]
    public static int Main()
    {
        string kind = "$kind";
        if (kind == "dllmissing") return unchecked((int)0xC0000135);
        if (kind == "badimage") return unchecked((int)0xC000007B);
        if (kind == "exit")
        {
            Console.Error.WriteLine("Synthetic startup fixture exits with 23");
            return 23;
        }
        if (kind == "headless")
        {
            Thread.Sleep(300000);
            return 0;
        }
        Application.EnableVisualStyles();
        Application.Run(new Form { Text = "蜂窝加速器 Fixture", Width = 480, Height = 240 });
        return 0;
    }
}
"@
    [IO.File]::WriteAllText($sourcePath, $source, [Text.UTF8Encoding]::new($true))
    $executable = Join-Path $directory 'FengWo.exe'
    & $compiler /nologo /target:winexe /platform:x64 "/out:$executable" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $sourcePath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Fixture compilation failed: $kind" }
}
