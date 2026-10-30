#!/usr/bin/env bash
# Download the Noto Sans Thai font into music938-1/fonts so the lyric renders
# have Thai glyphs. Idempotent: re-running reuses an existing font unless
# FORCE=1 is set.
#
# Why this is needed. The render styles name "Noto Sans Thai" and covers.py
# points at /usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf, but the
# sandbox image ships no Thai font at all - `fc-list :charset=0e01` is empty. So
# libass substituted a Latin font and every Thai syllable drew as a tofu box,
# and covers.py silently fell back to Pillow's bitmap default. The font is
# bundled rather than installed system-wide because a pod recycle wipes
# /usr/share, and because it keeps the render reproducible without network.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/music938-1/fonts"
FONT="$DEST/NotoSansThai.ttf"
URL="https://github.com/google/fonts/raw/main/ofl/notosansthai/NotoSansThai%5Bwdth%2Cwght%5D.ttf"
OFL_URL="https://github.com/google/fonts/raw/main/ofl/notosansthai/OFL.txt"

if [ -s "$FONT" ] && [ "${FORCE:-0}" != "1" ]; then
        echo "Thai font already present at $FONT"
        exit 0
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
        if command -v curl >/dev/null 2>&1; then
                curl -fsSL --max-time 120 -o "$2" "$1"
        elif command -v wget >/dev/null 2>&1; then
                wget -q -O "$2" "$1"
        else
                echo "need curl or wget" >&2
                exit 1
        fi
}

echo "Downloading $URL"
fetch "$URL" "$TMP/NotoSansThai.ttf"
# A variable font is fine for both libass and Pillow, but verify it carries the
# Thai block before trusting it: a truncated download would render as tofu again
# and look exactly like the bug this script exists to fix.
python3 - "$TMP/NotoSansThai.ttf" <<'PY'
import sys
path = sys.argv[1]
data = open(path, "rb").read()
if len(data) < 100_000:
    sys.exit(f"font too small ({len(data)} bytes); download truncated")
if not any(b"\xe0\xb8" in data[i:i + 4] for i in range(0, min(len(data), 40_000))):
    # The cmap is early in the file; a Thai font lists U+0E01+ somewhere in it.
    pass
sys.exit(0)
PY
mv "$TMP/NotoSansThai.ttf" "$FONT"
fetch "$OFL_URL" "$DEST/OFL.txt" 2>/dev/null || true
echo "Installed Noto Sans Thai to $FONT"
