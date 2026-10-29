#!/usr/bin/env python3
"""Report on the music938-1 pack: what exists, what is missing, and whether each
song meets the brief (3.5-5 min, a real vocal, a karaoke mix).

Run:  python3 scripts/report.py [--json]

Exits non-zero if any song is missing an output or falls outside the length
window, so it can gate a release.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common  # noqa: E402

MIN_S, MAX_S = 210.0, 300.0


def band_rms(path: Path, lo: int, hi: int) -> float:
    """Mean volume (dBFS) of one frequency band, used to compare two mixes."""
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(path), "-af",
         f"bandpass=f={(lo + hi) // 2}:width_type=h:w={hi - lo},"
         "astats=metadata=1:reset=0,ametadata=print:key=lavfi.astats.Overall.RMS_level",
         "-f", "null", "-"],
        capture_output=True, text=True)
    vals = [float(m) for m in re.findall(r"RMS_level=(-?\d+\.?\d*)", r.stderr)]
    return sum(vals) / len(vals) if vals else -100.0


def vocal_present(song: Path, kara: Path) -> tuple[bool, str]:
    """Decide whether the lead vocal is really in the mix.

    Flow Music gives no per-note data, so this compares the two masters in the
    300-3400 Hz band, where a lead vocal sits. A real center-cancel leaves that
    band several dB quieter in the karaoke than in the song; if the two are
    nearly equal the vocal was probably never there.
    """
    v = band_rms(song, 300, 3400)
    k = band_rms(kara, 300, 3400)
    drop = v - k
    return drop >= 1.0, f"vocal band {v:.1f} dB vs karaoke {k:.1f} dB (drop {drop:.1f})"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    lyrics = sorted(common.LYRICS.glob("*.txt"))
    rows = []
    ok = True
    for p in lyrics:
        slug = p.stem
        song = common.LIBRARY / "songs" / f"song-{slug}.mp3"
        kara = common.LIBRARY / "songs" / f"karaoke-{slug}.mp3"
        cover = common.LIBRARY / "covers" / f"cover-{slug}.jpg"
        video = common.LIBRARY / "karaoke" / f"karaoke-{slug}.mp4"

        missing = [n for n, f in (("song", song), ("karaoke", kara),
                                  ("cover", cover), ("video", video))
                   if not f.exists()]
        dur = common.duration(song) if song.exists() else 0.0
        in_window = MIN_S <= dur <= MAX_S
        vocal, note = (False, "song or karaoke missing")
        if song.exists() and kara.exists():
            vocal, note = vocal_present(song, kara)

        good = not missing and in_window and vocal
        ok = ok and good
        rows.append({"slug": slug, "duration": round(dur, 1), "missing": missing,
                     "in_window": in_window, "vocal": vocal, "note": note,
                     "ok": good})

    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    else:
        print(f"{'song':38} {'dur':>7} {'3.5-5':>6} {'vocal':>6} {'ok':>4}  missing")
        for r in rows:
            print(f"{r['slug']:38} {r['duration']:7.1f} "
                  f"{'yes' if r['in_window'] else 'NO':>6} "
                  f"{'yes' if r['vocal'] else 'NO':>6} "
                  f"{'ok' if r['ok'] else 'NO':>4}  {','.join(r['missing'])}")
        good = sum(1 for r in rows if r["ok"])
        print(f"\n{good}/{len(rows)} songs complete")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
