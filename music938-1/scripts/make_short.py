#!/usr/bin/env python3
"""Render a vertical Short (1080x1920, <=60s) from a Flow Music song.

Why this exists. The channel's own numbers say it plainly: of 449 lifetime views
on เพลงส้นทีนไรเนี่ย, 382 came from Shorts and about 33 from long-form. A channel with
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
    _words, ass_filter, estimate, load_lyrics, load_timing, load_timing_blocks,
)
import release  # noqa: E402  the hook titles live with the rest of the copy

W, H = 1080, 1920
FPS = 30
MAX_SECONDS = 58.0        # under the 60s Shorts ceiling, with margin
HOOK_PAD = 0.6            # a beat of lead-in so the hook does not start on frame 0
ZOOM_MIN = 1.10           # zoom at frame 0; headroom for the pan without edges
ZOOM_MAX = 1.26           # the cover zoom ramp: ZOOM_MIN -> ZOOM_MAX across the clip

# Full-bleed vertical art. A landscape cover on a 9:16 frame can only be shown
# as a letterboxed strip over blurred bars, which measured 29% of the frame for
# art and 56% for a black caption band — Gemini scored that 4/10 and named both
# faults ("blurred top/bottom bars", "the same image repeated"). A 9:16 still
# generated for the song fills the frame instead, and several of them cut
# together give the clip something new to look at past the first few seconds.
VERT = ROOT / "library" / "vertical"
XFADE = 0.5               # crossfade between art stills; short, so cuts land hard
VERT_PAN = 30             # px of drift per still, so a held shot is not dead
GRAIN = 9                 # film grain, for the raw garage-punk texture
FLASH = 0.16              # a 2-frame brightness punch on each cut

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
    """One window per chorus, de-duplicated if two land on the same spot.

    When the clip carries real markers, a window starts exactly at a sung chorus
    (`marker_blocks`), so the Short opens on the hook instead of near it. Without
    markers it falls back to the share-of-lines estimate.
    """
    real = [b for b in load_timing_blocks(slug) if b["section"] == "chorus"
            and b["lines"]]
    if real:
        out: list[tuple[float, float]] = []
        for b in real:
            start = max(0.0, b["start"] - HOOK_PAD)
            length = min(MAX_SECONDS, duration - start)
            if length < 12:
                continue
            if all(abs(start - o[0]) > 5.0 for o in out):
                out.append((start, length))
        if out:
            return out

    out = []
    for sf, lf in chorus_spans(slug):
        w = _window(duration, sf, lf)
        if all(abs(w[0] - o[0]) > 5.0 for o in out):
            out.append(w)
    return out or [_window(duration, 0.35, 0.3)]


def _pick_window(slug: str, duration: float) -> tuple[float, float]:
    return _pick_windows(slug, duration)[0]


def _window_lyrics(slug: str, start: float, length: float,
                   timed: list[dict]) -> list[tuple[str, float, float]]:
    """The lyric lines inside this window, each with its span in clip time.

    Returns `(text, start_in_clip, end_in_clip)`. The spans come from the same
    estimate the timing fallback uses, so the card changes when the sung line
    would change rather than on a made-up cadence. Chunking the window into
    equal holds instead left the last 21.8 s of a 58 s clip with no text at all,
    which a review caught ("มีซับเฉพาะบางช่วง ... 36.5s, 43.5s, 50.5s ไม่มี
    ข้อความ") and measured against the ASS as a real gap.
    """
    out: list[tuple[str, float, float]] = []
    for t in timed:
        text = str(t.get("text", "")).strip()
        if len(text) < 2 or t["end"] <= start or t["start"] >= start + length:
            continue
        s = max(t["start"], start) - start
        e = min(t["end"], start + length) - start
        out.append((text, max(0.0, s), e))
    return out[:12]


def build_ass(slug: str, lines: list[str], meta: dict, start: float,
              length: float, duration: float, captions: bool = False,
              hook: int = 1, timed: list[dict] | None = None) -> str:
    """Vertical overlay: the title card and a watermark, and optionally the
    per-line lyric sweep.

    `timed` is the real per-line timing from the clip's markers; when it is
    present the sweep is note-accurate and `captions` should be on. When it is
    absent the only timing available is `estimate`, which guesses from the song
    length and drifts off the sung line — that is what K rejected (2026-11-03),
    so without real markers the default stays captions-off.
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
Style: Lyric,{FONT},54,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H90000000,1,0,0,0,100,100,0.6,0,1,5,3,2,90,90,330,1
Style: Brand,{FONT},40,&H00DDFFFF,&H00DDFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,4,2,7,44,44,40,1
Style: Title,{FONT},64,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,1,0,1,5,2,7,44,44,34,1
Style: Follow,{FONT},72,&H0020E0FF,&H0020E0FF,{OUTLINE},&H00000000,1,0,0,0,100,100,0.5,0,1,8,4,2,60,60,260,1
Style: FollowSub,{FONT},54,&H00E8E8E8,&H00E8E8E8,{OUTLINE},&H00000000,0,0,0,0,100,100,0.5,0,1,6,3,2,60,60,190,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    # Timing is real (markers) when the clip carries them, else estimated over
    # the whole song and shifted into the window.
    full = timed if timed else estimate(lines, duration)
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

    # Real markers make the sweep honest, so it is drawn whenever they exist;
    # the estimated sweep stays off unless asked for (K, 2026-11-04: a sweep that
    # does not match the sung line makes the song look like it is lying).
    for item in (full if (captions or timed) else []):
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

    # Without real timing the clip showed *no lyric at all* for its whole run —
    # just the title card and the follow ask. Gemini scored that 6/10 and its
    # first criterion is "มีเนื้อเพลง/ซับไตเติลบนจอ". A drifting karaoke sweep
    # stays off (it drifts off the sung line, K 2026-11-03), but the words can
    # still be on screen as a still card: the chorus this window was cut from,
    # held in readable chunks that change every few seconds. No word claims to
    # land on a beat it was not measured against, so it does not lie.
    if not timed and not captions:
        chorus = _window_lyrics(slug, start, length, full)
        if chorus:
            for line, t0, t1 in chorus:
                t1 = min(t1, length - FOLLOW_CARD_LEAD)
                if t1 - t0 < 0.8:
                    continue
                events.append(f"Dialogue: 0,{_ts(t0)},{_ts(t1)},Lyric,,0,0,0,,"
                              f"{{\\fad(220,220)}}{_escape(line)}")

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


def vertical_art(slug: str, count: int = 12) -> list[Path]:
    """The song's 9:16 stills, generating any that are missing. Cached on disk.

    Free and key-less: the same pollinations backend the covers use, asked for a
    portrait frame and a per-still scene so the clip is not one image held for a
    minute. A failure here is not fatal — the caller falls back to the letterbox
    chain — but it is the difference between a 4/10 clip and a passing one.

    Six stills over a 58s clip is a cut every ~10s. Three was too few: Gemini
    rejected that render as "ภาพนิ่ง/ค้างนานเกินไป" and named the three shots it
    could see sitting still. A Short has to change what is on screen faster than
    a viewer's patience.
    """
    sys.path.insert(0, str(ROOT / "scripts"))
    import ai_covers  # noqa: PLC0415  heavy import, only needed on a render

    meta = ai_covers._meta(slug)
    mood = meta["mood"]
    genre = (meta.get("genre") or "").lower()
    # The pictures must match the song, not one house style. A calm lofi track
    # scored badly against punk imagery and a punk prompt drew "too soft" the
    # other way round, so the scene set is chosen by mood. Within a set every
    # scene is a different subject: a re-used subject reads as a loop even when
    # it is re-cropped, which is what three reviews in a row flagged.
    calm = [
        "a lone silhouette walking a rain-slick street at night, soft neon "
        "reflections, gentle bokeh",
        "rain running down a lit window at night, warm city lights blurred "
        "beyond",
        "a quiet room at 3am, a single lamp, dust drifting in the warm glow",
        "a city rooftop at blue hour, glowing windows, a small still figure",
        "light breaking through clouds over a calm dark skyline",
        "a nearly empty late-night train carriage, one passenger by the window",
        "a desk with a cooling cup of tea and a notebook, dim warm lamplight",
        "a quiet street corner under a soft streetlamp, wet pavement reflections",
        "a window seat looking out at falling rain, curtain half drawn",
        "a small figure standing at the end of a long pier at dawn, soft mist",
        "a stairwell lit by one warm bulb, long soft shadows",
        "a hand resting on a windowsill, city lights soft in the background",
    ]
    grit = [
        "a smashed electric guitar leaning against a wet brick wall, harsh "
        "flash, high contrast, gritty film grain",
        "a rain-soaked alley lit by one bare bulb, graffiti on concrete, deep "
        "shadows, raw documentary flash photography",
        "a singer screaming into a microphone in a dark small club, sweat and "
        "stage light, motion blur, gritty concert photo",
        "a drum kit in a squatted room, dust in a hard shaft of light, peeling "
        "paint, raw high-contrast photograph",
        "a crowd of raised fists silhouetted against harsh stage strobes, "
        "grainy, high contrast",
        "a cracked mirror reflecting a harsh flash, torn posters behind, "
        "gritty texture",
        "a night street corner under a broken flickering sign, wet asphalt, "
        "raw high-contrast photograph, heavy grain",
        "a fist gripping a microphone cable, hard side light, deep shadow, "
        "gritty close-up",
        "a dark stage from behind the amps, cables on a dirty floor, one "
        "harsh spotlight, raw photograph",
        "a torn gig poster on a wet wall, harsh flash, high contrast, grain",
        "a lone figure walking into heavy rain under a streetlamp, harsh "
        "contrast, gritty, raw photograph",
        "a wall of stacked amps in a dark room, one harsh light, heavy shadow",
    ]
    soft = mood in ("calm", "chill", "sad", "dreamy", "ambient", "romantic")
    scenes = calm if soft else grit
    VERT.mkdir(parents=True, exist_ok=True)
    out: list[Path] = []
    for i in range(count):
        p = VERT / f"vert-{slug}-{i}.jpg"
        if not p.exists():
            prompt = (f"vertical portrait cinematic artwork for a Thai "
                      f"{meta['genre'] or 'rock'} song, mood {mood}. "
                      f"Scene: {scenes[i % len(scenes)]}. No text, no letters, "
                      f"no watermark. Cinematic lighting, strong composition, "
                      f"rich detail.")
            try:
                p.write_bytes(ai_covers._fetch_pollinations(prompt, 48 + i * 7))
            except Exception as exc:  # rate limit or offline: fall back, never fail
                print(f"  vertical art {i} unavailable ({exc})", file=sys.stderr)
                break
        out.append(p)
    return out


def _scrim_png() -> Path:
    """A cached vertical gradient, transparent at the top, dark at the bottom.

    A `drawbox` scrim has a hard top edge, and Gemini read that edge as a render
    bug: "เส้นรอยต่อ/แถบสีแนวนอนครึ่งจอ ... คล้ายรอยต่อเลเยอร์". A gradient has no
    edge to see, and it still gives white Thai text its contrast at the foot.
    """
    p = VERT / "_scrim.png"
    if p.exists():
        return p
    from PIL import Image  # noqa: PLC0415

    h = 480
    img = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / (h - 1)
        img.putpixel((0, y), (0, 0, 0, int(round(165 * (t ** 1.6)))))
    VERT.mkdir(parents=True, exist_ok=True)
    img.save(p)
    return p


def _shots(arts: list[Path], hook: int) -> list[tuple[Path, float, float, int, str]]:
    """The shot list: one still per cut, never the same picture twice.

    Gemini rejected two earlier cuts of this clip for repetition, naming the
    timestamps that reused an earlier frame ("เฟรมที่ 1.5s, 8.5s, 15.5s ...
    ถูกนำมาใช้ซ้ำเกือบเหมือนเดิมเป๊ะในครึ่งหลัง"). Re-cropping the same still is
    still the same picture, so the fix is more pictures, not a cleverer crop:
    one shot per still, and the caller generates enough of them.
    """
    shots: list[tuple[Path, float, float, int, str]] = []
    anchors = ("center", "left", "right", "top", "bottom")
    for i, a in enumerate(arts):
        z0, z1 = (1.04, 1.20) if i % 2 == 0 else (1.18, 1.34)
        shots.append((a, z0, z1, 1 if (hook + i) % 2 else -1,
                      anchors[(i + hook) % len(anchors)]))
    return shots


def _fullbleed_chain(shots: list[tuple[Path, float, float, int, str]],
                     clip_seconds: float, ass: Path) -> str:
    """Full-frame chain: the shots fill 9:16, crossfading, each drifting.

    No blurred bars and no letterbox — that treatment is what Gemini scored 4/10
    ("blurred top/bottom bars", "the same image repeated the whole clip").
    """
    n = len(shots)
    each = clip_seconds / n + (XFADE * (n - 1) / n)
    span = max(1.0, each * FPS)
    # The pan origin per anchor. `zoompan` positions the visible window with
    # x/y, so a re-crop of the same still from another corner is a different
    # composition — which is the point: a repeat must not read as a loop.
    anchor_xy = {
        "center": ("iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)"),
        "left": ("0", "ih/2-(ih/zoom/2)"),
        "right": ("iw-iw/zoom", "ih/2-(ih/zoom/2)"),
        "top": ("iw/2-(iw/zoom/2)", "0"),
        "bottom": ("iw/2-(iw/zoom/2)", "ih-ih/zoom"),
    }
    parts: list[str] = []
    for i, (_path, z0, z1, pan, anchor) in enumerate(shots):
        rate = (z1 - z0) / span
        bx, by = anchor_xy[anchor]
        parts.append(
            f"[{i}:v]scale={W}:{H}:force_original_aspect_ratio=increase,"
            f"crop={W}:{H},setsar=1,"
            f"eq=contrast=1.06:brightness=0.02,"
            f"zoompan=z='min({z0}+{rate:.8f}*on,{z1})':d=1:"
            f"x='{bx}+{VERT_PAN*pan}*(on/{span:.0f}-0.5)':"
            f"y='{by}':s={W}x{H}:fps={FPS}[s{i}]")
    prev = "s0"
    for i in range(1, n):
        offset = (each - XFADE) * i
        label = f"x{i}" if i < n - 1 else "art"
        parts.append(f"[{prev}][s{i}]xfade=transition=fade:duration={XFADE}:"
                     f"offset={offset:.3f}[{label}]")
        prev = label
    if n == 1:
        parts.append("[s0]null[art]")
    parts.append(f"[{n}:v]scale={W}:{H},format=rgba[sc];"
                 f"[art][sc]overlay=0:0,"
                 f"noise=alls={GRAIN}:allf=t+u,vignette=PI/5[scrimd]")
    parts.append(f"[scrimd]{ass_filter(ass)}[v]")
    return ";".join(parts)


def _letterbox_chain(cover: Path, clip_seconds: float, ass: Path,
                     hook: int = 1) -> str:
    """The original blurred-bars treatment, kept as the fallback.

    It is used only when no 9:16 art could be generated, because it measures 29%
    art / 56% black band and fails the review gate.
    """
    cw = int(W * 0.94)
    cy = int(H * 0.05)
    scrim = int(H * 0.44)
    span = max(1.0, clip_seconds * FPS)
    rate = (ZOOM_MAX - ZOOM_MIN) / span
    d = 1 if hook % 2 else -1
    dx, dy = 26 * d, 14 * d
    return (
        f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        f"gblur=sigma=26,eq=brightness=-0.12:saturation=1.05[bg];"
        f"[0:v]scale={cw}:-1[fg];"
        f"[bg][fg]overlay=(W-w)/2:{cy}[base];"
        f"[base]drawbox=x=0:y={scrim}:w={W}:h={H - scrim}:"
        f"color=black@0.42:t=fill[scrimd];"
        f"[scrimd]zoompan=z='min({ZOOM_MIN}+{rate:.8f}*on,{ZOOM_MAX})':d=1:"
        f"x='iw/2-(iw/zoom/2)+{dx}*(on/{span:.0f}-0.5)':"
        f"y='ih/2-(ih/zoom/2)+{dy}*(on/{span:.0f}-0.5)':s={W}x{H}:fps={FPS}[zp];"
        f"[zp]{ass_filter(ass)}[v]"
    )


def render(slug: str, *, mix: str = "song", out_dir: Path | None = None,
           all_hooks: bool = False, captions: bool = False) -> list[Path]:
    """Render one Short per chorus. Returns the files written.

    `all_hooks=True` writes every chorus as its own Short (hook-1, hook-2, ...).
    The default writes just the first, so a caller that wants one file per song
    still gets exactly that.

    `captions=False` (default) draws no *estimated* lyric sweep; the estimate
    drifts off the sung line and K ordered it dropped (2026-11-03). When the clip
    carries real markers the sweep is note-accurate and is drawn regardless.
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
    timed = load_timing(slug)
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

    # The cover is landscape, so a hard centre crop to 9:16 slices the title off
    # the sides. Prefer generated 9:16 stills, which fill the frame; fall back to
    # the blurred-bars treatment only if none could be made. The ass filter is
    # per-hook, so the chain is assembled inside the loop.
    arts = vertical_art(slug)
    if arts:
        print(f"  art: {len(arts)} vertical still(s)", file=sys.stderr)

    written: list[Path] = []
    for i, (start, length) in enumerate(windows, 1):
        suffix = f"-h{i}" if multi else ""
        ass_path = work / f"short-{mix}{suffix}.ass"
        ass_path.write_text(build_ass(slug, lines, meta, start, length, duration,
                                      captions=captions, hook=i, timed=timed),
                            encoding="utf-8")
        out = out_dir / f"short-{mix}{suffix}-{slug}.mp4"
        if arts:
            shots = _shots(arts, i)
            scrim = _scrim_png()
            inputs = [x for s in shots for x in ("-loop", "1", "-i", str(s[0]))]
            inputs += ["-loop", "1", "-i", str(scrim)]
            graph = _fullbleed_chain(shots, length, ass_path)
            audio_idx = len(shots) + 1
        else:
            inputs = ["-loop", "1", "-i", str(cover)]
            graph = _letterbox_chain(cover, length, ass_path, i)
            audio_idx = 1
        args = [*inputs,
                "-ss", f"{start:.3f}", "-i", str(audio),
                "-filter_complex", graph
                + f";[{audio_idx}:a]loudnorm=I=-14:TP=-2.0:LRA=11,"
                  f"alimiter=limit=0.7:level=0[aout]",
                "-map", "[v]", "-map", "[aout]",
                "-t", f"{length:.3f}",
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
                "-pix_fmt", "yuv420p", "-r", str(FPS),
                "-c:a", "aac", "-ar", "48000", "-b:a", "192k", "-shortest",
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
    # The Short's own frame is dark by construction: a blurred, scrimmed copy of
    # the cover fills the frame, so the mean luma lands near 18 and the title
    # reads as "no title" on the thumbnail floor. A gamma lift plus a light
    # unsharp makes the caption legible without touching the clip itself.
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-ss", "1.5", "-i", str(short),
         "-frames:v", "1", "-vf", "eq=gamma=1.6,unsharp=5:5:0.8", str(dest)],
        check=True)
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
