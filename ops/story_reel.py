#!/usr/bin/env python3
"""Render a Thai narrated story Reel (1080x1920, vertical) from a script file.

Why this lane exists (K, 2026-11-13): the Facebook Page must reach 500 followers
(Stars) and 5,000 (Subscriptions) to unlock revenue, and the four-surface review
showed the music clips do not attach an audience. Facebook gives Reels free
distribution, so the growth lever is a short vertical story the viewer finishes,
not another song. K: "ไม่จำเป็นต้องเป็นเพลงก็ได้" — it does not have to be music.

Everything here is free (Rule #1): the voice is edge-tts, the pictures are
licence-checked Wikimedia Commons stills, the render is ffmpeg. No API key, no
login, no cost.

The sound leads (K's AUDIO FIRST rule): the narration is synthesised and measured
before a single picture is laid down, and each paragraph's own duration decides
where its caption sits.

Script format (a plain .md, one paragraph per block separated by blank lines):

    # TITLE: ห้องเช่าหมายเลข 9
    # THEME: horror
    คืนนั้นผมได้ยินเสียงเคาะประตู...
    <blank line>
    ผมเปิดประตูออกไป...

    python3 ops/story_reel.py --script scripts_story/horror-01.md --out /tmp/reel
    python3 ops/story_reel.py --plan --script scripts_story/horror-01.md
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thai_tts  # noqa: E402
import stills_rail as sr  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_DIR = os.path.join(ROOT, "music938-1", "fonts")
FONT_NAME = "Noto Sans Thai"
W, H, FPS = 1080, 1920, 30
# K (2026-11-20): the picture library is 4K material and the finished clip is
# 720p. Holding the stills at 4K and only shrinking at the final encode is what
# keeps a pan or push sharp; scaling a 1920 still up first would show its edges.
SOURCE_MIN_W = 3840
LANDSCAPE = False        # --landscape renders 1280x720 for the trivia-style lane
BRAND = "เพลงส้นทีนไรเนี่ย"
FOLLOW_ASK = "กดติดตามไว้เลย"
FOLLOW_PROMISE = "เรื่องเล่าใหม่ทุกวัน"
AI_NOTE = "เสียงและภาพสร้างด้วย AI"

# One stock query set per theme. English, because Commons returns 0 for Thai.
THEME_QUERIES = {
    "horror": ["dark corridor night", "abandoned house fog", "old wooden door dark",
               "candle in dark room", "misty forest night", "empty street lamp night",
               "rain window night", "old staircase dark"],
    "lesson": ["quiet road sunrise", "old man hands coffee", "rain on window",
               "lone tree field", "mountain path fog", "still lake reflection dawn",
               "open sky clouds", "candle in dark"],
    "humour": ["thai street market", "motorbike traffic bangkok", "thai food stall",
               "monk alms bowl morning", "bangkok skyline night", "thai cat street"],
}


def ffmpeg() -> str:
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def run(args, **kw):
    subprocess.run(args, check=True, **kw)


def read_script(path: str):
    """Returns (title, theme, [paragraphs]). # TITLE: / # THEME: decide the rest."""
    raw = open(path, encoding="utf-8").read()
    title, theme = None, None
    for line in raw.splitlines():
        s = line.strip()
        if s.upper().startswith("# TITLE:"):
            title = s.split(":", 1)[1].strip()
        elif s.upper().startswith("# THEME:"):
            theme = s.split(":", 1)[1].strip()
    body = [l for l in raw.splitlines() if not l.strip().startswith("#")]
    paras = [re.sub(r"\s+", " ", p).strip()
             for p in re.split(r"\n\s*\n", "\n".join(body)) if p.strip()]
    if not paras:
        raise SystemExit(f"no paragraphs in {path}")
    return title or os.path.basename(path), theme or "lesson", paras


def narrate(paras: list[str], work: str, log=print):
    """Synthesise one clip per paragraph so each caption knows its own length."""
    os.makedirs(work, exist_ok=True)
    voice = thai_tts.VOICE_MALE
    segs = []
    for i, p in enumerate(paras):
        out = os.path.join(work, f"n{i:02d}.mp3")
        if os.path.exists(out) and os.path.getsize(out) > 1000:
            secs = thai_tts.audio_seconds(out)
        else:
            _, secs = thai_tts.synth(p, out, voice=voice)
        segs.append({"path": out, "secs": secs, "text": p})
        log(f"  [tts] {i+1}/{len(paras)}  {secs:5.1f}s  {p[:32]}...")
    return segs


