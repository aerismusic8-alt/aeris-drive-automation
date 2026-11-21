#!/usr/bin/env python3
"""Turn one song master into the two posts the Facebook Page publishes.

K sends a song as a **square 1024x1024 mp4 with an embedded subtitle track**.
That file is a *master*, not a postable clip: the square has no profile in
`ops/clip_standard.py`, the audio runs hot (+0.2 dBTP on the 2026-11-18 song),
and the picture is a still, so the vertical profile's motion floor rejects it.
Every song has needed the same three fixes, so they live here instead of in a
throwaway script per song:

  * a vertical **Reel** (1080x1920, <= 90 s) — blurred background, the square
    cover in the upper area, a scrim band for the lyrics, the master's own timed
    lyrics, a slow zoom so the frame is alive, and the brand end card.
  * a landscape **full-song** video (1920x1080) — the cover on the left, the
    lyrics in the right band, the whole track.

Both are measured by `clip_standard` and the render is discarded on a fail, so a
below-floor file can never be posted. `--post` then publishes them with
`fb_graph` (API-only; browser posting is off, K 2026-11-15).

    python3 ops/song_to_page.py --src master.mp4 --slug maps-and-concrete \
        --title "Maps and Concrete" --tagline "ฮิปฮอปฟิวชัน" --render
    python3 ops/song_to_page.py --src master.mp4 --slug ... --title ... --post

The lyrics come from the file's own subtitle track, so the text on screen is what
is actually sung — never an estimate (K, 2026-11-03: a drifting sweep reads as
the clip lying to the viewer).
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))

MUSIC = ROOT / "music938-1"
FONTS = str(MUSIC / "fonts")
FONT = "Noto Sans Thai"

# The vertical treatment (blurred bg + cover + scrim) is sized off the frame so a
# change to W/H keeps the composition.
COVER_FRAC = 0.86          # cover width as a fraction of the frame
COVER_TOP_FRAC = 0.055
SCRIM_FRAC = 0.52
ZOOM_REEL = 1.40           # a rate sized to the clip length; see make_short.chain
ZOOM_FULL = 1.10
REEL_MAX = 88.0            # FB Reels API allows 3-90 s; leave headroom


def _tool(name: str) -> str:
    for cand in (os.environ.get(name.upper()),
                 shutil.which(name),
                 f"/workspace/ax-tools/ffmpeg/ffmpeg-master-latest-linux64-gpl/bin/{name}"):
        if cand and Path(cand).exists():
            return cand
    raise SystemExit(f"{name} not found on PATH; set ${name.upper()}")


def duration(src: Path) -> float:
    out = subprocess.run([_tool("ffprobe"), "-v", "error", "-show_entries",
                          "format=duration", "-of", "csv=p=0", str(src)],
                         capture_output=True, text=True).stdout
    return float(out.strip())


def extract_srt(src: Path, out: Path) -> Path:
    """The master carries its lyrics as a subtitle track; pull it verbatim."""
    rc = subprocess.run([_tool("ffmpeg"), "-v", "error", "-y", "-i", str(src),
                         "-map", "0:s:0", str(out)]).returncode
    if rc or not out.exists() or out.stat().st_size == 0:
        raise SystemExit("the master has no subtitle track to read the lyrics from")
    return out


def parse_srt(text: str) -> list[tuple[float, float, str]]:
    cues: list[tuple[float, float, str]] = []
    for block in re.split(r"\n\s*\n", text.strip()):
        m = re.search(r"(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)", block)
        if not m:
            continue
        g = [int(x) for x in m.groups()]
        st = g[0] * 3600 + g[1] * 60 + g[2] + g[3] / 1000
        en = g[4] * 3600 + g[5] * 60 + g[6] + g[7] / 1000
        lines = [ln.strip() for ln in block.splitlines()[2:] if ln.strip()]
        # The track scrolls a 3-line window, so the whole block repeats earlier
        # lines. Keep the last line only — that is the one just sung.
        if lines:
            cues.append((st, en, lines[-1]))
    return cues


def _ts(t: float) -> str:
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    return f"{h}:{m:02d}:{t % 60:05.2f}"


def _esc(x: str) -> str:
    return (x.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}")
             .replace("\n", "\\N"))


def _lyric_events(cues, start: float, length: float, end_card: float,
                  brand_ask: str, brand_promise: str) -> str:
    """Dialogue lines for the lyric track plus the follow end card."""
    ev: list[str] = []
    for st, en, txt in cues:
        if st >= start + length or en <= start:
            continue
        s = max(st, start) - start
        e = min(en, start + length, end_card) - start
        if e - s < 0.35:
            continue
        ev.append(f"Dialogue: 0,{_ts(s)},{_ts(e)},Lyric,,0,0,0,,{{\\fad(80,80)}}{_esc(txt)}")
    ev.append(f"Dialogue: 0,{_ts(end_card)},{_ts(length)},Follow,,0,0,0,,"
              f"{{\\fad(200,300)}}{_esc(brand_ask)}")
    ev.append(f"Dialogue: 0,{_ts(end_card)},{_ts(length)},FollowSub,,0,0,0,,"
              f"{{\\fad(200,300)}}{_esc(brand_promise)}")
    return "\n".join(ev)


def build_ass(path: Path, cues, start: float, length: float, W: int, H: int,
              style: str, brand_ask: str, brand_promise: str) -> Path:
    end_card = max(0.0, length - 3.0)
    if style == "vertical":
        styles = (
            f"Style: Lyric,{FONT},42,&H00FFFFFF,&H00FFFFFF,&H00101010,&H80000000,"
            "1,0,0,0,100,100,0.5,0,1,4,2,2,70,70,430,1\n"
            f"Style: Follow,{FONT},72,&H0020E0FF,&H0020E0FF,&H00000000,&H00000000,"
            "1,0,0,0,100,100,0.5,0,1,8,4,2,60,60,260,1\n"
            f"Style: FollowSub,{FONT},54,&H00E8E8E8,&H00E8E8E8,&H00000000,&H00000000,"
            "0,0,0,0,100,100,0.5,0,1,6,3,2,60,60,190,1"
        )
    else:
        styles = (
            f"Style: Lyric,{FONT},44,&H00FFFFFF,&H00FFFFFF,&H00101010,&H80000000,"
            "1,0,0,0,100,100,0.5,0,1,5,3,5,1180,90,60,1\n"
            f"Style: Follow,{FONT},64,&H0020E0FF,&H0020E0FF,&H00000000,&H00000000,"
            "1,0,0,0,100,100,0.5,0,1,8,4,5,0,0,60,1\n"
            f"Style: FollowSub,{FONT},44,&H00E8E8E8,&H00E8E8E8,&H00000000,&H00000000,"
            "0,0,0,0,100,100,0.5,0,1,6,3,2,0,0,60,1"
        )
    events = _lyric_events(cues, start, length, end_card, brand_ask, brand_promise)
    path.write_text(f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
{styles}

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
{events}
""", encoding="utf-8")
    return path


