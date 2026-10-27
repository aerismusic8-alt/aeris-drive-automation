#!/usr/bin/env bash
# Set the VNC password used by x11vnc. The password is NOT stored in the repo.
set -eu
PASS="${1:-}"
if [ -z "$PASS" ]; then
  echo "usage: $0 <password>" >&2
  exit 2
fi
mkdir -p "$HOME/.aeris938"
x11vnc -storepasswd "$PASS" "$HOME/.aeris938/vnc.pass" >/dev/null
chmod 600 "$HOME/.aeris938/vnc.pass"
echo "[+] VNC password written to $HOME/.aeris938/vnc.pass"
