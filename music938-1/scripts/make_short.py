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
import release  # noqa: E402  the hook titles live with the rest of the copy

W, H = 1080, 1920
FPS = 30
MAX_SECONDS = 58.0        # under the 60s Shorts ceiling, with margin
HOOK_PAD = 0.6            # a beat of lead-in so the hook does not start on frame 0
ZOOM_MAX = 1.18           # the cover zoom ramp: 1.0 -> ZOOM_MAX across the clip

# The opening card. Every platform's ranking leans hardest on the first two
# seconds — a scroll is decided before the chorus lands — and the file used to
# open on the cover art with no words at all. This draws the *first sung line*
# of the hook, so the one frame every viewer sees gives them something to read
# and sing along with. The 2026-11-07 advisor panel put lyric-led first and told
# us not to delay the song, so the card overlays frame 0 while the audio plays.
HOOK_CARD_SECONDS = 2.0
HOOK_CARD_FADE = 0.25

# The follow end card. Held for two seconds and released a beat before the clip
# ends, so it reads as a sign-off rather than a banner over the song. See
# `release.FOLLOW_ASK` for why it is an end card and not a whole-length button.
FOLLOW_CARD_SECONDS = 2.0
FOLLOW_CARD_LEAD = 0.4
# Below this the card would dominate the clip, so it is left off entirely rather
# than crammed in. Real Shorts are ~58s; this only guards a degenerate input.
FOLLOW_MIN_CLIP = 8.0

# K, 2026-11-07: "a karaoke clip whose words do not match the song is worse than
# no clip." We cannot machine-check syllable timing for free, but we can refuse
# the gross errors — a missing karaoke mix, a mix whose length differs from the
# song (a different take, or the wrong track), or a lyric file with no chorus.
# Any karaoke render must pass this first; a song that fails is simply not made
# into a karaoke clip, never shipped mismatched.
KARAOKE_LEN_TOLERANCE = 0.02