def concat_audio(segs, out, work, gap=0.45):
    """Join narration clips with a short breath between them; returns total secs."""
    ff = ffmpeg()
    silence = os.path.join(work, "gap.mp3")
    if not os.path.exists(silence):
        run([ff, "-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi",
             "-i", f"anullsrc=r=24000:cl=mono", "-t", f"{gap}", silence])
    lst = os.path.join(work, "narr.txt")
    with open(lst, "w", encoding="utf-8") as fh:
        for s in segs:
            fh.write(f"file '{os.path.abspath(s['path'])}'\n")
            fh.write(f"file '{os.path.abspath(silence)}'\n")
    raw = os.path.join(work, "narr_raw.m4a")
    run([ff, "-y", "-hide_banner", "-loglevel", "error", "-f", "concat",
         "-safe", "0", "-i", lst, "-c:a", "aac", "-b:a", "192k", raw])
    total = thai_tts.audio_seconds(raw)
    # Each caption starts at the running sum of its own clip + gap.
    t, marks = 0.0, []
    for s in segs:
        marks.append((t, t + s["secs"], s["text"]))
        t += s["secs"] + gap
    return raw, total, marks


def fetch_stills(theme: str, out_dir: str, want: int, log=print):
    """4K stills for the theme. Falls back to the local picture library first,
    then Commons at the 4K render size, so a clip never depends on one source."""
    os.makedirs(out_dir, exist_ok=True)
    have = sorted(glob.glob(os.path.join(out_dir, "s*.jpg")))
    if len(have) >= want:
        return have[:want]

    files = _library_stills(theme, out_dir, want, log)
    if len(files) < want:
        queries = THEME_QUERIES.get(theme, THEME_QUERIES["lesson"])
        items = []
        for q in queries:
            # Commons only: Openverse's large tier is 1024-1280 px, below the 4K
            # floor, so interleaving it only spends a download slot on a reject.
            items += sr.search(q, limit=6, min_width=SOURCE_MIN_W)
            if len(items) >= want:
                break
        got = sr.download(items[:want], out_dir, log=log)
        files += sorted(i["path"] for i in got)
    files = sorted(set(files))[:want]
    if not files:
        raise SystemExit(f"no stills downloaded for theme {theme!r}")
    return files


def _library_stills(theme: str, out_dir: str, want: int, log=print) -> list[str]:
    """Copy 4K stills out of the picture library, least-used first.

    The library is the reason a render costs nothing: generation happened once,
    and this step only picks. A short library is a normal outcome, not an error —
    the caller tops up from Commons.
    """
    import shutil  # noqa: PLC0415

    import media_home  # noqa: PLC0415
    try:
        lib = media_home.pictures()
    except SystemExit:
        return []
    idx = lib / "index.json"
    if not idx.exists():
        return []
    try:
        rows = json.loads(idx.read_text(encoding="utf-8")).get("images", [])
    except (OSError, ValueError):
        return []
    rows = [r for r in rows if r.get("theme") in (theme, None) or theme in (r.get("tags") or [])]
    rows.sort(key=lambda r: (r.get("uses") or 0, r.get("id") or ""))
    out = []
    for r in rows[:want]:
        src = lib / r["file"]
        if not src.exists():
            continue
        dest = os.path.join(out_dir, f"s{len(out):03d}{os.path.splitext(src.name)[1]}")
        if not os.path.exists(dest):
            shutil.copy2(src, dest)
        out.append(dest)
        r["uses"] = (r.get("uses") or 0) + 1
    if out:
        try:
            idx.write_text(json.dumps({"images": rows}, ensure_ascii=False, indent=1))
        except OSError:
            pass
        log(f"  [library] {len(out)} still(s) picked from {lib}")
    return out


