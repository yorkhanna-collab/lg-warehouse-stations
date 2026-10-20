# STATUS — lg-warehouse-stations

**2026-10-19 18:08 PT — 4th packing PC DONE: `lg-station-4` = CALAKM01 (100.110.89.38, LAN 192.168.1.190, Wi-Fi "Air flex", Windows 10 Pro 22H2, account `LP Telecom`).**
York pasted the one-liner 17:59; joined 18:01; key expiry disabled in the console 18:06. Verified over SSH 18:08: sshd Running/Automatic
(laptop + mini keys, `lgadmin` created), RDP on, Tailscale 1.104.1, power/USB hardening applied, `LG-ConnectWatchdog` + `LG-PrinterInstall` Ready.
- **Printers:** ZDesigner 10.6.12 driver staged with pnputil + ZD420 203/300 dpi drivers pre-added (no Zebra is plugged in yet; it binds on plug-in).
  Epson XP-15000 `EPSONEACE23` was already there as a WSD queue and is now the default. HP OfficeJet Pro 9130e, HP Color LaserJet M283cdw and
  HP LaserJet M209dw were asleep/off, so `LG-PrinterInstall` (logon + every 30 min) adds them as IPP queues when they answer and then removes itself.
  Cleaned out of the old office image: "HP LaserJet MFP M426fdw" (PendingDeletion, 6 stuck jobs) and the USB "HP OfficeJet Pro 8020" (printer not
  attached). The WSD `HPBC0742 (HP OfficeJet Pro 8020)` queue was left (offline, harmless).
- **ShipStation Connect:** installer 5.x went per-machine to `C:\Program Files\ShipStation Connect` (the script expected the per-user Squirrel path and
  logged a false WARN); it is running, HKCU Run key added, and the watchdog already checks the Program Files path. **Still needs a one-time
  sign-in on the PC with the station's ShipStation login** so its Zebra appears under Settings → Printing → ShipStation Connect.
- **Lesson:** the mini watcher never fired: the mini has no Tailscale CLI at `/Applications/Tailscale.app/Contents/MacOS/Tailscale` (it runs a
  different Tailscale build). The post-join steps were run from the laptop instead (`-F` ssh config with `User "LP Telecom"`; scp cannot take a
  user with a space inline). Next time: trigger off the report file alone, or find the mini's tailscale binary first.

## What was wrong, and what fixed it (9/24 – 10/12)
The "disconnects" were never the printers. Two things caused them: Windows USB power management, and per-user ShipStation
Connect re-activations that left duplicate registrations and ghost queues. `station-setup.ps1` was run once per PC and
re-run once more. It hardened power/USB/spooler/default-printer behaviour, installed the `LG-ConnectWatchdog` task, and
joined each PC to the tailnet with SSH + RDP. The right ZD420 also had a printer-side fault: a ZD420c saved in ribbon mode
with no cartridge, plus an uncalibrated label sensor. Fixed via SGD; see ZEBRA-DIAGNOSE.md.

