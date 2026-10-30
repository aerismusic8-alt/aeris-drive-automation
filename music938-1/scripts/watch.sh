#!/usr/bin/env bash
# Watch the music938-1 batch: durable log tail, process, and built counts.
# After a pod recycle, run resume.sh instead; this one only reports.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/work/batch.log"

echo "--- batch log (tail) ---"
tail -n "${1:-25}" "$LOG" 2>/dev/null || echo "(no log yet)"
echo
echo "--- batch process ---"
pgrep -af "build_songs.py" || echo "(not running - restart: scripts/resume.sh)"
echo
echo "--- built ---"
printf 'songs:  %s\n' "$(ls "$ROOT/library/songs"/song-*.mp3 2>/dev/null | wc -l)"
printf 'karaoke: %s\n' "$(ls "$ROOT/library/songs"/karaoke-*.mp3 2>/dev/null | wc -l)"
printf 'videos: %s\n' "$(ls "$ROOT/library/karaoke"/karaoke-*.mp4 2>/dev/null | wc -l)"
printf 'covers: %s\n' "$(ls "$ROOT/library/covers"/cover-*.jpg 2>/dev/null | wc -l)"
