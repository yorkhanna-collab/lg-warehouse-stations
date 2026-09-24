# STATUS — lg-warehouse-stations

**2026-09-24 (late)** — Remote admin access LIVE on all 3 stations. Ghost queue removed. ZD420 reset sent.

Station map (tailnet name ≠ runbook number — crew pasted lines on different PCs):
- lg-station-1 100.70.246.71 = DESKTOP-BQ2D6JS, account `Lakeside T-Mobile`, ZD420 RIGHT (USB001). LEFT printer not attached here.
- lg-station-2 100.85.242.68 = DESKTOP-NC5RQH1, account `liquor geeks`, GX420t. Healthy.
- lg-station-3 100.113.86.53 = DESKTOP-UKL2D68, account `lynci`, ZD420-300dpi (the "right" PC). Direct-thermal reset sent.
SSH: `ssh -i ~/.ssh/id_ed25519_mini "<account>@<ip>"`. Reports: mini `~/lg-station-reports/*-latest.json`.

Done today: USB/power/EPM hardening + Connect watchdog on all 3; tailnet join, key expiry disabled; SSH+RDP;
BQ2D6JS ghost "ZD420-203dpi" queue deleted (18 dead jobs), default → ZD420 RIGHT; UKL2D68 ZD420 direct-thermal config sent.

Right ZD420 FULLY FIXED 9/24 15:13 incl. ShipStation path (driver 10.6 + PI_StatusCheckType 0 + printer command_override ^MT; see memory). Open: crew picks "ZD420 RIGHT" in ShipStation Printing Setup on BQ2D6JS;
where is the LEFT ZD420 now; stale Connect registrations (after hours); all 3 on Wi-Fi → cable them; lgadmin gets
created on next re-run (not urgent). Auth key stays valid (rotate before 2026-12-23).

Resume: `ssh -i ~/.ssh/id_ed25519_mini "lynci@100.113.86.53"`
