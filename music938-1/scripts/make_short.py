#!/usr/bin/env python3
"""Render a vertical Short (1080x1920, <=60s) from a Flow Music song.

Why this exists. The channel's own numbers say it plainly: of 449 lifetime views
on AERIS Music, 382 came from Shorts and about 33 from long-form. A channel with
no subscribers gets no long-form impressions - YouTube gives Shorts free
distribution and long-form nothing until an audience exists. So a pack of 20
songs builds an audience through Shorts first; the long-form compilations earn
the watch hours once there is someone to watch them.

A Short is capped at 60s, so it does not depend on the 3.5-minute floor that
gates the songs: song 01 at 178.7s makes a perfectly good Short. That means this
rail runs even while generation is throttled.

Shape of a Short here:
  * the hook - the chorus, not the intro, because the first 2 seconds decide
    whether a scroll stops
  * the largest Thai caption that fits a phone, one line at a time
  * the cover art, slowly zooming, so there is motion without a video budget

    python3 scripts/make_short.py 01-khon-di-thi-chak-pai
    python3 scripts/make_short.py --all --mix song
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_karaoke import (  # noqa: E402  reuse the lyric engine
    FONT, LEAD, OUTLINE, PRIMARY, SECONDARY, _duration, _escape, _ts,
    _words, estimate, load_lyrics,
)

W, H = 1080, 1920
FPS = 30
MAX_SECONDS = 58.0        # under the 60s Shorts ceiling, with margin
HOOK_PAD = 0.6            # a beat of lead-in so the hook does not start on frame 0


def chorus_span(slug: str) -> tuple[float, float]:
    """Approximate the chorus as a fraction of the song, from the lyric structure.

    The lyric file marks sections, and the chorus is the repeated one. We take the
    first chorus block's share of all sung lines and map it onto the audio, which
    is the same proportional model make_karaoke uses for its sweep. It is an
    estimate - Flow Music's compose path hands us no real timing - but it lands
    the hook in the right third of the song rather than on the intro.
    """
    text = (ROOT / "lyrics" / f"{slug}.txt").read_text(encoding="utf-8")
    section, counts, order = "", {}, []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section in ("intro", "outro", "solo", "instrumental", "break", "end"):
            continue
        counts[section] = counts.get(section, 0) + 1
        order.append(section)
    total = sum(counts.values()) or 1
    # First chorus block's start and length as a share of sung lines.
    seen = 0
    start_frac, len_frac = 0.0, 0.3
    for sec in order:
        if sec == "chorus":
            start_frac = seen / total
            len_frac = counts.get("chorus", 1) / total
            break
        seen += 1
    return start_frac, len_frac


def _pick_window(slug: str, duration: float) -> tuple[float, float]:
    """The clip to show: the chorus, trimmed to MAX_SECONDS."""
    start_frac, len_frac = chorus_span(slug)
    start = max(0.0, duration * start_frac - HOOK_PAD)
    length = min(MAX_SECONDS, duration - start)
    if length < 12:                      # a very short tail: fall back to mid-song
        start = max(0.0, duration * 0.35)
        length = min(MAX_SECONDS, duration - start)
    return start, length


def build_ass(slug: str, lines: list[str], meta: dict, start: float,
              length: float, duration: float) -> str:
    """Vertical captions: one big line at a time, karaoke sweep, Thai-safe."""
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Hook,{FONT},96,{PRIMARY},{SECONDARY},{OUTLINE},&H80000000,1,0,0,0,100,100,0.5,0,1,6,3,2,60,60,760,1
Style: Cap,{FONT},30,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,0,0,0,0,100,100,1,0,1,4,2,8,60,60,60,1
Style: Brand,{FONT},40,&H00DDFFFF,&H00DDFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,8,60,60,170,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    # Timing is estimated over the WHOLE song, then shifted into the window.
    full = estimate(lines, duration)
    events: list[str] = []

    # Hook title for the first beat, then it gets out of the way.
    title = _escape(meta.get("title", ""))
    if title:
        events.append(f"Dialogue: 0,{_ts(0.15)},{_ts(2.2)},Brand,,0,0,0,,"
                      f"{{\\fad(250,300)}}{title}")

    for item in full:
        if item["end"] <= start or item["start"] >= start + length:
            continue
        s = max(item["start"], start) - start
        e = min(item["end"], start + length) - start
        if e - s < 0.35:
            continue
        words = _words(item["text"])
        weights = [max(1, len(w.replace(" ", ""))) for w in words]
        total = sum(weights) or 1
        parts = []
        for w, wt in zip(words, weights):
            cs = max(1, int(round((e - s) * 100 * wt / total)))
            parts.append(f"{{\\kf{cs}}}{_escape(w)}")
        events.append(f"Dialogue: 0,{_ts(s)},{_ts(e + 0.2)},Hook,,0,0,0,,"
                      f"{{\\fad(90,120)}}{''.join(parts)}")

    # A small always-on credit so a re-upload is traceable to the channel.
    events.append(f"Dialogue: 0,{_ts(0.15)},{_ts(length - 0.2)},Cap,,0,0,0,,"
                  f"AERIS Music")
    return head + "\n".join(events) + "\n"


def _ass_escape(p: Path) -> str:
    return str(p).replace("\\", "\\\\").replace(":", "\\:")


def render(slug: str, *, mix: str = "song", out_dir: Path | None = None) -> Path:
    audio = ROOT / "library" / "songs" / f"{mix}-{slug}.mp3"
    cover = ROOT / "library" / "covers" / f"cover-{slug}.jpg"
    for p in (audio, cover):
        if not p.exists():
            raise FileNotFoundError(f"missing {p}; run flow_song.py first")

    meta, lines = load_lyrics(slug)
    duration = _duration(audio)
    start, length = _pick_window(slug, duration)

    work = ROOT / "work" / slug
    work.mkdir(parents=True, exist_ok=True)
    ass_path = work / f"short-{mix}.ass"
    ass_path.write_text(build_ass(slug, lines, meta, start, length, duration),
                        encoding="utf-8")

    out_dir = out_dir or (ROOT / "library" / "shorts")
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"short-{mix}-{slug}.mp4"

    # Slow zoom on the cover, cropped to vertical. The cover is square, so a
    # centre crop to 9:16 is the honest fit; the zoom keeps it from looking dead.
    zoom = ("scale=1440:2560:force_original_aspect_ratio=increase,"
            "crop=%d:%d,zoompan=z='min(zoom+0.0006,1.22)':d=1:"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=%dx%d:fps=%d"
            % (W, H, W, H, FPS))
    args = ["-loop", "1", "-i", str(cover),
            "-ss", f"{start:.3f}", "-i", str(audio),
            "-filter_complex", f"[0:v]{zoom},ass={_ass_escape(ass_path)}[v]",
            "-map", "[v]", "-map", "1:a",
            "-t", f"{length:.3f}",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
            "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-c:a", "aac", "-b:a", "192k", "-shortest",
            "-movflags", "+faststart", str(out)]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--all", action="store_true", help="every song on disk")
    ap.add_argument("--mix", default="song", choices=["song", "karaoke"])
    args = ap.parse_args()

    if args.all:
        slugs = sorted(p.stem[5:] for p in (ROOT / "library" / "songs").glob("song-*.mp3"))
    elif args.slug:
        slugs = [args.slug]
    else:
        ap.error("give a slug or --all")

    rc = 0
    for slug in slugs:
        try:
            out = render(slug, mix=args.mix)
            print(f"{slug}: {out.relative_to(ROOT)} "
                  f"({_duration(out):.1f}s)")
        except Exception as exc:
            print(f"{slug}: FAILED {exc}", file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