def _gate(path: Path) -> None:
    """Refuse (and delete) a render that is below the channel floor."""
    import clip_standard
    try:
        clip_standard.assert_ok(str(path))
    except SystemExit:
        path.unlink(missing_ok=True)
        raise


def render_reel(src: Path, out: Path, cues, length: float, start: float,
                brand_ask: str, brand_promise: str) -> Path:
    W, H, FPS = 1080, 1920, 30
    cw, cy = int(W * COVER_FRAC), int(H * COVER_TOP_FRAC)
    scrim = int(H * SCRIM_FRAC)
    rate = (ZOOM_REEL - 1.0) / max(1.0, length * FPS)
    ass = build_ass(out.with_suffix(".ass"), cues, start, length, W, H,
                    "vertical", brand_ask, brand_promise)
    fc = (
        f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        "gblur=sigma=32,eq=brightness=-0.06:saturation=1.05[bg];"
        f"[0:v]scale={cw}:-1[fg];"
        f"[bg][fg]overlay=(W-w)/2:{cy}[base];"
        f"[base]drawbox=x=0:y={scrim}:w={W}:h={H - scrim}:color=black@0.38:t=fill[scrimd];"
        f"[scrimd]zoompan=z='min(1+{rate:.8f}*on,{ZOOM_REEL})':d=1:"
        f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS}[zp];"
        f"[zp]ass={ass}:fontsdir={FONTS}[vout];"
        f"[0:a]atrim={start}:{start + length},asetpts=PTS-STARTPTS,"
        "loudnorm=I=-14:TP=-2.0:LRA=11,alimiter=limit=0.7:level=0,aresample=48000[aout]"
    )
    subprocess.run([_tool("ffmpeg"), "-hide_banner", "-v", "error", "-y",
                    "-i", str(src), "-filter_complex", fc,
                    "-map", "[vout]", "-map", "[aout]", "-t", f"{length:.3f}",
                    "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-r", str(FPS),
                    "-c:a", "aac", "-ar", "48000", "-b:a", "192k",
                    "-movflags", "+faststart", str(out)], check=True)
    _gate(out)
    return out


