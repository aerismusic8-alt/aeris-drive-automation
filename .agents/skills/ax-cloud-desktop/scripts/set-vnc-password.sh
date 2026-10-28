#!/usr/bin/env bash
# Set the VNC password used by x11vnc. Stored on /workspace, never in git.
set -eu
STATE="${AERIS_STATE_DIR:-/workspace/ax-tools/aeris938-state}"
PASS="${1:-$(python3 -c 'import secrets;print(secrets.token_urlsafe(6))')}"
mkdir -p "$STATE"
x11vnc -storepasswd "$PASS" "$STATE/vnc.pass" >/dev/null
printf '%s' "$PASS" > "$STATE/vnc.pass.txt"
chmod 600 "$STATE/vnc.pass" "$STATE/vnc.pass.txt"
echo "[+] password written to $STATE/vnc.pass.txt"
echo "    $PASS"