def music_bed(track: str, total: float, out: str, level_db: float = -22.0) -> str:
    """Loop an AI track under the narration at a fixed, quiet level.

    The narration is the message and the music is the bed, so the track is
    trimmed to length and dropped to `level_db` rather than loudness-matched:
    loudnorm on both would fight, and the final master normalises the mix.
    """
    ff = ffmpeg()
    run([ff, "-y", "-hide_banner", "-loglevel", "error",
         "-stream_loop", "-1", "-i", track, "-t", f"{total:.3f}",
         "-af", f"volume={level_db}dB,afade=t=in:st=0:d=1.5,"
                f"afade=t=out:st={max(0.0, total - 2.0):.2f}:d=2.0",
         "-ar", "48000", "-ac", "2", "-c:a", "aac", "-b:a", "192k", out])
    return out


def mix_narration(narration: str, bed: str | None, total: float, out: str) -> str:
    """Narration on top of the bed. A missing bed yields the narration alone."""
    ff = ffmpeg()
    if not bed:
        run([ff, "-y", "-hide_banner", "-loglevel", "error", "-i", narration,
             "-t", f"{total:.3f}", "-c:a", "aac", "-b:a", "192k",
             "-ar", "48000", "-ac", "2", out])
        return out
    run([ff, "-y", "-hide_banner", "-loglevel", "error",
         "-i", narration, "-i", bed,
         "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=first:"
                            "dropout_transition=0:normalize=0[a]",
         "-map", "[a]", "-t", f"{total:.3f}", "-c:a", "aac", "-b:a", "192k",
         "-ar", "48000", "-ac", "2", out])
    return out


def _ts(t: float) -> str:
    return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"


def _esc(t: str) -> str:
    return t.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")


def _wrap(text: str, per_line: int, max_lines: int = 3) -> str:
    """Break Thai text into <=per_line-char lines (Thai has no spaces)."""
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


def build_ass(marks, total: float, path: str) -> str:
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,{FONT_NAME},86,&H00FFFFFF,&H00FFFFFF,&H00101010,&H78000000,1,0,0,0,100,100,0.4,0,1,7,4,2,90,90,150,1
Style: Brand,{FONT_NAME},46,&H00DDFFFF,&H00DDFFFF,&H00101010,&H80000000,1,0,0,0,100,100,1,0,1,4,2,7,54,54,70,1
Style: Follow,{FONT_NAME},92,&H0020E0FF,&H0020E0FF,&H00101010,&H00000000,1,0,0,0,100,100,0.5,0,1,8,4,2,90,90,300,1
Style: FollowSub,{FONT_NAME},62,&H00E8E8E8,&H00E8E8E8,&H00101010,&H00000000,0,0,0,0,100,100,0.5,0,1,6,3,2,90,90,220,1
Style: Note,{FONT_NAME},38,&H00CCCCCC,&H00CCCCCC,&H00101010,&H64000000,0,0,0,0,100,100,0.3,0,1,3,1,2,60,60,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ev = []
    for start, end, text in marks:
        ev.append(f"Dialogue: 0,{_ts(start)},{_ts(end)},Cap,,0,0,0,,"
                  f"{{\\fad(120,120)}}{_esc(_wrap(text, 26))}")
    ev.append(f"Dialogue: 0,{_ts(0)},{_ts(total)},Brand,,0,0,0,,"
              f"{{\\fad(300,300)}}{BRAND}")
    ev.append(f"Dialogue: 0,{_ts(0.6)},{_ts(total)},Note,,0,0,0,,"
              f"{{\\fad(300,300)}}{_esc(AI_NOTE)}")
    hold = 3.0
    start_at = max(0.0, total - hold)
    ev.append(f"Dialogue: 0,{_ts(start_at)},{_ts(start_at + hold)},Follow,,0,0,0,,"
              f"{{\\fad(200,300)}}{_esc(FOLLOW_ASK)}")
    ev.append(f"Dialogue: 0,{_ts(start_at)},{_ts(start_at + hold)},FollowSub,,0,0,0,,"
              f"{{\\fad(200,300)}}{_esc(FOLLOW_PROMISE)}")
    open(path, "w", encoding="utf-8").write(head + "\n".join(ev) + "\n")
    return path


