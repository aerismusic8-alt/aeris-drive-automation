"""Offline mood music, synthesised with ffmpeg.

This is the no-account fallback for the music library. It is not a substitute for
a real composed track, but it is deterministic, royalty-free and needs no login,
so the pipeline can always be run end to end. Tracks are generated from a mood
preset (root note, scale, tempo, timbre) and filed in the music manifest with the
same shape as a generated song, so the composer does not care which produced it.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library  # noqa: E402

# Mood presets: semitone offsets from the root, in a pentatonic-ish set that
# stays consonant however the notes are sequenced.
MOODS = {
    "calm":    {"root": 220.0, "tempo": 60, "scale": [0, 2, 4, 7, 9], "gain": 0.30, "bpm": 60},
    "warm":    {"root": 196.0, "tempo": 66, "scale": [0, 3, 5, 7, 10], "gain": 0.30, "bpm": 66},
    "sad":     {"root": 174.6, "tempo": 52, "scale": [0, 2, 3, 7, 8], "gain": 0.28, "bpm": 52},
    "hopeful": {"root": 261.6, "tempo": 72, "scale": [0, 2, 4, 7, 11], "gain": 0.30, "bpm": 72},
    "mystic":  {"root": 146.8, "tempo": 48, "scale": [0, 1, 5, 7, 8], "gain": 0.26, "bpm": 48},
    "epic":    {"root": 164.8, "tempo": 84, "scale": [0, 3, 5, 7, 10], "gain": 0.32, "bpm": 84},
}


def _freq(root: float, semitones: int) -> float:
    return root * (2 ** (semitones / 12))


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True)


def _measure(path: Path) -> dict:
    out = _run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
                "-filter_complex", "ebur128=peak=true", "-f", "null", "-"])
    lufs = None
    for line in out.stderr.splitlines():
        s = line.strip()
        if s.startswith("I:"):
            lufs = float(s.split()[1])
    return {"integrated_lufs": lufs}


def _synthesise(mood: str, out: Path, duration: float) -> dict:
    """Layer a slow pad, a plucked arpeggio and a soft bass, then loop-tile it."""
    preset = MOODS[mood]
    root, scale = preset["root"], preset["scale"]
    bpm = preset["bpm"]
    beat = 60.0 / bpm

    # A pad: two detuned saws through a lowpass, plus slow tremolo.
    pad = (
        f"sine=frequency={root:.2f}:duration={duration}[p1];"
        f"sine=frequency={root * 1.005:.2f}:duration={duration}[p2];"
        f"sine=frequency={root * 2:.2f}:duration={duration}[p3];"
        f"[p1][p2][p3]amix=inputs=3:normalize=0,"
        f"lowpass=f=900,tremolo=f=0.15:d=0.35,volume={preset['gain']:.2f}[pad]"
    )

    # An arpeggio: one short note per beat, cycling the scale, decaying.
    notes = []
    steps = int(duration / beat)
    for i in range(steps):
        semi = scale[i % len(scale)] + 12 * ((i // len(scale)) % 2)
        notes.append(f"sine=frequency={_freq(root, semi):.2f}:duration={beat * 1.8}")
    if not notes:
        notes = [f"sine=frequency={root:.2f}:duration={duration}"]
    arp = (
        ";".join(f"{n}[n{i}]" for i, n in enumerate(notes))
        + ";" + "".join(f"[n{i}]" for i in range(len(notes)))
        + f"amix=inputs={len(notes)}:normalize=0,"
        + f"aeval='val(0)*exp(-3*t)':c=same,volume={preset['gain'] * 0.55:.2f},"
        + "highpass=f=180[arp]"
    )

    bass = (
        f"sine=frequency={root / 2:.2f}:duration={duration},"
        f"volume={preset['gain'] * 0.8:.2f}[bass]"
    )

    filt = (
        f"{pad};{arp};{bass};"
        f"[pad][arp][bass]amix=inputs=3:normalize=0,"
        f"aecho=0.8:0.85:220|380:0.28|0.18,"
        f"afade=t=in:d=3,afade=t=out:st={max(0.0, duration - 4):.2f}:d=4,"
        f"loudnorm=I=-20:TP=-3:LRA=9"
    )

    out.parent.mkdir(parents=True, exist_ok=True)
    res = _run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-filter_complex", filt, "-map", "[out]",
                "-c:a", "libmp3lame", "-b:a", "192k", str(out)])
    if res.returncode != 0 or not out.exists() or out.stat().st_size == 0:
        # The amix label is implicit; re-run with an explicit output label.
        filt2 = filt.replace("loudnorm=I=-20:TP=-3:LRA=9",
                             "loudnorm=I=-20:TP=-3:LRA=9[out]")
        res = _run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-filter_complex", filt2, "-map", "[out]",
                    "-c:a", "libmp3lame", "-b:a", "192k", str(out)])
        if res.returncode != 0:
            raise RuntimeError(f"music synthesis failed: {res.stderr.strip()[-900:]}")
    return {"bytes": out.stat().st_size, "bpm": bpm, **_measure(out)}


def make(mood: str, key: str, *, duration: float = 90.0, force: bool = False) -> dict:
    if mood not in MOODS:
        raise ValueError(f"unknown mood {mood!r}; choose from {sorted(MOODS)}")
    existing = library.find("music", key)
    if existing and not force:
        return {"status": "REUSED", "entry": existing}

    out = library.KINDS["music"] / f"{library.entry_id('music', key)}.mp3"
    info = _synthesise(mood, out, duration)
    entry = library.add("music", key, out, source="ffmpeg-synth", mood=mood,
                        duration_seconds=duration, bpm=info["bpm"],
                        integrated_lufs=info["integrated_lufs"])
    return {"status": "CREATED", "entry": entry}


def main() -> int:
    ap = argparse.ArgumentParser(description="Synthesise a mood music bed offline")
    ap.add_argument("key")
    ap.add_argument("mood", choices=sorted(MOODS))
    ap.add_argument("--duration", type=float, default=90.0)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    result = make(args.mood, args.key, duration=args.duration, force=args.force)
    print(json.dumps(result, ensure_ascii=False, indent=2) if args.json
          else f"{result['status']}: {result['entry']['file']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
