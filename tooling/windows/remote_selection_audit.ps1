$ErrorActionPreference = 'Stop'
if (-not ('FengWoSelectionAudit' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class FengWoSelectionAudit {
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] filename, out IntPtr database, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr database, byte[] sql, int length, out IntPtr statement, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr statement);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern long sqlite3_column_int64(IntPtr statement, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr statement, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr statement, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr statement);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr database);
    public sealed class Selection { public long Id; public string Group; public string SelectedMap; }
    static string Text(IntPtr statement, int column) {
        IntPtr value=sqlite3_column_text(statement,column);
        if(value==IntPtr.Zero) return null;
        byte[] bytes=new byte[sqlite3_column_bytes(statement,column)];
        Marshal.Copy(value,bytes,0,bytes.Length);
        return Encoding.UTF8.GetString(bytes);
    }
    public static Selection[] Read(string path) {
        IntPtr database;
        int opened=sqlite3_open_v2(Encoding.UTF8.GetBytes(path+"\0"),out database,1,IntPtr.Zero);
        try {
            if(opened!=0) throw new InvalidOperationException("Read-only selection database open failed: "+opened);
            byte[] sql=Encoding.UTF8.GetBytes("SELECT id,current_group_name,selected_map FROM profiles ORDER BY id\0");
            IntPtr statement;
            int prepared=sqlite3_prepare_v2(database,sql,sql.Length,out statement,IntPtr.Zero);
            if(prepared!=0) throw new InvalidOperationException("Selection query failed: "+prepared);
            try {
                List<Selection> rows=new List<Selection>();
                int result;
                while((result=sqlite3_step(statement))==100)
                    rows.Add(new Selection { Id=sqlite3_column_int64(statement,0),Group=Text(statement,1),SelectedMap=Text(statement,2) });
                if(result!=101) throw new InvalidOperationException("Selection query step failed: "+result);
                return rows.ToArray();
            } finally { sqlite3_finalize(statement); }
        } finally { if(database!=IntPtr.Zero) sqlite3_close(database); }
    }
}
'@
}
function Save-FengWoSelection([string]$Phase) {
    if ($Phase -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid selection audit phase' }
    $records = @(Get-ChildItem (Join-Path $env:APPDATA 'FengWo') -Filter database.sqlite -Recurse | ForEach-Object { [FengWoSelectionAudit]::Read($_.FullName) })
    $records | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $script:AuditRoot ($Phase+'-selections.json'))
    Write-Output ('SELECTION_AUDIT '+$Phase+' Profiles='+$records.Count)
}
Save-FengWoSelection 'candidate-111-cache-entry'