def build_video(stills, narration, ass_path, total, out, work, log=print):
    """Hold each still so the pictures fill the narration, then burn captions."""
    ff = ffmpeg()
    os.makedirs(work, exist_ok=True)
    n = max(1, len(stills))
    per = total / n + 0.4  # slight overlap slack, trimmed by -t
    segs = []
    xf = 0.8 if n > 1 else 0.0   # a crossfade, so a still change is not a cut
    for i, s in enumerate(stills):
        p = os.path.join(work, f"v{i:03d}_{per:.2f}_{xf}.mp4")
        if not (os.path.exists(p) and os.path.getsize(p) > 20000):
            # Alternate the push direction so consecutive stills do not drift the
            # same way; a one-way push reads as a pan of one long picture.
            z = "min(zoom+0.0006,1.18)" if i % 2 == 0 else "if(eq(on,1),1.18,max(zoom-0.0006,1.0))"
            run([ff, "-y", "-hide_banner", "-loglevel", "error", "-loop", "1",
                 "-i", s, "-t", f"{per + xf:.2f}", "-r", str(FPS),
                 "-vf", (f"scale={W*2}:{H*2}:force_original_aspect_ratio=increase,"
                         f"crop={W*2}:{H*2},"
                         f"zoompan=z='{z}':d={int((per + xf)*FPS)}:"
                         f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS},"
                         f"format=yuv420p"),
                 "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", p])
        segs.append(p)
        if i % 4 == 0:
            log(f"  [video] segment {i+1}/{n}")

    silent = os.path.join(work, "silent.mp4")
    if n == 1:
        run([ff, "-y", "-hide_banner", "-loglevel", "error", "-i", segs[0],
             "-t", f"{total:.3f}", "-c", "copy", silent])
    else:
        # `concat -c copy` butts the segments together, and every seam measures as
        # a hard cut (128 against a 20 limit). xfade blends them instead.
        args = [ff, "-y", "-hide_banner", "-loglevel", "error"]
        for p in segs:
            args += ["-i", p]
        chain, prev = [], "[0:v]"
        for k in range(1, n):
            off = k * per
            lbl = f"[v{k}]" if k < n - 1 else "[vout]"
            chain.append(f"{prev}[{k}:v]xfade=transition=fade:duration={xf}:"
                         f"offset={off:.3f}{lbl}")
            prev = f"[v{k}]"
        run(args + ["-filter_complex", ";".join(chain), "-map", "[vout]",
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
                    "-pix_fmt", "yuv420p", silent])

    ass_esc = ass_path.replace("\\", "/").replace(":", r"\:")
    fontdir_esc = FONT_DIR.replace("\\", "/").replace(":", r"\:")
    # Loudness is normalised here, once, on the finished mix: measuring and
    # correcting the narration and the bed separately would fight each other.
    run([ff, "-y", "-hide_banner", "-loglevel", "error",
         "-i", silent, "-i", narration,
         "-vf", f"ass={ass_esc}:fontsdir={fontdir_esc}",
         "-af", "loudnorm=I=-15:TP=-2.0:LRA=11",
         "-map", "0:v", "-map", "1:a", "-t", f"{total:.3f}",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "21",
         "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
         "-ar", "48000", "-ac", "2",
         "-movflags", "+faststart", out])
    return out


def pick_music() -> str | None:
    """An AI *instrumental* for the bed, from the song library, genre-gated.

    The karaoke renders are the instrumental mixes (drums+bass+other, vocal stem
    left out), so they are preferred: a sung track under a Thai narration puts
    two voices in the same band and the words stop being intelligible. A sung
    track is only a last resort, and the gate is the compass (one rule everywhere).
    """
    import random  # noqa: PLC0415

    lib = os.path.join(ROOT, "music938-1", "library", "songs")
    try:
        sys.path.insert(0, os.path.join(ROOT, "ops"))
        sys.path.insert(0, os.path.join(ROOT, "music938-1", "scripts"))
        import compass  # noqa: PLC0415
        import genres  # noqa: PLC0415
    except Exception:  # noqa: BLE001 - no gate available means no music
        return None

    def ok(t: str) -> bool:
        slug = genres.resolve_slug(os.path.basename(t))
        return bool(slug and compass.is_publishable(slug)[0])

    instrumental = [t for t in sorted(glob.glob(os.path.join(lib, "karaoke-*.mp3"))) if ok(t)]
    if instrumental:
        return random.choice(instrumental)
    sung = [t for t in sorted(glob.glob(os.path.join(lib, "*.mp3"))) if ok(t)]
    return random.choice(sung) if sung else None


