#!/usr/bin/env bash
# Build the AX Arena place without PC1.
#
# Rojo ships a Linux binary and the place is just a file, so nothing about the
# build needs Windows. That matters because PC1 has been unreachable, and a
# build step that only runs there makes the whole pipeline hostage to one
# machine.
#
# Usage:
#   bash scripts/build-place-linux.sh [output-path]
#
# Writes the .rbxlx and prints BUILD_PLACE=<path> on success.

set -euo pipefail

OUT="${1:-AXGarden.rbxlx}"
ROJO_VERSION="${ROJO_VERSION:-7.7.1}"
TOOLS_DIR="${TOOLS_DIR:-.rojo-tools}"
PROJECT="${PROJECT:-roblox-garden/default.project.json}"

if [ ! -f "$PROJECT" ]; then
  echo "PROJECT_MISSING=$PROJECT" >&2
  exit 2
fi

mkdir -p "$TOOLS_DIR"

if [ ! -x "$TOOLS_DIR/rojo" ]; then
  echo "ROJO_DOWNLOAD=starting"
  url="https://github.com/rojo-rbx/rojo/releases/download/v${ROJO_VERSION}/rojo-${ROJO_VERSION}-linux-x86_64.zip"
  curl -sS -L -o "$TOOLS_DIR/rojo.zip" "$url"
  # `unzip` is not present in every runner image, so use Python, which is.
  python3 - "$TOOLS_DIR" <<'PY'
import os
import sys
import zipfile

d = sys.argv[1]
with zipfile.ZipFile(os.path.join(d, "rojo.zip")) as z:
    z.extractall(d)
for name in os.listdir(d):
    if name == "rojo" or name.startswith("rojo"):
        p = os.path.join(d, name)
        if os.path.isfile(p) and not name.endswith(".zip"):
            os.chmod(p, 0o755)
PY
  rm -f "$TOOLS_DIR/rojo.zip"
fi

if [ ! -x "$TOOLS_DIR/rojo" ]; then
  echo "ROJO_MISSING_AFTER_EXTRACT" >&2
  exit 2
fi

echo "ROJO_VERSION=$("$TOOLS_DIR/rojo" --version)"

"$TOOLS_DIR/rojo" build "$PROJECT" --output "$OUT"

if [ ! -s "$OUT" ]; then
  echo "BUILD_OUTPUT_EMPTY=$OUT" >&2
  exit 2
fi

# A place file that parses but carries nothing would still pass a size check,
# so assert the root element and a couple of classes the game needs.
python3 - "$OUT" <<'PY'
import sys

path = sys.argv[1]
head = open(path, "rb").read(4096).decode("utf-8", "replace")
if "<roblox" not in head:
    print(f"BUILD_OUTPUT_NOT_A_PLACE={path}", file=sys.stderr)
    sys.exit(2)
print(f"PLACE_ROOT_OK={path}")
PY

SIZE=$(wc -c < "$OUT")
echo "BUILD_PLACE_SIZE=$SIZE"
echo "BUILD_PLACE=$OUT"
