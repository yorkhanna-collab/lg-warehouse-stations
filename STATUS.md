# STATUS — lg-warehouse-stations

**2026-10-12** — ZD420 Ethernet option confirmed: none of the printers has it (details below); LEFT PC watchdog was never running, now fixed.
**2026-09-24 (close)** — Right packing station is DONE and confirmed on paper by York ("all good").

## Stations
| tailnet | PC | account | printer | state |
|---|---|---|---|---|
| lg-station-1 100.70.246.71 | DESKTOP-BQ2D6JS (LEFT) | `Lakeside T-Mobile` | TWO ZD420c: 50J194903190 = queue "ZD420 RIGHT" (USB001), 50J194906607 = queue "ZD420 LEFT" (USB002, plugged back in since 9/24) | working; ghost queue removed; still 3x2 label size |
| lg-station-2 100.85.242.68 | DESKTOP-NC5RQH1 (MIDDLE) | `liquor geeks` | GK420t 29J215301686 (queue uses the GX420t driver name; firmware `~HI` says GK420t-200dpi V61.17.17Z) | working; still 3x2 label size |
| lg-station-3 100.113.86.53 | DESKTOP-UKL2D68 (RIGHT) | `lynci` | ZD420c 50J201201727 | **fixed**: direct thermal, sensor calibrated, 4x6 full width, rotated 180, override `^MT,^PO` |

All three: USB/power hardening, Connect watchdog, tailnet (expiry off), SSH + RDP, reports to the mini.
SSH: `ssh -i ~/.ssh/id_ed25519_mini "<account>@<ip>"` from the laptop, `-i ~/.ssh/id_ed25519` from the mini. Diagnose any Zebra: `zebra-status.ps1` (`-Serial` picks one printer on the two-printer LEFT PC) + ZEBRA-DIAGNOSE.md.

## Printer network options (read off the printers 2026-10-12)
All three ZD420s are the same part, **ZD42043-C01W018N**: ZD420c, 300 dpi, USB + USB Host, factory **802.11ac Wi-Fi + Bluetooth 4.1**,
**no Ethernet** (`internal_wired.mac_addr` = 00:00:00:00:00:00). None has a ribbon cartridge (`ribbon.cartridge.authenticated` = not installed); all are
saved direct thermal. Wi-Fi is present but not joined (`wlan.associated` no). The GK420t has no print server either.
- **Ethernet** = Zebra field kit **P1080383-442** (10/100 module for the ZD420c/d/t and ZD410, installs in the printer's connectivity slot). Zebra lists it discontinued; resellers still
  carry it at ~$132–163 each (Barcodes Inc lists $162.70). Not bought.
- **Free alternative:** join the built-in Wi-Fi to "Air flex" (`wlan.essid` + security SGDs, then `device.reset`, so after hours only) and add a
  Standard TCP/IP port 9100 queue under the SAME queue name so Connect's printer id still matches.
- **Evidence it isn't needed now:** no PrintService/Admin errors on any station since 9/25, and on the middle + right PCs the watchdog ran every
  5 min for 13+ days without once restarting Connect or clearing an offline flag (`C:\LG\watchdog.log` is written only when it acts, and it doesn't exist).
- **Watchdog fix 10/12:** on the LEFT PC `LG-ConnectWatchdog` had NEVER run (0x41303). Its only trigger was at-logon and that PC has been logged in since
  9/23 16:38, before setup. Re-registered with an added clock trigger (every 5 min); first run 08:57:57 → 0x0. `station-setup.ps1` now registers both triggers.

## Open (none blocking)
- York's call: switch LEFT + MIDDLE to full 4x6 too (`set-label-size.ps1` + delete HKCU DevModes2; flip only if their stock needs it).
- Any phone/other browser still set to the middle printer sends labels there; set Print To per device.
- LEFT PC browser: pick "ZD420 RIGHT" in Printing Setup (or drive it with tools-print-from-station.js).
- Stale ShipStation Connect registrations (after hours). All 3 PCs on Wi-Fi ("Air flex"): cable them.
- `lgadmin` account gets created on the next setup re-run.
- Tailnet auth key: the reusable 9/24 key (kRaNXzEydd11CNTRL) was REVOKED 2026-10-10 after all 3 stations joined; they stay on the tailnet (revoking never deauthorizes a joined node; node key expiry is off). To join a new or re-imaged PC, generate a one-off key at console.tailscale.com/admin/settings/keys and pass it as `-TsKey`. A re-run on an already-joined station skips `tailscale up`, so it needs no key.

Resume: `ssh -i ~/.ssh/id_ed25519_mini "lynci@100.113.86.53"` then read ZEBRA-DIAGNOSE.md.