def render_full(src: Path, out: Path, cues, dur: float,
                brand_ask: str, brand_promise: str) -> Path:
    W, H, FPS = 1920, 1080, 30
    rate = (ZOOM_FULL - 1.0) / max(1.0, dur * FPS)
    ass = build_ass(out.with_suffix(".ass"), cues, 0.0, dur, W, H,
                    "horizontal", brand_ask, brand_promise)
    fc = (
        f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        "gblur=sigma=28,eq=brightness=-0.10:saturation=1.0[bg];"
        "[0:v]scale=620:-1[cover];"
        "[bg][cover]overlay=x=60:y=(H-h)/2[base];"
        f"[base]zoompan=z='min(1+{rate:.8f}*on,{ZOOM_FULL})':d=1:"
        f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS}[zp];"
        f"[zp]ass={ass}:fontsdir={FONTS}[vout];"
        "[0:a]loudnorm=I=-14:TP=-2.0:LRA=11,alimiter=limit=0.7:level=0,"
        "aresample=48000[aout]"
    )
    subprocess.run([_tool("ffmpeg"), "-hide_banner", "-v", "error", "-y",
                    "-i", str(src), "-filter_complex", fc,
                    "-map", "[vout]", "-map", "[aout]",
                    "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-r", str(FPS),
                    "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(out)], check=True)
    _gate(out)
    return out


def caption(title: str, tagline: str, *, full: bool) -> str:
    sys.path.insert(0, str(MUSIC / "scripts"))
    import branding
    lead = "🎵 เพลงเต็ม" if full else "🎵 ตัวอย่างจากเพลง"
    lines = [
        f"{lead} \"{title}\"",
        f"🎧 {tagline}" if tagline else "",
        branding.LABEL,
        f"❤️ {branding.FOLLOW_ASK} · {branding.FOLLOW_PROMISE}",
        f"🎬 YouTube {branding.HANDLE}",
        branding.HASHTAGS,
    ]
    return "\n".join(x for x in lines if x)


def post(reel: Path, full: Path, title: str, tagline: str) -> dict:
    import fb_graph
    ids = {}
    ids["reel"] = fb_graph.post_reel(reel, caption(title, tagline, full=False))
    ids["video"] = fb_graph.post_video(full, caption(title, tagline, full=True),
                                       title=title)
    return ids


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, type=Path, help="the square master mp4")
    ap.add_argument("--slug", required=True, help="filename-safe song id")
    ap.add_argument("--title", required=True)
    ap.add_argument("--tagline", default="")
    ap.add_argument("--out-dir", type=Path,
                    default=Path("/workspace/ax-tools/incoming/songs"))
    ap.add_argument("--reel-seconds", type=float, default=REEL_MAX)
    ap.add_argument("--reel-start", type=float, default=0.0)
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--post", action="store_true")
    args = ap.parse_args()

    if not args.src.exists():
        raise SystemExit(f"no such master: {args.src}")

    # This is a publish route, not just a render: `--post` writes to the Page.
    # So the slug goes through the compass first, exactly as the four render
    # lanes do — a slug on argv is not exempt from K's genre rule, and a
    # synthesised bed is not a song.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import compass  # noqa: PLC0415
    compass.require_publishable(args.slug)

    sys.path.insert(0, str(MUSIC / "scripts"))
    import branding

    args.out_dir.mkdir(parents=True, exist_ok=True)
    srt = extract_srt(args.src, args.out_dir / f"{args.slug}.srt")
    cues = parse_srt(srt.read_text(encoding="utf-8"))
    dur = duration(args.src)
    length = min(args.reel_seconds, max(5.0, dur))
    print(f"{args.title}: {dur:.1f}s, {len(cues)} lyric lines, reel {length:.0f}s")

    reel = args.out_dir / f"reel-{args.slug}-1080x1920.mp4"
    full = args.out_dir / f"full-{args.slug}-1920x1080.mp4"

    if args.render or args.post:
        render_reel(args.src, reel, cues, length, args.reel_start,
                    branding.FOLLOW_ASK, branding.FOLLOW_PROMISE)
        print("reel ok ->", reel)
        render_full(args.src, full, cues, dur, branding.FOLLOW_ASK,
                    branding.FOLLOW_PROMISE)
        print("full ok ->", full)
    if args.post:
        ids = post(reel, full, args.title, args.tagline)
        print("posted:", ids)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
