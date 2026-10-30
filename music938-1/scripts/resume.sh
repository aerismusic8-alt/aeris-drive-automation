#!/usr/bin/env bash
# Bring the music938-1 batch back after a pod recycle.
# A recycle kills the cloud desktop, the batch process and the pip packages;
# /workspace survives, so the Flow Music login and the outputs are still there.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
PROFILE=/workspace/ax-tools/aeris938-state/chrome-profile

echo "[1/4] cloud desktop"
python3 "$REPO/.agents/skills/ax-cloud-desktop/scripts/bootstrap.py" --status | tail -6

echo "[2/4] chromium CDP"
if ! curl -s --max-time 3 http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
  echo "  CDP down - clearing stale profile locks and relaunching"
  pkill -9 -f /usr/lib/chromium; sleep 2
  # SingletonLock is a symlink into the dead pod's /tmp; chromium then never
  # binds the debugging port and every Playwright attach is refused.
  rm -f "$PROFILE"/Singleton* "$PROFILE"/DevToolsActivePort
  DISPLAY=:99 nohup /usr/lib/chromium/chromium --no-sandbox --disable-dev-shm-usage \
    --no-first-run --no-default-browser-check --disable-features=Translate,MediaRouter \
    --user-data-dir="$PROFILE" --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port=9222 --remote-allow-origins='*' \
    --window-size=1500,860 --lang=th-TH https://accounts.google.com/ \
    > /tmp/chrome-relaunch.log 2>&1 &
  sleep 8
fi
curl -s --max-time 5 http://127.0.0.1:9222/json/version | head -2

echo "[3/4] python deps (a recycle wipes them)"
if ! python3 -c "import PIL, pythainlp" >/dev/null 2>&1; then
  python3 -m pip install --quiet --break-system-packages pillow pythainlp python-crfsuite
fi
python3 -c "import PIL, pythainlp; print('  pillow+pythainlp ok')"

# ffmpeg lives on the container overlay too, and a recycle takes it. Without it
# every render dies with `FileNotFoundError: 'ffprobe'` *after* the generation
# call has already been spent, so a rare window is burned on a song that then
# cannot be encoded. Check it before the batch, not when it is already too late.
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  echo "  ffmpeg missing - installing"
  sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg
fi
command -v ffprobe >/dev/null && echo "  ffmpeg ok" || { echo "  ffmpeg STILL MISSING - renders will fail" >&2; exit 1; }

echo "[4/4] batch"
if pgrep -f "build_songs.py" >/dev/null 2>&1; then
  echo "  already running"
else
  cd "$REPO"
  nohup python3 "$ROOT/scripts/build_songs.py" --workers 1 >> "$ROOT/work/batch.log" 2>&1 &
  sleep 4
  echo "  started pid $(pgrep -f build_songs.py | head -1)"
fi
tail -3 "$ROOT/work/batch.log" 2>/dev/null
