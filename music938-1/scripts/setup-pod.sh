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

python3 -m pip install -q numpy pythainlp python-crfsuite pillow 2>&1 | tail -2

if [ ! -x "$BIN/ffmpeg" ]; then
  url="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
  tmp=$(mktemp -d)
  echo "fetching static ffmpeg..."
  curl -sL -o "$tmp/ff.tar.xz" "$url" &&
    python3 -c "import tarfile,sys; tarfile.open(sys.argv[1]).extractall(sys.argv[2])" \
      "$tmp/ff.tar.xz" "$tmp" &&
    d=$(find "$tmp" -maxdepth 1 -type d -name 'ffmpeg-master*' | head -1) &&
    ln -sf "$d/bin/ffmpeg" "$BIN/ffmpeg" && ln -sf "$d/bin/ffprobe" "$BIN/ffprobe"
  rm -rf "$tmp"
fi

"$BIN/ffmpeg" -version 2>/dev/null | head -1
echo
echo "add to PATH before building:  export PATH=$BIN:\$PATH"
