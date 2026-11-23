#!/usr/bin/env bash
# Bring the cloud desktop and its live-view link back in one command.
#
# A container restart takes everything with it: pip packages, Xvfb, Chromium and
# port 12001. The link then answers nothing and K reads that as "the link is
# broken". This runs the two restore steps in the only order that works and
# prints the operator URLs, so a restart costs one command, not a diagnosis.
#
#   scripts/desk-up.sh          # restore + print the links
#   scripts/desk-up.sh --check  # report only, change nothing
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
PY="${PYTHON:-python3}"
BOOTSTRAP="$REPO/.agents/skills/ax-cloud-desktop/scripts/bootstrap.py"
WATCH="$REPO/ops/desktop_watch.py"

if [ "${1:-}" = "--check" ]; then
  exec "$PY" "$WATCH"
fi

# 1. Python deps under /workspace, so they survive the next restart.
bash "$REPO/scripts/bootstrap-pod.sh" || true

# 2. Xvfb + Chromium + live view, then restore the sealed cookies.
"$PY" "$BOOTSTRAP"

# 3. Point the live view at a real tab. Without a target it serves a blank
#    frame, which looks identical to a dead server.
"$PY" - <<'PY'
import json, urllib.request
base = "http://127.0.0.1:12001"
try:
    tabs = json.load(urllib.request.urlopen(base + "/tabs", timeout=8)).get("tabs", [])
except Exception as exc:
    print(f"live view not reachable: {type(exc).__name__}")
    raise SystemExit(0)
pages = [t for t in tabs if t.get("type") == "page"] or tabs
if not pages:
    print("no browser tab to attach; open one and re-run")
    raise SystemExit(0)
tid = pages[0]["id"]
req = urllib.request.Request(base + "/watch", data=json.dumps({"target": tid}).encode(),
                             headers={"Content-Type": "application/json"})
print("watching:", json.load(urllib.request.urlopen(req, timeout=10)).get("status", {}).get("target", "?"))
PY

echo
"$PY" "$WATCH"
echo
echo "live view (this is the link to use):"
echo "  https://work-2-${RUNTIME_ID:-<work-host>}.prod-runtime.all-hands.dev/"
echo "noVNC fallback (whole X desktop; frozen picture on this sandbox):"
echo "  https://work-1-${RUNTIME_ID:-<work-host>}.prod-runtime.all-hands.dev/vnc.html?autoconnect=1&resize=remote"
