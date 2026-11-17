#!/usr/bin/env python3
"""Render a Thai "เกร็ดความรู้รอบตัว" (everyday-science trivia) short, 1280x720.

This lane exists because K supplied a reference clip on 2026-11-17 and asked for
that quality first, then to make it the standard and upload it. The numbers below
are measured from that clip, not guessed; `SPEC` records each one and
`tests/run.py::test_trivia_reel` pins them so the standard cannot drift.

Measured spec of the reference (1280x720, 4.03 s):

  container   MP4, h264 High, yuv420p, 1280x720, 24 fps, ~2.3 Mbps
  audio       AAC-LC 48 kHz stereo, loudness -14.9 LUFS / -2.6 dBTP (EBU R128)
  background  real moving footage (drifting clouds): no cuts, no zoom
  text        white Thai, thin ~3 px dark outline, no shadow, left-anchored at
              10.5 % of the width, block centred at ~48 % of the height,
              font ~72 px at 720p (= 0.10 * height)

The three quality factors, in order of how much they matter:
  1. a real moving picture (free Commons footage, `footage_rail`) — a static
     still reads as a slideshow;
  2. loudness-normalised speech (raw edge-tts is ~6 dB quieter and inconsistent);
  3. clean, large, left-anchored text with a thin outline.

Everything is free (Rule #1): edge-tts voice, licence-checked Wikimedia Commons
footage (falling back to Wikimedia stills), ffmpeg render. No key, no login.

Script format (a plain .md, one card per block separated by blank lines):

    # TITLE: ทำไมท้องฟ้าถึงเป็นสีฟ้า
    # THEME: sky
    ทำไมท้องฟ้าถึงเป็นสีฟ้า?
    <blank line>
    เพราะแสงแดดนั้น...

    python3 ops/trivia_reel.py --script scripts_trivia/sky-blue.md --out /tmp/trivia
    python3 ops/trivia_reel.py --plan --script scripts_trivia/sky-blue.md
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thai_tts  # noqa: E402
import stills_rail as sr  # noqa: E402
import footage_rail as fr  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_DIR = os.path.join(ROOT, "music938-1", "fonts")
FONT_NAME = "Noto Sans Thai"

sys.path.insert(0, os.path.join(ROOT, "music938-1", "scripts"))
import branding  # noqa: E402

# --- The standard, measured from K's reference clip (2026-11-17). ------------
SPEC = {
    "width": 1280,
    "height": 720,
    "fps": 24,
    "card_font": 72,          # px at 720p; measured line height 73
    "card_outline": 3,        # thin dark outline, no shadow
    "margin_left": 134,       # 10.5 % of 1280, where the text block starts
    "margin_v": 0,            # block vertically centred (measured 48 %)
    "lufs": -15.0,            # integrated loudness target (reference -14.9)
    "true_peak": -2.5,        # dBTP (reference -2.6)
    "video_bitrate": "2300k",
    "audio_bitrate": "128k",
}
W, H, FPS = SPEC["width"], SPEC["height"], SPEC["fps"]

AI_NOTE = "เสียงและภาพสร้างด้วย AI"

# Footage/still query sets per theme (English; Commons returns 0 for Thai).
# Footage is tried first; the stills set is the fallback.
THEME_QUERIES = {
    "sky": ["clouds blue sky", "sky sun clouds", "clouds timelapse"],
    "water": ["ocean waves", "river water flowing", "water surface ripple"],
    "space": ["night sky stars", "moon", "galaxy"],
    "plants": ["green leaves wind", "sunflower field", "tree branches light"],
    "earth": ["mountain clouds", "volcano", "desert sand"],
    "body": ["human eye", "heart model", "skeleton"],
    "weather": ["lightning storm", "rain", "snow falling"],
    "light": ["prism light", "rainbow", "sunlight through trees"],
}
THEME_STILLS = {
    "sky": ["blue sky white clouds daylight", "sunlight rays through clouds"],
    "water": ["clear water surface ripple", "ocean waves blue"],
    "space": ["night sky stars milky way", "moon surface detail"],
    "plants": ["green leaf macro sunlight", "sunflower field bright"],
    "earth": ["mountain landscape clouds", "volcano crater smoke"],
    "body": ["human eye macro", "heart anatomy model"],
    "weather": ["lightning storm clouds", "rain on window"],
    "light": ["prism light spectrum", "rainbow refraction"],
}


def ffmpeg() -> str:
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def run(args, **kw):
    subprocess.run(args, check=True, **kw)


def read_script(path: str):
    """Returns (title, theme, [cards]). # TITLE: / # THEME: decide the rest."""
    raw = open(path, encoding="utf-8").read()
    title, theme = None, None
    for line in raw.splitlines():
        s = line.strip()
        if s.upper().startswith("# TITLE:"):
            title = s.split(":", 1)[1].strip()
        elif s.upper().startswith("# THEME:"):
            theme = s.split(":", 1)[1].strip()
    body = [l for l in raw.splitlines() if not l.strip().startswith("#")]
    cards = [re.sub(r"\s+", " ", p).strip()
             for p in re.split(r"\n\s*\n", "\n".join(body)) if p.strip()]
    if not cards:
        raise SystemExit(f"no cards in {path}")
    return title or os.path.basename(path), theme or "sky", cards


