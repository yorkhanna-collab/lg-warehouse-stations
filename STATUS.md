# STATUS — lg-warehouse-stations

**2026-09-24** — Core repair LIVE on all 3 stations. SSH access pending one re-run each.

## Done (applied on all 3 during first run)
- USB selective suspend off, per-hub/device power management off, Zebra Enhanced Power
  Management off, never-sleep, Fast Startup off, spooler auto-restart, default-printer lock,
  Zebra queues out of "Use Printer Offline", ShipStation Connect watchdog task (5 min).
- All 3 joined the tailnet: lg-station-1 (DESKTOP-NC5RQH1), lg-station-2 (DESKTOP-BQ2D6JS),
  lg-station-3 (DESKTOP-UKL2D68).
- ShipStation Connect: the 3 real stations are already **Shared** (any login can print).

## Pending
- SSH: first run authorized only admins; packer login is a standard `User`, so my key was
  denied. Fixed in c5ad1b5 (also writes each local user's authorized_keys). Needs ONE re-run
  of the same one-liner per PC for me to get in. station-2's sshd is up; 1 & 3 were still
  installing OpenSSH when probed.
- Stale Connect registrations (F04617U x2, GAAQTQN x2, BQ2D6JS dup, 2 Macs): harmless clutter.
  Deactivation needs a re-activation sign-in, and two belong to Mathew/Iker — do after hours
  or during the SSH pass, never mid-shift.
- Auth key `~/.config/liquorgeeks/tailscale-warehouse-authkey.env` — revoke after SSH re-run pass.

## Next (once a station is re-run and SSH works)
ssh User@<tailscale ip>  -> read C:\LG\station-report.json ; on BQ2D6JS resolve the 3rd
"ZD420-203dpi" ghost queue ; confirm Ethernet option on the ZD420s ; then revoke the key.

Resume: cd ~/projects/lg-warehouse-stations && tailscale status | grep lg-station
