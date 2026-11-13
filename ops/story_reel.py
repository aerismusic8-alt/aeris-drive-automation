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
BRAND = "AERIS MUSIC"
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
    os.makedirs(out_dir, exist_ok=True)
    have = sorted(glob.glob(os.path.join(out_dir, "s*.jpg")))
    if len(have) >= want:
        return have[:want]
    queries = THEME_QUERIES.get(theme, THEME_QUERIES["lesson"])
    items = []
    for q in queries:
        items += sr.search(q, limit=4, min_width=1200)
        if len(items) >= want:
            break
    got = sr.download(items[:want], out_dir, log=log)
    files = sorted(i["path"] for i in got)
    if not files:
        raise SystemExit(f"no stills downloaded for theme {theme!r}")
    return files


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
    for i, s in enumerate(stills):
        p = os.path.join(work, f"v{i:03d}.mp4")
        if not (os.path.exists(p) and os.path.getsize(p) > 20000):
            zdir = "zoom+" if i % 2 == 0 else "zoom-"
            run([ff, "-y", "-hide_banner", "-loglevel", "error", "-loop", "1",
                 "-i", s, "-t", f"{per:.2f}", "-r", str(FPS),
                 "-vf", (f"scale={W*2}:{H*2}:force_original_aspect_ratio=increase,"
                         f"crop={W*2}:{H*2},"
                         f"zoompan=z='min(zoom+0.0006,1.18)':d={int(per*FPS)}:"
                         f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={W}x{H}:fps={FPS},"
                         f"format=yuv420p"),
                 "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", p])
        segs.append(p)
        if i % 4 == 0:
            log(f"  [video] segment {i+1}/{n}")
    lst = os.path.join(work, "vlist.txt")
    with open(lst, "w", encoding="utf-8") as fh:
        for p in segs:
            fh.write(f"file '{os.path.abspath(p)}'\n")
    silent = os.path.join(work, "silent.mp4")
    run([ff, "-y", "-hide_banner", "-loglevel", "error", "-f", "concat",
         "-safe", "0", "-i", lst, "-c", "copy", silent])
    ass_esc = ass_path.replace("\\", "/").replace(":", r"\:")
    fontdir_esc = FONT_DIR.replace("\\", "/").replace(":", r"\:")
    run([ff, "-y", "-hide_banner", "-loglevel", "error",
         "-i", silent, "-i", narration,
         "-vf", f"ass={ass_esc}:fontsdir={fontdir_esc}",
         "-map", "0:v", "-map", "1:a", "-t", f"{total:.3f}",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "21",
         "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
         "-movflags", "+faststart", out])
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--script", required=True)
    ap.add_argument("--out", default="/tmp/story-reel")
    ap.add_argument("--still-secs", type=float, default=4.0)
    ap.add_argument("--plan", action="store_true")
    a = ap.parse_args()

    title, theme, paras = read_script(a.script)
    chars = sum(len(p) for p in paras)
    print(f"title : {title}")
    print(f"theme : {theme}")
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
    stills = fetch_stills(theme, os.path.join(work, "stills"),
                          max(3, int(total / a.still_secs) + 1))
    print(f"[video] {len(stills)} stills, theme {theme}")
    ass_path = os.path.join(work, "cap.ass")
    build_ass(marks, total, ass_path)
    out = os.path.join(a.out, os.path.basename(a.script).replace(".md", "") + ".mp4")
    build_video(stills, narration, ass_path, total, out, os.path.join(work, "segs"))
    info = subprocess.run([ffmpeg(), "-hide_banner", "-i", out],
                          capture_output=True, text=True).stderr
    dur = re.search(r"Duration: (\d+):(\d+):([\d.]+)", info)
    secs = (int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 + float(dur.group(3))) if dur else 0
    print(f"[done] {out}  {secs:.1f}s  {os.path.getsize(out)//1024} KB")
    json.dump({"title": title, "theme": theme, "seconds": secs, "out": out,
               "still_count": len(stills)},
              open(os.path.join(a.out, "reel.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