def narrate(cards: list[str], work: str, log=print):
    """One clip per card so each caption knows its own length (AUDIO FIRST)."""
    os.makedirs(work, exist_ok=True)
    voice = thai_tts.VOICE_MALE
    segs = []
    for i, p in enumerate(cards):
        out = os.path.join(work, f"n{i:02d}.mp3")
        if os.path.exists(out) and os.path.getsize(out) > 1000:
            secs = thai_tts.audio_seconds(out)
        else:
            _, secs = thai_tts.synth(p, out, voice=voice)
        segs.append({"path": out, "secs": secs, "text": p})
        log(f"  [tts] {i+1}/{len(cards)}  {secs:5.1f}s  {p[:34]}...")
    return segs


def concat_audio(segs, work, gap=0.4):
    """Join narration clips, loudness-normalised, return (file, total, marks)."""
    ff = ffmpeg()
    silence = os.path.join(work, "gap.mp3")
    if not os.path.exists(silence):
        run([ff, "-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi",
             "-i", "anullsrc=r=48000:cl=stereo", "-t", f"{gap}", silence])
    lst = os.path.join(work, "narr.txt")
    with open(lst, "w", encoding="utf-8") as fh:
        for s in segs:
            fh.write(f"file '{os.path.abspath(s['path'])}'\n")
            fh.write(f"file '{os.path.abspath(silence)}'\n")
    raw = os.path.join(work, "narr_raw.m4a")
    run([ff, "-y", "-hide_banner", "-loglevel", "error", "-f", "concat",
         "-safe", "0", "-i", lst, "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
         "-ac", "2", raw])
    total = thai_tts.audio_seconds(raw)
    t, marks = 0.0, []
    for s in segs:
        marks.append((t, t + s["secs"], s["text"]))
        t += s["secs"] + gap
    return raw, total, marks


def _usable(path: str, min_secs: float):
    """(ok, reason) for a candidate source clip.

    Two ways a source ruins the no-cut floor: a cut inside it (a montage or a
    jump-cutting timelapse), or being shorter than the segment it fills, because
    `build_video` loops a short source with `-stream_loop -1` and the loop seam
    is a hard cut. Verified 2026-11-17: three of five `plants` clips had an
    internal cut (max 62-123) and a 5.3 s clip looped into an 8.9 s segment;
    both made the finished clip fail and get deleted.
    """
    import clip_standard as cs
    try:
        info = cs.probe(path)
    except Exception:
        return False, "unreadable"
    if info["seconds"] < min_secs:
        return False, f"too short ({info['seconds']:.1f}s < {min_secs:.1f}s)"
    peak = cs.motion(path)[2]
    # A montage's internal cut is a step in the *source*, which no crossfade can
    # soften; it must screen out well under the 20 floor, not 2 units under it.
    if peak > 14.0:
        return False, f"internal cut (max {peak})"
    return True, ""


