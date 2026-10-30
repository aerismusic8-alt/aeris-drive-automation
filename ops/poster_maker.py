#!/usr/bin/env python3
"""Cinematic movie-poster covers for the AX channels.

K's brief (2026-10-24): the cover must read as a *film poster* — the reference is
a Pinterest board of Thai movie posters. Measured from 14 of those posters, the
shared shape is:

  * portrait, aspect 0.55-0.79 (median ~0.65, i.e. 2:3)
  * a dark, low-key base (brightness 39-130 of 255) with ONE warm accent
    (amber #c99a3c / gold #b6a591) or a cold teal-blue for the drama end
  * a dense text band — usually the top third — holding the Thai title
  * a vignette, film grain and a small credit line at the foot

So this tool does not draw a "thumbnail". It composes a poster: it takes a base
image (generated or supplied), grades it to that palette, lays a title block
over it, then adds vignette + grain.

Why the base image is pluggable: the free generator rail (Pollinations) is
measured-flaky — 1 success then HTTP 402 on the next few calls. A poster build
must not die because the image rail coughed, so `--base` accepts a local file
and `--procedural` synthesises a graded abstract base with no network at all.

Thai text needs Pillow built with `raqm`; without it every tone mark lands on the
wrong consonant and the cover is silently wrong. `_font()` checks and refuses.
"""
import argparse
import math
import os
import random
import subprocess
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageStat

# Display faces that actually carry Thai. Umpush/Garuda are the boldest of the
# TLWG set, so they read at thumbnail size; Kinnari is the serif for drama.
FONT_BOLD = "/usr/share/fonts/truetype/tlwg/Umpush-Bold.ttf"
FONT_BOLD_ALT = "/usr/share/fonts/truetype/tlwg/Garuda-Bold.ttf"
FONT_SERIF = "/usr/share/fonts/truetype/tlwg/Kinnari-Bold.ttf"
FONT_LIGHT = "/usr/share/fonts/truetype/tlwg/Loma.ttf"

PRESETS = {
    # name: (w, h) — thumb is YouTube's 16:9, the rest are poster portraits
    "thumb": (1280, 720),
    "poster": (1000, 1500),
    "story": (1080, 1920),
}

# Grades measured off the reference posters. `warm` is the drama/dhamma look,
# `cold` the thriller look, `noir` near-monochrome.
GRADES = {
    "warm": ((12, 7, 3), (201, 154, 60)),
    "cold": ((4, 10, 16), (90, 140, 180)),
    "noir": ((6, 6, 7), (190, 186, 180)),
    "jade": ((3, 10, 8), (120, 190, 150)),
}


def _have_raqm():
    try:
        from PIL import features
        return bool(features.check("raqm"))
    except Exception:
        return False


def _font(path, size):
    for cand in (path, FONT_BOLD, FONT_BOLD_ALT, FONT_SERIF):
        if cand and os.path.exists(cand):
            return ImageFont.truetype(cand, size)
    raise SystemExit("no usable font found")


def _fetch_base(prompt, out, w, h, seed=None, tries=6):
    """Pollinations with backoff. Returns True on a real image.

    The rail answers 200 with a JPEG, or 402/5xx with a tiny error body, so a
    plain status check is not enough — the body has to decode as an image.
    """
    import time

    for i in range(tries):
        q = urllib.parse.quote(prompt)
        url = (f"https://image.pollinations.ai/prompt/{q}"
               f"?width={w}&height={h}&model=sana&nologo=true&seed={seed or 0}")
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "AX-poster/1.0"})
            with urllib.request.urlopen(req, timeout=90) as r:
                data = r.read()
            with open(out, "wb") as f:
                f.write(data)
            Image.open(out).verify()          # a 402 body is not an image
            return True
        except Exception as e:
            print(f"  base attempt {i+1}/{tries} failed: {str(e)[:70]}")
            time.sleep(6 * (i + 1))
    return False


def _procedural_base(w, h, grade, seed=0):
    """A graded abstract background: no network, never fails.

    Built from a vertical gradient, a soft off-centre glow (the 'key light' the
    reference posters all have) and a low-frequency cloud so it does not look
    like a flat gradient. Kept deliberately dark — the reference posters sit at
    brightness 39-130 of 255, and a bright base leaves the title no contrast.
    """
    rnd = random.Random(seed)
    dark, accent = GRADES[grade]
    img = Image.new("RGB", (w, h))
    px = img.load()
    # key light sits in the upper third, off-centre, like a poster's rim light
    lx, ly = w * rnd.uniform(0.30, 0.70), h * rnd.uniform(0.20, 0.42)
    radius = max(w, h) * rnd.uniform(0.30, 0.50)
    for y in range(h):
        t = y / max(1, h - 1)
        for x in range(0, w, 2):
            d = math.hypot(x - lx, y - ly) / radius
            glow = max(0.0, 1.0 - d) ** 3.0
            base = 0.05 + 0.30 * (1 - t) ** 1.8 + glow * 0.55
            cloud = 0.05 * math.sin(x / (w * 0.13) + seed) * math.cos(y / (h * 0.11))
            k = max(0.0, min(1.2, base + cloud))
            for dx in (0, 1):
                if x + dx < w:
                    px[x + dx, y] = (
                        min(255, int(dark[0] + accent[0] * k)),
                        min(255, int(dark[1] + accent[1] * k)),
                        min(255, int(dark[2] + accent[2] * k)),
                    )
    return img.filter(ImageFilter.GaussianBlur(1.2))


