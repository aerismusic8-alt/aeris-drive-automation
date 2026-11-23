#!/usr/bin/env python3
"""Measure a rendered song for the defect K heard as "เพลงมีกระตุก" (2026-11-23).

A Flow Music take is created near 180 s and then *extended*: each extend
re-renders the whole take with a section appended, and the model appends what it
last sang. On song 52 that produced five choruses and three outros, and the
chorus blocks correlate 0.99-1.00 with each other — the same recording pasted
back, not a re-sung variation. That is the jerk: the song restarts itself.

Three numbers catch it, all read from the artifact:

* how many times each section name is sung, and how long each block lasts,
* the timbre correlation between blocks of the same name (>0.97 = the same
  audio pasted, not a new performance),
* the longest block as a share of the song (an outro of 40 s is a tail, not a
  section).

The section *times* are the model's own labels and are coarse — a 60 s block can
carry three choruses — so this does not test whether a section ends on a bar line.
It tests the form: how often each section is sung, how long the tail runs, and
whether two same-named blocks are literally the same audio.

Run:  python3 ops/song_qc.py 52-phuean-kan-talot-pai [--json out.json]
Exit: 0 clean, 1 repeat-stitched, 2 too few sections to judge.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MUSIC = ROOT / "music938-1"
CLIPMETA = MUSIC / "library" / "songs"
SONGS = MUSIC / "library" / "songs"

# A chorus four times is a normal pop/rock form, so counting choruses cannot
# separate a good take from a stitched one: song 53 (four choruses, written that
# way) and song 52 (five choruses, three outros) differ by the tail, not by the
# count. The labels are also the model's own and are noisy — it emits "Section12".
# So the gate keeps only what it can measure reliably: a tail that eats the song,
# and two blocks that are literally the same audio.
MAX_TAIL_SHARE = 0.16
SAME_AUDIO = 0.90


def markers(clipmeta: dict) -> list[tuple[str, float, float]]:
    """Section name, start and end, from the model's own timing markers."""
    text = clipmeta.get("lyrics", {}).get("value", {}).get("text", "")
    names = [line.strip().strip("[]") for line in text.splitlines()
             if line.strip().startswith("[") and line.strip().endswith("]")]
    marks = [m[1] for m in clipmeta.get("lyrics_timing", {})
             .get("value", {}).get("markers", [])]
    end = float(clipmeta.get("duration", {}).get("value", 0) or 0)
    out = []
    for i, start in enumerate(marks):
        stop = marks[i + 1] if i + 1 < len(marks) else end
        name = names[i] if i < len(names) else f"Section{i + 1}"
        out.append((name, float(start), float(stop)))
    return out


def wave_corr(a: np.ndarray, b: np.ndarray, sr: int, maxlag: float = 0.5) -> float:
    """Waveform correlation with a small lag search.

    A 24-band spectrum correlates ~1.00 between two *different* performances of
    the same arrangement, so it cannot tell "pasted" from "re-sung". The waveform
    can: a pasted block lands near 1.0, a re-sung one well under 0.6. Measured on
    song 52 (124.3s vs 177.2s): spectrum 1.00, waveform 0.06 — re-sung.
    """
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    if n < sr:
        return 0.0
    best = -1.0
    for lag in range(-int(maxlag * sr), int(maxlag * sr) + 1, 64):
        bb = np.roll(b, lag)
        best = max(best, float(a @ bb / (np.linalg.norm(a) * np.linalg.norm(bb) + 1e-9)))
    return best


def load_audio(path: Path) -> tuple[np.ndarray, int]:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        wav = Path(t.name)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-ac", "1",
                    "-ar", "22050", str(wav)], check=True)
    w = wave.open(str(wav))
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    wav.unlink(missing_ok=True)
    return x, sr


def measure(slug: str) -> dict:
    meta_path = CLIPMETA / f"clipmeta-{slug}.json"
    song = SONGS / f"song-{slug}.mp3"
    report: dict = {"slug": slug, "song": str(song), "problems": []}
    if not meta_path.exists() or not song.exists():
        report["problems"].append("missing clipmeta or master")
        report["verdict"] = "NO_INPUT"
        return report
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    secs = markers(meta)
    x, sr = load_audio(song)
    total = len(x) / sr
    report["seconds"] = round(total, 1)
    report["sections"] = [{"name": n, "start": round(a, 1), "seconds": round(b - a, 1)}
                          for n, a, b in secs]
    counts: dict[str, int] = {}
    for n, _, _ in secs:
        counts[n] = counts.get(n, 0) + 1
    report["counts"] = counts
    if len(secs) < 3:
        report["verdict"] = "TOO_FEW_SECTIONS"
        report["problems"].append(f"only {len(secs)} sections")
        return report

    worst = 0.0
    worst_pair = None
    for i in range(len(secs)):
        for j in range(i + 1, len(secs)):
            if secs[i][0] != secs[j][0]:
                continue
            c = wave_corr(x[int(secs[i][1] * sr):int(secs[i][2] * sr)],
                          x[int(secs[j][1] * sr):int(secs[j][2] * sr)], sr)
            if c > worst:
                worst, worst_pair = c, (secs[i][0], round(secs[i][1], 1), round(secs[j][1], 1))
    report["same_section_correlation"] = round(worst, 3)
    report["same_section_pair"] = worst_pair

    tail_name, tail_start, tail_end = secs[-1]
    share = (tail_end - tail_start) / total
    report["tail"] = {"name": tail_name, "seconds": round(tail_end - tail_start, 1),
                      "share": round(share, 3)}
    if share > MAX_TAIL_SHARE:
        report["problems"].append(
            f"the last section ({tail_name}) runs {tail_end - tail_start:.0f}s, "
            f"{share:.0%} of the song")
    if worst >= SAME_AUDIO:
        report["problems"].append(
            f"{worst_pair[0]} at {worst_pair[1]}s and {worst_pair[2]}s are the same audio "
            f"(waveform correlation {worst:.2f}) — the take was extended by pasting it back")
    report["verdict"] = "LONG_TAIL" if report["problems"] else "CLEAN"
    return report


def bpm_from_audio(x: np.ndarray, sr: int) -> float | None:
    """Tempo measured from the onsets, not read from the lyric header.

    The header is what the model was *asked* for; song 52 asked 104 and came back
    at 103.4. A grid check against the wrong tempo invents broken sections, so the
    grid is drawn from the audio.
    """
    hop = 256
    n = 1024
    frames = [x[i:i + n] * np.hanning(n) for i in range(0, len(x) - n, hop)]
    S = np.abs(np.fft.rfft(np.array(frames), axis=1))
    flux = np.maximum(0, np.diff(S, axis=0)).sum(1)
    flux = flux - flux.mean()
    ac = np.correlate(flux, flux, "full")[len(flux) - 1:]
    dt = hop / sr
    lo, hi = int(0.3 / dt), int(1.0 / dt)
    k = lo + int(np.argmax(ac[lo:hi]))
    return round(60.0 / (k * dt), 1) if k > 0 else None



def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("slugs", nargs="+")
    ap.add_argument("--json", help="write the report here")
    args = ap.parse_args()
    out = [measure(s) for s in args.slugs]
    for r in out:
        print(f"{r['slug']}: {r['verdict']}  {r.get('seconds', '?')}s  {r.get('counts', {})}")
        for p in r["problems"]:
            print(f"   - {p}")
    if args.json:
        Path(args.json).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if all(r["verdict"] == "CLEAN" for r in out) else 1


if __name__ == "__main__":
    sys.exit(main())
