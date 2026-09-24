# Send raw ZPL/SGD to a printer queue, bypassing the driver.  Usage (on the station):
#   .\send-zpl.ps1 -Printer 'ZDesigner ZD420-300dpi ZPL' -Zpl '~WC'
# or from irm:  & ([scriptblock]::Create((irm <raw url>))) -Printer '...' -Zpl '...'
param([Parameter(Mandatory)][string]$Printer, [Parameter(Mandatory)][string]$Zpl)
if (-not ('RawPrint' -as [type])) {
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
    var di = new DOCINFOA { pDocName = "LG raw ZPL", pDataType = "RAW" };
    bool ok = false; if (StartDocPrinter(h, 1, di)) { if (StartPagePrinter(h)) { IntPtr p = Marshal.AllocCoTaskMem(bytes.Length); Marshal.Copy(bytes, 0, p, bytes.Length); int w; ok = WritePrinter(h, p, bytes.Length, out w); Marshal.FreeCoTaskMem(p); EndPagePrinter(h); } EndDocPrinter(h); }
    ClosePrinter(h); return ok;
  }
}
"@
}
$ok = [RawPrint]::Send($Printer, [Text.Encoding]::ASCII.GetBytes($Zpl + "`r`n"))
Write-Output ("{0}: {1}" -f $Printer, $(if ($ok) { 'sent' } else { 'FAILED' }))
