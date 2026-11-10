#!/usr/bin/env bash
# Install the realistic-sound sampler (sfizz) and its real instrument banks.
#
# K (2026-11-09): the sleep music used a General-MIDI SoundFont, which "sounds
# fake — find a program that makes realistic sound." sfizz is a free SFZ sampler
# that plays multi-velocity recordings of real instruments; this builds it and
# fetches two CC0 banks. Everything lives under /workspace, which survives a pod
# recycle, and the banks are gigabytes so they never enter the repo.
#
# Idempotent: re-running only rebuilds/fetches what is missing.
#
#   music938-1/scripts/install-sfizz.sh
#
# After it runs, `scripts/sampler.py --probe` should pass and every bed renders
# through real instruments. Without it the pack falls back to fluidsynth GM.
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
BIN=/workspace/ax-tools/bin
INST=/workspace/ax-tools/instruments
SFIZZ_BIN="$REPO/tools/sfizz/sfizz_render"

mkdir -p "$BIN" "$INST"

# --- 1. build sfizz_render ----------------------------------------------------
# The release tarball has no Linux binary, so it is built from source. cmake and
# a compiler are needed only here, not at render time.
if [ ! -x "$SFIZZ_BIN" ]; then
  echo "building sfizz..."
  if ! command -v cmake >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq \
      cmake ninja-build build-essential libsndfile1-dev
  fi
  tmp=$(mktemp -d)
  git clone --depth 1 https://github.com/sfztools/sfizz.git "$tmp/sfizz" &&
    git -C "$tmp/sfizz" submodule update --init --recursive &&
    cmake -S "$tmp/sfizz" -B "$tmp/sfizz/build" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DSFIZZ_JACK=OFF -DSFIZZ_LV2=OFF \
      -DSFIZZ_VST=OFF -DSFIZZ_TESTS=OFF -DSFIZZ_DEMOS=OFF \
      -DSFIZZ_DEVTOOLS=OFF -DSFIZZ_RENDER=ON &&
    cmake --build "$tmp/sfizz/build" -j"$(nproc)" &&
    mkdir -p "$REPO/tools/sfizz" &&
    cp "$tmp/sfizz/build/library/bin/sfizz_render" "$SFIZZ_BIN"
  rm -rf "$tmp"
fi
[ -x "$SFIZZ_BIN" ] && echo "sfizz_render -> $SFIZZ_BIN" || {
  echo "sfizz build failed" >&2; exit 1; }

# --- 2. real instrument banks (CC0) ------------------------------------------
fetch_zip() {  # url dest_dir marker_subpath
  local url=$1 dest=$2 marker=$3
  [ -e "$dest/$marker" ] && { echo "have $(basename "$dest")"; return 0; }
  echo "fetching $(basename "$dest")..."
  local tmp; tmp=$(mktemp -d)
  curl -sL -o "$tmp/x.zip" "$url" &&
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
      "$tmp/x.zip" "$tmp/x" &&
    mkdir -p "$dest" &&
    src=$(find "$tmp/x" -maxdepth 1 -mindepth 1 -type d | head -1) &&
    cp -r "$src"/. "$dest"/ &&
    rm -rf "$tmp"
}

# Salamander Grand Piano V3 — a real Yamaha C5, CC0 (Alexander Holm).
fetch_zip "https://github.com/sfzinstruments/SalamanderGrandPiano/archive/refs/heads/master.zip" \
  "$INST/salamander" "Salamander Grand Piano V3.sfz"

# Sonatina Symphonic Orchestra — CC0 orchestral samples (Mattias Westlund).
fetch_zip "https://github.com/peastman/sso/archive/refs/heads/master.zip" \
  "$INST/sso/Sonatina Symphonic Orchestra" "Concert Harp.sfz"

# --- 3. verify ----------------------------------------------------------------
echo "--- probe ---"
python3 "$REPO/scripts/sampler.py" --probe || {
  echo "sampler probe failed" >&2; exit 1; }
echo
echo "realistic instruments ready. Beds render through the sampler when present;"
echo "set USE_REAL_INSTRUMENTS=0 to force the fluidsynth GM fallback."
