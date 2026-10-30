#!/bin/bash
# Keep the rendezvous alive.
#
# PC1 polls this endpoint, so a dead rendezvous is a dead channel: the worker on
# the far side keeps polling and has no way to tell anyone that nothing is
# listening. Restarting immediately turns a crash into a few seconds of missed
# polls rather than an outage that needs a person to notice.
#
# This does not survive the sandbox itself being torn down. While the sandbox
# lives, the channel lives; if it is recreated, run this again and PC1's worker
# reconnects on its next poll with no change needed on the Windows side.
set -u
cd "$(dirname "$0")" || exit 1
PORT="${AX_PORT:-12000}"
LOG="${AX_RENDEZVOUS_LOG:-/tmp/rendezvous.log}"

while true; do
  python3 -u ax-rendezvous.py --port "$PORT" --results-dir "$(pwd)/ax-results" >> "$LOG" 2>&1
  echo "$(date -Is) rendezvous exited, restarting" >> "$LOG"
  sleep 3
done