def fetch_footage(theme: str, out_dir: str, want: int, min_secs: float, log=print):
    """Free Commons footage for the theme; returns (paths, items).

    `items` carries the licence/credit for each clip so the description can
    attribute it — a CC BY / BY-SA clip requires that, and a music channel must
    not ship one without it. Each candidate must be smooth and long enough for
    its segment (`_usable`), so the assembled clip can hold the no-cut floor; a
    wide candidate pool is pulled so enough usable clips survive screening.
    """
    os.makedirs(out_dir, exist_ok=True)
    cmap_path = os.path.join(out_dir, "_credits.json")
    cmap = {}
    try:
        cmap = json.load(open(cmap_path, encoding="utf-8"))
    except (OSError, ValueError):
        cmap = {}
    have = sorted(glob.glob(os.path.join(out_dir, "c*.webm")) +
                  glob.glob(os.path.join(out_dir, "c*.mp4")))
    if len(have) >= want:
        keep = [h for h in have if _usable(h, min_secs)[0]]
        if len(keep) >= want:
            return keep[:want], [cmap.get(os.path.basename(h), {}) for h in keep[:want]]
    items, seen = [], set()
    for q in THEME_QUERIES.get(theme, THEME_QUERIES["sky"]):
        for it in fr.search_video(q, limit=8):
            key = it.get("url") or it.get("title")
            if key and key not in seen:
                seen.add(key)
                items.append(it)
    got, used = [], []
    for it in items:
        if len(got) >= want:
            break
        name = f"c{len(got):02d}" + (os.path.splitext(it["url"])[1] or ".webm")
        p = fr.download(it, out_dir, name=name)
        if not p:
            continue
        ok, why = _usable(str(p), min_secs)
        if not ok:
            log(f"  [footage] skip {os.path.basename(str(p))}: {why}")
            os.remove(str(p))
            continue
        got.append(str(p))
        used.append(it)
        cmap[os.path.basename(str(p))] = {
            "title": it.get("title", ""), "licence": it.get("licence", ""),
            "source": it.get("source", ""), "origin": it.get("origin", "")}
    if got:
        log(f"  [footage] {len(got)} clips, theme {theme}")
    try:
        json.dump(cmap, open(cmap_path, "w", encoding="utf-8"), ensure_ascii=False)
    except OSError:
        pass
    return got, used


def fetch_stills(theme: str, out_dir: str, want: int, log=print):
    os.makedirs(out_dir, exist_ok=True)
    have = sorted(glob.glob(os.path.join(out_dir, "s*.jpg")))
    if len(have) >= want:
        return have[:want]
    items = []
    for q in THEME_STILLS.get(theme, THEME_STILLS["sky"]):
        items += sr.search_multi(q, limit=4, min_width=1200)
        if len(items) >= want:
            break
    got = sr.download(items[:want], out_dir, log=log)
    return sorted(i["path"] for i in got)


def _ts(t: float) -> str:
    return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"


def _esc(t: str) -> str:
    return t.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")


def _wrap(text: str, per_line: int, max_lines: int = 3) -> str:
    """Break Thai text into <=per_line-char lines (Thai has no word spaces)."""
    words, lines, cur = text.split(" "), [], ""
    for w in words:
        if len(cur) + len(w) + 1 <= per_line:
            cur = (cur + " " + w).strip()
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        lines[-1] = lines[-1][: max(0, per_line - 1)] + "…"
    return r"\N".join(lines)


