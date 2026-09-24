# Sends zd420-direct-thermal.txt straight to every Zebra ZD420 queue on this PC (raw, bypasses driver rendering).
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class RawPrint {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)] public class DOCINFOA { [MarshalAs(UnmanagedType.LPStr)] public string pDocName; [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile; [MarshalAs(UnmanagedType.LPStr)] public string pDataType; }
  [DllImport("winspool.Drv", EntryPoint="OpenPrinterA", SetLastError=true, CharSet=CharSet.Ansi)] public static extern bool OpenPrinter(string n, out IntPtr h, IntPtr d);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool ClosePrinter(IntPtr h);
  [DllImport("winspool.Drv", EntryPoint="StartDocPrinterA", SetLastError=true, CharSet=CharSet.Ansi)] public static extern bool StartDocPrinter(IntPtr h, int l, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool EndDocPrinter(IntPtr h);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool StartPagePrinter(IntPtr h);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool EndPagePrinter(IntPtr h);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool WritePrinter(IntPtr h, IntPtr b, int c, out int w);
  public static bool Send(string printer, byte[] bytes) {
    IntPtr h; if (!OpenPrinter(printer, out h, IntPtr.Zero)) return false;
    var di = new DOCINFOA { pDocName = "LG ZD420 direct-thermal fix", pDataType = "RAW" };
    bool ok = false; if (StartDocPrinter(h, 1, di)) { if (StartPagePrinter(h)) { IntPtr p = Marshal.AllocCoTaskMem(bytes.Length); Marshal.Copy(bytes, 0, p, bytes.Length); int w; ok = WritePrinter(h, p, bytes.Length, out w); Marshal.FreeCoTaskMem(p); EndPagePrinter(h); } EndDocPrinter(h); }
    ClosePrinter(h); return ok;
  }
}
"@
$zpl = (Invoke-RestMethod 'https://raw.githubusercontent.com/yorkhanna-collab/lg-warehouse-stations/main/zd420-direct-thermal.txt')
$bytes = [Text.Encoding]::ASCII.GetBytes($zpl)
$targets = Get-Printer | Where-Object { $_.Name -match 'ZD420|ZDesigner' }
if (-not $targets) { Write-Host 'No Zebra queue found on this PC' -ForegroundColor Red; return }
foreach ($p in $targets) {
  Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue
  $ok = [RawPrint]::Send($p.Name, $bytes)
  Write-Host ("{0}: {1}" -f $p.Name, $(if ($ok) { 'sent (stuck jobs cleared) - printer should feed labels and go green' } else { 'FAILED to send' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}
