"""Generate the AERIS Music channel identity: banner and avatar.

Both frames reuse the cover-art helpers in `covers.py` (gradient, blobs, a warm
highlight, a deep vignette) so the channel reads as one brand rather than a
song cover next to an unrelated logo.

Two layout facts decide the geometry:

- The YouTube banner is 2560x1440 but only a **1546x423** strip in the centre is
  guaranteed visible on every surface. Everything that must be read lives inside
  that strip; the rest is background.
- The avatar is displayed as small as **88x88**, so it carries a monogram, not a
  sentence.

Run: python3 scripts/brand.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from common import LIBRARY, ROOT
from covers import (
    LATIN_FONT,
    THAI_FONT,
    _blobs,
    _font,
    _gradient,
    _highlight,
    _hsv_rgb,
    _vignette,
)

import random

BANNER_SIZE = (2560, 1440)
SAFE_W, SAFE_H = 1546, 423
AVATAR_SIZE = (800, 800)

BRAND = "AERIS MUSIC"
TAGLINE = "เพลงไทยป็อป · แดนซ์ · ร็อก"
SUB = "ศิลปินทีละคน ปล่อยเป็นชุด ฟังได้ทุกวัน"


def _ring(img: Image.Image, cx: float, cy: float, r: float, alpha: int, width: int) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, alpha), width=width)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(1.2)))


def _centered(draw: ImageDraw.ImageDraw, text: str, font, y: int, w: int,
              fill, shadow: bool = True) -> None:
    tw = draw.textlength(text, font=font)
    x = (w - tw) / 2
    if shadow:
        draw.text((x + 3, y + 3), text, font=font, fill=(0, 0, 0, 150))
    draw.text((x, y), text, font=font, fill=fill)


def make_banner(size: tuple[int, int] = BANNER_SIZE) -> Path:
    w, h = size
    rng = random.Random(938)
    # Deep indigo -> near-black, the same family as the "sad"/"mystic" covers.
    img = _gradient(size, _hsv_rgb(248, 0.62, 0.42), _hsv_rgb(268, 0.55, 0.10)).convert("RGBA")
    _blobs(img, rng, 252, n=9)
    _ring(img, w * 0.5, h * 0.5, w * 0.30, 22, 3)
    _ring(img, w * 0.5, h * 0.5, w * 0.24, 14, 2)
    _highlight(img, w * 0.50, h * 0.34, w * 0.46, 0.72)
    _vignette(img, 0.50)

    draw = ImageDraw.Draw(img)
    cy = h * 0.5
    word_font = _font(LATIN_FONT, 168, bold=True)
    tag_font = _font(THAI_FONT, 60, bold=True)
    sub_font = _font(THAI_FONT, 38)

    # Wordmark with letter spacing, centred on the safe strip.
    y_word = int(cy - 205)
    _centered(draw, BRAND, word_font, y_word, w, (255, 255, 255, 255))

    rule_y = int(cy + 5)
    draw.line([(w * 0.5 - 260, rule_y), (w * 0.5 + 260, rule_y)], fill=(255, 255, 255, 110), width=3)
    _centered(draw, TAGLINE, tag_font, int(cy + 32), w, (255, 255, 255, 235))
    _centered(draw, SUB, sub_font, int(cy + 112), w, (235, 232, 255, 200), shadow=False)

    # Small label, kept inside the safe strip (which ends at y = 931).
    label_font = _font(LATIN_FONT, 28)
    _centered(draw, "MUSIC938  ·  @aerismusicth", label_font, int(cy + 172), w,
              (220, 216, 255, 170), shadow=False)

    out = ROOT / "channel" / "banner-2560x1440.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def make_avatar(size: tuple[int, int] = AVATAR_SIZE) -> Path:
    w, h = size
    rng = random.Random(44)
    img = _gradient(size, _hsv_rgb(252, 0.66, 0.60), _hsv_rgb(272, 0.60, 0.14)).convert("RGBA")
    _blobs(img, rng, 256, n=6)
    _ring(img, w * 0.5, h * 0.5, w * 0.42, 40, max(3, int(w * 0.012)))
    _highlight(img, w * 0.42, h * 0.32, w * 0.52, 0.78)
    _vignette(img, 0.42)

    draw = ImageDraw.Draw(img)
    # A single letter is what survives an 88x88 render.
    mono_font = _font(LATIN_FONT, int(w * 0.62), bold=True)
    tw = draw.textlength("A", font=mono_font)
    x = (w - tw) / 2
    y = int(h * 0.13)
    draw.text((x + 5, y + 5), "A", font=mono_font, fill=(0, 0, 0, 160))
    draw.text((x, y), "A", font=mono_font, fill=(255, 255, 255, 255))

    # A small note, so the monogram reads as music, not a name initial.
    note = "♪"
    nf = _font(LATIN_FONT, int(w * 0.20), bold=True)
    nw = draw.textlength(note, font=nf)
    draw.text(((w - nw) / 2 + w * 0.30, int(h * 0.60)), note, font=nf, fill=(255, 226, 150, 235))

    name_font = _font(LATIN_FONT, int(w * 0.115), bold=True)
    _centered(draw, "AERIS", name_font, int(h * 0.76), w, (255, 255, 255, 235))

    out = ROOT / "channel" / "avatar-800x800.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def make_compilation_thumb(size: tuple[int, int] = (1280, 720)) -> Path:
    """A 16:9 thumbnail for the long compilation.

    YouTube renders the player at 16:9, so a square cover would be pillarboxed.
    The text is the title's selling point - the number of songs and the
    "listen to what you like" promise - set large enough to read at 168px.
    """
    w, h = size
    rng = random.Random(9381)
    img = _gradient(size, _hsv_rgb(258, 0.62, 0.46), _hsv_rgb(280, 0.58, 0.10)).convert("RGBA")
    _blobs(img, rng, 262, n=7)
    _highlight(img, w * 0.5, h * 0.34, w * 0.6, 0.72)
    _vignette(img, 0.5)

    draw = ImageDraw.Draw(img)
    big = _font(THAI_FONT, 118, bold=True)
    mid = _font(THAI_FONT, 64, bold=True)
    small = _font(THAI_FONT, 46)

    def center(text, font, y, fill, shadow=True):
        tw = draw.textlength(text, font=font)
        x = (w - tw) / 2
        if shadow:
            draw.text((x + 4, y + 4), text, font=font, fill=(0, 0, 0, 160))
        draw.text((x, y), text, font=font, fill=fill)

    center("รวมเพลงไทย", big, int(h * 0.20), (255, 255, 255, 255))
    center("ป็อป · แดนซ์ · ร็อก", mid, int(h * 0.50), (255, 226, 150, 245))
    center("เลือกเพลงฟังได้ · 57 นาที", small, int(h * 0.68), (238, 235, 255, 225), shadow=False)
    center("AERIS MUSIC", _font(LATIN_FONT, 34, bold=True), int(h * 0.85),
           (220, 216, 255, 190), shadow=False)

    out = ROOT / "library" / "thumbs" / "thumb-compilation.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def main() -> int:
    b = make_banner()
    a = make_avatar()
    t = make_compilation_thumb()
    print("banner:", b)
    print("avatar:", a)
    print("compilation thumb:", t)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
