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
