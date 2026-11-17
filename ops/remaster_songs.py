#!/usr/bin/env python3
"""Re-master the song library to the channel standard (free: ffmpeg only).

The video lanes mux `library/songs/song-<slug>.mp3` directly, so a master that
clips ships a clipped clip. Measured 2026-11-17: 24 of 28 song masters sat above
0 dBTP (up to +1.6) — stale artifacts from before the two-pass master, not a bug
in `make_song.py` (which reproduces -14.1 LUFS / -13.1 dBTP correctly). This
normalises each master to the same target the masterer uses, so the floor holds
for every lane at once instead of patching each mux.

    python3 ops/remaster_songs.py                 # fix every out-of-band master
    python3 ops/remaster_songs.py --dry-run       # report only
    python3 ops/remaster_songs.py --only song-24-yut-mai-yom

A master already inside the band and under -1.0 dBTP is left untouched, so the
tool is idempotent and safe to re-run. Song masters go to -14 LUFS; karaoke
masters (the instrumental) to -17 LUFS, matching make_song's -3 LU offset.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

SONG_TARGET = -14.0
KARAOKE_TARGET = -17.0
TRUE_PEAK = -1.5
LRA = 11


def ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def measure(path: str):
    out = subprocess.run(
        [ffmpeg(), "-hide_banner", "-i", path,
         "-af", "loudnorm=print_format=summary", "-f", "null", "-"],
        capture_output=True, text=True)
    lufs = peak = None
    for line in out.stderr.splitlines():
        if "Input Integrated:" in line:
            lufs = float(line.split(":")[1].strip().split()[0])
        elif "Input True Peak:" in line:
            peak = float(line.split(":")[1].strip().split()[0])
    return lufs, peak


def target_for(name: str) -> float:
    return KARAOKE_TARGET if name.startswith("karaoke-") else SONG_TARGET


def in_band(lufs, peak, target: float) -> bool:
    return (lufs is not None and peak is not None
            and target - 2.0 <= lufs <= target + 2.0 and peak <= -1.0)


def remaster(path: str, target: float) -> None:
    """Normalise in place. Decode from the lossless WAV master when it exists."""
    wav = os.path.splitext(path)[0] + ".wav"
    src = wav if os.path.exists(wav) else path
    tmp = path + ".tmp.mp3"
    subprocess.run(
        [ffmpeg(), "-y", "-v", "error", "-i", src,
         "-af", f"loudnorm=I={target}:TP={TRUE_PEAK}:LRA={LRA}",
         "-ar", "48000", "-ac", "2",
         "-c:a", "libmp3lame", "-b:a", "192k", tmp], check=True)
    os.replace(tmp, path)
    if src == wav:  # keep the WAV master consistent for future renders
        subprocess.run(
            [ffmpeg(), "-y", "-v", "error", "-i", wav,
             "-af", f"loudnorm=I={target}:TP={TRUE_PEAK}:LRA={LRA}",
             "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", wav + ".tmp.wav"],
            check=True)
        os.replace(wav + ".tmp.wav", wav)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="music938-1/library/songs")
    ap.add_argument("--only", help="a slug fragment, e.g. song-24")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not os.path.isdir(a.dir):
        raise SystemExit(f"no such directory: {a.dir}")
    files = sorted(f for f in os.listdir(a.dir)
                   if f.endswith(".mp3") and (f.startswith("song-")
                                              or f.startswith("karaoke-")))
    if a.only:
        files = [f for f in files if a.only in f]
    fixed = skipped = 0
    for name in files:
        path = os.path.join(a.dir, name)
        lufs, peak = measure(path)
        target = target_for(name)
        if in_band(lufs, peak, target):
            skipped += 1
            continue
        fixed += 1
        print(f"  {'would fix' if a.dry_run else 'fixing  '} {name:42s} "
              f"{lufs} LUFS {peak} dBTP -> {target} LUFS")
        if not a.dry_run:
            remaster(path, target)
            nl, npk = measure(path)
            print(f"            -> {nl} LUFS {npk} dBTP")
    print(f"\n{fixed} {'to fix' if a.dry_run else 'fixed'}, {skipped} already in band")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
