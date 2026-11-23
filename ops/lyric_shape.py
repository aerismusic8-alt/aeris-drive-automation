#!/usr/bin/env python3
"""Measure how a hit song is built — syllables per line, hook, riff period.

K (2026-11-23): "จับเรื่องเนื้อหาการแต่งเนื้อเพลง พยางค์ที่ใช้ อันนี้สำคัญ ช่วงฮุค
จังหวะริฟ" — the craft, not just the loudness. The reference songs are hits from
the past, so their shape is the part worth copying.

No lyrics file is needed. Thai is syllable-timed: one syllable is one vowel
nucleus, and in the 250-3500 Hz band that is one energy peak. Counting peaks
between breaths gives the line length a singer actually has to fill, which is
the number `ai_lyrics.py` asks a model for.

What is measured:

  phrase_peaks        energy peaks between pauses >= 250 ms (NOT syllables)

The acoustic syllable count was tried and failed: on a finished master the
250-3500 Hz band carries the instruments too, so the envelope never falls quiet
and one "phrase" swallowed the whole song (276 and 520 peaks/line measured on
real hits). Those numbers are reported as `phrase_peaks`, not syllables, and the
syllable question is answered from the words in `ops/lyric_text.py`.
  lines               how many such phrases the song has
  hook_at             first position (share of the song) of the most repeated
                      8 s block — where the chorus lands
  hook_repeats        how many blocks sound like that one
  riff_beats          onset autocorrelation peak, in beats — the riff length

Limits, stated so nobody reads more into it: it says where the hook is and how
long the riff is, not whether either is good. Rhyme and syllables need words —
`ops/lyric_text.py`.

    python3 ops/lyric_shape.py --dir work/refs --limit 8 --out work/lyric-shape.json
"""
from __future__ import annotations

import argparse
import json
import statistics as st
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from reference_profile import AUDIO_EXT, SR, decode, estimate_bpm, onset_envelope  # noqa: E402

WIN, HOP = 1024, 256
FPS = SR / HOP


def stft(x: np.ndarray) -> np.ndarray:
    frames = 1 + (len(x) - WIN) // HOP
    idx = np.arange(WIN)[None, :] + HOP * np.arange(frames)[:, None]
    return np.abs(np.fft.rfft(x[idx] * np.hanning(WIN), axis=1))


def vocal_envelope(spec: np.ndarray) -> np.ndarray:
    freqs = np.fft.rfftfreq(WIN, 1.0 / SR)
    band = (freqs >= 250) & (freqs <= 3500)
    env = spec[:, band].sum(axis=1)
    return np.convolve(env, np.ones(5) / 5, mode="same")


def count_phrases(env: np.ndarray) -> list[int]:
    """Split at pauses, then count energy peaks inside each phrase."""
    floor = np.median(env) * 0.25
    quiet = env < floor
    phrases, start = [], None
    gap = 0
    for i, q in enumerate(quiet):
        if q:
            gap += 1
            if start is not None and gap > 0.25 * FPS:
                phrases.append((start, i - gap))
                start = None
        else:
            if start is None:
                start = i
            gap = 0
    if start is not None:
        phrases.append((start, len(env) - 1))
    out = []
    for a, b in phrases:
        seg = env[a:b]
        if len(seg) < 0.4 * FPS:
            continue
        thr = seg.mean() * 1.25
        peaks, i = 0, 1
        while i < len(seg) - 1:
            if seg[i] > thr and seg[i] >= seg[i - 1] and seg[i] > seg[i + 1]:
                peaks += 1
                i += int(0.10 * FPS)  # a syllable is >= 100 ms apart
            else:
                i += 1
        if peaks >= 3:
            out.append(peaks)
    return out


def chroma_blocks(spec: np.ndarray, block_s: float = 8.0) -> np.ndarray:
    freqs = np.fft.rfftfreq(WIN, 1.0 / SR)
    midi = np.round(69 + 12 * np.log2(np.maximum(freqs, 1e-9) / 440.0)).astype(int)
    pc = np.mod(midi, 12)
    valid = freqs > 55
    chroma = np.zeros((spec.shape[0], 12))
    for k in range(12):
        sel = valid & (pc == k)
        if sel.any():
            chroma[:, k] = spec[:, sel].mean(axis=1)
    per = int(block_s * FPS)
    n = chroma.shape[0] // per
    if n < 2:
        return np.zeros((0, 12))
    blocks = chroma[:n * per].reshape(n, per, 12).mean(axis=1)
    return blocks / (np.linalg.norm(blocks, axis=1, keepdims=True) + 1e-9)


