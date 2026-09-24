# STATUS — lg-warehouse-stations

**2026-09-24** — Kit built and published (commit ead346f). NOT yet run on a real station.

- Stations (ShipStation Connect): DESKTOP-NC5RQH1 (GX420t), DESKTOP-BQ2D6JS (ZD420 LEFT/RIGHT + ghost queue), DESKTOP-UKL2D68 (ZD420-300dpi). Stale registrations: GAAQTQN ×2, F04617U ×2, BQ2D6JS dup, two Macs.
- Stations are on a network segment the Mac mini cannot see → nothing is remotely reachable until the script joins them to the tailnet.
- Tailnet auth key: `~/.config/liquorgeeks/tailscale-warehouse-authkey.env` (reusable, expires 2026-12-23). Revoke after all 3 join.

**Blocked on:** someone at the warehouse running the one-liner (README) in an admin PowerShell on each PC.

**Next (remote, after join):** read `C:\LG\station-report.json`, delete ghost Zebra queues, deactivate stale Connect registrations + enable Shared, put Connect under the account the packers use, revoke the key.

Resume: `cd ~/projects/lg-warehouse-stations && tailscale status | grep lg-station`