## Stations, verified 2026-10-12 17:19 PT
| tailnet | PC | account | printer(s) | labels last 7d | state |
|---|---|---|---|---|---|
| lg-station-1 100.70.246.71 | DESKTOP-BQ2D6JS (LEFT) | `Lakeside T-Mobile` | TWO ZD420c: 50J194903190 = queue "ZD420 RIGHT" (USB001), 50J194906607 = queue "ZD420 LEFT" (USB002) | 163 (156 "ZD420 RIGHT", 7 "ZD420 LEFT"), 28 today | working; 3x2 label size |
| lg-station-2 100.85.242.68 | DESKTOP-NC5RQH1 (MIDDLE) | `liquor geeks` | GK420t 29J215301686 (queue name "ZDesigner GX420t") | 30 Connect PDFs, last 10/8 (this PC's PrintService/Operational log is off, so no event-307 count) | working, lightly used; 3x2 label size |
| lg-station-3 100.113.86.53 | DESKTOP-UKL2D68 (RIGHT) | `lynci` | ZD420c 50J201201727 | 338, 18 today | **fixed**: direct thermal, sensor calibrated, 4x6 full width, rotated 180, override `^MT,^PO` |
| lg-station-4 100.110.89.38 | CALAKM01 (NEW 10/19) | `LP Telecom` | none yet (ZDesigner driver staged); Epson XP-15000 default; HPs pending via LG-PrinterInstall | — | joined 10/19 18:01; Connect installed, not signed in |

All three: queues Normal, 0 stuck jobs, 0 PrintService/Admin errors since 9/25, and Connect is running.
`LG-ConnectWatchdog` has **both triggers** (at-logon + a 5-min clock trigger) on all three and last ran 0x0. The clock trigger
was added on the LEFT PC 10/12 09:00 and on MIDDLE + RIGHT 10/12 17:20, so they match `station-setup.ps1`.
`C:\LG\watchdog.log` does not exist on any station, which means the watchdog has never had to restart Connect or clear an
offline flag. Tailscale 1.102.4 on all three; node key expiry is off. All three connect over Wi-Fi "Air flex".

**Tailnet reach:** the stations' packet filter (`tailscale debug netmap`) admits only yorkhanna-collab@ nodes: the 3 stations,
macmini, macbook-pro-4, iphone181, yorks-pc and lorends-mac-mini-2. **Bern's `laptop-jo95hkts` (bern@, 100.79.190.59) is on
the tailnet but cannot reach the stations.**

## How to work on it
- SSH from the mini: `ssh -i ~/.ssh/id_ed25519 "<account>@<ip>"`. From the laptop, use `-i ~/.ssh/id_ed25519_mini`. Either way
  you land in PowerShell as admin. From a /today sandbox, go through the proxy with ncat; the recipe is in the memory
  `project_lg_warehouse_stations`.
- Any printer complaint: open ShipStation `/settings/connect` first to see which workstation is offline. Then run
  `zebra-status.ps1` on that station (`-Serial` on the two-printer LEFT PC), read ZEBRA-DIAGNOSE.md, and check
  `C:\LG\watchdog.log`. To find a lost print, list each station's `%LocalAppData%\Temp\ShipStation Connect\*.pdf`.
- Never deactivate a live Connect workstation mid-shift. Re-activating one needs a ShipStation sign-in on that PC.
- New or re-imaged PC: mint a one-off auth key at console.tailscale.com/admin/settings/keys (GitHub sign-in) and pass it as
  `-TsKey` to the one-liner in README.md. The reusable 9/24 key was **revoked 2026-10-10**. A re-run on a station that is
  already joined skips `tailscale up`, so it needs no key.

## Printer network options (read off the printers 2026-10-12)
All three ZD420s are the same part, **ZD42043-C01W018N**: ZD420c, 300 dpi, USB + USB Host, factory **802.11ac Wi-Fi + Bluetooth 4.1**,
**no Ethernet** (`internal_wired.mac_addr` = 00:00:00:00:00:00). None has a ribbon cartridge, and all are saved as direct thermal.
Wi-Fi is present but not joined. The GK420t has no print server.
- **Ethernet** = Zebra field kit **P1080383-442**, ~$132–163 each (Zebra lists it as discontinued). Not bought, and not needed so far.
- **Free alternative if disconnects come back:** join the built-in Wi-Fi to "Air flex". That takes the `wlan.essid` + security
  SGDs, then `device.reset`, so it is after hours only. Then add a Standard TCP/IP port 9100 queue under the SAME queue name,
  so Connect's printer id still matches.

## Optional, nothing blocking
- ~~Stale Connect registrations~~ **DONE 2026-10-12 18:34 PT**: all 7 deactivated in ShipStation `/settings/connect` (F04617U ×2,
  GAAQTQN ×2, BQ2D6JS dup `e3980d84`, Ronees-MBP, MacBook-Pro-2). `/api/seller/workstations` now lists exactly the 3 live
  stations: NC5RQH1 `30c4ccf9`, BQ2D6JS `7ee07952` (Mathew), UKL2D68 `0b8313fe` (Iker). Their Zebra queues (GX420t, ZD420
  LEFT/RIGHT, ZD420-300dpi) are still Shared, not Disabled. A PC comes back by signing into Connect on it.
  Trap: the page's Deactivate button has no confirm dialog, and a Playwright ref click is resolved as `.first()` button on the
  page, which after two removals is the LIVE NC5RQH1 card. Match each card by name + "Activated by" owner, never by position.
- York's call: switch LEFT + MIDDLE to full 4x6 too (`set-label-size.ps1` + delete HKCU DevModes2; flip only if their stock
  needs it). Today's small labels scan fine.
- Durable network: run a cable to each PC (all on Wi-Fi). Only worth it if disconnects return.
- `lgadmin` does not exist on any station; the next setup re-run creates it. Not needed: each packer account is an admin.
- Any phone or other browser whose ShipStation Print To is still set to the middle printer will send labels there. Set Print To
  per device (`tools-set-shipstation-print-to.js` works for a station's own browser).

Resume: `cd ~/projects/lg-warehouse-stations && cat STATUS.md`, then SSH to the station in question (table above).
