#!/usr/bin/env python3
"""Measure reference songs so the song generator stops guessing.

K (2026-11-23): "เพลงที่มียอดวิว 200 ล้านวิวขึ้นไป ... 20 เพลงในแต่ละแนว".
`ops/reference_chart.py` answers *which* songs; this answers *what they measure*
— and a number is the only part of "listen to a lot of music" that transfers to
a renderer. Every value below becomes a parameter in `make_song.py`, so the
output is a profile, not a review.

What is measured, per file:

  duration      the song's actual length
  bpm           onset-envelope autocorrelation (30-200 bpm), tempo only
  lufs          EBU R128 integrated loudness, the same unit our clip floor uses
  peak_dbfs     true peak, so a master that clips is visible
  centroid_hz   mean spectral centroid — a rough "bright vs dark" number
  onset_rate    onsets per second — how busy the arrangement is
  crest         peak/RMS ratio — how much dynamic range survives the master

What it cannot measure: whether the song is good, the chord progression, the
vocal. Those need a musician or a model, and pretending otherwise is how a
"profile" turns into a lie.

    python3 ops/reference_profile.py --dir work/refs --out work/reference-profiles/thai-pop.json
    python3 ops/reference_profile.py --file one.mp3
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

SR = 22050
AUDIO_EXT = {".mp3", ".m4a", ".wav", ".flac", ".ogg", ".opus", ".aac"}


def ffmpeg() -> str:
    """A fresh pod has no system ffmpeg; imageio-ffmpeg ships a static one."""
    found = shutil.which("ffmpeg")
    if found:
        return found
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"no ffmpeg on PATH and imageio-ffmpeg unavailable: {exc}")


def _run(cmd: list[str], timeout: int = 600) -> tuple[int, bytes, bytes]:
    p = subprocess.run(cmd, capture_output=True, timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def decode(path: Path) -> "np.ndarray":
    import numpy as np
    rc, out, err = _run([ffmpeg(), "-v", "error", "-i", str(path), "-ac", "1",
                         "-ar", str(SR), "-f", "s16le", "-"])
    if rc != 0 or not out:
        raise RuntimeError(f"decode failed: {err.decode()[:120]}")
    return np.frombuffer(out, dtype=np.int16).astype(np.float32) / 32768.0


def lufs_and_peak(path: Path) -> tuple[float, float]:
    rc, _, err = _run([ffmpeg(), "-hide_banner", "-i", str(path),
                       "-af", "ebur128=peak=true", "-f", "null", "-"])
    text = err.decode("utf-8", "replace")
    lufs = peak = 0.0
    m = re.findall(r"I:\s*(-?\d+\.\d+)\s*LUFS", text)
    if m:
        lufs = float(m[-1])
    m = re.findall(r"Peak:\s*(-?\d+\.\d+)\s*dBFS", text)
    if m:
        peak = float(m[-1])
    return lufs, peak


def onset_envelope(x, hop: int = 512, win: int = 1024):
    """Spectral-flux onset envelope, plus the spectrum mean for the centroid."""
    import numpy as np
    if len(x) < win * 4:
        return np.zeros(1), np.zeros(1)
    frames = 1 + (len(x) - win) // hop
    idx = np.arange(win)[None, :] + hop * np.arange(frames)[:, None]
    spec = np.abs(np.fft.rfft(x[idx] * np.hanning(win), axis=1))
    flux = np.maximum(0.0, np.diff(spec, axis=0)).sum(axis=1)
    freqs = np.fft.rfftfreq(win, 1.0 / SR)
    energy = spec.sum(axis=1)
    centroid = np.where(energy > 0, (spec * freqs).sum(axis=1) / np.maximum(energy, 1e-9), 0.0)
    return flux, centroid


def estimate_bpm(flux) -> float:
    import numpy as np
    if len(flux) < 32 or flux.std() == 0:
        return 0.0
    fps = SR / 512.0
    env = flux - flux.mean()
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    lo, hi = int(fps * 60 / 200), int(fps * 60 / 30)
    if hi >= len(ac):
        return 0.0
    lag = lo + int(np.argmax(ac[lo:hi]))
    bpm = 60.0 * fps / lag if lag else 0.0
    # Autocorrelation picks an octave freely: 34.9 and 69.8 fit the same track.
    # Fold into the range a listener would tap, so a median is meaningful.
    while bpm and bpm < 70:
        bpm *= 2
    while bpm > 160:
        bpm /= 2
    return round(bpm, 1)


def measure(path: Path) -> dict:
    import numpy as np
    x = decode(path)
    dur = len(x) / SR
    lufs, peak = lufs_and_peak(path)
    flux, centroid = onset_envelope(x)
    rms = float(np.sqrt(np.mean(x ** 2)) + 1e-12)
    peak_lin = float(np.max(np.abs(x)) + 1e-12)
    # An onset is a flux value well above the local noise floor.
    thr = float(np.median(flux) + 2.0 * np.std(flux)) if len(flux) else 0.0
    onsets = int(np.sum(flux > thr)) if thr else 0
    return {
        "file": path.name,
        "duration_s": round(dur, 1),
        "bpm": estimate_bpm(flux),
        "lufs": lufs,
        "peak_dbfs": peak,
        "centroid_hz": int(np.mean(centroid)) if len(centroid) else 0,
        "onset_rate": round(onsets / dur, 2) if dur else 0.0,
        "crest_db": round(20 * np.log10(peak_lin / rms), 1),
    }


def summarise(rows: list[dict]) -> dict:
    import statistics as st
    keys = ("duration_s", "bpm", "lufs", "peak_dbfs", "centroid_hz", "onset_rate", "crest_db")
    out = {"songs": len(rows)}
    for k in keys:
        vals = [r[k] for r in rows if r.get(k)]
        out[k] = round(st.median(vals), 1) if vals else 0
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir")
    ap.add_argument("--file", action="append", default=[])
    ap.add_argument("--out")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    files: list[Path] = [Path(f) for f in args.file]
    if args.dir:
        files += sorted(p for p in Path(args.dir).rglob("*")
                        if p.suffix.lower() in AUDIO_EXT)
    if args.limit:
        files = files[:args.limit]
    if not files:
        raise SystemExit("nothing to measure")

    rows = []
    for p in files:
        try:
            r = measure(p)
        except Exception as exc:  # noqa: BLE001 - one bad file must not stop the set
            print(f"  SKIP {p.name}: {type(exc).__name__} {str(exc)[:80]}", file=sys.stderr)
            continue
        rows.append(r)
        print(f"  {r['duration_s']:6.1f}s {r['bpm']:5.1f}bpm {r['lufs']:6.1f}LUFS "
              f"{r['centroid_hz']:5d}Hz {r['onset_rate']:5.2f}on/s  {p.name[:52]}")

    if not rows:
        return 1
    summary = summarise(rows)
    print("\nprofile:", json.dumps(summary, ensure_ascii=False))
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"summary": summary, "songs": rows},
                                  ensure_ascii=False, indent=2), encoding="utf-8")
        print("written:", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
