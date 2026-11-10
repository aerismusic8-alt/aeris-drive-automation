#!/usr/bin/env bash
# Restore the tools music938-1 needs after a pod recycle.
#
# A recycle wipes $HOME, /tmp and every pip package, and ffmpeg is not in the
# image. This puts the pip dependencies back and installs a static ffmpeg under
# /workspace/ax-tools/bin (which survives a recycle), then prints how to use it.
#
# The daily-release automation does not need any of this: it only publishes
# media that already exists. This is for building songs and running the tests.
set -u

BIN=/workspace/ax-tools/bin
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$BIN"

# Install *under /workspace*, not into $HOME. A pod recycle keeps /workspace and
# drops everything else, so a $HOME install (the default) disappears and every
# script that needs numpy/Pillow/pythainlp/playwright dies until it is redone.
PYLIBS=/workspace/ax-tools/pylibs
python3 -m pip install -q --target="$PYLIBS" \
  numpy pythainlp python-crfsuite pillow playwright websocket-client mido 2>&1 | tail -2
# A .pth in site-packages makes every `python3` find the durable libs without a
# PYTHONPATH export, so an unattended cron script cannot miss them. The system
# site-packages is root-owned in this image, so fall back to the user site dir
# (which python adds to sys.path on its own).
SITE=$(python3 -c 'import site; print(site.getsitepackages()[0])')
if ! echo "$PYLIBS" > "$SITE/ax-pylibs.pth" 2>/dev/null; then
  SITE=$(python3 -m site --user-site)
  mkdir -p "$SITE"
  echo "$PYLIBS" > "$SITE/ax-pylibs.pth"
fi
echo "pth -> $SITE/ax-pylibs.pth"

# The binaries must be unpacked *under /workspace*, not into a mktemp dir: the
# symlinks below point at the extracted tree, so a temp dir that is deleted
# leaves dangling links and the next run sees "ffmpeg installed" while it is not.
FFDIR=/workspace/ax-tools/ffmpeg
if [ ! -x "$BIN/ffmpeg" ]; then
  url="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
  tmp=$(mktemp -d)
  echo "fetching static ffmpeg..."
  mkdir -p "$FFDIR"
  curl -sL -o "$tmp/ff.tar.xz" "$url" &&
    python3 -c "import tarfile,sys; tarfile.open(sys.argv[1]).extractall(sys.argv[2])" \
      "$tmp/ff.tar.xz" "$FFDIR" &&
    d=$(find "$FFDIR" -maxdepth 1 -type d -name 'ffmpeg-master*' | head -1) &&
    ln -sf "$d/bin/ffmpeg" "$BIN/ffmpeg" && ln -sf "$d/bin/ffprobe" "$BIN/ffprobe"
  rm -rf "$tmp"
fi

"$BIN/ffmpeg" -version 2>/dev/null | head -1
echo
echo "add to PATH before building:  export PATH=$BIN:\$PATH"

# The music bed is rendered with real instruments via fluidsynth (K rejected the
# ffmpeg tone synth as "fake", 2026-11-09). These are apt packages, not pip, and
# they live under /usr — which a pod recycle *does* keep (only $HOME is wiped),
# so this only reinstalls when a fresh image lacks them.
if ! command -v fluidsynth >/dev/null 2>&1; then
  echo "installing fluidsynth + soundfonts..."
  sudo apt-get update -qq &&
    sudo apt-get install -y -qq fluidsynth fluid-soundfont-gm \
      musescore-general-soundfont
fi
fluidsynth --version 2>/dev/null | head -1

# K (2026-11-09, later): the GM SoundFont "sounds fake — find a program that
# makes realistic sound." sfizz plays multi-velocity recordings of real
# instruments; it and its CC0 banks live under /workspace and are fetched by a
# separate script so this stays fast when they are already present.
if [ ! -x "$REPO/tools/sfizz/sfizz_render" ] || \
   [ ! -e /workspace/ax-tools/instruments/salamander/"Salamander Grand Piano V3.sfz" ]; then
  echo "installing the realistic-sound sampler (sfizz)..."
  bash "$(dirname "$0")/install-sfizz.sh" || \
    echo "[warn] sfizz install failed; beds fall back to the GM SoundFont"
fi