def hook(blocks: np.ndarray, block_s: float) -> tuple[float, int]:
    if len(blocks) < 4:
        return 0.0, 0
    # Centred cosine: without removing the mean every block in one key scores
    # ~0.99 against every other, and "the hook" becomes block 0 for every song.
    centred = blocks - blocks.mean(axis=1, keepdims=True)
    norm = np.linalg.norm(centred, axis=1, keepdims=True) + 1e-9
    sim = (centred / norm) @ (centred / norm).T
    sim[np.abs(np.subtract.outer(np.arange(len(blocks)), np.arange(len(blocks)))) <= 1] = -1
    repeats = (sim > 0.93).sum(axis=1)
    best = int(np.argmax(repeats))
    # Prefer the first occurrence of a shape that repeats, not a later copy.
    if repeats[best] < 2:
        return 0.0, 0
    for i in range(len(repeats)):
        if repeats[i] >= repeats[best] - 1 and sim[i, best] > 0.93:
            best = i
            break
    return round(best * block_s / (len(blocks) * block_s) * 100, 1), int(repeats[best])


def riff_beats(flux: np.ndarray, bpm: float) -> float:
    if len(flux) < 64 or flux.std() == 0 or not bpm:
        return 0.0
    env = flux - flux.mean()
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    beat = 60.0 / bpm * FPS
    lo, hi = int(beat * 0.8), int(beat * 8.1)
    if hi >= len(ac):
        return 0.0
    lag = lo + int(np.argmax(ac[lo:hi]))
    return round(lag / beat, 1)


def measure(path: Path) -> dict:
    x = decode(path)
    spec = stft(x)
    env = vocal_envelope(spec)
    lines = count_phrases(env)
    flux, _ = onset_envelope(x)
    bpm = estimate_bpm(flux)
    pos, reps = hook(chroma_blocks(spec), 8.0)
    return {
        "file": path.name,
        "duration_s": round(len(x) / SR, 1),
        "bpm": bpm,
        "lines": len(lines),
        "phrase_peaks_median": int(st.median(lines)) if lines else 0,
        "phrase_peaks_mode": st.mode(lines) if lines else 0,
        "phrase_peaks_p10_p90": [int(np.percentile(lines, 10)), int(np.percentile(lines, 90))] if lines else [0, 0],
        "hook_at_pct": pos,
        "hook_repeats": reps,
        "riff_beats": riff_beats(flux, bpm),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir")
    ap.add_argument("--file", action="append", default=[])
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--out")
    args = ap.parse_args()

    files = [Path(f) for f in args.file]
    if args.dir:
        files += sorted(p for p in Path(args.dir).rglob("*") if p.suffix.lower() in AUDIO_EXT)
    if args.limit:
        files = files[:args.limit]
    if not files:
        raise SystemExit("nothing to measure")

    rows = []
    for p in files:
        try:
            r = measure(p)
        except Exception as exc:  # noqa: BLE001
            print(f"  SKIP {p.name}: {type(exc).__name__} {str(exc)[:70]}", file=sys.stderr)
            continue
        rows.append(r)
        print(f"  {r['phrase_peaks_median']:3d} peaks/phrase (mode {r['phrase_peaks_mode']:2d}, "
              f"{r['lines']:3d} lines)  hook@{r['hook_at_pct']:5.1f}% x{r['hook_repeats']:2d}  "
              f"riff {r['riff_beats']:4.1f} beats  {p.name[:44]}")

    if not rows:
        return 1
    summary = {
        "songs": len(rows),
        "phrase_peaks_median": int(st.median([r["phrase_peaks_median"] for r in rows])),
        "phrase_peaks_mode": st.mode([r["phrase_peaks_median"] for r in rows]),
        "lines_median": int(st.median([r["lines"] for r in rows])),
        "hook_at_pct_median": round(st.median([r["hook_at_pct"] for r in rows]), 1),
        "riff_beats_median": round(st.median([r["riff_beats"] for r in rows]), 1),
        "bpm_median": round(st.median([r["bpm"] for r in rows]), 1),
    }
    print("\nshape:", json.dumps(summary, ensure_ascii=False))
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"summary": summary, "songs": rows},
                                  ensure_ascii=False, indent=2), encoding="utf-8")
        print("written:", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
