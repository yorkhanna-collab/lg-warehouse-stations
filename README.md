# LG warehouse packing stations

Setup + hardening for the three Windows packing PCs at the Liquor Geeks warehouse
(ShipStation Connect → Zebra label printers). One script, run once per PC, safe to re-run.

## Run it (on each packing PC)

1. Log in to the PC as the account the packers use.
2. Start → type `powershell` → right-click **Windows PowerShell** → **Run as administrator**.
3. Paste the one-liner York sends you (it contains a join key, so it is not written here), press Enter.
4. Wait for `DONE on DESKTOP-…`. Unplug and re-plug the Zebra's USB cable once.
5. If it printed a line starting with `[TODO] connect`, open ShipStation Connect from the Start menu and sign in with that station's ShipStation login.

The one-liner has this shape (the key and station number differ per PC):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; & ([scriptblock]::Create((irm https://raw.githubusercontent.com/yorkhanna-collab/lg-warehouse-stations/main/station-setup.ps1))) -TsKey 'tskey-auth-…' -Station 1
```

Station numbers: `1` = DESKTOP-NC5RQH1 (GX420t), `2` = DESKTOP-BQ2D6JS (two ZD420s), `3` = DESKTOP-UKL2D68 (ZD420 300dpi).
Wrong number is harmless; it only sets the tailnet name.

`-ReportOnly` inventories without changing anything. `-SkipTailscale`, `-SkipSsh`, `-SkipRdp` exist.

## What it changes and why

| Area | Change | Why the Zebra "disconnects" |
|---|---|---|
| Power | Never sleep/hibernate on AC, Fast Startup off, USB selective suspend off | Windows powers the USB port down after idle; the printer drops off and comes back as a *new* queue |
| Power | "Allow the computer to turn off this device" off on every USB hub and the Zebra | Same, at device level (the tick box in Device Manager, done for every hub at once) |
| Power | Zebra Enhanced Power Management off (`EnhancedPowerManagementEnabled=0`) | Zebra's own KB fix for printers that go offline after a pause |
| Printing | Spooler auto-restarts on crash; "Let Windows manage my default printer" off | A hung spooler or a swapped default sends labels to the wrong/no printer |
| Printing | Zebra queues taken out of "Use Printer Offline"; ghost `(Copy N)` queues reported | ShipStation Connect keeps pointing at the old queue name |
| Connect | Installed if missing, auto-start at logon, 5-minute watchdog task `LG-ConnectWatchdog` | Connect quietly dies → workstation shows "No Printers connected" in ShipStation |
| Remote | Tailscale (`lg-station-N`), OpenSSH server, Remote Desktop, all firewall-scoped to the tailnet + LAN | So the rest gets fixed from York's Mac without anyone at the station |

Output: `C:\LG\station-report.json` (before/after inventory), `C:\LG\station-setup-<time>.log`, `C:\LG\watchdog.log`.

## After the script

From the Mac: `ssh Administrator@lg-station-1` (or whichever account ran it) lands in PowerShell.
Remote Desktop: Windows App → `lg-station-1`.

Remaining manual/remote work is tracked in the project memory `project_lg_warehouse_stations`.

## Adding a new packing PC (done for station 4, CALAKM01, 2026-10-19)
1. Find it: the AT&T gateway lists every device with its hostname at `http://192.168.1.254/cgi-bin/devices.ha`
   (needs the session cookie from `/cgi-bin/home.ha` first). A fresh Windows PC answers nothing on TCP, so this
   is the only way to spot it. `nbtstat -A <ip>` from any station confirms it is Windows.
2. Mint a one-off auth key at console.tailscale.com/admin/settings/keys (GitHub sign-in as yorkhanna-collab):
   not reusable, 1–2 days, no tags. Keys from an OAuth client would be tagged and fall outside the stations' ACL.
3. Paste on the PC (admin PowerShell): the one-liner above with `-TsKey '<key>' -Station <N>`.
   The script joins the tailnet as `lg-station-N`, installs SSH keys + RDP, hardens USB/power, installs
   ShipStation Connect, and POSTs its report to the mini (`~/lg-station-reports/<COMPUTER>-latest.json`,
   which carries the account name to SSH in as).
4. Printers, over SSH once it has joined: copy a tar of another station's ZDesigner DriverStore folder to
   `C:\LG\zdesigner.tar` (`tar.exe -cf C:\LG\zdesigner.tar -C C:\WINDOWS\System32\DriverStore\FileRepository\zdesigner.inf_amd64_* .`),
   then run `printers-install.ps1`. It stages the Zebra driver and adds the shared HP/Epson printers as IPP
   queues by mDNS name; anything asleep is retried by the `LG-PrinterInstall` task. The mini's
   `~/lg-station-reports/post-join-lg-station-4.sh` is the automated version of this step.
5. Disable key expiry for the new node in the console (Machines → … → Disable key expiry), then sign ShipStation
   Connect in on the PC with the station's ShipStation login so its Zebra shows up under Settings → Printing.
