param([string]$Printer, [int]$WidthTenthMm, [int]$LengthTenthMm)
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class Paper {
  [StructLayout(LayoutKind.Sequential)] public struct PRINTER_DEFAULTS { public IntPtr pDatatype; public IntPtr pDevMode; public int DesiredAccess; }
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool OpenPrinterW(string n, out IntPtr h, ref PRINTER_DEFAULTS d);
  [DllImport("winspool.drv", SetLastError=true)] static extern bool ClosePrinter(IntPtr h);
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)] static extern int DocumentPropertiesW(IntPtr hwnd, IntPtr h, string n, IntPtr outDm, IntPtr inDm, int mode);
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool SetPrinterW(IntPtr h, int level, IntPtr info, int cmd);
  public static string Set(string name, short w, short l) {
    var pd = new PRINTER_DEFAULTS(); pd.DesiredAccess = 0x000F000C; // PRINTER_ALL_ACCESS
    IntPtr h; if (!OpenPrinterW(name, out h, ref pd)) return "OPENFAIL " + Marshal.GetLastWin32Error();
    int sz = DocumentPropertiesW(IntPtr.Zero, h, name, IntPtr.Zero, IntPtr.Zero, 0);
    if (sz <= 0) { ClosePrinter(h); return "SIZEFAIL"; }
    IntPtr cur = Marshal.AllocHGlobal(sz); IntPtr nxt = Marshal.AllocHGlobal(sz);
    DocumentPropertiesW(IntPtr.Zero, h, name, cur, IntPtr.Zero, 2); // DM_OUT_BUFFER
    string before = "before " + Marshal.ReadInt16(cur, 82) + "x" + Marshal.ReadInt16(cur, 80);
    int f = Marshal.ReadInt32(cur, 72) | 0x2 | 0x4 | 0x8; Marshal.WriteInt32(cur, 72, f);
    Marshal.WriteInt16(cur, 78, 256); Marshal.WriteInt16(cur, 80, l); Marshal.WriteInt16(cur, 82, w);
    int r = DocumentPropertiesW(IntPtr.Zero, h, name, nxt, cur, 2 | 8); // driver validates + merges private data
    string after = "after " + Marshal.ReadInt16(nxt, 82) + "x" + Marshal.ReadInt16(nxt, 80) + " (driver rc=" + r + ")";
    IntPtr info = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(info, nxt);
    bool g = SetPrinterW(h, 8, info, 0); int ge = Marshal.GetLastWin32Error(); // global default
    bool u = SetPrinterW(h, 9, info, 0); int ue = Marshal.GetLastWin32Error(); // per-user default
    Marshal.FreeHGlobal(info); Marshal.FreeHGlobal(cur); Marshal.FreeHGlobal(nxt); ClosePrinter(h);
    return before + " | " + after + " | global=" + g + (g ? "" : "(" + ge + ")") + " user=" + u + (u ? "" : "(" + ue + ")");
  }
}
"@
[Paper]::Set($Printer, [int16]$WidthTenthMm, [int16]$LengthTenthMm)
