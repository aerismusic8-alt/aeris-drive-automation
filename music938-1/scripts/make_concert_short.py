#!/usr/bin/env python3
"""Render the "live concert" clips for the Facebook + TikTok surfaces.

K (2026-11-09): "ทำเพลงที่ใช้เสียงร้องแบบแสดงสดคอนเสิร์ตหน่อยสิ เห็นคลิปใช้เทคนิค
นี้คนดูเป็นล้านเลย" — the concert-sounding clips reach millions.

`concert.py` owns the identity and the audio mix; this is the renderer that turns
one of our own songs into a 9:16 live take. The picture is the cover art pushed
under moving stage lights (a warm gradient screen-blended on, a slow push-in, a
vignette), so it reads as a venue and not a studio card. The burned label is the
live card, the brand, the AI disclosure and the follow ask — Thai, no emoji.

Everything is free and offline: the audience, the hall and the room tone are
built from ffmpeg's own noise sources inside `concert.mix_filter`, and the lights
are ffmpeg's `gradients` source. Nothing is downloaded, nothing is paid for.

    python3 scripts/make_concert_short.py --plan
    python3 scripts/make_concert_short.py --all --once --limit 3
    python3 scripts/make_concert_short.py 01-khon-di-thi-chak-pai
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import concert  # noqa: E402  the identity + the mix
import release  # noqa: E402  the follow copy
from make_karaoke import FONT, OUTLINE, ass_filter, _duration  # noqa: E402
from make_short import _pick_window, load_lyrics, thumb_for  # noqa: E402

SONGS = ROOT / "library" / "songs"
COVERS = ROOT / "library" / "covers"
OUT_DIR = ROOT / "library" / "concert"
THUMBS = ROOT / "library" / "thumbs"
WORK = ROOT / "work" / "concert"

W, H, FPS = 1080, 1920, 30
MAX_SECONDS = 42.0          # a live hook, well under the 60 s Shorts ceiling
CARD_SECONDS = 3.2
CARD_FADE = 0.4
FOLLOW_CARD_SECONDS = 2.5
FOLLOW_CARD_LEAD = 0.4

# Stage-light palettes. Each is a two-to-three stop gradient screen-blended over
# the darkened cover; the slow `speed` makes the colour drift across the take.
# The palette is chosen per song (deterministically), so the grid shows a few
# different venues instead of one look on repeat.
PALETTES: dict[str, str] = {
    "amber": "c0=0x2a0a3a:c1=0xff8a3d:c2=0x1a0a2a",
    "crimson": "c0=0x3a0510:c1=0xff3b5c:c2=0x14020a",
    "violet": "c0=0x1a0730:c1=0x8a5cff:c2=0x0a0418",
    "teal": "c0=0x04201e:c1=0x2ee6c8:c2=0x02100f",
}
PALETTE_ORDER = ("amber", "crimson", "violet", "teal")


def palette_for(slug: str) -> str:
    """Pick a stage palette from the slug's own bytes (stable across renders)."""
    n = 0
    for ch in slug:
        n = (n * 131 + ord(ch)) % (2 ** 31)
    return PALETTE_ORDER[n % len(PALETTE_ORDER)]


def all_slugs() -> list[str]:
    return sorted(p.stem[len("song-"):] for p in SONGS.glob("song-*.mp3"))


def plan(slug: str, *, seconds: float = concert.CLIP_SECONDS) -> dict:
    """Everything the render needs, with nothing executed or downloaded."""
    return {
        "slug": slug,
        "seconds": seconds,
        "song": SONGS / f"song-{slug}.mp3",
        "cover": COVERS / f"cover-{slug}.jpg",
        "palette": palette_for(slug),
        "out": OUT_DIR / f"concert-{slug}.mp4",
        "thumb": THUMBS / f"thumb-concert-{slug}.png",
    }


def _escape(text: str) -> str:
    return text.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")


