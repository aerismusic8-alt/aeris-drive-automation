#!/usr/bin/env python3
"""Assemble stills into a calm long-form video, then mux the audio bed.

Two ffmpeg traps this module exists to avoid, both hit for real on 2026-10-24:

  * `zoompan` defaults to s=hd720 and SILENTLY downscales. Every zoompan call
    here passes an explicit s=WxH, and the finished file's size is measured
    afterwards rather than assumed.
  * One filter graph holding every input eventually dies. Stills are crossfaded
    in small batches and the batches are then concatenated.

Motion comes from a slow zoom/pan per still, alternating direction so a long
episode does not feel like it is breathing in and out on a loop.
"""
import json
import os
import re
import subprocess

import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
W, H, FPS = 1920, 1080, 25


def run(args, timeout=3600):
    p = subprocess.run([FF, "-hide_banner", "-y"] + args,
                       capture_output=True, text=True, timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {' '.join(str(a) for a in args[:8])}\n{p.stderr[-1200:]}")
    return p.stderr


def probe(path):
    err = subprocess.run([FF, "-hide_banner", "-i", path],
                         capture_output=True, text=True).stderr
    dur = re.search(r"Duration: (\d+):(\d+):(\d+\.?\d*)", err)
    size = re.search(r"Video:.*?(\d{2,5})x(\d{2,5})", err)
    return {
        "seconds": (int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 + float(dur.group(3))
                    if dur else None),
        "width": int(size.group(1)) if size else None,
        "height": int(size.group(2)) if size else None,
    }


def still_segment(src, out, seconds, index, zoom_span=0.11):
    """One still held for `seconds`, scaled to fill 1080p with a slow zoom.

    The zoom RATE must be derived from the segment length. A fixed rate (e.g.
    z=min(1+0.001*on,1.10)) reaches its ceiling in ~4 s and then holds a frozen
    frame for the rest of a 17 s segment. Measured 2026-10-24 on a 12:35 build:
    that mistake left 747 of 1510 sampled steps static. So the step is
    zoom_span/frames and the motion lasts exactly as long as the still is shown.
    """
    frames = max(2, int(seconds * FPS))
    step = zoom_span / frames
    if index % 2 == 0:
        z = f"min(1+{step:.6f}*on,{1+zoom_span:.4f})"
    else:
        z = f"max({1+zoom_span:.4f}-{step:.6f}*on,1.0)"
    # Drift the crop so consecutive stills never move in the same direction.
    x = "iw/2-(iw/zoom/2)+sin(on/180)*iw*0.010"
    y = "ih/2-(ih/zoom/2)+cos(on/210)*ih*0.008"
    vf = (
        f"scale={W}:{H}:force_original_aspect_ratio=increase,"
        f"crop={W}:{H},setsar=1,"
        f"zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s={W}x{H}:fps={FPS},"
        f"format=yuv420p"
    )
    run(["-loop", "1", "-i", src, "-t", f"{seconds:.3f}", "-vf", vf,
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
         "-pix_fmt", "yuv420p", out])
    return out


def xfade_batch(segments, out, xfade=1.5):
    """Crossfade a small group of segments into one file."""
    if len(segments) == 1:
        run(["-i", segments[0], "-c", "copy", out])
        return out
    durs = [probe(s)["seconds"] for s in segments]
    args = []
    for s in segments:
        args += ["-i", s]
    parts, prev, offset = [], "[0:v]", 0.0
    for i in range(1, len(segments)):
        offset += durs[i - 1] - xfade
        lbl = f"[v{i}]"
        parts.append(f"{prev}[{i}:v]xfade=transition=fade:duration={xfade}"
                     f":offset={offset:.3f}{lbl}")
        prev = lbl
    filt = ";".join(parts)
    run(args + ["-filter_complex", filt, "-map", prev,
               "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
               "-pix_fmt", "yuv420p", out])
    return out


def concat(parts, out, work_dir):
    lst = os.path.join(work_dir, "concat.txt")
    with open(lst, "w", encoding="utf-8") as f:
        for p in parts:
            f.write(f"file '{os.path.abspath(p)}'\n")
    run(["-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out])
    return out


def build(stills, audio, out, work_dir, batch=8, xfade=1.5, log=print):
    """Hold each still so the pictures exactly fill the narration."""
    os.makedirs(work_dir, exist_ok=True)
    total = probe(audio)["seconds"]
    n = len(stills)
    # xfade eats `xfade` seconds per join, so holds are widened to compensate.
    per = (total + (n - 1) * xfade) / n
    log(f"  {n} stills x {per:.1f}s, {n-1} xfades of {xfade}s -> target {total:.1f}s")

    segs = []
    for i, s in enumerate(stills):
        p = os.path.join(work_dir, f"seg{i:03d}.mp4")
        if not (os.path.exists(p) and os.path.getsize(p) > 20000):
            still_segment(s, p, per, i)
        segs.append(p)
        if i % 8 == 0:
            log(f"    segment {i+1}/{n}")

    batches = [segs[i:i + batch] for i in range(0, len(segs), batch)]
    bfiles = []
    for i, b in enumerate(batches):
        p = os.path.join(work_dir, f"batch{i:02d}.mp4")
        if not (os.path.exists(p) and os.path.getsize(p) > 20000):
            xfade_batch(b, p, xfade)
        bfiles.append(p)
        log(f"    batch {i+1}/{len(batches)} = {probe(p)['seconds']:.1f}s")

    silent = os.path.join(work_dir, "video_silent.mp4")
    concat(bfiles, silent, work_dir)
    log(f"  silent video {probe(silent)['seconds']:.1f}s")

    run(["-i", silent, "-i", audio, "-map", "0:v", "-map", "1:a",
         "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
         "-shortest", "-movflags", "+faststart", out])
    return out


def thai_font_path(cache="/tmp/Sarabun-Bold.ttf"):
    """Fetch Sarabun Bold and hand back a real TTF path.

    Google Fonts serves **WOFF2** to a modern User-Agent. PIL cannot open WOFF2 and
    the file still starts with a valid-looking sfnt header, so the failure is easy to
    miss. We download, convert the flavour away with fontTools, and cache the TTF.
    Thai also needs complex-text shaping: verified `raqm` is available, and the font's
    cmap covers every codepoint in our scripts (0 missing).
    """
    if os.path.exists(cache) and open(cache, "rb").read(4) == b"\x00\x01\x00\x00":
        return cache
    import urllib.request
    from fontTools.ttLib import TTFont

    css = urllib.request.urlopen(urllib.request.Request(
        "https://fonts.googleapis.com/css2?family=Sarabun:wght@700",
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                               "(KHTML, like Gecko) Chrome/120 Safari/537.36"}), timeout=30).read().decode()
    url = re.search(r"src: url\((https://[^)]+)\)", css)
    if not url:
        raise RuntimeError("no font url in Google Fonts CSS")
    raw = urllib.request.urlopen(url.group(1), timeout=60).read()
    tmp = cache + ".woff2"
    open(tmp, "wb").write(raw)
    f = TTFont(tmp)
    f.flavor = None
    f.save(cache)
    return cache


def make_thumbnail(still, out, title, sub=""):
    """Draw the thumbnail with a real Thai font."""
    from PIL import Image, ImageDraw, ImageFont

    font_path = thai_font_path()
    img = Image.open(still).convert("RGB")
    img = img.resize((1280, 720), Image.LANCZOS)
    # Darken the lower half so the text is readable over any photo.
    ov = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(ov)
    for y in range(340, 720):
        d.line([(0, y), (1280, y)], fill=int(200 * (y - 340) / 380))
    img = Image.composite(Image.new("RGB", img.size, (0, 0, 0)), img, ov)

    d = ImageDraw.Draw(img)
    f1 = ImageFont.truetype(font_path, 64)
    f2 = ImageFont.truetype(font_path, 34)

    def wrap(text, font, maxw):
        words, lines, cur = text.split(" "), [], ""
        for w in words:
            t = (cur + " " + w).strip()
            if d.textlength(t, font=font) <= maxw:
                cur = t
            else:
                lines.append(cur)
                cur = w
        if cur:
            lines.append(cur)
        return lines[:3]

    y = 470
    for line in wrap(title, f1, 1160):
        d.text((60, y), line, font=f1, fill=(255, 245, 225),
               stroke_width=3, stroke_fill=(20, 12, 0))
        y += 78
    if sub:
        d.text((62, y + 6), sub, font=f2, fill=(255, 214, 150),
               stroke_width=2, stroke_fill=(20, 12, 0))
    img.save(out, quality=92)
    return out