def shelve(clip: str, title: str, theme: str) -> str:
    """Move a QC-passed clip onto the finished shelf and index it.

    K (2026-11-20): finished videos wait in their own place, separate from the
    published material. The index is what makes the shelf readable — without it
    a directory of mp4s says nothing about what is ready to upload.
    """
    import datetime  # noqa: PLC0415
    import shutil  # noqa: PLC0415

    import media_home  # noqa: PLC0415

    shelf = media_home.finished()
    dest = os.path.join(shelf, os.path.basename(clip))
    shutil.move(clip, dest)

    idx = os.path.join(shelf, "index.json")
    try:
        doc = json.loads(open(idx, encoding="utf-8").read())
    except (OSError, ValueError):
        doc = {"clips": []}
    doc.setdefault("clips", []).append({
        "file": os.path.basename(dest), "title": title, "theme": theme,
        "bytes": os.path.getsize(dest),
        "at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "uploaded": False,
    })
    with open(idx, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=1)
    return dest


def main() -> int:
    global W, H, FPS
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--script", required=True)
    ap.add_argument("--out", default="/tmp/story-reel")
    ap.add_argument("--still-secs", type=float, default=4.0)
    ap.add_argument("--music", default="",
                    help="AI track for the bed; empty picks one from library/music")
    ap.add_argument("--no-music", action="store_true")
    ap.add_argument("--landscape", action="store_true",
                    help="render 1280x720 (the trivia-style lane)")
    ap.add_argument("--keep", action="store_true",
                    help="leave the clip where it was rendered instead of shelving it")
    ap.add_argument("--plan", action="store_true")
    a = ap.parse_args()

    if a.landscape:
        W, H, FPS = 1280, 720, 24

    title, theme, paras = read_script(a.script)
    chars = sum(len(p) for p in paras)
    print(f"title : {title}")
    print(f"theme : {theme}")
    print(f"size  : {W}x{H} @ {FPS}")
    print(f"paras : {len(paras)}  chars {chars}  "
          f"~{chars/thai_tts.CHARS_PER_SECOND:.1f}s narration")
    if a.plan:
        for i, p in enumerate(paras):
            print(f"  {i+1:02d}. {p[:60]}")
        return 0

    work = os.path.join(a.out, "work")
    os.makedirs(work, exist_ok=True)
    print("[audio] synthesising narration")
    segs = narrate(paras, os.path.join(work, "tts"))
    narration, total, marks = concat_audio(segs, None, os.path.join(work, "tts"))
    print(f"[audio] narration {total:.1f}s")

    bed = None
    if not a.no_music:
        track = a.music or pick_music()
        if track:
            print(f"[audio] music bed {os.path.basename(track)}")
            bed = music_bed(track, total, os.path.join(work, "bed.m4a"))
        else:
            print("[audio] no AI track available; narration only")
    mixed = mix_narration(narration, bed, total, os.path.join(work, "mix.m4a"))

    stills = fetch_stills(theme, os.path.join(work, "stills"),
                          max(3, int(total / a.still_secs) + 1))
    print(f"[video] {len(stills)} stills, theme {theme}")
    ass_path = os.path.join(work, "cap.ass")
    build_ass(marks, total, ass_path)
    out = os.path.join(a.out, os.path.basename(a.script).replace(".md", "") + ".mp4")
    build_video(stills, mixed, ass_path, total, out, os.path.join(work, "segs"))

    import clip_standard as cs  # noqa: PLC0415
    problems = cs.check(out, "trivia" if a.landscape else "vertical")
    for name, ok, detail in problems:
        print(f"  [qc] {'ok  ' if ok else 'FAIL'} {name}: {detail}")
    if not all(ok for _, ok, _ in problems):
        os.unlink(out)
        print("[qc] clip deleted — a below-floor clip must not exist")
        return 1

    dest = out if a.keep else shelve(out, title, theme)
    info = subprocess.run([ffmpeg(), "-hide_banner", "-i", dest],
                          capture_output=True, text=True).stderr
    dur = re.search(r"Duration: (\d+):(\d+):([\d.]+)", info)
    secs = (int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 + float(dur.group(3))) if dur else 0
    print(f"[done] {dest}  {secs:.1f}s  {os.path.getsize(dest)//1024} KB")
    json.dump({"title": title, "theme": theme, "seconds": secs, "out": dest,
               "still_count": len(stills), "music": os.path.basename(bed or ""),
               "size": f"{W}x{H}", "qc": "pass"},
              open(os.path.join(a.out, "reel.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
