#!/usr/bin/env bash
# Serve the finished music938-1 pack on the pod's public port so it can be
# previewed or handed to PC1 for the Drive copy. Regenerates the staging tree
# from the library first, so it never serves a stale render.
#
#   music938-1/scripts/serve-pack.sh          # stage + serve on :12001
#
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
STAGE=/tmp/deliver
PORT=12001

rm -rf "$STAGE"; mkdir -p "$STAGE/songs" "$STAGE/karaoke" "$STAGE/covers"
cp "$ROOT"/library/songs/song-*.mp3    "$STAGE/songs/"
cp "$ROOT"/library/songs/karaoke-*.mp3 "$STAGE/songs/"
cp "$ROOT"/library/karaoke/*.mp4       "$STAGE/karaoke/"
cp "$ROOT"/library/covers/*.png        "$STAGE/covers/"
python3 "$HERE/pack_index.py" "$STAGE"
# One archive is easier to hand over than 60 files; zip(1) is not installed here.
python3 - "$STAGE" <<'PY'
import sys, zipfile
from pathlib import Path
stage = Path(sys.argv[1])
out = stage / "music938-1-karaoke-20songs.zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
    for sub in ("songs", "karaoke", "covers"):
        for p in sorted((stage / sub).iterdir()):
            z.write(p, f"{sub}/{p.name}")
    z.write(stage / "index.html", "index.html")
print(f"wrote {out} ({out.stat().st_size / 1048576:.0f} MB)")
PY

pkill -f "http.server $PORT" 2>/dev/null
sleep 1
# setsid + </dev/null, or the server holds the caller's shell open and the
# command never returns.
cd "$STAGE" && setsid python3 -m http.server "$PORT" --bind 0.0.0.0 \
  </dev/null >"$STAGE/server.log" 2>&1 &
sleep 2
echo "serving $STAGE on :$PORT"
echo "public: https://work-2-<work-host>.prod-runtime.all-hands.dev/"
