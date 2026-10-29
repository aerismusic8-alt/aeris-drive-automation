"""Shared plumbing for the music938-1 song pipeline.

ffmpeg is the only audio backend. Everything here is deterministic: the same
lyrics and the same seed produce the same bytes, so a rebuild can be compared
against the recorded manifest instead of trusted.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
LYRICS = ROOT / "lyrics"
LIBRARY = ROOT / "library"
WORK = ROOT / "work"
CACHE = WORK / "_tts-cache"

SR = 44100  # output sample rate for every rendered stem


def run(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    res = subprocess.run(args, capture_output=True, text=True)
    if check and res.returncode != 0:
        tail = (res.stderr or "").strip().splitlines()[-8:]
        raise RuntimeError(f"command failed ({res.returncode}): {' '.join(args[:6])} ...\n"
                           + "\n".join(tail))
    return res


def ffmpeg(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    return run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=check)


def duration(path: Path) -> float:
    res = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=nw=1:nk=1", str(path)])
    try:
        return float(res.stdout.strip())
    except ValueError:
        return 0.0


def integrated_lufs(path: Path) -> float | None:
    res = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
               "-filter_complex", "ebur128=peak=true", "-f", "null", "-"],
              check=False)
    lufs = None
    for line in res.stderr.splitlines():
        s = line.strip()
        if s.startswith("I:"):
            try:
                lufs = float(s.split()[1])
            except (IndexError, ValueError):
                pass
    return lufs


def true_peak_dbfs(path: Path) -> float | None:
    res = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
               "-filter_complex", "ebur128=peak=true", "-f", "null", "-"],
              check=False)
    peak = None
    for line in res.stderr.splitlines():
        s = line.strip()
        if s.startswith("Peak:"):
            try:
                peak = float(s.split()[1])
            except (IndexError, ValueError):
                pass
    return peak


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path: Path, payload: dict) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, path)
    return path


def peak(path: Path) -> float:
    """Sample peak of an audio file, 0..1+ (1.0 is full scale)."""
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
         "-af", "astats=metadata=1:reset=0", "-f", "null", "-"],
        capture_output=True, text=True).stderr
    m = re.findall(r"Peak level dB:\s*(-?[\d.]+|-inf)", out)
    if not m:
        return 0.0
    last = m[-1]
    if last == "-inf":
        return 0.0
    return 10 ** (float(last) / 20.0)


def read_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def atempo_chain(factor: float) -> str:
    """Build an atempo filter chain for any factor (atempo caps at 0.5-2.0)."""
    parts = []
    f = factor
    while f > 2.0:
        parts.append("atempo=2.0")
        f /= 2.0
    while f < 0.5:
        parts.append("atempo=0.5")
        f /= 0.5
    parts.append(f"atempo={f:.6f}")
    return ",".join(parts)
