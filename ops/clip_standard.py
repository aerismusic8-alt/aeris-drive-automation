#!/usr/bin/env python3
"""The clip quality gate: a clip below the standard must not ship.

K (2026-11-17): the trivia standard is a **floor, not a target** —
"ห้ามมาตรฐานต่ำกว่านี้เด็ดขาดในช่องของเรา". A rule that lives only in a doc drifts;
so this module *measures* a finished clip and fails if it drops below the numbers
measured from K's reference clip (`docs/trivia-clip-standard.md`). Every trivia
clip goes through `check()` before it is published, and a fail is a red run, not a
warning.

Thresholds (reference value -> the gate), with the reason each one exists:

    width x height   1280x720    -> exactly 1280x720        (the format)
    fps              24          -> 24/25/30                (a real frame rate)
    video codec      h264        -> h264                    (widely playable)
    audio            48k stereo  -> aac, 48000, 2ch         (the reference)
    duration         4.03 s      -> >= 3 s
    loudness         -14.9 LUFS  -> -16.5 .. -13.5 LUFS     (raw TTS is ~-22)
    true peak        -2.6 dBTP   -> <= -1.0 dBTP            (no clipping)
    motion, max      7.4         -> <= 20  (a hard cut is ~94)
    motion, median   2.8         -> >= 0.15 (a frozen still is 0.0)
    text pixels      215         -> >= 120  (text must be present and big)

`motion` is the mean absolute difference between consecutive frames at 24 fps;
the max catches a hard cut, the median catches a frozen frame. `text pixels`
counts bright pixels that touch a dark pixel in the middle band, which is what a
white Thai caption with a thin dark outline produces.

CLI:  python3 ops/clip_standard.py <clip.mp4> [--json]
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

# --- The standard (kind="trivia"). Change these only with a new reference. ---
THRESHOLDS = {
    "width": 1280,
    "height": 720,
    "fps_allowed": (24, 25, 30),
    "video_codec": "h264",
    "audio_codec": "aac",
    "audio_rate": 48000,
    "audio_channels": 2,
    "min_seconds": 3.0,
    "lufs_min": -16.5,
    "lufs_max": -13.5,
    "true_peak_max": -1.0,
    "motion_max": 20.0,
    "motion_median_min": 0.15,
    "text_px_min": 120,
}

ANALYZE_W = 480        # downscale width for the motion/text pass
ANALYZE_MAX_SECONDS = 120.0   # bound the cost on a long clip


def ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def ffprobe() -> str:
    exe = shutil.which("ffprobe")
    if exe:
        return exe
    cand = os.path.join(os.path.dirname(ffmpeg()), "ffprobe")
    return cand if os.path.exists(cand) else "ffprobe"


def probe(path: str) -> dict:
    out = subprocess.run(
        [ffprobe(), "-v", "error", "-show_streams", "-show_format",
         "-of", "json", path], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {path}: {out.stderr[:200]}")
    data = json.loads(out.stdout)
    v = next((s for s in data["streams"] if s["codec_type"] == "video"), {})
    a = next((s for s in data["streams"] if s["codec_type"] == "audio"), {})
    num, den = (v.get("avg_frame_rate") or "0/1").split("/")
    fps = (float(num) / float(den)) if float(den) else 0.0
    return {
        "width": int(v.get("width") or 0),
        "height": int(v.get("height") or 0),
        "fps": round(fps, 3),
        "video_codec": v.get("codec_name") or "",
        "audio_codec": a.get("codec_name") or "",
        "audio_rate": int(a.get("sample_rate") or 0),
        "audio_channels": int(a.get("channels") or 0),
        "seconds": float(data.get("format", {}).get("duration") or 0.0),
    }


def _frames(path: str):
    """Yield downscaled grayscale frames as numpy arrays, straight off the pipe."""
    import numpy as np
    info = probe(path)
    w = ANALYZE_W
    h = int(round(ANALYZE_W * info["height"] / info["width"])) if info["width"] else 0
    if h % 2:
        h += 1
    args = [ffmpeg(), "-v", "error", "-i", path,
            "-t", f"{min(info['seconds'], ANALYZE_MAX_SECONDS):.3f}",
            "-vf", f"fps=24,scale={w}:{h},format=gray",
            "-f", "rawvideo", "-"]
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    n = w * h
    try:
        while True:
            buf = proc.stdout.read(n)
            if len(buf) < n:
                break
            yield np.frombuffer(buf, dtype=np.uint8).reshape(h, w).astype(np.float32)
    finally:
        proc.stdout.close()
        proc.wait()


def motion(path: str):
    """(median, p99, max) consecutive-frame difference. Max ~94 = a hard cut."""
    import numpy as np
    prev, diffs = None, []
    for f in _frames(path):
        if prev is not None:
            diffs.append(float(np.mean(np.abs(f - prev))))
        prev = f
    if not diffs:
        return 0.0, 0.0, 0.0
    return (round(float(np.median(diffs)), 3),
            round(float(np.percentile(diffs, 99)), 3),
            round(float(max(diffs)), 3))


def text_pixels(path: str) -> int:
    """Median count of bright pixels touching a dark pixel, in the middle band."""
    import numpy as np
    vals = []
    for i, f in enumerate(_frames(path)):
        if i % 12:      # ~2 fps is plenty for a per-frame constant caption
            continue
        h = f.shape[0]
        band = f[int(h * 0.15):int(h * 0.85)]
        bright = band > 235
        dark = band < 110
        nb = np.zeros_like(dark)
        nb[1:, :] |= dark[:-1, :]
        nb[:-1, :] |= dark[1:, :]
        nb[:, 1:] |= dark[:, :-1]
        nb[:, :-1] |= dark[:, 1:]
        vals.append(int((bright & nb).sum()))
    if not vals:
        return 0
    vals.sort()
    return vals[len(vals) // 2]


def loudness(path: str):
    """(integrated LUFS, true peak dBTP) via ffmpeg's EBU R128 meter."""
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


