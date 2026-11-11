#!/usr/bin/env bash
# Print the link the operator uses to sign in to the cloud desktop.
set -u
PORT="${AERIS_NOVNC_PORT:-12000}"
# The work host is per-pod and changes on every recycle, so build it from
# RUNTIME_ID instead of hardcoding one (a stale default points at a dead pod).
HOST="${AERIS_PUBLIC_HOST:-work-1-${RUNTIME_ID:?RUNTIME_ID not set - export it from the session work_hosts}.prod-runtime.all-hands.dev}"
echo "Cloud desktop: https://${HOST}/vnc.html?autoconnect=1&resize=scale"
echo "  VNC port    : ${PORT}"
if pgrep -f "websockify.*${PORT}" >/dev/null 2>&1; then
  echo "  status      : UP"
else
  echo "  status      : DOWN  (run scripts/desktop.sh up)"
fi
echo
echo "Sign in to the sites you want the agent to drive, then re-run the task."
echo "The session is stored in ~/.aeris938/chrome-profile and is reused."
