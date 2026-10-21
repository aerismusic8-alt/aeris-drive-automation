#!/usr/bin/env bash
# Build the Breachline place from the recovered base plus the source overlay.
#
# Two stages: the overlay replaces script sources and adds new modules, then the
# scene pass bakes the lighting values into the place. Both write a whole place
# file, so the output of this script is what gets published.
#
# Usage:
#   bash scripts/build-breachline.sh [output.rbxl]
#
# Writes breachline/build/breachline.rbxl and prints BUILD_PLACE=<path>.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/breachline/build/breachline.rbxl}"
BASE="$ROOT/breachline/base.rbxl"
OVERLAY="$ROOT/breachline/overlay"
RBXMK="${RBXMK:-$ROOT/tools/rbxmk/rbxmk}"

if [ ! -x "$RBXMK" ]; then
  echo "RBXMK_MISSING=$RBXMK (run scripts/fetch-rbxmk.sh)" >&2
  echo "Install rbxmk v0.9.1, or set RBXMK to its path." >&2
  exit 2
fi

if [ ! -s "$BASE" ]; then
  # The committed artifact is the compact zstd original; the readable place is
  # derived from it, so a fresh checkout rebuilds it rather than storing 2.3 MB.
  if [ -s "$ROOT/breachline-src/breachline-place.rbxl" ]; then
    echo "BASE_UNPACK=starting"
    bash "$ROOT/scripts/unpack-breachline.sh" "$ROOT/breachline-src/breachline-place.rbxl" "$BASE"
  fi
fi

if [ ! -s "$BASE" ]; then
  echo "BASE_MISSING=$BASE (run scripts/unpack-breachline.sh)" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

"$RBXMK" run --allow-insecure-paths "$ROOT/breachline/build.lua" \
  "$BASE" "$OVERLAY" "$STAGE/stage1.rbxl"

"$RBXMK" run --allow-insecure-paths "$ROOT/breachline/scene.lua" \
  "$STAGE/stage1.rbxl" "$OUT"

echo "BUILD_PLACE=$OUT"
echo "BUILD_BYTES=$(wc -c < "$OUT")"
# retested 2026-10-21T20:47:33Z after the scope grant