def build_ass(marks, total: float, path: str, title: str) -> str:
    """Cards match the reference: white, thin outline, left-anchored, centred.

    Body cards carry no brand or watermark, exactly as the reference does; the
    brand and the AI note live in the description. The closing card is the
    follow ask (K's rule: every clip ends with it).
    """
    fs = SPEC["card_font"]
    ol = SPEC["card_outline"]
    ml = SPEC["margin_left"]
    mv = SPEC["margin_v"]
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Card,{FONT_NAME},{fs},&H00FFFFFF,&H00FFFFFF,&H00202020,&H00000000,1,0,0,0,100,100,0.5,0,1,{ol},0,4,{ml},80,{mv},1
Style: Follow,{FONT_NAME},{fs},&H00FFFFFF,&H00FFFFFF,&H00202020,&H00000000,1,0,0,0,100,100,0.5,0,1,{ol},0,4,{ml},80,{mv},1
Style: FollowSub,{FONT_NAME},{fs - 18},&H00F0E0C0,&H00F0E0C0,&H00202020,&H00000000,0,0,0,0,100,100,0.5,0,1,3,0,7,{ml},80,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ev = []
    for start, end, text in marks:
        ev.append(f"Dialogue: 0,{_ts(start)},{_ts(end)},Card,,0,0,0,,"
                  f"{{\\fad(150,150)}}{_esc(_wrap(text, 24))}")
    hold = 3.0
    start_at = max(0.0, total - hold)
    ev.append(f"Dialogue: 0,{_ts(start_at)},{_ts(start_at + hold)},Follow,,0,0,0,,"
              f"{{\\fad(200,300)}}{_esc(branding.FOLLOW_ASK)}")
    ev.append(f"Dialogue: 0,{_ts(start_at)},{_ts(start_at + hold)},FollowSub,,0,0,0,,"
              f"{{\\fad(200,300)}}{_esc(branding.FOLLOW_PROMISE)}")
    open(path, "w", encoding="utf-8").write(head + "\n".join(ev) + "\n")
    return path