def build_ass(slug: str, song_title: str, seconds: float) -> str:
    """The live overlay: the venue card, the brand, the note, the follow card."""
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
Style: Card,{FONT},132,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H64000000,1,0,0,0,100,100,0.6,0,1,6,3,2,60,60,60,1
Style: Tag,{FONT},58,&H00EAF2FF,&H00EAF2FF,{OUTLINE},&H64000000,0,0,0,0,100,100,0.4,0,1,5,2,2,60,60,60,1
Style: Song,{FONT},52,&H00FFE6B0,&H00FFE6B0,{OUTLINE},&H64000000,0,0,0,0,100,100,0.4,0,1,4,2,2,60,60,60,1
Style: Brand,{FONT},44,&H00DDFFFF,&H00DDFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,7,54,54,60,1
Style: Follow,{FONT},78,&H0020E0FF,&H0020E0FF,{OUTLINE},&H00000000,1,0,0,0,100,100,0.5,0,1,8,4,2,60,60,280,1
Style: FollowSub,{FONT},58,&H00E8E8E8,&H00E8E8E8,{OUTLINE},&H00000000,0,0,0,0,100,100,0.5,0,1,6,3,2,60,60,210,1
Style: Note,{FONT},38,&H00CCCCCC,&H00CCCCCC,{OUTLINE},&H64000000,0,0,0,0,100,100,0.3,0,1,3,1,2,60,60,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ev = []
    # The venue card, on screen from frame 0: the wordmark, the promise, and the
    # song it is playing live.
    ev.append(f"Dialogue: 0,{ts(0)},{ts(CARD_SECONDS)},Card,,0,0,0,,"
              f"{pos(540, 800)}{{\\fad({int(CARD_FADE*1000)},{int(CARD_FADE*1000)})}}"
              f"{_escape(concert.NAME)}")
    ev.append(f"Dialogue: 0,{ts(0.3)},{ts(CARD_SECONDS)},Tag,,0,0,0,,"
              f"{pos(540, 940)}{{\\fad({int(CARD_FADE*1000)},{int(CARD_FADE*1000)})}}"
              f"{_escape(concert.SHOW_LINE)}")
    if song_title:
        ev.append(f"Dialogue: 0,{ts(0.6)},{ts(CARD_SECONDS)},Song,,0,0,0,,"
                  f"{pos(540, 1040)}{{\\fad({int(CARD_FADE*1000)},{int(CARD_FADE*1000)})}}"
                  f"{_escape(song_title)}")
    # The brand mark and the AI disclosure, steady and low.
    ev.append(f"Dialogue: 0,{ts(0)},{ts(seconds)},Brand,,0,0,0,,"
              f"{pos(540, 1780)}{{\\fad(300,300)}}AERIS MUSIC")
    ev.append(f"Dialogue: 0,{ts(0.6)},{ts(seconds)},Note,,0,0,0,,"
              f"{pos(540, 1850)}{{\\fad(300,300)}}{_escape(concert.AI_NOTE)}")
    # The follow end card, held briefly and released a beat before the end.
    hold = min(FOLLOW_CARD_SECONDS, max(0.0, seconds - FOLLOW_CARD_LEAD))
    if hold >= 0.5:
        start_at = max(0.0, seconds - FOLLOW_CARD_LEAD - hold)
        ev.append(f"Dialogue: 0,{ts(start_at)},{ts(start_at + hold)},Follow,,0,0,0,,"
                  f"{pos(540, 1500)}{{\\fad(200,300)}}{_escape(release.FOLLOW_ASK)}")
        ev.append(f"Dialogue: 0,{ts(start_at)},{ts(start_at + hold)},FollowSub,,0,0,0,,"
                  f"{pos(540, 1610)}{{\\fad(200,300)}}{_escape(release.FOLLOW_PROMISE)}")
    return head + "\n".join(ev) + "\n"


def render(slug: str, out_dir: Path | None = None) -> Path:
    p = plan(slug)
    for path in (p["song"], p["cover"]):
        if not path.exists():
            raise FileNotFoundError(f"missing {path}; pull media first")

    meta, _lines = load_lyrics(slug)
    song_title = meta.get("TITLE", slug)

    dur = _duration(p["song"])
    start, length = _pick_window(slug, dur)
    length = min(length, MAX_SECONDS)

    WORK.mkdir(parents=True, exist_ok=True)
    live = WORK / f"live-{slug}.wav"
    concert.render(slug, live, start=start, seconds=length)

    ass_path = WORK / f"concert-{slug}.ass"
    ass_path.write_text(build_ass(slug, song_title, length), encoding="utf-8")

    out_dir = out_dir or OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"concert-{slug}.mp4"

    lights = (f"gradients=s={W}x{H}:{PALETTES[p['palette']]}:n=3:"
              f"speed=0.015:d={length:.3f}")
    chain = (
        f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        f"eq=brightness=-0.42:saturation=1.12,"
        f"zoompan=z='min(zoom+0.0006,1.12)':d=1:s={W}x{H}:fps={FPS}[base];"
        f"[1:v]format=rgba[light];"
        f"[base][light]blend=all_mode=screen:all_opacity=0.85,"
        f"vignette=PI/3.2,eq=brightness=0.02[art];"
        f"[art]{ass_filter(ass_path)}[v]"
    )
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-loop", "1", "-i", str(p["cover"]),
         "-f", "lavfi", "-i", lights,
         "-i", str(live),
         "-filter_complex", chain,
         "-map", "[v]", "-map", "2:a",
         "-t", f"{length:.3f}",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
         "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "192k", "-shortest",
         "-movflags", "+faststart", str(out)],
        check=True)
    live.unlink(missing_ok=True)
    thumb_for(out, p["cover"])
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--all", action="store_true", help="every song on disk")
    ap.add_argument("--plan", action="store_true", help="show the clips, render nothing")
    ap.add_argument("--skip-existing", action="store_true",
                    help="skip a slug whose clip is already rendered")
    ap.add_argument("--limit", type=int, default=0,
                    help="render at most N new clips (0 = no limit)")
    args = ap.parse_args()

    if args.all or (args.plan and not args.slug):
        slugs = all_slugs()
    elif args.slug:
        slugs = [args.slug]
    else:
        ap.error("give a slug or --all")
    if not slugs:
        print("no songs on disk — pull media first")
        return 1

    if args.plan:
        for slug in slugs:
            print(f"{slug:34} {plan(slug)['out'].name}  {palette_for(slug)}")
        return 0

    # A daily rail must not re-render the whole catalogue, and a wall of
    # look-alike clips is the reach-killing pattern the advisor panel named. So
    # already-rendered takes are skipped and the batch is capped.
    if args.skip_existing:
        slugs = [s for s in slugs if not (OUT_DIR / f"concert-{s}.mp4").exists()]
    if args.limit:
        slugs = slugs[:args.limit]
    if not slugs:
        print("nothing new to render")
        return 0

    rc = 0
    for slug in slugs:
        try:
            out = render(slug)
            print(f"{slug}: {out.relative_to(ROOT)} ({_duration(out):.1f}s)")
        except Exception as exc:  # noqa: BLE001
            print(f"{slug}: FAILED {exc}")
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
