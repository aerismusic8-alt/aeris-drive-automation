#!/usr/bin/env bash
# Fetch the rbxmk CLI, which reads and writes Roblox place files.
#
# Pinned to a version rather than "latest": the build depends on a specific
# reader and writer, and a silent upgrade would change the output of a publish
# with no diff to review. The archive is cached under tools/ and .gitignored.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${RBXMK_DIR:-$ROOT/tools/rbxmk}"
VERSION="${RBXMK_VERSION:-v0.9.1}"

if [ -x "$DEST/rbxmk" ]; then
  echo "RBXMK_PRESENT=$DEST/rbxmk"
  exit 0
fi

mkdir -p "$DEST"
url="https://github.com/Anaminus/rbxmk/releases/download/${VERSION}/rbxmk-${VERSION}-linux-amd64.zip"
echo "RBXMK_FETCH=$url"
curl -sS -fL -o "$DEST/rbxmk.zip" "$url"

python3 - "$DEST" <<'PY'
import os
import sys
import zipfile

d = sys.argv[1]
with zipfile.ZipFile(os.path.join(d, "rbxmk.zip")) as z:
    z.extractall(d)
PY

chmod +x "$DEST/rbxmk"
"$DEST/rbxmk" version
echo "RBXMK=$DEST/rbxmk"
