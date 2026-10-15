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
SUP_PIDF="$DATA/supervisor.pid"
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

# Vòng LED 2 cần joystick trên Brick Pro: sunxi_led10..sunxi_led22.
# QUIRK phần cứng (user verify 2026-10-15): tên kênh r/g trong sysfs bị đảo
# so với màu đèn thật (ghi "g" thì đèn ĐỎ sáng). Map ở đây để chỗ gọi dùng
# đúng ý nghĩa: green = bật, red = tắt.
led_color() { # led_color <green|red|blue> -> tên kênh sysfs
  case "$1" in green) echo r;; red) echo g;; *) echo "$1";; esac
}
led_blink() { # led_blink <green|red|blue> <số lần> — phản hồi trực quan khi toggle
  c="$(led_color "$1")"; n="${2:-2}"
  i=0; while [ "$i" -lt "$n" ]; do
    j=10; while [ "$j" -le 22 ]; do
      echo 255 > "/sys/class/leds/sunxi_led${j}${c}/brightness" 2>/dev/null
      j=$((j + 1))
    done
    sleep 0.3
    j=10; while [ "$j" -le 22 ]; do
      echo 0 > "/sys/class/leds/sunxi_led${j}${c}/brightness" 2>/dev/null
      j=$((j + 1))
    done
    sleep 0.3
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

dropbear_on() {
  # Start dropbear một lần (vòng supervisor sẽ dựng lại khi nó chết,
  # vd sau khi máy suspend/resume).
  if p="$(alive "$DB_PIDF")"; then log "dropbear đã chạy (pid $p)"; return 0; fi
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
    log "dropbear chạy: pid=$p port=$PORT"
    return 0
  fi
  log "LỖI: dropbear không chạy được (port $PORT bận? xem $LOG)"
  return 1
}

tunnel_once() {
  # Start 1 dbclient (supervisor gọi lại khi nó chết). Không dùng setsid ở
  # đây để $! chắc chắn là pid của dbclient (setsid có thể fork làm pidfile sai).
  [ -s "$TKEYDB" ] || return 0
  nohup "$BIN/dbclient" -p "$VPS_PORT" -R "$VPS_RPORT:localhost:$PORT" \
    -N -T -y -K 120 -i "$TKEYDB" "$VPS_USER@$VPS_HOST" >>"$LOG" 2>&1 &
  _tp=$!
  echo "$_tp" > "$TN_PIDF" 2>/dev/null
  log "tunnel: dbclient pid=$_tp (VPS port $VPS_RPORT)"
}

supervisor_on() {
  # Vòng giám sát nền (15s/vòng): đảm bảo cả dropbear lẫn tunnel luôn sống.
  # Sống sót qua suspend/resume — đây là chỗ dựng lại dropbear khi máy ngủ dậy
  # (bản cũ chỉ trông tunnel nên dropbear chết là SSH mất hẳn).
  if alive "$SUP_PIDF" >/dev/null; then log "supervisor đã chạy"; return 0; fi
  ensure_tunnelkey || log "thiếu data/tunnel_key — supervisor chỉ giữ dropbear (vẫn SSH được trong LAN)"
  ( trap '' HUP 2>/dev/null
    while :; do
      alive "$DB_PIDF" >/dev/null || dropbear_on
      if [ -s "$TKEYDB" ]; then
        alive "$TN_PIDF" >/dev/null || tunnel_once
      fi
      sleep 15
    done ) &
  echo $! > "$SUP_PIDF" 2>/dev/null
  log "supervisor đã chạy (15s/vòng: dropbear + tunnel)"
}

do_on() {
  if p="$(alive "$DB_PIDF")"; then log "SSH đã bật sẵn (pid $p)"; echo "SSH đã bật"; return 0; fi
  ensure_hostkey
  install_authkeys
  keeper_on
  if dropbear_on; then
    ip="$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {sub(/\/.*/, "", $2); print $2; exit}')"
    log "SSH ĐÃ BẬT: port=$PORT ip=${ip:-?}"
    echo "SSH đã bật"
    ( led_blink green 3 ) &
  else
    echo "LỖI: không bật được SSH"
    return 1
  fi
  supervisor_on
}

do_off() {
  killpid "$SUP_PIDF"
  killpid "$TN_PIDF"
  killpat "SSHToggle/bin/dbclient"
  killpid "$KP_PIDF"
  rm -f /tmp/stay_alive 2>/dev/null
  killpid "$DB_PIDF"
  killpat "SSHToggle/bin/dropbear"
  log "SSH ĐÃ TẮT"
  echo "SSH đã tắt"
  ( led_blink red 2 ) &
}

do_status() {
  if p="$(alive "$DB_PIDF")"; then
    echo "SSH: BẬT (dropbear pid=$p port=$PORT)"
    if alive "$SUP_PIDF" >/dev/null; then echo "supervisor: đang chạy (giữ dropbear + tunnel)"; fi
    if p="$(alive "$TN_PIDF")"; then echo "tunnel VPS: dbclient pid=$p (port $VPS_RPORT)"; fi
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
