#!/usr/bin/env bash
# Render the long-form clip for every song whose cover is newer than its clip.
#
# The clips are what gets uploaded: a 1080p frame built from the AI cover plus
# the song, with no burned text (make_karaoke.py --captions is off by default, at
# K's order). A new cover therefore invalidates the old clip, which is why this
# compares mtimes rather than just existence.
#
# It is resumable and safe to interrupt: it renders whatever is ready and exits,
# so it can be called again as more covers land.
#
#   scripts/render_clips.sh            # render what is stale
#   scripts/render_clips.sh --loop     # keep going as covers appear
set -u
cd "$(dirname "$0")/.."
export PYTHONPATH="${PYTHONPATH:-/workspace/ax-tools/pylibs}"

LOOP=0
[ "${1:-}" = "--loop" ] && LOOP=1

render_one() {
  local slug="$1"
  local cover="library/covers/cover-${slug}.jpg"
  local song="library/songs/song-${slug}.mp3"
  local clip="library/karaoke/song-${slug}.mp4"
  [ -f "$cover" ] || return 1
  [ -f "$song" ] || return 1
  if [ -f "$clip" ] && [ "$clip" -nt "$cover" ]; then
    return 2   # already current
  fi
  python3 scripts/make_karaoke.py "$slug" --mix song >/dev/null 2>&1 \
    && echo "  rendered ${slug}" || echo "  FAILED ${slug}"
  return 0
}

round=0
while :; do
  round=$((round + 1))
  stale=0
  for f in library/covers/cover-*.jpg; do
    slug="$(basename "$f" .jpg)"; slug="${slug#cover-}"
    render_one "$slug"
    rc=$?
    [ "$rc" -eq 0 ] && stale=$((stale + 1))
  done
  echo "round ${round}: ${stale} rendered"
  [ "$stale" -eq 0 ] && break
  [ "$LOOP" -eq 0 ] && break
  # covers are still being generated; wait and re-check
  sleep 60
done
