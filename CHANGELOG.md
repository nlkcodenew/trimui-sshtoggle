# Changelog — Trimui-SSHToggle

## v0.1.0

- Initial release: one-tap background SSH toggle (no UI).
- ON: dropbear (LAN port 2222) + dbclient reverse tunnel to VPS
  (remote port 22223) with retry loop; keep-alive against deep-suspend.
- OFF: stops everything, device can suspend normally.
- Reuses TrimuiRemote host key / tunnel key when present; generates
  Ed25519 host key on first run otherwise.
- Log rotation: `data/toggle.log` keeps last 200 lines.
