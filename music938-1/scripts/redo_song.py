#!/usr/bin/env python3
"""Re-do one of K's own songs: remaster the audio and give it a new AI cover.

K keeps a few of his own tracks in Drive and asked for them to be reworked
("เพลงแบบว่ามันเบลอ v-2 ... เอามาทำใหม่"). The uploads are phone exports: an
H.264 file that is a single still (a picture of a vintage radio) held for the
song's length, with the audio at +0.0 dBTP, which YouTube clips on playback.

So "redo" is three passes, and the interesting one is the middle:

1. strip the video, keep the audio;
2. remaster to the YouTube target (about -14 LUFS, -1.0 dBTP) with a gentle
   high-pass and a slow levelling pass, so it is loud enough to sit beside a
   commercial track without clipping;
3. rebuild the video as a 1080p still over a fresh AI cover, so the upload stops
   being a photo of a radio.

The cover is drawn by `ai_covers.py`, so the art direction and the "no text from
the model" rule are shared with the catalogue rather than duplicated here.

    python3 scripts/redo_song.py --source ../work/k-songs/x.mp4 \\
        --title "แบบว่ามันเบลอ" --slug k-baep-wa-man-bloe --out ../work/k-songs/redo.mp4
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import ai_covers  # noqa: E402
import common  # noqa: E402

# YouTube normalises playback to about -14 LUFS and clips anything above -1 dBTP,
# so that pair is the target, not "as loud as possible".
TARGET_I = -14.0
TARGET_TP = -1.0
TARGET_LRA = 11.0


def _measure(src: Path) -> dict:
    """First loudnorm pass: the measured values the second pass corrects for."""
    res = common.run(["ffmpeg", "-hide_banner", "-i", str(src),
                      "-af", f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}"
                             ":print_format=json", "-f", "null", "-"])
    import json
    tail = res.stderr[res.stderr.rfind("{"):res.stderr.rfind("}") + 1]
    return json.loads(tail)


def remaster(src: Path, dst: Path) -> Path:
    """Extract, high-pass, then two-pass loudnorm to the YouTube target."""
    m = _measure(src)
    af = (f"highpass=f=30,"
          f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}"
          f":measured_I={m['input_i']}:measured_TP={m['input_tp']}"
          f":measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}"
          f":offset={m['target_offset']}:linear=true,"
          f"aresample=48000")
    dst.parent.mkdir(parents=True, exist_ok=True)
    common.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(src), "-vn", "-af", af, "-c:a", "libmp3lame",
                "-b:a", "320k", "-ar", "48000", str(dst)])
    return dst


def build_video(cover: Path, audio: Path, dst: Path) -> Path:
    """A slow push-in on the cover, held for the whole song, plus the audio."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    # zoompan works on a still: 1.0 -> 1.06 over the whole clip reads as alive
    # without looking like a slideshow.
    dur = common.duration(audio)
    fps = 25
    frames = max(1, int(dur * fps))
    common.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-loop", "1", "-i", str(cover),
                "-i", str(audio),
                "-vf", (f"scale=2112:1188,zoompan=z='min(1.0+0.06*on/{frames},1.06)'"
                        f":x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}"
                        f":s=1920x1080:fps={fps},format=yuv420p"),
                "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                "-c:a", "aac", "-b:a", "192k", "-shortest",
                "-movflags", "+faststart", str(dst)])
    return dst


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, help="K's file (audio or video)")
    ap.add_argument("--title", required=True, help="Thai title for the cover")
    ap.add_argument("--slug", required=True, help="key for the AI cover and output names")
    ap.add_argument("--subtitle", default="")
    ap.add_argument("--mood", default="mystic")
    ap.add_argument("--direction", default=None, help="force an art-direction name")
    ap.add_argument("--out", default="", help="output mp4 (default work/<slug>.mp4)")
    ap.add_argument("--audio-only", action="store_true", help="stop after the remaster")
    args = ap.parse_args()

    src = Path(args.source).resolve()
    if not src.exists():
        print(f"no such file: {src}", file=sys.stderr)
        return 2

    audio = ROOT / "work" / f"{args.slug}-master.mp3"
    remaster(src, audio)
    m = _measure(audio)
    print(f"  remastered -> {audio}  (I={m['input_i']} LUFS, TP={m['input_tp']} dBTP)")
    if args.audio_only:
        return 0

    # Reuse the catalogue cover path so the art rules live in one place.
    variant = None
    if args.direction:
        names = [n for n, _ in ai_covers.ART_DIRECTIONS]
        variant = names.index(args.direction) if args.direction in names else None
    bg = ai_covers.build(args.slug, variant=variant, force=True)
    cover = Path(bg["cover"])
    print(f"  cover -> {cover}  [{bg['direction']}]")

    out = Path(args.out) if args.out else ROOT / "work" / f"{args.slug}.mp4"
    build_video(cover, audio, out)
    print(f"  video -> {out}  ({common.duration(out):.1f}s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
