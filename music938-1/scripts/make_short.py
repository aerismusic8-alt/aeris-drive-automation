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
    _words, ass_filter, estimate, load_lyrics,
)

W, H = 1080, 1920
FPS = 30
MAX_SECONDS = 58.0        # under the 60s Shorts ceiling, with margin
HOOK_PAD = 0.6            # a beat of lead-in so the hook does not start on frame 0


def chorus_spans(slug: str) -> list[tuple[float, float]]:
    """Every chorus block as a (start, length) share of the sung lines.

    A song has three choruses, and they are the hook three times over. One Short
    per chorus gives a song three chances to stop a scroll instead of one, for no
    extra generation - which matters most on a channel with no subscribers, where
    each Short is a fresh lottery ticket rather than a guaranteed impression.
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
    spans, seen, prev = [], 0, ""
    for sec in order:
        # A chorus block starts where the section changes into "chorus", so the
        # three choruses give three spans, not one span per sung line.
        if sec == "chorus" and prev != "chorus":
            spans.append([seen / total, 0.0])
        if sec == "chorus" and spans:
            spans[-1][1] += 1 / total
        seen += 1
        prev = sec
    if not spans:
        spans = [[0.35, 0.3]]
    return [(a, b) for a, b in spans]


def chorus_span(slug: str) -> tuple[float, float]:
    """The first chorus - kept for the single-hook callers and the tests."""
    return chorus_spans(slug)[0]


def _window(duration: float, start_frac: float, len_frac: float) -> tuple[float, float]:
    start = max(0.0, duration * start_frac - HOOK_PAD)
    length = min(MAX_SECONDS, duration - start)
    if length < 12:                      # a very short tail: fall back to mid-song
        start = max(0.0, duration * 0.35)
        length = min(MAX_SECONDS, duration - start)
    return start, length


def _pick_windows(slug: str, duration: float) -> list[tuple[float, float]]:
    """One window per chorus, de-duplicated if two land on the same spot."""
    out: list[tuple[float, float]] = []
    for sf, lf in chorus_spans(slug):
        w = _window(duration, sf, lf)
        if all(abs(w[0] - o[0]) > 5.0 for o in out):
            out.append(w)
    return out or [_window(duration, 0.35, 0.3)]


def _pick_window(slug: str, duration: float) -> tuple[float, float]:
    return _pick_windows(slug, duration)[0]


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
Style: Hook,{FONT},88,{PRIMARY},{SECONDARY},{OUTLINE},&H80000000,1,0,0,0,100,100,0.5,0,1,6,3,2,70,70,430,1
Style: Cap,{FONT},38,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,8,70,70,310,1
Style: Brand,{FONT},40,&H00DDFFFF,&H00DDFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,7,44,44,40,1
Style: Title,{FONT},64,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,5,2,7,44,44,34,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    # Timing is estimated over the WHOLE song, then shifted into the window.
    full = estimate(lines, duration)
    events: list[str] = []

    # The song title for the first beat, then it gets out of the way.
    title = _escape(meta.get("title", ""))
    if title:
        events.append(f"Dialogue: 0,{_ts(0.15)},{_ts(2.6)},Title,,0,0,0,,"
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

    # A small always-on watermark so a re-upload is traceable to the channel.
    events.append(f"Dialogue: 0,{_ts(0.15)},{_ts(length - 0.2)},Brand,,0,0,0,,"
                  f"AERIS Music")
    return head + "\n".join(events) + "\n"


def _ass_escape(p: Path) -> str:
    return str(p).replace("\\", "\\\\").replace(":", "\\:")


def render(slug: str, *, mix: str = "song", out_dir: Path | None = None,
           all_hooks: bool = False) -> list[Path]:
    """Render one Short per chorus. Returns the files written.

    `all_hooks=True` writes every chorus as its own Short (hook-1, hook-2, ...).
    The default writes just the first, so a caller that wants one file per song
    still gets exactly that.
    """
    audio = ROOT / "library" / "songs" / f"{mix}-{slug}.mp3"
    cover = ROOT / "library" / "covers" / f"cover-{slug}.jpg"
    for p in (audio, cover):
        if not p.exists():
            raise FileNotFoundError(f"missing {p}; run flow_song.py first")

    meta, lines = load_lyrics(slug)
    duration = _duration(audio)
    windows = _pick_windows(slug, duration)
    if not all_hooks:
        windows = windows[:1]

    work = ROOT / "work" / slug
    work.mkdir(parents=True, exist_ok=True)
    out_dir = out_dir or (ROOT / "library" / "shorts")
    out_dir.mkdir(parents=True, exist_ok=True)
    # A single hook keeps the plain name release.py looks for; multiple hooks get
    # an -h1/-h2 suffix so they are distinct files.
    multi = all_hooks and len(windows) > 1

    # The cover is square, so a hard centre crop to 9:16 would slice the title
    # text off the sides. Instead: a blurred, zoomed copy of the cover fills the
    # vertical frame, the whole cover sits centred on top, and the pair zooms
    # slowly so the frame is not dead. This is the usual Shorts treatment and it
    # keeps the art intact on a phone. The ass filter is per-hook, so the chain is
    # assembled inside the loop.
    def chain(ass: Path) -> str:
        # The cover is square, so a hard centre crop to 9:16 would slice its title
        # text off the sides and drop the captions on top of it. Instead: a
        # blurred, dimmed copy fills the frame, the whole cover sits in the upper
        # half, and a scrim below it gives the captions a clean band. The whole
        # composite zooms slowly so the frame is not dead.
        cw = int(W * 0.86)
        cy = int(H * 0.055)
        scrim = int(H * 0.52)
        return (
            f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
            f"gblur=sigma=32,eq=brightness=-0.06:saturation=1.05[bg];"
            f"[0:v]scale={cw}:-1[fg];"
            f"[bg][fg]overlay=(W-w)/2:{cy}[base];"
            f"[base]drawbox=x=0:y={scrim}:w={W}:h={H - scrim}:"
            f"color=black@0.38:t=fill[scrimd];"
            f"[scrimd]zoompan=z='min(zoom+0.0005,1.12)':d=1:"
            f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS}[zp];"
            f"[zp]{ass_filter(ass)}[v]"
        )

    written: list[Path] = []
    for i, (start, length) in enumerate(windows, 1):
        suffix = f"-h{i}" if multi else ""
        ass_path = work / f"short-{mix}{suffix}.ass"
        ass_path.write_text(build_ass(slug, lines, meta, start, length, duration),
                            encoding="utf-8")
        out = out_dir / f"short-{mix}{suffix}-{slug}.mp4"
        args = ["-loop", "1", "-i", str(cover),
                "-ss", f"{start:.3f}", "-i", str(audio),
                "-filter_complex", chain(ass_path),
                "-map", "[v]", "-map", "1:a",
                "-t", f"{length:.3f}",
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
                "-pix_fmt", "yuv420p", "-r", str(FPS),
                "-c:a", "aac", "-b:a", "192k", "-shortest",
                "-movflags", "+faststart", str(out)]
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)
        written.append(out)
        thumb_for(out, cover)
    return written


def thumb_for(short: Path, cover: Path):
    """Save a Short's thumbnail next to the other thumbs, in 9:16.

    release.py looks for `thumb-short-<slug>.png` and, finding nothing, falls
    back to the square cover - which YouTube then pillarboxes, so the one image
    a scroller sees is a small box with black bars either side. The Short's own
    first seconds already are the thumbnail: blurred art, the cover and a Thai
    caption, composed for exactly this frame.
    """
    dest = ROOT / "library" / "thumbs" / f"thumb-{short.stem}.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-ss", "1.5", "-i", str(short),
         "-frames:v", "1", str(dest)], check=True)
    return dest


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--all", action="store_true", help="every song on disk")
    ap.add_argument("--mix", default="song", choices=["song", "karaoke"])
    ap.add_argument("--hooks", action="store_true",
                    help="one Short per chorus, not just the first")
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
            outs = render(slug, mix=args.mix, all_hooks=args.hooks)
            for out in outs:
                print(f"{slug}: {out.relative_to(ROOT)} ({_duration(out):.1f}s)")
        except Exception as exc:
            print(f"{slug}: FAILED {exc}", file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
