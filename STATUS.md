# STATUS — lg-warehouse-stations

**2026-09-24 (close)** — Right packing station is DONE and confirmed on paper by York ("all good").

## Stations
| tailnet | PC | account | printer | state |
|---|---|---|---|---|
| lg-station-1 100.70.246.71 | DESKTOP-BQ2D6JS (LEFT) | `Lakeside T-Mobile` | ZD420 "ZD420 RIGHT" | working; ghost queue removed; still 3x2 label size |
| lg-station-2 100.85.242.68 | DESKTOP-NC5RQH1 (MIDDLE) | `liquor geeks` | GX420t | working; still 3x2 label size |
| lg-station-3 100.113.86.53 | DESKTOP-UKL2D68 (RIGHT) | `lynci` | ZD420c | **fixed**: direct thermal, sensor calibrated, 4x6 full width, rotated 180, override `^MT,^PO` |

All three: USB/power hardening, Connect watchdog, tailnet (expiry off), SSH + RDP, reports to the mini.
SSH: `ssh -i ~/.ssh/id_ed25519_mini "<account>@<ip>"`. Diagnose any Zebra: `zebra-status.ps1` + ZEBRA-DIAGNOSE.md.

## Open (none blocking)
- York's call: switch LEFT + MIDDLE to full 4x6 too (`set-label-size.ps1` + delete HKCU DevModes2; flip only if their stock needs it).
- Any phone/other browser still set to the middle printer sends labels there; set Print To per device.
- LEFT PC browser: pick "ZD420 RIGHT" in Printing Setup (or drive it with tools-print-from-station.js).
- Stale ShipStation Connect registrations (after hours). All 3 PCs on Wi-Fi ("Air flex"): cable them.
- `lgadmin` account gets created on the next setup re-run. Rotate the tailnet auth key before 2026-12-23.

Resume: `ssh -i ~/.ssh/id_ed25519_mini "lynci@100.113.86.53"` then read ZEBRA-DIAGNOSE.md.
