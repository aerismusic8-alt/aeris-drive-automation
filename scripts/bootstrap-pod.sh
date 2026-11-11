#!/usr/bin/env bash
# One command to make a fresh pod able to run AR's work.
#
# The pod is disposable: a recycle wipes $HOME, /tmp and every pip package, so a
# rail that was green dies with `ModuleNotFoundError`. This restores everything
# from requirements.txt into /workspace (which survives a recycle), installs the
# system tools, and runs the readiness check. Idempotent — run it after every
# recycle, or first thing in a new session.
#
#   scripts/bootstrap-pod.sh            # restore, then report readiness
#   scripts/bootstrap-pod.sh --check    # report only, install nothing
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
PYLIBS=/workspace/ax-tools/pylibs
BIN=/workspace/ax-tools/bin
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# --- python deps, installed UNDER /workspace so a recycle keeps them ---
if [ "$CHECK_ONLY" = 0 ]; then
  mkdir -p "$PYLIBS"
  if [ -f "$REPO/requirements.txt" ]; then
    echo "[bootstrap] python deps -> $PYLIBS"
    python3 -m pip install -q --target="$PYLIBS" -r "$REPO/requirements.txt" 2>&1 | tail -3
  else
    echo "[bootstrap][warn] requirements.txt missing; falling back to the known set"
    python3 -m pip install -q --target="$PYLIBS" \
      g4f ddgs trafilatura numpy pillow pythainlp mido edge-tts imageio-ffmpeg \
      fonttools playwright websocket-client cryptography PyNaCl fastmcp \
      web3 eth-account pytest 2>&1 | tail -3
  fi
  # A .pth in site-packages makes every `python3` find the durable libs with no
  # PYTHONPATH export, so an unattended rail cannot miss them.
  SITE=$(python3 -c 'import site; print(site.getsitepackages()[0])')
  if ! echo "$PYLIBS" > "$SITE/ax-pylibs.pth" 2>/dev/null; then
    SITE=$(python3 -m site --user-site); mkdir -p "$SITE"
    echo "$PYLIBS" > "$SITE/ax-pylibs.pth"
  fi
  echo "[bootstrap] pth -> $SITE/ax-pylibs.pth"
fi

# --- system tools (apt; a recycle keeps /usr, so usually a no-op) ---
if [ "$CHECK_ONLY" = 0 ]; then
  missing=""
  for c in ffmpeg fluidsynth xvfb x11vnc websockify; do
    command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
  done
  # Thai fonts are a *silent* failure: the SVG renderer substitutes a font with no
  # Thai glyphs and every label becomes tofu. ax_readiness.py checks tlwg dirs.
  if ! ls /usr/share/fonts/*/tlwg/*.ttf >/dev/null 2>&1 \
     && ! ls /usr/share/fonts/*/tlwg/*.otf >/dev/null 2>&1; then
    missing="$missing thai-fonts"
  fi
  if [ -n "$missing" ]; then
    echo "[bootstrap] apt install:$missing"
    sudo apt-get update -qq && sudo apt-get install -y -qq \
      ffmpeg fluidsynth fluid-soundfont-gm musescore-general-soundfont \
      fonts-thai-tlwg-ttf fonts-thai-tlwg-otf \
      xvfb openbox x11vnc websockify 2>&1 | tail -2
  fi
fi

# --- readiness: prove it, do not claim it ---
echo
echo "[bootstrap] readiness:"
cd "$REPO"
python3 ops/ax_readiness.py 2>&1 | tail -30 || true
echo
echo "[bootstrap] done. For the cloud desktop (Duck.ai / Flow Music) run:"
echo "  python3 .agents/skills/ax-cloud-desktop/scripts/bootstrap.py"
