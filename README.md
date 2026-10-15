# Trimui-SSHToggle

One-tap SSH toggle for TrimUI handhelds (Brick Pro / Smart Pro S, stock OS).
No UI, no OTA, no dependencies — press once to turn background SSH on,
press again to turn it off.

## What it does

- **ON**: starts `dropbear` SSH server (LAN, port 2222) + a reverse tunnel
  to the VPS (`dbclient -R 22223:localhost:2222`) so you can SSH from
  anywhere: `ssh root@<vps> -p 22223` (or via your `trimui-brick` alias).
  A tiny keeper re-touches `/tmp/stay_alive` every 30s so the stock OS
  doesn't deep-suspend the device while SSH is on.
- **OFF**: kills dropbear, the tunnel and the keeper, removes
  `/tmp/stay_alive` so the device can suspend normally (saves battery).

## Install

Copy the `SSHToggle` folder to `/mnt/SDCARD/Apps/` on the SD card.
It appears in the Apps menu as **SSH Toggle**.

## Keys (not shipped)

- `data/dropbear_host_key` — generated on first run (Ed25519). If
  TrimuiRemote is installed, its host key is reused automatically.
- `data/tunnel_key` — your private key for the VPS `trimui` user. Reused
  from TrimuiRemote when present; otherwise drop your own key there.
  Never commit keys: `data/` is git-ignored.
- `data/authorized_keys` (optional) — copied to `/root/.ssh/authorized_keys`
  on every start so key-based login works (the FAT card can't hold 0600
  permissions, hence the copy).

## Files

| file           | purpose                              |
|----------------|--------------------------------------|
| `launch.sh`    | TrimUI entry point (runs the toggle) |
| `sshtoggle.sh` | toggle/on/off/status logic           |
| `bin/`         | static aarch64 `dropbear`, `dbclient`, `dropbearkey`, `dropbearconvert` |
| `data/`        | runtime: keys, pidfiles, `toggle.log` (kept to last 200 lines) |

## Note

Don't run SSHToggle and TrimuiRemote at the same time — both use port
2222 and VPS remote port 22223.