def _background_segment(src: str, per: float, is_video: bool, out: str):
    """One background clip of `per` seconds at the standard size and rate.

    Footage is looped and scaled/cropped with no zoom (the reference has none);
    a still gets a gentle Ken Burns push so it does not read as a frozen slide.
    """
    ff = ffmpeg()
    vf_common = (f"scale={W}:{H}:force_original_aspect_ratio=increase,"
                 f"crop={W}:{H},setsar=1")
    if is_video:
        run([ff, "-y", "-hide_banner", "-loglevel", "error",
             "-stream_loop", "-1", "-i", src, "-t", f"{per:.2f}",
             "-r", str(FPS), "-vf", f"{vf_common},format=yuv420p",
             "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", out])
    else:
        run([ff, "-y", "-hide_banner", "-loglevel", "error", "-loop", "1",
             "-i", src, "-t", f"{per:.2f}", "-r", str(FPS),
             "-vf", (f"scale={W*2}:{H*2}:force_original_aspect_ratio=increase,"
                     f"crop={W*2}:{H*2},"
                     f"zoompan=z='min(zoom+0.0005,1.12)':d={int(per*FPS)}:"
                     f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
                     f"s={W}x{H}:fps={FPS},format=yuv420p"),
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", out])


def fit_backgrounds(clips, total, xf=0.9, log=print):
    """The subset of `clips` that never has to be looped to fill its segment.

    `build_video` splits the narration evenly across the clips, so with `n`
    clips each segment is `per = (total + (n-1)*xf)/n` seconds. A source shorter
    than its segment is repeated with `-stream_loop -1`, and that loop seam is a
    hard cut the clip standard rejects. Drop the shortest clip until every
    remaining one is at least as long as its segment; if even one clip cannot
    fill the whole narration, return [] so the caller falls back to stills.
    """
    import clip_standard as cs
    lens = []
    for c in clips:
        try:
            lens.append(cs.probe(c)["seconds"])
        except Exception:
            lens.append(0.0)
    kept = sorted(range(len(clips)), key=lambda i: lens[i], reverse=True)
    while len(kept) > 1:
        per = (total + (len(kept) - 1) * xf) / len(kept)
        if lens[kept[-1]] >= per:
            break
        log(f"  [footage] drop a short clip "
            f"({lens[kept[-1]]:.1f}s < {per:.1f}s segment)")
        kept.pop()
    if not kept:
        return []
    per = (total + (len(kept) - 1) * xf) / len(kept)
    if lens[kept[0]] < per:
        return []
    return [clips[i] for i in kept]


def _mean_luma(path: str) -> float:
    """Mean grey level (0-255) of a source, for sizing the crossfade."""
    out = subprocess.run(
        [ffmpeg(), "-v", "error", "-i", path,
         "-vf", "fps=1,scale=1:1,format=gray", "-f", "rawvideo", "-"],
        capture_output=True)
    data = out.stdout
    return (sum(data) / len(data)) if data else 128.0


def _crossfade_for(paths, lo: float = 0.9, hi: float = 2.2) -> float:
    """A crossfade long enough that the seam stays under the no-cut floor.

    A crossfade is a per-frame blend, so two clips of very different brightness
    produce a step of roughly `|Δluma| / (xf · fps)` on the frame-difference
    metric the floor reads. At the old fixed 0.5 s a bright→dark seam measured
    21-37 (limit 20) and the finished clip was deleted. Size the fade from the
    worst adjacent brightness gap, with a 0.9 s floor so even a modest gap keeps
    clear headroom under the limit.
    """
    lum = []
    for p in paths:
        try:
            lum.append(_mean_luma(str(p)))
        except Exception:  # noqa: BLE001 — an unreadable source just gets the mean
            lum.append(128.0)
    if len(lum) < 2:
        return lo
    step = max(abs(lum[i] - lum[i + 1]) for i in range(len(lum) - 1))
    need = step / (6.0 * FPS)
    return max(lo, min(hi, round(need, 2)))


def build_video(backgrounds, narration, ass_path, total, out, work, xf=None, log=print):
    """Blend the backgrounds across the narration, then burn the cards.

    The reference has no hard cut, so consecutive backgrounds crossfade instead
    of butting together. The fade length is sized to the footage (`xf`) so a
    bright→dark seam does not read as a cut; each source is a little longer than
    its share so the blend has material to pull from, and the extra is trimmed by
    the final -t.
    """
    ff = ffmpeg()
    os.makedirs(work, exist_ok=True)
    n = max(1, len(backgrounds))
    if xf is None:
        xf = _crossfade_for([src for src, _ in backgrounds])
    if n == 1:
        xf = 0.0
    per = (total + (n - 1) * xf) / n
    segs = []
    for i, (src, is_video) in enumerate(backgrounds):
        # `per` is in the name: a retry with a longer fade rebuilds at a new `per`
        # and must not reuse a segment cut for the old one.
        p = os.path.join(work, f"b{i:03d}_{per:.2f}.mp4")
        if not (os.path.exists(p) and os.path.getsize(p) > 20000):
            _background_segment(src, per, is_video, p)
        segs.append(p)
    silent = os.path.join(work, f"silent_{per:.2f}.mp4")
    if n == 1:
        run([ff, "-y", "-hide_banner", "-loglevel", "error", "-i", segs[0],
             "-c", "copy", silent])
    else:
        args = [ff, "-y", "-hide_banner", "-loglevel", "error"]
        for p in segs:
            args += ["-i", p]
        chain, prev = [], "[0:v]"
        for k in range(1, n):
            off = k * (per - xf)
            lbl = f"[v{k}]" if k < n - 1 else "[vout]"
            chain.append(f"{prev}[{k}:v]xfade=transition=fade:"
                         f"duration={xf}:offset={off:.3f}{lbl}")
            prev = f"[v{k}]"
        run(args + ["-filter_complex", ";".join(chain), "-map", "[vout]",
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
                    "-pix_fmt", "yuv420p", silent])
    ass_esc = ass_path.replace("\\", "/").replace(":", r"\:")
    fontdir_esc = FONT_DIR.replace("\\", "/").replace(":", r"\:")
    loud = f"loudnorm=I={SPEC['lufs']}:TP={SPEC['true_peak']}:LRA=11"
    run([ff, "-y", "-hide_banner", "-loglevel", "error",
         "-i", silent, "-i", narration,
         "-vf", f"ass={ass_esc}:fontsdir={fontdir_esc}",
         "-af", loud,
         "-map", "0:v", "-map", "1:a", "-t", f"{total:.3f}",
         "-c:v", "libx264", "-preset", "medium", "-crf", "20",
         "-maxrate", SPEC["video_bitrate"], "-bufsize", "4600k",
         "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", SPEC["audio_bitrate"],
         "-ar", "48000", "-ac", "2",
         "-movflags", "+faststart", out])
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--script", required=True)
    ap.add_argument("--out", default="/tmp/trivia-reel")
    ap.add_argument("--card-secs", type=float, default=5.0)
    ap.add_argument("--stills-only", action="store_true",
                    help="skip footage and render from stills")
    ap.add_argument("--plan", action="store_true")
    a = ap.parse_args()

    title, theme, cards = read_script(a.script)
    chars = sum(len(p) for p in cards)
    print(f"title : {title}")
    print(f"theme : {theme}")
    print(f"cards : {len(cards)}  chars {chars}  "
          f"~{chars/thai_tts.CHARS_PER_SECOND:.1f}s narration")
    if a.plan:
        for i, p in enumerate(cards):
            print(f"  {i+1:02d}. {p[:60]}")
        return 0

    work = os.path.join(a.out, "work")
    os.makedirs(work, exist_ok=True)
    print("[audio] synthesising narration")
    segs = narrate(cards, os.path.join(work, "tts"))
    narration, total, marks = concat_audio(segs, os.path.join(work, "tts"))
    print(f"[audio] narration {total:.1f}s, normalised to {SPEC['lufs']} LUFS")

    want = max(2, int(total / a.card_secs) + 1)
    backgrounds, credits = [], []
    xf = None
    if not a.stills_only:
        # Screen at the smallest possible segment (all `want` clips used); a clip
        # longer than its real segment is fine, a shorter one is dropped by
        # `fit_backgrounds` below. The crossfade is sized first, because a longer
        # fade lengthens every segment and can disqualify a clip that the default
        # 0.5 s would have kept.
        clips, items = fetch_footage(theme, os.path.join(work, "footage"),
                                     want, min_secs=total / want)
        xf = _crossfade_for(clips)
        fitted = fit_backgrounds(clips, total, xf=xf)
        keep = set(fitted)
        credits = [it for c, it in zip(clips, items) if c in keep]
        backgrounds = [(c, True) for c in fitted]
    if not backgrounds:
        stills = fetch_stills(theme, os.path.join(work, "stills"), want)
        if not stills:
            raise SystemExit(f"no footage or stills for theme {theme!r}")
        backgrounds = [(s, False) for s in stills]
        print(f"[video] {len(stills)} stills (footage unavailable), theme {theme}")
    else:
        print(f"[video] {len(backgrounds)} footage clips, theme {theme}")

    ass_path = os.path.join(work, "cap.ass")
    build_ass(marks, total, ass_path, title)
    out = os.path.join(a.out, os.path.basename(a.script).replace(".md", "") + ".mp4")
    segs_dir = os.path.join(work, "segs")

    # The standard is a floor (K, 2026-11-17: "ห้ามมาตรฐานต่ำกว่านี้เด็ดขาด").
    # A clip that drops below it is not written out as a finished artifact. The
    # only soft check is the crossfade seam, so widen the fade and rebuild rather
    # than throw the render away; anything else fails immediately.
    import clip_standard
    for attempt in range(3):
        build_video(backgrounds, narration, ass_path, total, out, segs_dir, xf=xf)
        info = subprocess.run([ffmpeg(), "-hide_banner", "-i", out],
                              capture_output=True, text=True).stderr
        dur = re.search(r"Duration: (\d+):(\d+):([\d.]+)", info)
        secs = (int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 +
                float(dur.group(3))) if dur else 0
        print(f"[done] {out}  {secs:.1f}s  {os.path.getsize(out)//1024} KB")
        rows = clip_standard.check(out)
        for name, ok, detail in rows:
            print(f"  {'ok  ' if ok else 'FAIL'} {name:28s} {detail}")
        bad = [name for name, ok, _ in rows if not ok]
        if not bad:
            break
        if bad != ["no hard cut"] or attempt == 2:
            os.remove(out)
            raise SystemExit("clip below the standard (removed): " + "; ".join(bad))
        xf = min(2.5, round((xf or _crossfade_for([s for s, _ in backgrounds])) * 1.8, 2))
        print(f"[video] seam still over the floor; rebuilding with a {xf}s crossfade")

    json.dump({"title": title, "theme": theme, "seconds": secs, "out": out,
               "backgrounds": len(backgrounds), "spec": SPEC,
               "cards": cards,
               "credits": [{"title": it.get("title", ""),
                            "licence": it.get("licence", ""),
                            "source": it.get("source", ""),
                            "origin": it.get("origin", "")} for it in credits]},
              open(os.path.join(a.out, "trivia.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
