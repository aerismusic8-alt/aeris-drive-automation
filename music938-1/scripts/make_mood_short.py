#!/usr/bin/env python3
"""Turn each real-instrument mood bed into a short vertical clip.

K (2026-11-09) heard the six instrument beds and approved them — "เสียงดนตรีใช้
ได้ รวมทั้งเสียง6แบบด้วย เอาไปทำคลิปเลย" (the music works, all six moods too —
go make clips). The sleep lane turns one mood into an 8-hour container; this rail
turns each mood into a shareable 9:16 clip for Shorts / Reels / TikTok.

The audio is the bed and nothing else (K: music only), so the clip carries no
rain and no vocal. The picture is a slow colour field drawn from the mood's own
palette — no cover art, no download — with the mood's Thai name on the opening
card and the channel's follow ask as the end card.

Rule #1: the art is ffmpeg's `gradients` source, the music is our own SoundFont
render, so a clip costs nothing and needs no login.

    python3 scripts/make_mood_short.py --plan     # what it would build
    python3 scripts/make_mood_short.py --all      # render all six
    python3 scripts/make_mood_short.py calm
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import covers  # noqa: E402  the mood palettes
import release  # noqa: E402  the follow copy
import surreal  # noqa: E402  the AI-disclosure line
from ambient_loop import ensure_bed, bed_path  # noqa: E402  the shared bed cache
from make_karaoke import FONT, OUTLINE, _duration  # noqa: E402

OUT_DIR = ROOT / "library" / "moods"
THUMBS = ROOT / "library" / "thumbs"
STATE = ROOT / "work" / "mood-clips-state.json"
# Bump to force a re-render after a renderer change; `--once` skips a mood whose
# clip is already on disk at this version.
STATE_VERSION = 3

W, H, FPS = 1080, 1920, 30
# Well under the 60 s Shorts ceiling; long enough to hear the harmony turn once.
CLIP_SECONDS = 45.0
CARD_SECONDS = 3.0
CARD_FADE = 0.4
FOLLOW_CARD_SECONDS = 2.5
FOLLOW_CARD_LEAD = 0.4

# The six approved moods. `name` is the Thai label that goes on the card and in
# the title; `key` only moves the bed's root octave, as in `soundfont`. Ids stay
# English so the file names and the bed cache agree.
MOODS: dict[str, dict] = {
    "calm":    {"name": "กล่อมนอน",   "key": "C",
                "tagline": "ผ่อนคลาย หลับสบาย"},
    "warm":    {"name": "อบอุ่น",      "key": "F",
                "tagline": "อบอุ่นใจ เหมือนได้พัก"},
    "sad":     {"name": "เศร้า",       "key": "A",
                "tagline": "สำหรับวันที่ใจไม่ไหว"},
    "hopeful": {"name": "มีความหวัง", "key": "D",
                "tagline": "เริ่มใหม่อีกครั้ง"},
    "mystic":  {"name": "ขลัง",        "key": "G",
                "tagline": "ขลัง ๆ แบบไทย"},
    "epic":    {"name": "ยิ่งใหญ่",    "key": "F",
                "tagline": "ยิ่งใหญ่ กึกก้อง"},
}

# The music is a machine performance of a written arrangement, so it is
# synthetic and must say so (COMPLIANCE.md). This names the instruments, because
# the whole point of the swap was that the sounds are real recordings.
AI_NOTE = "ดนตรีบรรเลงเครื่องดนตรีจริง สร้างด้วย AI"


def title_for(mood: str) -> str:
    m = MOODS[mood]
    return f"เพลง{m['name']} เครื่องดนตรีจริง | {m['tagline']} | AERIS Music"


def _hex(h: float, s: float, v: float) -> str:
    r, g, b = covers._hsv_rgb(h, s, v)
    return f"0x{r:02X}{g:02X}{b:02X}"


def art_colors(mood: str) -> tuple[str, str]:
    """Two gradient endpoints for the mood, from the shared cover palette.

    Reusing `covers.PALETTES` keeps a mood the same colour wherever it appears,
    so the clip, the cover and the sleep thumbnail read as one family.
    """
    (h1, s1, v1), (h2, s2, v2) = covers.PALETTES[mood]
    # The second anchor is darkened so the field has depth rather than two flat
    # bands; the first stays bright so the frame is not near-black on a phone.
    return _hex(h1, s1, v1), _hex(h2, s2, min(0.9, v2 * 0.55))


def art_source(mood: str, seconds: float) -> str:
    """The `gradients` lavfi source string — the whole moving background."""
    c0, c1 = art_colors(mood)
    return (f"gradients=s={W}x{H}:c0={c0}:c1={c1}:speed=0.012:"
            f"d={seconds:.3f}:r={FPS}")


def build_ass(mood: str, seconds: float) -> str:
    """The overlay: the mood card, the brand mark, the follow end card."""
    m = MOODS[mood]

    def pos(x: int, y: int) -> str:
        return f"{{\\an5\\pos({x},{y})}}"

    def ts(t: float) -> str:
        t = max(0.0, t)
        return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"

    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Card,{FONT},150,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H64000000,1,0,0,0,100,100,0.6,0,1,6,3,2,60,60,60,1
Style: Tag,{FONT},64,&H00F0E6D2,&H00F0E6D2,{OUTLINE},&H64000000,0,0,0,0,100,100,0.4,0,1,5,2,2,60,60,60,1
Style: Brand,{FONT},44,&H00DDFFFF,&H00DDFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,7,54,54,60,1
Style: Follow,{FONT},78,&H0020E0FF,&H0020E0FF,{OUTLINE},&H00000000,1,0,0,0,100,100,0.5,0,1,8,4,2,60,60,280,1
Style: FollowSub,{FONT},58,&H00E8E8E8,&H00E8E8E8,{OUTLINE},&H00000000,0,0,0,0,100,100,0.5,0,1,6,3,2,60,60,210,1
Style: Note,{FONT},38,&H00CCCCCC,&H00CCCCCC,{OUTLINE},&H64000000,0,0,0,0,100,100,0.3,0,1,3,1,2,60,60,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ev = []
    # The opening card. The first two seconds decide a scroll, so the mood name
    # is on screen from frame 0 while the music plays underneath.
    ev.append(f"Dialogue: 0,{ts(0)},{ts(CARD_SECONDS)},Card,,0,0,0,,"
              f"{pos(540, 820)}{{\\fad({int(CARD_FADE*1000)},{int(CARD_FADE*1000)})}}"
              f"{_escape(m['name'])}")
    ev.append(f"Dialogue: 0,{ts(0.3)},{ts(CARD_SECONDS)},Tag,,0,0,0,,"
              f"{pos(540, 970)}{{\\fad({int(CARD_FADE*1000)},{int(CARD_FADE*1000)})}}"
              f"{_escape(m['tagline'])}")
    # The brand mark, low and quiet, so the frame is signed without shouting.
    ev.append(f"Dialogue: 0,{ts(0)},{ts(seconds)},Brand,,0,0,0,,"
              f"{pos(540, 1780)}{{\\fad(300,300)}}AERIS MUSIC")
    # The AI disclosure, on every clip, small and steady.
    ev.append(f"Dialogue: 0,{ts(0.6)},{ts(seconds)},Note,,0,0,0,,"
              f"{pos(540, 1850)}{{\\fad(300,300)}}{_escape(AI_NOTE)}")
    # The follow end card, held briefly and released a beat before the end.
    hold = min(FOLLOW_CARD_SECONDS, max(0.0, seconds - FOLLOW_CARD_LEAD))
    if hold >= 0.5:
        start_at = max(0.0, seconds - FOLLOW_CARD_LEAD - hold)
        ev.append(f"Dialogue: 0,{ts(start_at)},{ts(start_at + hold)},Follow,,0,0,0,,"
                  f"{{\\fad(200,300)}}{_escape(release.FOLLOW_ASK)}")
        ev.append(f"Dialogue: 0,{ts(start_at)},{ts(start_at + hold)},FollowSub,,0,0,0,,"
                  f"{{\\fad(200,300)}}{_escape(release.FOLLOW_PROMISE)}")
    return head + "\n".join(ev) + "\n"


def plan(mood: str, *, seconds: float = CLIP_SECONDS) -> dict:
    """Everything the render needs, with nothing executed or downloaded."""
    if mood not in MOODS:
        raise ValueError(f"unknown mood {mood!r}; choose from {sorted(MOODS)}")
    bed = bed_path(mood, MOODS[mood]["key"])
    return {
        "mood": mood,
        "name": MOODS[mood]["name"],
        "title": title_for(mood),
        "seconds": seconds,
        "bed": bed,
        "art": art_source(mood, seconds),
        "out": OUT_DIR / f"mood-{mood}.mp4",
        "thumb": THUMBS / f"thumb-mood-{mood}.png",
    }


def _escape(text: str) -> str:
    return text.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")


def render(mood: str, *, seconds: float = CLIP_SECONDS) -> Path:
    p = plan(mood, seconds=seconds)
    # The bed caches by mood+key, so a re-render of the clip does not re-synth.
    ensure_bed(mood, MOODS[mood]["key"])
    if not p["bed"].exists():
        raise RuntimeError(f"bed missing after render: {p['bed']}")

    work = ROOT / "work" / "moods"
    work.mkdir(parents=True, exist_ok=True)
    ass_path = work / f"mood-{mood}.ass"
    ass_path.write_text(build_ass(mood, seconds), encoding="utf-8")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    chain = (f"[0:v]vignette=PI/4,format=yuv420p[art];"
             f"[art]{_ass_filter(ass_path)}[v]")
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-f", "lavfi", "-i", p["art"],
         "-i", str(p["bed"]),
         "-filter_complex", chain,
         "-map", "[v]", "-map", "1:a",
         "-t", f"{seconds:.3f}",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
         "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "192k", "-shortest",
         "-movflags", "+faststart", str(p["out"])],
        check=True)
    _thumb(p["out"], p["thumb"])
    return p["out"]


def _ass_filter(ass_path: Path) -> str:
    from make_karaoke import ass_filter  # noqa: PLC0415
    return ass_filter(ass_path)


def _thumb(clip: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-ss", "1.5", "-i", str(clip), "-frames:v", "1", str(dest)], check=True)


def already_done(mood: str) -> bool:
    """Whether `--once` can skip this mood: its clip is on disk at this version."""
    if not plan(mood)["out"].exists() or not STATE.exists():
        return False
    try:
        state = json.loads(STATE.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return False
    return state.get("version") == STATE_VERSION and mood in state.get("moods", [])


def _record(moods: list[str]) -> None:
    """Record the moods built, merging into any state already there."""
    state = {"version": STATE_VERSION, "moods": []}
    if STATE.exists():
        try:
            state = json.loads(STATE.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            pass
    if state.get("version") != STATE_VERSION:
        state = {"version": STATE_VERSION, "moods": []}
    state["moods"] = sorted(set(state.get("moods", [])) | set(moods))
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mood", nargs="?")
    ap.add_argument("--all", action="store_true", help="every mood")
    ap.add_argument("--plan", action="store_true", help="show the clips, render nothing")
    ap.add_argument("--once", action="store_true",
                    help="skip a mood already rendered at the current state version")
    ap.add_argument("--seconds", type=float, default=CLIP_SECONDS)
    args = ap.parse_args()

    if args.all or (args.plan and not args.mood):
        moods = list(MOODS)
    elif args.mood:
        moods = [args.mood]
    else:
        ap.error("give a mood or --all")

    if args.plan:
        for mood in moods:
            p = plan(mood, seconds=args.seconds)
            print(f"{mood:8} {p['name']:12} {p['out'].name}  "
                  f"{p['seconds']:.0f}s  {p['title']}")
        return 0

    rc = 0
    built: list[str] = []
    for mood in moods:
        if args.once and already_done(mood):
            print(f"{mood}: already rendered (v{STATE_VERSION})")
            continue
        try:
            out = render(mood, seconds=args.seconds)
            built.append(mood)
            print(f"{mood}: {out.relative_to(ROOT)} ({_duration(out):.1f}s)")
        except Exception as exc:  # noqa: BLE001
            print(f"{mood}: FAILED {exc}", file=sys.stderr)
            rc = 1
    if built:
        _record(built)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