def check(path: str, t: dict | None = None) -> list[tuple[str, bool, str]]:
    """Return [(name, ok, detail)] for every rule. Never raises on a bad clip."""
    t = t or THRESHOLDS
    res: list[tuple[str, bool, str]] = []

    def add(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    try:
        info = probe(path)
    except Exception as e:                       # unreadable file is a hard fail
        add("readable file", False, str(e)[:120])
        return res
    add("readable file", True, os.path.basename(path))
    add("landscape 1280x720",
        info["width"] == t["width"] and info["height"] == t["height"],
        f"{info['width']}x{info['height']}")
    add("frame rate is real", info["fps"] in t["fps_allowed"], f"{info['fps']} fps")
    add("video codec", info["video_codec"] == t["video_codec"], info["video_codec"])
    add("audio aac 48k stereo",
        info["audio_codec"] == t["audio_codec"]
        and info["audio_rate"] == t["audio_rate"]
        and info["audio_channels"] == t["audio_channels"],
        f"{info['audio_codec']} {info['audio_rate']}Hz {info['audio_channels']}ch")
    add("long enough", info["seconds"] >= t["min_seconds"], f"{info['seconds']:.1f}s")

    lufs, peak = loudness(path)
    add("loudness normalised",
        lufs is not None and t["lufs_min"] <= lufs <= t["lufs_max"],
        f"{lufs} LUFS (want {t['lufs_min']}..{t['lufs_max']})")
    add("no clipping",
        peak is not None and peak <= t["true_peak_max"],
        f"{peak} dBTP")

    med, p99, mx = motion(path)
    add("no hard cut", mx <= t["motion_max"], f"max {mx} (limit {t['motion_max']})")
    add("picture is not frozen", med >= t["motion_median_min"],
        f"median {med}")
    tx = text_pixels(path)
    add("caption is present and big", tx >= t["text_px_min"],
        f"{tx} text px (min {t['text_px_min']})")
    return res


def assert_ok(path: str, t: dict | None = None) -> None:
    """Raise unless every rule passes. Used on the publish path."""
    failed = [n for n, ok, _ in check(path, t) if not ok]
    if failed:
        raise SystemExit("clip below the standard: " + "; ".join(failed))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("clip")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    rows = check(a.clip)
    if a.json:
        print(json.dumps([{"rule": n, "ok": ok, "detail": d} for n, ok, d in rows],
                         ensure_ascii=False, indent=2))
    else:
        for n, ok, d in rows:
            print(f"  {'ok  ' if ok else 'FAIL'} {n:28s} {d}")
    bad = [n for n, ok, _ in rows if not ok]
    print(f"\n{'PASS' if not bad else 'FAIL'} — {len(rows)-len(bad)}/{len(rows)} rules")
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())
