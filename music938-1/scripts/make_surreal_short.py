#!/usr/bin/env python3
"""Render the absurdist "exhibit" clips for the Facebook + TikTok surfaces.

K (2026-11-09): the FB/TK channels should stop being tidy and become an absurd
art project — "สุดโต่งแต่ไม่ผิดกฏ บ้าๆบอๆหลุดโลก" — and sell the idea nobody else
is doing. This is the renderer for that lane.

An "exhibit" is one song turned into a moving painting: the cover art run through
a surreal ffmpeg effect recipe (melting, upside-down, a colour wave, a glitch, a
ghost trail), overlaid with a museum label that files one ordinary Thai thing
under one impossible feeling, and bedded on that song's chorus. The caption that
travels with it comes from `surreal.py`, so the clip and the post always agree.

Why this is safe to run unattended (advisor panel, duck + pollinations,
2026-11-09, quorum PASS):
  * every clip is short (<= 30 s) and each is visually different — the panel's
    single biggest warning was a reach-killing "low-quality / look-alike" flag,
    so the recipe is picked per song, not copied;
  * the premise is drawn from a closed vocabulary of absurd nouns and feelings,
    so a caption can never drift into a real-world claim; a banned substring is
    refused, not published (`surreal.claim_problem`);
  * the AI content is disclosed on every clip and every caption.

Rule #1: the art is ffmpeg filters over covers we already own. Nothing is
downloaded, nothing is paid for, no login.

    python3 scripts/make_surreal_short.py --plan
    python3 scripts/make_surreal_short.py --all
    python3 scripts/make_surreal_short.py 01-khon-di-thi-chak-pai
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_karaoke import FONT, OUTLINE, ass_filter, _duration  # noqa: E402
from make_short import _pick_window, load_lyrics, thumb_for  # noqa: E402
import release  # noqa: E402
import surreal  # noqa: E402

SONGS = ROOT / "library" / "songs"
COVERS = ROOT / "library" / "covers"
OUT_DIR = ROOT / "library" / "surreal"
WORK = ROOT / "work" / "surreal"

W, H, FPS = 1080, 1920, 30
MAX_SECONDS = 28.0          # well under the 60 s ceiling, and under the 30 s
                            # the panel named as the safe, shareable length.

# The art recipes. Each is a named ffmpeg filter chain applied to the cover,
# after the vertical crop. They are deliberately *different from each other* so
# a viewer scrolling the grid sees five kinds of painting, not one effect on
# repeat — that difference is what keeps the lane off the look-alike flag.
#
# `t` is the ffmpeg time variable; a still image loops so `t` advances with the
# clip. All chains were verified to parse and encode on the standalone ffmpeg
# in this repo (2026-11-09); `shear`/`rgbashift` do NOT take expressions here, so
# the motion comes from `rotate`, `hue`, `geq`, `tblend` and `vignette` instead.
RECIPES: dict[str, str] = {
    # A slow melting sway, colour drifting through the wheel.
    "melt": "rotate='PI/24*sin(t*0.6)':fillcolor=black@0,hue=H=t*0.15",
    # Upside-down and tilting: the gallery's "hanging the wrong way up" joke.
    "topsy": "vflip,rotate='PI/12*sin(t*0.4)':fillcolor=black@0,"
             "hue=H=t*0.1,vignette=PI/3",
    # A horizontal colour wave, like the painting is breathing.
    "wave": "geq=r='r(X+8*sin(Y/22+T*2),Y)':g='g(X+8*sin(Y/22+T*2),Y)':"
            "b='b(X,Y)',hue=H=t*0.2",
    # A hard glitch: negative, chroma tearing sideways.
    "glitch": "negate,hue=H=t*0.5,rgbashift=rh=16:bh=-16",
    # A ghost trail of darker pixels, smearing the frame over time.
    "ghost": "tblend=all_mode=grainextract,hue=H=t*0.3",
}

RECIPE_ORDER = ("melt", "topsy", "wave", "glitch", "ghost")


def recipe_for(slug: str) -> str:
    """Which recipe this song gets — stable per slug, spread across the set."""
    return RECIPE_ORDER[surreal._seed(slug) % len(RECIPE_ORDER)]


def _esc(text: str) -> str:
    return (text.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")
            .replace("\n", r"\N"))


def build_ass(slug: str, song_title: str, seconds: float) -> str:
    """The museum label: exhibit number, the absurd pairing, the ask, the note.

    Laid out with explicit positions rather than style stacking: several styles
    sharing an alignment/margin overprint on one line in libass (learned on the
    affiliate card). Top block is the label, bottom block is the ask + AI note.
    """
    thing, feeling = surreal.pair(slug)
    no = surreal.exhibit_no(slug)

    def pos(x: int, y: int) -> str:
        return f"{{\\an5\\pos({x},{y})}}"

    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: No,{FONT},40,&H00E0E0E0,&H00E0E0E0,{OUTLINE},&H64000000,1,0,0,0,100,100,0.6,0,1,4,2,2,60,60,60,1
Style: Exhibit,{FONT},84,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H64000000,1,0,0,0,100,100,0.6,0,1,7,3,2,60,60,60,1
Style: Rule,{FONT},42,&H0060FFFF,&H0060FFFF,{OUTLINE},&H64000000,0,0,0,0,100,100,0.4,0,1,4,2,2,60,60,60,1
Style: Ask,{FONT},46,&H0000FFC0,&H0000FFC0,{OUTLINE},&H64000000,1,0,0,0,100,100,0.4,0,1,5,2,2,60,60,60,1
Style: Note,{FONT},36,&H00CCCCCC,&H00CCCCCC,{OUTLINE},&H64000000,0,0,0,0,100,100,0.3,0,1,3,1,2,60,60,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    def ts(t: float) -> str:
        t = max(0.0, t)
        return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"

    y_no, y_title, y_rule = 250, 360, 470
    y_ask, y_note = 1620, 1740
    ev = []
    ev.append(f"Dialogue: 0,{ts(0)},{ts(seconds)},No,,0,0,0,,"
              f"{pos(540, y_no)}{{\\fad(180,180)}}{_esc(no)}")
    # The pairing, one line each, so Thai tone marks have room and the colon
    # does not force a wrap.
    ev.append(f"Dialogue: 0,{ts(0.2)},{ts(seconds)},Exhibit,,0,0,0,,"
              f"{pos(540, y_title)}{{\\fad(180,180)}}{_esc(thing)}")
    ev.append(f"Dialogue: 0,{ts(0.4)},{ts(seconds)},Rule,,0,0,0,,"
              f"{pos(540, y_rule)}{{\\fad(180,180)}}→ {_esc(feeling)}")
    ev.append(f"Dialogue: 0,{ts(1.2)},{ts(seconds)},Ask,,0,0,0,,"
              f"{pos(540, y_ask)}{{\\fad(180,180)}}{_esc(surreal.RITUAL_ASK)}")
    ev.append(f"Dialogue: 0,{ts(0.8)},{ts(seconds)},Note,,0,0,0,,"
              f"{pos(540, y_note)}{{\\fad(180,180)}}{_esc(surreal.AI_NOTE)}")
    if song_title:
        ev.append(f"Dialogue: 0,{ts(0.6)},{ts(seconds)},Note,,0,0,0,,"
                  f"{pos(540, y_note + 70)}{{\\fad(180,180)}}{_esc('เพลง: ' + song_title)}")
    return head + "\n".join(ev) + "\n"


def render(slug: str, out_dir: Path | None = None) -> Path:
    audio = SONGS / f"song-{slug}.mp3"
    cover = COVERS / f"cover-{slug}.jpg"
    for p in (audio, cover):
        if not p.exists():
            raise FileNotFoundError(f"missing {p}; pull media first")

    meta, _lines = load_lyrics(slug)
    song_title = meta.get("TITLE", slug)
    # Guard the copy *we* author — the exhibit premise and the ask. The song's own
    # title is the artist's and is only quoted, so a normal word in a sad lyric
    # ("ตาย") must not be treated as a claim of ours and block the clip.
    problem = surreal.claim_problem(
        " ".join([surreal.title_line(slug), surreal.RITUAL_ASK]))
    if problem:
        raise SystemExit(f"{slug}: exhibit text carries banned {problem!r} — fix it")

    dur = _duration(audio)
    start, length = _pick_window(slug, dur)
    length = min(length, MAX_SECONDS)

    WORK.mkdir(parents=True, exist_ok=True)
    ass_path = WORK / f"surreal-{slug}.ass"
    ass_path.write_text(build_ass(slug, song_title, length), encoding="utf-8")

    out_dir = out_dir or OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"surreal-{slug}.mp4"

    recipe = RECIPES[recipe_for(slug)]
    chain = (
        f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        f"eq=saturation=1.25:brightness=-0.02,{recipe},"
        f"eq=brightness=-0.06[art];"
        # A soft dark band top and bottom so the label and the ask stay legible
        # over whatever the effect is doing underneath.
        f"[art]drawbox=x=0:y=0:w={W}:h=560:color=black@0.34:t=fill,"
        f"drawbox=x=0:y={H-380}:w={W}:h=380:color=black@0.34:t=fill[band];"
        f"[band]{ass_filter(ass_path)}[v]"
    )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error",
         "-loop", "1", "-i", str(cover),
         "-ss", f"{start:.3f}", "-i", str(audio),
         "-filter_complex", chain,
         "-map", "[v]", "-map", "1:a",
         "-t", f"{length:.3f}",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
         "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "192k", "-shortest",
         "-movflags", "+faststart", str(out)],
        check=True)
    thumb_for(out, cover)
    return out


def _all_slugs() -> list[str]:
    return sorted(p.stem[len("song-"):] for p in SONGS.glob("song-*.mp3"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--all", action="store_true", help="every song on disk")
    ap.add_argument("--plan", action="store_true", help="show the exhibits, render nothing")
    ap.add_argument("--skip-existing", action="store_true",
                    help="skip a slug whose exhibit is already rendered")
    ap.add_argument("--limit", type=int, default=0,
                    help="render at most N new exhibits (0 = no limit)")
    args = ap.parse_args()

    if args.all or (args.plan and not args.slug):
        slugs = _all_slugs()
    elif args.slug:
        slugs = [args.slug]
    else:
        ap.error("give a slug or --all")
    if not slugs:
        print("no songs on disk — pull media first")
        return 1

    if args.plan:
        for slug in slugs:
            thing, feeling = surreal.pair(slug)
            print(f"{surreal.exhibit_no(slug):14} {recipe_for(slug):7} "
                  f"{thing} : {feeling}")
        return 0

    # A daily rail must not re-render the whole gallery, and the panel warned
    # that mass-producing look-alikes reads as spam. So the batch is capped and
    # already-rendered exhibits are skipped, leaving the pace to the schedule.
    if args.skip_existing:
        slugs = [s for s in slugs if not (OUT_DIR / f"surreal-{s}.mp4").exists()]
    if args.limit:
        slugs = slugs[:args.limit]
    if not slugs:
        print("nothing new to render")
        return 0

    rc = 0
    for slug in slugs:
        try:
            out = render(slug)
            print(f"{slug}: {out.relative_to(ROOT)}")
        except Exception as exc:  # noqa: BLE001
            print(f"{slug}: FAILED {exc}")
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
