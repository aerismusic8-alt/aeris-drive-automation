#!/usr/bin/env python3
"""Draw an equalizer from the song's own spectrum.

K, 2026-11-21 asked for the kind of equalizer graphic a stock site sells. Pixabay
answers this sandbox with a Cloudflare Turnstile, and a downloaded still cannot
move anyway. Drawing the bars from the master gives the same look and reacts to
the actual song, which is the point of the element.

    python3 ops/eq_overlay.py song.mp3 --out /tmp/eq --seconds 14 \
        --width 2160 --height 620 --bars 72

Writes `frame-00000.png` … as RGBA, ready for `ffmpeg -i frame-%05d.png`.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

BOTTOM = (110, 247, 200)
TOP = (255, 138, 216)
FLOOR_DB = -58.0
ATTACK = 0.55
MAX_STEP = 0.14     # a bar may not jump more than this in one frame
RELEASE = 0.14


def load(path: Path, sr: int = 44100) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", str(path), "-ac", "1", "-ar", str(sr),
         "-f", "s16le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def levels(x: np.ndarray, sr: int, start: float, seconds: float, fps: int,
           bars: int) -> np.ndarray:
    """One row of band levels per video frame, in 0..1."""
    win = 4096
    freqs = np.fft.rfftfreq(win, 1.0 / sr)
    edges = np.logspace(np.log10(38), np.log10(min(16000, sr / 2 - 1)), bars + 1)
    idx = [(int(np.searchsorted(freqs, lo)), max(int(np.searchsorted(freqs, hi)),
                                                int(np.searchsorted(freqs, lo)) + 1))
           for lo, hi in zip(edges[:-1], edges[1:])]
    window = np.hanning(win)
    out, prev = [], np.zeros(bars, dtype=np.float32)
    for f in range(int(seconds * fps)):
        c = int((start + f / fps) * sr)
        seg = x[c:c + win]
        if len(seg) < win:
            seg = np.pad(seg, (0, win - len(seg)))
        mag = np.abs(np.fft.rfft(seg * window))
        db = 20 * np.log10(mag / (win / 2) + 1e-9)
        v = np.clip((np.array([db[a:b].max() for a, b in idx]) - FLOOR_DB)
                    / -FLOOR_DB, 0.0, 1.0)
        v = np.clip(v ** 0.70 * 1.12, 0.0, 1.0)
        nxt = np.where(v > prev, prev + (v - prev) * ATTACK, prev + (v - prev) * RELEASE)
        prev = prev + np.clip(nxt - prev, -MAX_STEP, MAX_STEP)
        out.append(prev.copy())
    return np.array(out)


def draw(row: np.ndarray, width: int, height: int) -> Image.Image:
    """Bars whose own height carries the gradient: pink at the tip, green at the foot."""
    bars = len(row)
    bw = width / bars
    gap = bw * 0.26
    mask = Image.new("L", (width, height), 0)
    d = ImageDraw.Draw(mask)
    tops = np.zeros(width, dtype=np.float32)
    hs = np.ones(width, dtype=np.float32)
    for i, v in enumerate(row):
        h = max(int(v * height * 0.94), 2)
        x0 = int(i * bw + gap / 2)
        x1 = int((i + 1) * bw - gap / 2)
        tops[x0:x1] = height - h
        hs[x0:x1] = h
        r = max(int(min(bw - gap, h) / 2), 1)
        d.rounded_rectangle([x0, height - h, x1, height], radius=r, fill=255)

    y = np.arange(height, dtype=np.float32)[:, None]
    t = np.clip((y - tops[None, :]) / hs[None, :], 0.0, 1.0)[:, :, None]
    grad = (np.array(TOP)[None, None, :] * (1 - t)
            + np.array(BOTTOM)[None, None, :] * t).astype(np.uint8)
    rgb = Image.fromarray(grad, "RGB")

    glow = mask.filter(ImageFilter.GaussianBlur(max(height / 26, 3)))
    alpha = Image.fromarray(
        np.clip(np.array(mask, dtype=np.float32)
                + np.array(glow, dtype=np.float32) * 0.55, 0, 255).astype(np.uint8), "L")
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("song", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--seconds", type=float, default=14.0)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--width", type=int, default=2160)
    ap.add_argument("--height", type=int, default=620)
    ap.add_argument("--bars", type=int, default=72)
    args = ap.parse_args()

    sr = 44100
    x = load(args.song, sr)
    rows = levels(x, sr, args.start, args.seconds, args.fps, args.bars)
    args.out.mkdir(parents=True, exist_ok=True)
    for i, row in enumerate(rows):
        draw(row, args.width, args.height).save(args.out / f"frame-{i:05d}.png")
    print(f"{len(rows)} frames -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
