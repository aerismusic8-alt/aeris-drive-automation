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
mkdir -p "$BIN"

# Install *under /workspace*, not into $HOME. A pod recycle keeps /workspace and
# drops everything else, so a $HOME install (the default) disappears and every
# script that needs numpy/Pillow/pythainlp/playwright dies until it is redone.
PYLIBS=/workspace/ax-tools/pylibs
python3 -m pip install -q --target="$PYLIBS" \
  numpy pythainlp python-crfsuite pillow playwright 2>&1 | tail -2
# A .pth in site-packages makes every `python3` find the durable libs without a
# PYTHONPATH export, so an unattended cron script cannot miss them.
SITE=$(python3 -c 'import site; print(site.getsitepackages()[0])')
echo "$PYLIBS" > "$SITE/ax-pylibs.pth"

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
