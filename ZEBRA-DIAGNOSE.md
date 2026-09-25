# Diagnosing a Zebra that "says printing but nothing comes out"

**Read the printer before touching anything.** `zebra-status.ps1` opens the Zebra's USB interface directly
(bypassing the Windows spooler, which does not pass replies back on USB) and reads real answers.

Run on the station (over SSH):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
$c = @(
  @{c='~HQES'; w=1500},
  @{c='! U1 getvar "media.status"'; w=900},
  @{c='! U1 getvar "head.latch"'; w=900},
  @{c='! U1 getvar "ezpl.print_method"'; w=900},
  @{c='! U1 getvar "device.command_override.list"'; w=900}
) | ConvertTo-Json -Compress
& .\zebra-status.ps1 -CmdsB64 ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($c)))
```

## Decode `~HQES` ERRORS (last 8 hex digits, rightmost nibble first)
| nibble (from right) | bit 1 | bit 2 | bit 4 | bit 8 |
|---|---|---|---|---|
| 1 | Media out | Ribbon out | Head open | Cutter fault |
| 2 | Head over-temp | Motor over-temp | Bad head element | Head detect error |
| 3 | Invalid firmware cfg | Head thermistor open | | |
| 4 | Paper jam (retract) | Presenter not running | Paper feed error | Clear path failed |
| 5 | **Paused** | Retract timed out | Black mark cal error | Black mark not found |

`00010001` = Media out + Paused. `00000000` = healthy.

## Fixes that are proven (right-PC ZD420c, 2026-09-24)
- **media.status "out" with head.latch "ok"** → label sensor mis-calibrated. `~JC` (calibrate) then `~PS` (resume).
  Resume only AFTER calibrate, or it stays Paused.
- **Cartridge model (ZD420c) with no cartridge** → `! U1 setvar "ezpl.print_method" "direct thermal"` plus
  `device.command_override.add "^MT"` + `.active "yes"`, so the driver's per-job `^MTT` cannot flip it back.
- **Stuck replies / "no reply" to everything** → a previous query process is still holding the USB handle.
  Find and kill stray `powershell` running `zebra-status`/`zusb`.

## Gotcha
Only one process can read the Zebra's USB at a time. Never leave a query hanging.

## "Nothing printed" — find where the job actually went first
ShipStation sends each label to the workstation + printer chosen in the **sending browser's** Print To
(localStorage `v3-<acct>.shipstation.printSettings`, per browser, per machine). A label printed from a phone or
another PC goes to whatever THAT browser is set to. Before touching a printer, list what each station's Connect
received: `%LocalAppData%\Temp\ShipStation Connect\*.pdf` timestamps on all three PCs. 9/24: three "nothing
printed" attempts had landed on the middle GX420t from a device still set to the middle printer.

## Label size (label printed as a small box on 4x6 stock)
Every ZDesigner queue here defaulted to a 3.00" x 2.00" page (`dmPaperWidth 762 / dmPaperLength 508`), so the driver
shrank ShipStation's ~4.86x6.25in label to fit 3x2. Fix per queue:
`set-label-size.ps1 -Printer '<queue>' -WidthTenthMm 1016 -LengthTenthMm 1524` (DocumentProperties so the driver
merges its private data, then SetPrinter level 8). Then **delete `HKCU:\Printers\DevModes2\<queue>`** — Connect runs as
the user and a stale per-user 3x2 silently wins. Verify in the stream log: `^PW1200 ^LL1800`.
Width is the limit on 4" stock: the WeShip PDF is wider in proportion than 4x6, so it fills the width at ~82% and
leaves ~1" at the bottom. That is the maximum size without cropping the sides.

## Rotate 180
`! U1 setvar "device.command_override.add" "^PO"` + `.active "yes"`, then `! U1 setvar "zpl.print_orientation" "inv"`.
The override is required because the driver sends `^PON` on every job. Undo: `zpl.print_orientation "nor"`.
Current right-PC override list: `^MT,^PO`.

## Driving a station's own browser (to print "from that computer")
Chrome 154 ignores `--remote-debugging-port` on the default profile. As the station user (scheduled task,
Interactive): kill Chrome, robocopy `User Data\Default` + `Local State` to `C:\LG\cp`, relaunch the crew's Chrome
normally, then launch a second Chrome with `--user-data-dir=C:\LG\cp --remote-debugging-port=9223`; `ssh -L 9223`
and drive it with `tools-print-from-station.js` (aborts unless exactly 1 row is selected and the destination is the
expected printer). The Shipments grid's FIRST checkbox is select-all (500 rows) — never click it. **Delete `C:\LG\cp`
afterwards: it holds a logged-in session cookie.**
