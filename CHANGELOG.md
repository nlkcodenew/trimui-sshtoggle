# Changelog — Trimui-SSHToggle

## v0.1.3
- Launcher background: thêm `background.png` (gradient đỏ → xanh lá theo tông
  icon) + key `"background"` trong `config.json` — menu TrimUI đổi nền khi
  focus vào icon app.

## v0.1.2
- Supervisor giám sát cả dropbear lẫn tunnel (15s/vòng): fix SSH mất hẳn sau khi
  máy suspend/resume (bản cũ chỉ trông tunnel nên dropbear chết là mất SSH).

## v0.1.1
- Nháy vòng LED 2 cần joystick (sunxi_led10..22) thay cho LED trước máy.
- Fix quirk phần cứng Brick Pro: kênh r/g sysfs bị đảo so với màu thật.


## v0.1.0

- Initial release: one-tap background SSH toggle (no UI).
- ON: dropbear (LAN port 2222) + dbclient reverse tunnel to VPS
  (remote port 22223) with retry loop; keep-alive against deep-suspend.
- OFF: stops everything, device can suspend normally.
- Reuses TrimuiRemote host key / tunnel key when present; generates
  Ed25519 host key on first run otherwise.
- Log rotation: `data/toggle.log` keeps last 200 lines.
