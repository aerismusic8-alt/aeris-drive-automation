#!/usr/bin/env bash
# Print the link the operator uses to sign in to the cloud desktop.
set -u
PORT="${AERIS_NOVNC_PORT:-12000}"
HOST="${AERIS_PUBLIC_HOST:-work-1-jhakqeqvkcqlwmjh.prod-runtime.all-hands.dev}"
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
