#!/bin/sh
# sshtoggle.sh — bật/tắt SSH nền cho TrimUI, càng nhẹ càng tốt.
#   sh sshtoggle.sh toggle | on | off | status
# Không UI, không OTA, không phụ thuộc app nào khác.
# Gồm: dropbear (SSH LAN, port 2222) + dbclient (tunnel VPS -> ssh từ xa).
case "$0" in */*) cd "$(dirname "$0")" || exit 1;; esac
APP="$(pwd)"
DATA="$APP/data"
BIN="$APP/bin"
SDCARD="${SDCARD_PATH:-/mnt/SDCARD}"
TR="$SDCARD/Apps/TrimuiRemote"   # tái dùng key nếu có (không bắt buộc)

PORT="${SSH_PORT:-2222}"
VPS_HOST="13.251.88.185"
VPS_PORT=22
VPS_USER="trimui"
VPS_RPORT=22223

DB_PIDF="$DATA/dropbear.pid"
TN_PIDF="$DATA/tunnel.pid"
KP_PIDF="$DATA/keeper.pid"
KEYF="$DATA/dropbear_host_key"
TKEY="$DATA/tunnel_key"
TKEYDB="$DATA/tunnel_key.db"
AUTHK="$DATA/authorized_keys"
LOG="$DATA/toggle.log"

mkdir -p "$DATA" 2>/dev/null
# Xoay log: giữ 200 dòng cuối.
if [ -f "$LOG" ] && command -v tail >/dev/null 2>&1; then
  tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
fi
log() { echo "[$(date '+%m-%d %H:%M:%S' 2>/dev/null)] $*" >>"$LOG" 2>&1; }

alive() { # alive <pidfile> -> in pid nếu tiến trình còn sống
  [ -f "$1" ] || return 1
  p="$(cat "$1" 2>/dev/null | tr -d ' \r\n')"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  echo "$p"
}

killpat() { # kill theo chuỗi con trong cmdline (stock OS không có pkill)
  pat="$1"; me="$$"
  for d in /proc/[0-9]*; do
    pid="${d#/proc/}"
    case "$pid" in ''|*[!0-9]*) continue;; esac
    [ "$pid" = "$me" ] && continue
    cl="$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)"
    case "$cl" in *"$pat"*) kill "$pid" 2>/dev/null;; esac
  done
}

killpid() { # killpid <pidfile>
  p="$(alive "$1")" || { rm -f "$1"; return 0; }
  kill "$p" 2>/dev/null; sleep 1; kill -9 "$p" 2>/dev/null
  rm -f "$1"
}

led_blink() { # led_blink <r|g|b> <so lan> — phản hồi trực quan khi toggle
  c="$1"; n="${2:-2}"; led="/sys/class/leds/sunxi_led0$c/brightness"
  [ -w "$led" ] || return 0
  i=0; while [ "$i" -lt "$n" ]; do
    echo 255 > "$led" 2>/dev/null; sleep 0.3
    echo 0 > "$led" 2>/dev/null; sleep 0.3
    i=$((i + 1))
  done
}

keeper_on() {
  if alive "$KP_PIDF" >/dev/null; then return 0; fi
  # Giữ máy không deep-suspend (học từ Trimui-Remote): stock OS tự xoá
  # /tmp/stay_alive khi hết phiên nên phải chạm lại định kỳ.
  touch /tmp/stay_alive 2>/dev/null
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup sh -c 'while true; do touch /tmp/stay_alive 2>/dev/null; sleep 30; done' >/dev/null 2>&1 &
  else
    nohup sh -c 'while true; do touch /tmp/stay_alive 2>/dev/null; sleep 30; done' >/dev/null 2>&1 &
  fi
  echo $! > "$KP_PIDF" 2>/dev/null
}

ensure_hostkey() {
  [ -s "$KEYF" ] && return 0
  if [ -s "$TR/data/dropbear_host_key" ]; then
    cp "$TR/data/dropbear_host_key" "$KEYF" 2>/dev/null && \
      log "tái dùng host key của TrimuiRemote" && return 0
  fi
  if [ -x "$BIN/dropbearkey" ]; then
    # The FAT không hỗ trợ cách dropbearkey đổi tên file tạm (ENOSYS)
    # nên sinh ra /tmp rồi cp sang data/.
    t="/tmp/ssh_hostkey.$$"
    "$BIN/dropbearkey" -t ed25519 -f "$t" >/dev/null 2>&1 && cp "$t" "$KEYF" 2>/dev/null
    rm -f "$t" "$t.pub" 2>/dev/null
    [ -s "$KEYF" ] && { log "đã sinh host key mới"; return 0; }
  fi
  log "CẢNH BÁO: không có host key — dropbear sẽ chạy không có -r"
  return 1
}

install_authkeys() {
  # User bỏ file authorized_keys vào data/ để dùng đăng nhập bằng key.
  # (dropbear luôn đọc /root/.ssh/authorized_keys nên phải copy sang đó;
  # thẻ FAT không giữ được chmod 600.)
  [ -f "$AUTHK" ] || return 0
  mkdir -p /root/.ssh 2>/dev/null && \
  cp "$AUTHK" /root/.ssh/authorized_keys 2>/dev/null && \
  chmod 700 /root/.ssh 2>/dev/null && \
  chmod 600 /root/.ssh/authorized_keys 2>/dev/null && \
    log "đã cài authorized_keys"
}

ensure_tunnelkey() {
  [ -s "$TKEY" ] && return 0
  if [ -s "$TR/data/tunnel_key" ]; then
    cp "$TR/data/tunnel_key" "$TKEY" 2>/dev/null && chmod 600 "$TKEY" 2>/dev/null
    log "tái dùng tunnel_key của TrimuiRemote"
  fi
  [ -s "$TKEY" ] || return 1
  if [ ! -s "$TKEYDB" ] && [ -x "$BIN/dropbearconvert" ]; then
    "$BIN/dropbearconvert" openssh dropbear "$TKEY" "$TKEYDB" 2>/dev/null
  fi
  [ -s "$TKEYDB" ]
}

tunnel_on() {
  if alive "$TN_PIDF" >/dev/null; then log "tunnel đã chạy"; return 0; fi
  if ! ensure_tunnelkey; then
    log "thiếu data/tunnel_key — bỏ qua tunnel VPS (vẫn SSH được trong LAN)"
    return 0
  fi
  # Vòng retry nền: tự nối lại khi mất mạng. Cổng VPS_RPORT có thể bị phiên
  # cũ giữ ~3 phút (ClientAliveInterval) — vòng này sẽ vào được khi cổng trống.
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup sh -c "while true; do '$BIN/dbclient' -p $VPS_PORT -R $VPS_RPORT:localhost:$PORT -N -T -y -K 120 -i '$TKEYDB' $VPS_USER@$VPS_HOST >>'$LOG' 2>&1; sleep 15; done" >/dev/null 2>&1 &
  else
    nohup sh -c "while true; do '$BIN/dbclient' -p $VPS_PORT -R $VPS_RPORT:localhost:$PORT -N -T -y -K 120 -i '$TKEYDB' $VPS_USER@$VPS_HOST >>'$LOG' 2>&1; sleep 15; done" >/dev/null 2>&1 &
  fi
  echo $! > "$TN_PIDF" 2>/dev/null
  log "tunnel VPS đang nối (port $VPS_RPORT)"
}

do_on() {
  if p="$(alive "$DB_PIDF")"; then log "SSH đã bật sẵn (pid $p)"; echo "SSH đã bật"; return 0; fi
  ensure_hostkey
  install_authkeys
  keeper_on
  rm -f "$DB_PIDF"
  if [ -s "$KEYF" ]; then
    set -- "$BIN/dropbear" -p "$PORT" -r "$KEYF" -P "$DB_PIDF"
  else
    set -- "$BIN/dropbear" -p "$PORT" -P "$DB_PIDF"
  fi
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup "$@" >>"$LOG" 2>&1 &
  else
    nohup "$@" >>"$LOG" 2>&1 &
  fi
  sleep 1
  if p="$(alive "$DB_PIDF")"; then
    ip="$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {sub(/\/.*/, "", $2); print $2; exit}')"
    log "SSH ĐÃ BẬT: pid=$p port=$PORT ip=${ip:-?}"
    echo "SSH đã bật"
    ( led_blink g 3 ) &
  else
    log "LỖI: dropbear không chạy được (port $PORT bận? xem $LOG)"
    echo "LỖI: không bật được SSH"
    return 1
  fi
  tunnel_on
}

do_off() {
  killpid "$TN_PIDF"
  killpat "SSHToggle/bin/dbclient"
  killpid "$KP_PIDF"
  rm -f /tmp/stay_alive 2>/dev/null
  killpid "$DB_PIDF"
  killpat "SSHToggle/bin/dropbear"
  log "SSH ĐÃ TẮT"
  echo "SSH đã tắt"
  ( led_blink r 2 ) &
}

do_status() {
  if p="$(alive "$DB_PIDF")"; then
    echo "SSH: BẬT (dropbear pid=$p port=$PORT)"
    if p="$(alive "$TN_PIDF")"; then echo "tunnel VPS: vòng retry đang chạy (port $VPS_RPORT)"; fi
  else
    echo "SSH: TẮT"
  fi
}

case "${1:-toggle}" in
  on) do_on;;
  off) do_off;;
  status) do_status;;
  toggle)
    if alive "$DB_PIDF" >/dev/null; then do_off; else do_on; fi;;
  *) echo "dùng: $0 toggle|on|off|status" >&2; exit 1;;
esac
