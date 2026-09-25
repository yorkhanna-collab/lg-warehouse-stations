param([string]$CmdsB64)
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Threading; using Microsoft.Win32.SafeHandles;
public class ZUsb2 {
  static Guid USBPRINT = new Guid("28d78fad-5a12-11d1-ae5b-0000f803a8c2");
  [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
  [DllImport("setupapi.dll", SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr w, int f);
  [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref SP_DEVICE_INTERFACE_DATA did);
  [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Auto)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA did, IntPtr det, int sz, out int req, IntPtr dev);
  [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)] static extern SafeFileHandle CreateFile(string n, uint a, uint sh, IntPtr sa, uint cd, uint fl, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteFile(SafeFileHandle h, byte[] b, int n, out int w, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadFile(SafeFileHandle h, byte[] b, int n, out int r, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CancelIoEx(SafeFileHandle h, IntPtr o);
  public static string Path() {
    var g = USBPRINT; string found = null;
    IntPtr s = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);
    for (int i = 0; ; i++) {
      var did = new SP_DEVICE_INTERFACE_DATA(); did.cbSize = Marshal.SizeOf(did);
      if (!SetupDiEnumDeviceInterfaces(s, IntPtr.Zero, ref g, i, ref did)) break;
      int req; SetupDiGetDeviceInterfaceDetail(s, ref did, IntPtr.Zero, 0, out req, IntPtr.Zero);
      IntPtr det = Marshal.AllocHGlobal(req); Marshal.WriteInt32(det, IntPtr.Size == 8 ? 8 : 6);
      if (SetupDiGetDeviceInterfaceDetail(s, ref did, det, req, out req, IntPtr.Zero)) { string p = Marshal.PtrToStringAuto(new IntPtr(det.ToInt64() + 4)); if (p.ToLower().Contains("vid_0a5f")) found = p; }
      Marshal.FreeHGlobal(det);
    }
    SetupDiDestroyDeviceInfoList(s); return found;
  }
  static SafeFileHandle H;
  public static bool Open(string p) { H = CreateFile(p, 0xC0000000, 0x3, IntPtr.Zero, 3, 0, IntPtr.Zero); return !H.IsInvalid; }
  public static void Close() { if (H != null) H.Close(); }
  // read with timeout: a worker thread does blocking ReadFile; we cancel it after ms
  public static string ReadFor(int ms) {
    var sb = new StringBuilder(); bool done = false;
    var t = new Thread(() => { byte[] b = new byte[8192]; int r; while (!done) { if (ReadFile(H, b, b.Length, out r, IntPtr.Zero) && r > 0) lock (sb) sb.Append(Encoding.ASCII.GetString(b, 0, r)); else break; } });
    t.IsBackground = true; t.Start();
    t.Join(ms); done = true; CancelIoEx(H, IntPtr.Zero); t.Join(500);
    lock (sb) return sb.ToString();
  }
  public static string Send(string cmd, int ms) {
    ReadFor(250); // drain anything stale so replies map to this command
    byte[] wb = Encoding.ASCII.GetBytes(cmd); int w; WriteFile(H, wb, wb.Length, out w, IntPtr.Zero);
    return ReadFor(ms);
  }
}
"@
$cmds = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($CmdsB64)) | ConvertFrom-Json
$p = [ZUsb2]::Path(); if (-not $p) { "NO ZEBRA USB"; return }
if (-not [ZUsb2]::Open($p)) { "OPENFAIL"; return }
foreach ($c in $cmds) {
  $wait = 1200; if ($c.w) { $wait = [int]$c.w }
  $r = [ZUsb2]::Send(($c.c + "`r`n"), $wait)
  "[$($c.c)] => " + ($(if ($r) { ($r -replace "`r","" -replace "`n"," | ").Trim() } else { "(no reply)" }))
}
[ZUsb2]::Close()