def _grade(img, grade, contrast=1.32, sat=0.80):
    dark, accent = GRADES[grade]
    img = ImageEnhance.Color(img).enhance(sat)
    img = ImageEnhance.Contrast(img).enhance(contrast)
    # push toward the grade by multiplying with the accent tint
    tint = Image.new("RGB", img.size, (max(30, accent[0]), max(30, accent[1]), max(30, accent[2])))
    img = Image.blend(img, Image.blend(img, tint, 0.40), 0.45)
    # lift the shadows toward `dark` so the base never goes pure black
    shadow = Image.new("RGB", img.size, dark)
    img = Image.blend(img, Image.blend(img, shadow, 0.40), 0.38)
    return img


def _cover(img, w, h):
    """Crop-to-fill, so any base aspect lands without letterboxing."""
    sw, sh = img.size
    scale = max(w / sw, h / sh)
    img = img.resize((max(1, int(sw * scale + 0.5)), max(1, int(sh * scale + 0.5))), Image.LANCZOS)
    sw, sh = img.size
    return img.crop(((sw - w) // 2, (sh - h) // 2, (sw - w) // 2 + w, (sh - h) // 2 + h))


def _vignette(img, strength=0.72):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-w * 0.30, -h * 0.34, w * 1.30, h * 1.30), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.14))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    return Image.composite(img, Image.blend(img, dark, strength), mask)


