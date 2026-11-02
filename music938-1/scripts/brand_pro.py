#!/usr/bin/env python3
"""Professional AERIS Music identity: avatar, YouTube banner, Facebook cover.

Direction (adopted 2026-11-02, from a Gemini design pass): "Calm Minimalist
Sanctuary" — a twilight-indigo field, one delicate soundwave that doubles as the
letter A, and a single warm-coral accent. It keeps the existing indigo family so
the channel does not change identity mid-growth, but replaces the heavy
gradient-and-blobs look with a flat, premium frame that survives being rendered
small.

Three sizes, three jobs:

* Avatar 800x800, safe inside a circle. It is shown as small as 88x88, so it
  carries the mark, not a sentence. The mark is a soundwave arch; at 88px the
  arch reads and the wordmark is dropped.
* YouTube banner 2560x1440. Only the centre 1546x423 strip is guaranteed visible
  on every surface, so every readable element lives inside it.
* Facebook Page cover 1640x624, with the lower-centre kept clear because the
  Page avatar overlaps there.

Run: python3 scripts/brand_pro.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "fonts"
THAI_FONT = str(FONTS / "NotoSansThai.ttf")
LATIN_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# "Calm Minimalist Sanctuary" palette.
INK = (30, 27, 46)          # #1E1B2E twilight indigo
INK_DEEP = (17, 15, 30)     # deeper field for vignette
SILVER = (149, 165, 166)    # #95A5A6 muted silver
FOG = (223, 230, 233)       # #DFE6E9 soft fog
CORAL = (255, 107, 107)     # #FF6B6B warm coral accent

BRAND = "AERIS MUSIC"
TAGLINE = "เพลงไทยเพื่อชีวิต · คาราโอเกะ"
SUB = "เพลงใหม่ทุกวัน · ร้องตามได้"


def _font(path: str, size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(path, size)
    if bold:
        try:
            font.set_variation_by_name("Bold")
        except (OSError, ValueError):
            pass
    return font


def _field(size: tuple[int, int], top=(46, 42, 72), bottom=INK_DEEP) -> Image.Image:
    """A quiet vertical gradient — no blobs, so the frame stays calm."""
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = (y / max(1, h - 1)) ** 0.85
        row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row
    return img


def _vignette(img: Image.Image, strength: float = 0.45) -> None:
    w, h = img.size
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse([-w * 0.25, -h * 0.35, w * 1.25, h * 1.35], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=w * 0.14))
    dark = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dark.putalpha(Image.composite(Image.new("L", img.size, 0),
                                  Image.new("L", img.size, int(255 * strength)), mask))
    img.alpha_composite(dark)


def _soundwave_A(img: Image.Image, cx: float, cy: float, r: float,
                 color=CORAL, width_frac: float = 0.055) -> None:
    """One continuous stroke: a sine arch that peaks into the apex of an 'A'.

    Drawn as a filled polygon so it scales cleanly at any size. The left leg
    rises as a sine, meets the apex, and the right leg falls, so the mark is
    both a soundwave and the letter A.
    """
    w, h = img.size
    lw = max(2, int(min(w, h) * width_frac))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 160
    pts = []
    for i in range(steps + 1):
        t = i / steps                      # 0..1 left->right
        x = cx - r + 2 * r * t
        # sine arch: 0 at the ends, 1 at the apex
        y = cy + r * 0.42 - math.sin(math.pi * t) * r * 0.92
        pts.append((x, y))
    d.line(pts, fill=color + (255,), width=lw, joint="curve")
    # The crossbar of the A, kept short so it reads as a deliberate stroke.
    y_bar = cy - r * 0.10
    d.line([(cx - r * 0.34, y_bar), (cx + r * 0.34, y_bar)],
           fill=color + (230,), width=lw)
    img.alpha_composite(layer)


def make_avatar(size: int = 800) -> Path:
    img = _field((size, size), top=(52, 47, 82), bottom=INK_DEEP).convert("RGBA")
    _vignette(img, 0.40)
    # A thin silver ring, the "sanctuary" frame.
    ring = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([size * 0.055, size * 0.055, size * 0.945, size * 0.945],
                                 outline=SILVER + (70,), width=max(2, int(size * 0.010)))
    img.alpha_composite(ring.filter(ImageFilter.GaussianBlur(1.5)))
    _soundwave_A(img, size * 0.5, size * 0.55, size * 0.30)
    out = ROOT / "channel" / "avatar-pro-800x800.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def make_youtube_banner(size: tuple[int, int] = (2560, 1440)) -> Path:
    w, h = size
    img = _field(size).convert("RGBA")
    _vignette(img, 0.50)
    # A wide, faint soundwave band behind the safe strip for texture.
    band = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(band)
    for k in range(3):
        pts = []
        for i in range(257):
            t = i / 256
            x = w * 0.08 + w * 0.84 * t
            y = h * 0.5 + math.sin(math.pi * t * (1 + k)) * h * (0.10 + k * 0.03)
            pts.append((x, y))
        d.line(pts, fill=SILVER + (30 - k * 8,), width=3)
    img.alpha_composite(band.filter(ImageFilter.GaussianBlur(2)))

    draw = ImageDraw.Draw(img)
    word = _font(LATIN_FONT, 130, bold=True)
    tag = _font(THAI_FONT, 54, bold=True)
    sub = _font(THAI_FONT, 36)
    label = _font(LATIN_FONT, 26)

    def center(text, font, y, fill, shadow=True):
        tw = draw.textlength(text, font=font)
        x = (w - tw) / 2
        if shadow:
            draw.text((x + 3, y + 3), text, font=font, fill=(0, 0, 0, 140))
        draw.text((x, y), text, font=font, fill=fill)

    # Every readable element lives inside the guaranteed-visible strip
    # (y 508..931), top to bottom: mark, wordmark, rule, tagline, sub, label.
    _soundwave_A(img, w * 0.5, 585, 62, color=CORAL, width_frac=0.05)
    center(BRAND, word, 610, (255, 255, 255, 255))
    draw.line([(w * 0.5 - 250, 752), (w * 0.5 + 250, 752)], fill=CORAL + (200,), width=3)
    center(TAGLINE, tag, 762, FOG + (235,))
    center(SUB, sub, 828, SILVER + (215,), shadow=False)
    center("MUSIC938  ·  @aerismusicth", label, 878, SILVER + (160,), shadow=False)

    out = ROOT / "channel" / "banner-pro-2560x1440.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def make_facebook_cover(size: tuple[int, int] = (1640, 624)) -> Path:
    """Page cover. The Page avatar sits over the lower-centre, so keep it clear."""
    w, h = size
    img = _field(size, top=(50, 45, 80)).convert("RGBA")
    _vignette(img, 0.42)
    draw = ImageDraw.Draw(img)
    word = _font(LATIN_FONT, 92, bold=True)
    tag = _font(THAI_FONT, 42, bold=True)
    sub = _font(THAI_FONT, 30)
    # Left-aligned so the centre (avatar zone) stays empty.
    _soundwave_A(img, w * 0.14, h * 0.44, 66, color=CORAL, width_frac=0.07)
    draw.text((w * 0.22, h * 0.24), BRAND, font=word, fill=(255, 255, 255, 255))
    draw.text((w * 0.22, h * 0.56), TAGLINE, font=tag, fill=FOG + (235,))
    draw.text((w * 0.22, h * 0.74), SUB, font=sub, fill=SILVER + (210,))
    draw.line([(w * 0.22, h * 0.52), (w * 0.22 + 420, h * 0.52)],
              fill=CORAL + (200,), width=3)
    out = ROOT / "channel" / "cover-pro-1640x624.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def main() -> int:
    for p in (make_avatar(), make_youtube_banner(), make_facebook_cover()):
        print(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
