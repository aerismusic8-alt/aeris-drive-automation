#!/usr/bin/env bash
# Restore everything the media pipeline needs after a pod recycle.
#
# A recycled sandbox keeps /workspace but drops /tmp, the apt packages and the
# pip packages, so a session that resumes after one has to rebuild its toolchain
# before it can render. The generated assets themselves live in the repo
# (library/, work/) and are not touched here.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

need_apt=0
command -v ffmpeg >/dev/null 2>&1 || need_apt=1
command -v ffprobe >/dev/null 2>&1 || need_apt=1
if [ "$need_apt" = 1 ]; then
  echo "installing ffmpeg ..."
  sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg
fi

# Thai-capable fonts. The cover and subtitle renderers refuse to draw Thai
# without one rather than shipping tofu boxes.
if [ ! -f /usr/share/fonts/truetype/tlwg/Loma-Bold.ttf ] \
   || [ ! -f /usr/share/fonts/truetype/noto/NotoSansThai-Bold.ttf ]; then
  echo "installing Thai fonts ..."
  sudo apt-get install -y -qq fonts-thai-tlwg fonts-noto-core
fi

echo "installing python packages ..."
python3 -m pip install -q --disable-pip-version-check edge-tts Pillow playwright pytest pythainlp numpy

echo "installing the playwright browser if it is missing ..."
python3 - <<'PY'
try:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        if not p.chromium.executable_path or not __import__("os").path.exists(p.chromium.executable_path):
            raise RuntimeError("missing")
    print("chromium present")
except Exception:
    import subprocess, sys
    subprocess.run([sys.executable, "-m", "playwright", "install", "chromium"], check=False)
PY

echo "verifying ..."
python3 - <<'PY'
import shutil
for tool in ("ffmpeg", "ffprobe"):
    print(tool, shutil.which(tool) or "MISSING")
for mod in ("edge_tts", "PIL", "playwright", "pytest"):
    try:
        __import__(mod)
        print(mod, "OK")
    except Exception as exc:
        print(mod, "MISSING", exc)
PY