def _grain(img, amount=7, seed=0):
    rnd = random.Random(seed)
    w, h = img.size
    n = Image.new("L", (w // 2, h // 2))
    n.putdata([128 + rnd.randint(-amount, amount) for _ in range((w // 2) * (h // 2))])
    n = n.resize((w, h), Image.BILINEAR)
    return Image.blend(img, Image.merge("RGB", (n, n, n)), 0.055)


def _fit_lines(draw, text, font_path, max_w, start_size, min_size=18):
    """Shrink until the text fits, then wrap on spaces. Thai has no spaces in
    the usual place, so wrapping also breaks on the width when a word is long."""
    size = start_size
    while size > min_size:
        f = _font(font_path, size)
        if draw.textlength(text, font=f) <= max_w:
            return [text], f
        size -= 2
    f = _font(font_path, min_size)
    words, lines, cur = text.split(), [], ""
    for wd in words:
        t = (cur + " " + wd).strip()
        if draw.textlength(t, font=f) <= max_w:
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = wd
    if cur:
        lines.append(cur)
    return (lines or [text]), f


def _shadow_text(draw, xy, text, font, fill, anchor="la", shadow=(0, 0, 0), off=3):
    x, y = xy
    draw.text((x + off, y + off), text, font=font, fill=shadow, anchor=anchor)
    draw.text((x, y), text, font=font, fill=fill, anchor=anchor)


def compose(base_path, out, title, subtitle="", kicker="", credit="", tagline="",
            preset="thumb", grade="warm", seed=0, glow_accent=True):
    w, h = PRESETS[preset]
    if base_path:
        img = Image.open(base_path).convert("RGB")
    else:
        img = _procedural_base(w, h, grade, seed)
    img = _grade(img, grade)
    img = _cover(img, w, h)
    img = _vignette(img, 0.70 if preset == "thumb" else 0.78)

    # Dark scrim behind the title block. Without it a light area of the base can
    # swallow the Thai glyphs; every reference poster has this top-third darkening.
    scrim = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(scrim)
    top = int(h * 0.02)
    bot = int(h * (0.62 if preset == "thumb" else 0.58))
    for yy in range(top, bot):
        t = (yy - top) / max(1, bot - top)
        # strongest at the top, fading out by the lower third
        sd.line((0, yy, w, yy), fill=int(170 * (1 - t) ** 1.5))
    scrim = scrim.filter(ImageFilter.GaussianBlur(h * 0.05))
    img = Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), img, scrim)

    if glow_accent:
        # a thin warm rim so the title has something to sit against
        rim = Image.new("RGB", (w, h), GRADES[grade][1])
        band = Image.new("L", (w, h), 0)
        bd = ImageDraw.Draw(band)
        y0 = int(h * (0.06 if preset == "thumb" else 0.05))
        bd.rectangle((0, y0, w, int(h * (0.40 if preset == "thumb" else 0.34))), fill=90)
        band = band.filter(ImageFilter.GaussianBlur(h * 0.05))
        img = Image.composite(rim, img, band.point(lambda v: int(v * 0.22)))
    img = _grain(img, 7, seed)

    d = ImageDraw.Draw(img, "RGBA")
    pad = int(w * 0.075)
    maxw = w - pad * 2
    portrait = preset in ("poster", "story")

    if kicker:
        kf = _font(FONT_LIGHT, max(16, int(h * (0.020 if portrait else 0.022))))
        _shadow_text(d, (w // 2, int(h * (0.055 if portrait else 0.075))),
                     kicker.upper(), kf, (232, 214, 178), anchor="ma")

    # A portrait poster breathes more than a thumbnail: the title sits lower, is
    # larger, and a tagline sits above it. A thumb has no room for that.
    tsize = int(h * (0.082 if portrait else 0.105))
    lines, tf = _fit_lines(d, title, FONT_BOLD, maxw, tsize)
    line_h = int(tf.size * 1.28)
    block_h = line_h * len(lines)

    if tagline:
        gf = _font(FONT_SERIF, max(18, int(h * (0.026 if portrait else 0.030))))
        gl, gf = _fit_lines(d, tagline, FONT_SERIF, maxw, gf.size)
        gy = int(h * (0.235 if portrait else 0.10))
        for ln in gl:
            _shadow_text(d, (w // 2, gy), ln, gf, (206, 190, 164), anchor="ma", off=3)
            gy += int(gf.size * 1.3)
        y = gy + int(h * 0.012)
    else:
        y = int(h * (0.30 if portrait else 0.17))

    for ln in lines:
        _shadow_text(d, (w // 2, y), ln, tf, (255, 244, 222), anchor="ma", off=4)
        y += line_h

    # gold rule under the title — the reference posters all separate title/body
    if subtitle:
        ry = y + int(h * 0.016)
        d.line((w * (0.26 if portrait else 0.30), ry, w * (0.74 if portrait else 0.70), ry),
               fill=(*GRADES[grade][1], 200), width=max(2, h // 380))
        sf = _font(FONT_SERIF, max(18, int(h * (0.030 if portrait else 0.038))))
        sl, sf = _fit_lines(d, subtitle, FONT_SERIF, maxw, sf.size)
        y = ry + int(h * 0.030)
        for ln in sl:
            _shadow_text(d, (w // 2, y), ln, sf, (238, 226, 205), anchor="ma", off=3)
            y += int(sf.size * 1.28)

    # Credit block. A poster carries 2-3 tiny spaced lines at the foot; a thumb
    # gets one. `credit` may be " | "-separated to build that block.
    if credit:
        cf = _font(FONT_LIGHT, max(13, int(h * (0.016 if portrait else 0.019))))
        parts = [p.strip() for p in credit.split("|") if p.strip()]
        cy = int(h * (0.895 if portrait else 0.935))
        for p in parts:
            txt = p.upper()
            # manual letter-spacing so the credit line reads as a film billing
            if portrait:
                txt = "  ".join(txt)
            _shadow_text(d, (w // 2, cy), txt, cf, (208, 194, 170), anchor="ma", off=2)
            cy += int(cf.size * 1.9)

    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    img.save(out, quality=93, subsampling=1)
    return out, img.size


def main():
    ap = argparse.ArgumentParser(description="Compose a cinematic movie-poster cover.")
    ap.add_argument("title", help="main title (Thai is fine)")
    ap.add_argument("--subtitle", default="")
    ap.add_argument("--kicker", default="", help="small line above the title")
    ap.add_argument("--tagline", default="", help="one line between kicker and title")
    ap.add_argument("--credit", default="", help="' | '-separated lines for the foot billing")
    ap.add_argument("--preset", choices=list(PRESETS), default="thumb")
    ap.add_argument("--grade", choices=list(GRADES), default="warm")
    ap.add_argument("--base", help="use this image instead of generating one")
    ap.add_argument("--prompt", help="generate a base from this prompt")
    ap.add_argument("--no-generate", action="store_true", help="procedural base only, no network")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    if not _have_raqm():
        print("WARNING: Pillow lacks raqm — Thai tone marks will be misplaced.", file=sys.stderr)

    base = a.base
    tmp = None
    if not base and a.prompt and not a.no_generate:
        tmp = "/tmp/_ax_poster_base.jpg"
        w, h = PRESETS[a.preset]
        if _fetch_base(a.prompt, tmp, w, h, seed=a.seed):
            base = tmp
        else:
            print("  image rail unavailable -> procedural base")
    path, size = compose(base, a.out, a.title, a.subtitle, a.kicker, a.credit, a.tagline,
                         a.preset, a.grade, a.seed)
    print(f"wrote {path} ({size[0]}x{size[1]}) grade={a.grade} preset={a.preset}")


if __name__ == "__main__":
    main()