def karaoke_ok(slug: str) -> tuple[bool, str]:
    """May this song become a karaoke Short? Returns (ok, reason).

    The check is deliberately about *matching the song*, not about style: the
    karaoke mix must exist and run the same length as the song (±2%), the cover
    must exist, and the lyric file must actually carry a chorus. That is the
    strongest guarantee a free pipeline can give that the words on screen belong
    to the audio being played.
    """
    songs = ROOT / "library" / "songs"
    song = songs / f"song-{slug}.mp3"
    kara = songs / f"karaoke-{slug}.mp3"
    cover = ROOT / "library" / "covers" / f"cover-{slug}.jpg"
    lyric = ROOT / "lyrics" / f"{slug}.txt"
    if not song.exists():
        return False, f"missing {song.name}"
    if not kara.exists():
        return False, f"missing {kara.name}"
    if not cover.exists():
        return False, f"missing {cover.name}"
    if not lyric.exists():
        return False, f"missing lyrics/{slug}.txt"
    if "[chorus]" not in lyric.read_text(encoding="utf-8").lower():
        return False, "lyrics have no chorus section"
    ds, dk = _duration(song), _duration(kara)
    if abs(ds - dk) > KARAOKE_LEN_TOLERANCE * max(ds, dk):
        return False, f"karaoke length {dk:.1f}s != song {ds:.1f}s"
    return True, "ok"


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
              length: float, duration: float, captions: bool = False,
              hook: int = 1) -> str:
    """Vertical overlay: the title card and a watermark, and optionally the
    per-line lyric sweep.

    `captions=False` (default) draws no lyric text. The sweep timing is
    *estimated* from the song length, not measured, so it drifts off the sung
    line; K ordered it dropped (2026-11-03). Pass `captions=True` for the old
    behaviour.
    """
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
Style: HookCard,{FONT},104,{PRIMARY},{PRIMARY},{OUTLINE},&H64000000,1,0,0,0,100,100,0.5,0,1,7,3,5,50,50,0,1
Style: Cap,{FONT},38,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,8,70,70,310,1
Style: Brand,{FONT},40,&H00DDFFFF,&H00DDFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,7,44,44,40,1
Style: Title,{FONT},64,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,5,2,7,44,44,34,1
Style: Follow,{FONT},72,&H0020E0FF,&H0020E0FF,{OUTLINE},&H00000000,1,0,0,0,100,100,0.5,0,1,8,4,2,60,60,260,1
Style: FollowSub,{FONT},54,&H00E8E8E8,&H00E8E8E8,{OUTLINE},&H00000000,0,0,0,0,100,100,0.5,0,1,6,3,2,60,60,190,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    # Timing is estimated over the WHOLE song, then shifted into the window.
    full = estimate(lines, duration)
    events: list[str] = []

    # The opening card carries the *first sung line* of this hook, not a generic
    # question. The first frame is the one frame every viewer sees, so it shows
    # the actual lyric they are about to hear — a viewer gets something to read
    # and sing along with, which is the lever the 2026-11-07 advisor panel put
    # first ("lyric-led beats a template card; do not delay the song"). The
    # audio still starts on frame 0, so the card overlays, it does not delay.
    card = ""
    for t in full:
        if t.get("start", 0.0) >= start - 0.05 and str(t.get("text", "")).strip():
            card = str(t["text"]).strip()
            break
    card = card or release.hook_title(hook)
    if card:
        events.append(
            f"Dialogue: 0,0.00,{HOOK_CARD_SECONDS:.2f},HookCard,,0,0,0,,"
            f"{{\\fad({int(HOOK_CARD_FADE*1000)},{int(HOOK_CARD_FADE*1000)})}}"
            f"{_escape(card)}")

    # No overlay text at all. K (2026-11-04): the drifting lyric sweep did not
    # match the sung line, so every song looked like it was lying to the viewer,
    # and the channel is now "just songs" — album art and audio. The song title
    # still appears on the cover art itself, which is normal for a release.
    for item in (full if captions else []):
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

    # The follow ask, as a short end card. It is the only on-screen ask on the
    # channel and it is placed at the end, where it cannot cost the first-two-
    # seconds decision that decides whether the clip is watched at all. Held for
    # FOLLOW_CARD_SECONDS and no longer: the 2026-11-09 panel warned that a
    # persistent banner clutters the song and can pull retention down, and
    # retention is what buys reach.
    hold = min(FOLLOW_CARD_SECONDS, max(0.0, length - FOLLOW_CARD_LEAD))
    if length >= FOLLOW_MIN_CLIP and hold >= 0.5:
        start_at = max(0.0, length - FOLLOW_CARD_LEAD - hold)
        events.append(
            f"Dialogue: 0,{_ts(start_at)},{_ts(start_at + hold)},Follow,,0,0,0,,"
            f"{{\\fad(200,300)}}{_escape(release.FOLLOW_ASK)}")
        # The reason to return, under the ask. Both advisors put this first, and
        # the two lines share one card so the prompt is not just a bare command.
        events.append(
            f"Dialogue: 0,{_ts(start_at)},{_ts(start_at + hold)},FollowSub,,0,0,0,,"
            f"{{\\fad(200,300)}}{_escape(release.FOLLOW_PROMISE)}")
    return head + "\n".join(events) + "\n"


def _ass_escape(p: Path) -> str:
    return str(p).replace("\\", "\\\\").replace(":", "\\:")


