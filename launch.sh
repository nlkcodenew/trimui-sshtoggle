#!/bin/sh
# SSHToggle launcher — TrimUI chay file nay khi mo app tu menu.
# Bấm 1 lần: bật SSH nền (LAN + tunnel VPS). Bấm lần nữa: tắt.
case "$0" in
  /*) APP="${0%/*}" ;;
  */*) APP="$(cd "${0%/*}" 2>/dev/null && pwd)" ;;
  *) APP="/mnt/SDCARD/Apps/SSHToggle" ;;
esac
# The FAT khong giu quyen thuc thi — tu chua lai.
chmod +x "$APP"/bin/* "$APP"/*.sh 2>/dev/null
sh "$APP/sshtoggle.sh" toggle
