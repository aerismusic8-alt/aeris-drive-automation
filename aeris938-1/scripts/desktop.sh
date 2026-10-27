#!/usr/bin/env bash
# AERIS938-1 cloud desktop: Xvfb + openbox + x11vnc + noVNC.
# Purpose: a browser the operator can log into from a phone/laptop, so K can
# sign in to Google once and the agent can then drive that same session.
set -u

DISPLAY_NUM="${AERIS_DISPLAY:-:99}"
SCREEN="${AERIS_SCREEN:-1600x900x24}"
VNC_PORT="${AERIS_VNC_PORT:-5900}"
NOVNC_PORT="${AERIS_NOVNC_PORT:-12000}"
LOG_DIR="${AERIS_LOG_DIR:-/tmp/aeris938}"
RUN_DIR="${AERIS_RUN_DIR:-/tmp/aeris938}"
VNC_PASSFILE="${AERIS_VNC_PASSFILE:-$HOME/.aeris938/vnc.pass}"
CHROME_PROFILE="${AERIS_CHROME_PROFILE:-$HOME/.aeris938/chrome-profile}"
CDP_PORT="${AERIS_CDP_PORT:-9222}"

mkdir -p "$LOG_DIR" "$RUN_DIR" "$(dirname "$VNC_PASSFILE")" "$CHROME_PROFILE"

is_up() { pgrep -f "$1" >/dev/null 2>&1; }

start_xvfb() {
  if is_up "Xvfb $DISPLAY_NUM"; then echo "[=] Xvfb already up"; return; fi
  Xvfb "$DISPLAY_NUM" -screen 0 "$SCREEN" -ac -nolisten tcp \
    >"$LOG_DIR/xvfb.log" 2>&1 &
  sleep 2
  echo "[+] Xvfb $DISPLAY_NUM ($SCREEN)"
}

start_wm() {
  if is_up "openbox"; then echo "[=] openbox already up"; return; fi
  DISPLAY="$DISPLAY_NUM" openbox >"$LOG_DIR/openbox.log" 2>&1 &
  sleep 1
  echo "[+] openbox"
}

start_x11vnc() {
  if is_up "x11vnc -display $DISPLAY_NUM"; then echo "[=] x11vnc already up"; return; fi
  if [ ! -s "$VNC_PASSFILE" ]; then
    echo "[-] no VNC password file at $VNC_PASSFILE (run vnc-pass.sh first)"; return 1
  fi
  x11vnc -display "$DISPLAY_NUM" -rfbauth "$VNC_PASSFILE" -rfbport "$VNC_PORT" \
    -forever -shared -repeat -noxdamage -xkb \
    >"$LOG_DIR/x11vnc.log" 2>&1 &
  sleep 2
  echo "[+] x11vnc on :$VNC_PORT"
}

start_novnc() {
  if is_up "websockify.*$NOVNC_PORT"; then echo "[=] noVNC already up"; return; fi
  websockify --web=/usr/share/novnc "$NOVNC_PORT" "localhost:$VNC_PORT" \
    >"$LOG_DIR/novnc.log" 2>&1 &
  sleep 2
  echo "[+] noVNC on :$NOVNC_PORT -> http://localhost:$NOVNC_PORT/vnc.html"
}

start_chrome() {
  if is_up "remote-debugging-port=$CDP_PORT"; then echo "[=] chrome already up"; return; fi
  DISPLAY="$DISPLAY_NUM" chromium \
    --no-sandbox --disable-dev-shm-usage --no-first-run --no-default-browser-check \
    --disable-features=Translate,MediaRouter \
    --user-data-dir="$CHROME_PROFILE" \
    --remote-debugging-address=127.0.0.1 --remote-debugging-port="$CDP_PORT" \
    --window-size=1500,860 --window-position=20,20 \
    --lang=th-TH "https://accounts.google.com/" \
    >"$LOG_DIR/chrome.log" 2>&1 &
  sleep 5
  echo "[+] chromium (profile $CHROME_PROFILE, CDP :$CDP_PORT)"
}

status() {
  for p in "Xvfb $DISPLAY_NUM" "openbox" "x11vnc -display $DISPLAY_NUM" "websockify.*$NOVNC_PORT" "remote-debugging-port=$CDP_PORT"; do
    if is_up "$p"; then echo "UP    $p"; else echo "DOWN  $p"; fi
  done
}

case "${1:-up}" in
  up) start_xvfb; start_wm; start_x11vnc; start_novnc; start_chrome; echo; status ;;
  xvfb) start_xvfb ;;
  wm) start_wm ;;
  vnc) start_x11vnc ;;
  novnc) start_novnc ;;
  chrome) start_chrome ;;
  status) status ;;
  *) echo "usage: $0 {up|xvfb|wm|vnc|novnc|chrome|status}"; exit 2 ;;
esac
