#!/usr/bin/env python3
"""The "live concert" identity for the Facebook + TikTok surfaces.

K (2026-11-09): "ทำเพลงที่ใช้เสียงร้องแบบแสดงสดคอนเสิร์ตหน่อยสิ เห็นคลิปใช้เทคนิค
นี้คนดูเป็นล้านเลย" — make songs that sound like a live concert performance; the
clips that use this reach millions.

What the technique actually is, and what free tooling can honestly reach:

  * the *source* is a real sung vocal — we already have 27 of them, rendered by
    Flow Music (the only free path to a listenable vocal; the Piper lane is
    retired). Nothing here synthesises a voice, so the honest core of the format
    is real singing.
  * the *concert* is post-processing: the studio master is pushed through a hall
    (a long reverb tail), an arena PA (compression + a low-mid lift), an audience
    (applause that swells at the top and the end, and a crowd bed that swells
    under the chorus) and a room tone. All of it is built from ffmpeg's own
    sources — pink/brown noise for the hall impulse response, the crowd and the
    room — so nothing is downloaded, nothing is paid for, and no login is needed.

The AI disclosure still holds: the voice and the crowd are synthetic, so
`AI_NOTE` rides on every clip and every caption. The format is "จำลองบรรยากาศ
คอนเสิร์ต" — simulate the concert, not claim a real show.

The mix is a single ffmpeg pass; `mix_filter()` returns the graph as a string so
a test can pin the shape without encoding anything. Every constant a listener
would hear is named here.

    python3 scripts/concert.py --plan             # what it would build
    python3 scripts/concert.py --plan 01-khon-di-thi-chak-pai
    python3 scripts/concert.py 01-khon-di-thi-chak-pai --out /tmp/live.wav
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import surreal  # noqa: E402  the shared guardrails + handles
from make_song import _apply_loudnorm, _measure_loudnorm  # noqa: E402  the loudness contract

SONGS = ROOT / "library" / "songs"
OUT_DIR = ROOT / "library" / "concert"

SR = 44100
# 9:16, and short: a live take is a hook, not a full set.
CLIP_SECONDS = 38.0

# ── the identity ──────────────────────────────────────────────────────────────
# One recognisable rule, same as the exhibit lane: every clip is one song
# "played live". Thai, and the burned label is emoji-free (the bundled Noto Sans
# Thai has no emoji glyph, so an emoji would draw as tofu).
NAME = "AERIS LIVE"
PROJECT = "คอนเสิร์ตจำลอง"
SHOW_LINE = "บรรยากาศคอนเสิร์ต ฟังให้เหมือนยืนอยู่หน้าเวที"
# The recurring ask, in the same shape as the exhibit ritual.
SHOW_ASK = "อยากให้เพลงไหนออกคอนเสิร์ตต่อ? คอมเมนต์มาเลย"
# The AI disclosure is shared with the exhibit lane so it never drifts.
AI_NOTE = surreal.AI_NOTE
HANDLES = surreal.HANDLES

# ── the mix recipe ────────────────────────────────────────────────────────────
# Every number a listener hears, named. The hall is the format: without a long
# tail the vocal sits in a studio, not a venue.
HALL_IR_SECONDS = 3.0        # length of the synthesised impulse response
HALL_LOWPASS = 7000          # the hall absorbs the top end
HALL_HIGHPASS = 180          # ...and muddies the very bottom
HALL_WET = 0.85              # reverb return under the dry vocal
HALL_IRGAIN = 0.5

PA_LOWMID_HZ = 250           # a small lift so the PA reads "big", not "laptop"
PA_LOWMID_GAIN = 2.0
PA_THRESHOLD = 0.06          # gentle glue compression, a live desk
PA_RATIO = 4.0
PA_ATTACK = 6
PA_RELEASE = 160

CROWD_LEVEL = 1.0            # applause return
CROWD_BED = 0.22             # the low crowd under the whole take
ROOM_LEVEL = 0.18            # room tone, so silence is never digital-dead
INTRO_APPLAUSE = 4.5         # seconds of applause before the song
OUTRO_APPLAUSE = 4.5         # ...and after the last note

LIMIT = 0.95                 # the brickwall that keeps the sum from clipping


def mix_filter(seconds: float) -> str:
    """The single-pass ffmpeg graph that turns a song into a live take.

    Input 0 is the song (already seeked). The hall impulse, the crowd and the
    room are `anoisesrc`/lavfi sources created inside the graph, so the pass
    needs no external asset and no download. The crowd swells in for the intro,
    drops to a bed, then swells again for the outro (`between()` on `t`).
    """
    end = max(0.0, seconds - 1.0)
    crowd_env = (f"0.95*between(t,0,{INTRO_APPLAUSE})"
                 f"+{CROWD_BED}"
                 f"+0.75*between(t,{max(0.0, seconds - OUTRO_APPLAUSE)},{seconds})")
    return (
        # the hall impulse: decaying pink noise
        f"anoisesrc=d={HALL_IR_SECONDS}:c=pink:a=0.6:r={SR},"
        f"highpass=f={HALL_HIGHPASS},lowpass=f={HALL_LOWPASS},"
        f"afade=t=out:st=0:d={HALL_IR_SECONDS}:curve=exp,volume=0.9[ir];"
        # the audience: band-limited noise, combed by a chorus so many hands read
        f"anoisesrc=d={seconds}:c=pink:a=0.7:r={SR},"
        f"highpass=f=900,lowpass=f=6000,"
        f"acompressor=threshold=0.03:ratio=6:attack=1:release=50,"
        f"chorus=0.6:0.9:50|60:0.4|0.32:0.25|0.4:2|1.3,"
        f"volume='{crowd_env}':eval=frame,"
        f"afade=t=out:st={end}:d=1[crowd];"
        # the room tone: a low brown-noise floor
        f"anoisesrc=d={seconds}:c=brown:a=0.5:r={SR},"
        f"lowpass=f=800,volume={ROOM_LEVEL}[room];"
        # the performance through the PA
        f"[0:a]highpass=f=70,"
        f"equalizer=f={PA_LOWMID_HZ}:t=q:w=1:g={PA_LOWMID_GAIN},"
        f"acompressor=threshold={PA_THRESHOLD}:ratio={PA_RATIO}:"
        f"attack={PA_ATTACK}:release={PA_RELEASE}[perf];"
        f"[perf]asplit=2[pdry][pwet];"
        # the hall: the wet path convolved with the impulse
        f"[pwet][ir]afir=dry=1:wet=3:irgain={HALL_IRGAIN}[reverb];"
        f"[pdry][reverb]amix=inputs=2:weights=1 {HALL_WET}:normalize=0[hall];"
        f"[hall][room]amix=inputs=2:weights=1 {ROOM_LEVEL}:normalize=0[withroom];"
        f"[withroom][crowd]amix=inputs=2:weights=1 {CROWD_LEVEL}:normalize=0[full];"
        f"[full]alimiter=limit={LIMIT}[out]"
    )


def all_slugs() -> list[str]:
    return sorted(p.stem[len("song-"):] for p in SONGS.glob("song-*.mp3"))


def plan(slug: str, *, seconds: float = CLIP_SECONDS) -> dict:
    """Everything the mix needs, with nothing executed or downloaded."""
    return {
        "slug": slug,
        "seconds": seconds,
        "song": SONGS / f"song-{slug}.mp3",
        "out": OUT_DIR / f"concert-{slug}.wav",
        "filter": mix_filter(seconds),
    }


def render(slug: str, dest: Path, *, start: float = 0.0,
           seconds: float = CLIP_SECONDS) -> Path:
    """Mix the song's `[start, start+seconds)` window into a live take.

    The mix goes to a raw wav, then the shared two-pass loudnorm masters it to
    `TARGET_LUFS`, so a live take sits at the same level as the studio songs it
    came from. The crowd and the hall add energy the studio master did not have,
    so mastering after the mix is what keeps the level right.
    """
    p = plan(slug, seconds=seconds)
    if not p["song"].exists():
        raise FileNotFoundError(f"missing {p['song']}; pull media first")
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    raw = dest.with_name(dest.stem + "-raw.wav")
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-ss", f"{start:.3f}", "-i", str(p["song"]),
         "-filter_complex", p["filter"],
         "-map", "[out]", "-t", f"{seconds:.3f}",
         "-ar", str(SR), "-ac", "2", "-c:a", "pcm_s16le", str(raw)],
        check=True)
    measured = _measure_loudnorm(raw)
    _apply_loudnorm(raw, dest, measured)
    raw.unlink(missing_ok=True)
    return dest


def caption(slug: str, platform: str, song_title: str = "") -> str:
    """The live-show caption. Thai, disclosed, rule-safe, per-surface.

    Same project on both surfaces, one line different (the cross-promo), so the
    two feeds read as one identity and not two duplicates.
    """
    song = f"🎵 {song_title}" if song_title else ""
    if platform == "facebook":
        tail = (f"🎬 ดูคลิปอื่นที่ YouTube {HANDLES['youtube']} · "
                f"TikTok {HANDLES['tiktok']}")
    else:
        tail = (f"🎬 ดูเต็ม ๆ ที่ YouTube {HANDLES['youtube']} · "
                f"เพจ FB {HANDLES['facebook']}")
    lines = [f"🎤 {SHOW_LINE}"]
    if song:
        lines.append(song)
    lines += [f"🏟️ {PROJECT} — เสียงฮอลล์ เสียงเชียร์ เสียงวง",
              f"💬 {SHOW_ASK}", f"⚠️ {AI_NOTE}", tail,
              "#คอนเสิร์ตจำลอง #เพลงไทย #AERISMusic"]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--plan", action="store_true", help="show the mix, render nothing")
    ap.add_argument("--out", default="", help="output wav for a single render")
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--seconds", type=float, default=CLIP_SECONDS)
    args = ap.parse_args()

    slugs = [args.slug] if args.slug else all_slugs()
    if args.plan:
        for slug in slugs:
            p = plan(slug, seconds=args.seconds)
            print(f"{slug:34} {p['out'].name}  {p['seconds']:.0f}s")
        return 0
    if not args.slug:
        ap.error("give a slug to render, or --plan")
    dest = Path(args.out) if args.out else plan(args.slug)["out"]
    out = render(args.slug, dest, start=args.start, seconds=args.seconds)
    print(f"{out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