def render(slug: str, *, mix: str = "song", out_dir: Path | None = None,
           all_hooks: bool = False, captions: bool = False) -> list[Path]:
    """Render one Short per chorus. Returns the files written.

    `all_hooks=True` writes every chorus as its own Short (hook-1, hook-2, ...).
    The default writes just the first, so a caller that wants one file per song
    still gets exactly that.

    `captions=False` (default) draws no lyric sweep; the estimated timing drifts
    off the sung line and K ordered it dropped (2026-11-03).
    """
    audio = ROOT / "library" / "songs" / f"{mix}-{slug}.mp3"
    cover = ROOT / "library" / "covers" / f"cover-{slug}.jpg"
    for p in (audio, cover):
        if not p.exists():
            raise FileNotFoundError(f"missing {p}; run flow_song.py first")

    # A bed is an instrumental, not a sung song. A Short cut from it would play
    # music with no vocal while the caption promises a song — the bed-shipped-as-
    # a-song bug K caught (2026-11-07). Refuse it for every mix, before rendering.
    try:
        import provenance
    except ImportError:  # a missing module must not block an unrelated render
        provenance = None
    if provenance is not None and provenance.is_bed(
            ROOT / "library" / "songs" / f"song-{slug}.mp3"):
        raise RuntimeError(f"{slug} is an offline bed, not a sung song")

    # A karaoke clip must be refused outright when the words cannot be trusted to
    # match the song (K, 2026-11-07). The lyric-card path makes this a hard gate,
    # not a note: better to ship no karaoke clip than a mismatched one.
    if mix == "karaoke":
        ok, why = karaoke_ok(slug)
        if not ok:
            raise RuntimeError(f"karaoke refused — {why}")

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
    def chain(ass: Path, clip_seconds: float) -> str:
        # The cover is square, so a hard centre crop to 9:16 would slice its title
        # text off the sides and drop the captions on top of it. Instead: a
        # blurred, dimmed copy fills the frame, the whole cover sits in the upper
        # half, and a scrim below it gives the captions a clean band. The whole
        # composite zooms slowly so the frame is not dead.
        cw = int(W * 0.86)
        cy = int(H * 0.055)
        scrim = int(H * 0.52)
        # Zoom off the output frame counter `on`, NOT `zoom+rate`: with `d=1`
        # zoompan treats every input frame as its own still and resets the
        # `zoom` accumulator each frame, so `zoom+0.0005` never accumulated and
        # the "slow zoom" was in fact a dead frame (measured 0.005 mean abs
        # frame diff vs 5.25 for the `on` ramp). Sized so the ramp spans the clip.
        span = max(1.0, clip_seconds * FPS)
        rate = (ZOOM_MAX - 1.0) / span
        return (
            f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
            f"gblur=sigma=32,eq=brightness=-0.06:saturation=1.05[bg];"
            f"[0:v]scale={cw}:-1[fg];"
            f"[bg][fg]overlay=(W-w)/2:{cy}[base];"
            f"[base]drawbox=x=0:y={scrim}:w={W}:h={H - scrim}:"
            f"color=black@0.38:t=fill[scrimd];"
            f"[scrimd]zoompan=z='min(1+{rate:.8f}*on,{ZOOM_MAX})':d=1:"
            f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS}[zp];"
            f"[zp]{ass_filter(ass)}[v]"
        )

    written: list[Path] = []
    for i, (start, length) in enumerate(windows, 1):
        suffix = f"-h{i}" if multi else ""
        ass_path = work / f"short-{mix}{suffix}.ass"
        ass_path.write_text(build_ass(slug, lines, meta, start, length, duration,
                                      captions=captions, hook=i),
                            encoding="utf-8")
        out = out_dir / f"short-{mix}{suffix}-{slug}.mp4"
        args = ["-loop", "1", "-i", str(cover),
                "-ss", f"{start:.3f}", "-i", str(audio),
                "-filter_complex", chain(ass_path, length),
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
    ap.add_argument("--captions", action="store_true",
                    help="burn the estimated lyric sweep (retired: it drifts)")
    ap.add_argument("--skip-existing", action="store_true",
                    help="do not re-render a Short that is already on disk")
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
            # A bed on disk is not a song; skip it rather than turn a healthy
            # batch red. `render()` still refuses one when called directly.
            try:
                import provenance
                if provenance.is_bed(ROOT / "library" / "songs" / f"song-{slug}.mp3"):
                    print(f"{slug}: skip (offline bed, not a sung song)")
                    continue
            except ImportError:
                pass
            # A karaoke mix whose words cannot be trusted is refused by render(),
            # so a `--mix karaoke` batch skips those songs instead of shipping a
            # mismatched clip (K, 2026-11-07).
            if args.skip_existing:
                outs_dir = ROOT / "library" / "shorts"
                already = sorted(outs_dir.glob(f"short-{args.mix}*-{slug}.mp4"))
                if already:
                    print(f"{slug}: skip (exists)")
                    continue
            outs = render(slug, mix=args.mix, all_hooks=args.hooks,
                          captions=args.captions)
            for out in outs:
                print(f"{slug}: {out.relative_to(ROOT)} ({_duration(out):.1f}s)")
        except Exception as exc:
            print(f"{slug}: FAILED {exc}", file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
