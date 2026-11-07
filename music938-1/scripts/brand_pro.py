#!/usr/bin/env python3
"""AERIS Music identity, v3 — "Acoustic & Breeze", still the same channel.

K brought a design brief from an AI YouTube consult (2026-11-07) that asked for an
indie / warm / easy-listening look with headphone-and-gear cues and an earth-pastel
palette. The outside advisors were asked before any of it was drawn (consult quorum
PASS, 4 channels / 2 vendors, `channel/BRAND-BRIEF-2026-11-07.md`) and
they were unanimous on three points, all of which are enforced here:

  1. **Evolve, do not pivot.** Keep the twilight-indigo field and the single-stroke
     mark that is both a soundwave and the letter A. A full move to a cream/earth
     palette would throw away the recognition the channel has been building since
     2026-11-02 for no gain.
  2. **Headphones are a small prop, never the icon.** The channel publishes Thai
     songs and karaoke; a headphone-led identity promises gear reviews it does not
     make and attracts viewers who leave. The gear idea lives in the banner as a
     thumbnail-sized sketch at the edge, outside the safe strip.
  3. **The safe strip carries one line of text, not four.** Only the centre
     1546x423 of a 2560x1440 banner is guaranteed visible, so it holds the mark,
     the wordmark and one Thai tagline. The posting-schedule line and any "Gadget"
     wording were cut.

What changed is warmth: the coral accent is joined by a warm cream, a muted
terracotta and a sage green; the mark is drawn bolder so it survives 88px; and the
banner gains a morning-window / breeze scene in the corners.

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

# "Acoustic & Breeze" palette. Indigo is unchanged from v2; cream/coral/sage are
# the warmth the brief asked for, kept muted so nothing looks like a tech brand.
INK = (32, 42, 70)          # #202A46 twilight indigo — the field, unchanged
INK_DEEP = (18, 24, 42)     # #12182A deeper field for the vignette
CREAM = (244, 235, 221)     # #F4EBDD warm cream — text and light
CORAL = (217, 130, 112)     # #D98270 muted coral — the one accent stroke
SAGE = (168, 180, 161)      # #A8B4A1 sage — secondary detail
SILVER = (216, 220, 226)    # #D8DCE2 soft silver — thin rules only
TERRACOTTA = (197, 138, 104)  # #C58A68 wood / desk props

BRAND = "AERIS MUSIC"
TAGLINE = "เพลงไทยฟังสบาย · คาราโอเกะ"
SUB = "เพลงอบอุ่น ฟังแล้วใจนุ่ม"

# The strip of a 2560x1440 banner that every surface shows (1546x423). Nothing
# readable may be drawn outside it; the advisors were explicit that the corners
# are for scenery only.
SAFE_STRIP = (507, 509, 2053, 932)


def _font(path: str, size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default(size)


def _field(size: tuple[int, int], top=(46, 42, 72), bottom=INK_DEEP) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size, INK)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        # Ease the blend so the light gathers at the top, like a window.
        tt = t * t * (3 - 2 * t)
        row = tuple(int(top[i] + (bottom[i] - top[i]) * tt) for i in range(3))
        for x in range(w):
            px[x, y] = row
    return img


def _vignette(img: Image.Image, strength: float = 0.45) -> None:
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-w * 0.25, -h * 0.35, w * 1.25, h * 1.35], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
    dark = Image.new("RGB", (w, h), INK_DEEP)
    img.paste(Image.composite(img, dark, mask), (0, 0))
    # A soft light bloom near the top so the field reads "morning", not "night".
    bloom = Image.new("L", (w, h), 0)
    ImageDraw.Draw(bloom).ellipse(
        [w * 0.18, -h * 0.30, w * 0.82, h * 0.34], fill=int(90 * strength + 40))
    bloom = bloom.filter(ImageFilter.GaussianBlur(min(w, h) * 0.22))
    img.paste(Image.composite(img, Image.new("RGB", (w, h), (86, 92, 128)), bloom), (0, 0))


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


def _headphone(img: Image.Image, cx: float, cy: float, r: float,
               color=SILVER, width_frac: float = 0.020) -> None:
    """A thumbnail-sized headphone sketch — a prop, never the icon.

    The advisors' warning is the reason this is small, thin and pushed to the
    banner's edge: a large headphone says "gear review channel", which this is
    not. It is a cue that the songs are made to be listened to, no more.
    """
    w, h = img.size
    lw = max(2, int(min(w, h) * width_frac))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # The headband: a half circle over the ear cups.
    d.arc([cx - r, cy - r, cx + r, cy + r], start=185, end=355,
          fill=color + (200,), width=lw)
    # The two ear cups.
    for sx in (-1, 1):
        ex = cx + sx * r * 0.96
        d.rounded_rectangle([ex - r * 0.22, cy + r * 0.10,
                             ex + r * 0.22, cy + r * 0.78],
                            radius=r * 0.16, outline=color + (200,), width=lw)
    img.alpha_composite(layer)


def _window_light(img: Image.Image, x: float, y: float, w: float, h: float,
                  color=CREAM) -> None:
    """A morning-window frame with light spilling out of it, at the banner edge.

    Drawn as a warm glow *behind* a brighter frame. A bare outline disappeared
    once the vignette was applied — it read as one stray vertical line — so the
    pane is filled first and the frame is drawn at a higher alpha on top.
    """
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle([x, y, x + w, y + h], radius=w * 0.05,
                                           fill=(255, 232, 196, 64))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.10)))

    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([x, y, x + w, y + h], radius=w * 0.05,
                        outline=color + (185,), width=max(2, int(w * 0.020)))
    d.line([(x + w / 2, y), (x + w / 2, y + h)], fill=color + (150,),
           width=max(2, int(w * 0.014)))
    d.line([(x, y + h * 0.42), (x + w, y + h * 0.42)], fill=color + (150,),
           width=max(2, int(w * 0.014)))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(1.2)))


def _breeze(img: Image.Image, pts: list[tuple[float, float, float, float]],
            color=SILVER) -> None:
    """The air of AERIS: thin, blurred sine lines that never sit behind the text."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k, (x0, y0, x1, amp) in enumerate(pts):
        line = []
        for i in range(121):
            t = i / 120
            line.append((x0 + (x1 - x0) * t, y0 + math.sin(t * math.pi * 2.2) * amp))
        d.line(line, fill=color + (70 - k * 12,), width=3)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(1.6)))


def make_avatar(size: int = 800) -> Path:
    """The mark alone. Seen at 88px, so: no text, no headphone, no thin ring."""
    img = _field((size, size), top=(48, 58, 92), bottom=INK_DEEP).convert("RGBA")
    _vignette(img, 0.34)
    _breeze(img, [(size * 0.06, size * 0.22, size * 0.94, size * 0.035),
                  (size * 0.10, size * 0.80, size * 0.90, size * 0.030)])
    # Bolder than v2 on purpose: the advisors said the mark must hold at 88px.
    _soundwave_A(img, size * 0.5, size * 0.56, size * 0.33,
                 color=CREAM, width_frac=0.075)
    out = ROOT / "channel" / "avatar-pro-800x800.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def make_youtube_banner(size: tuple[int, int] = (2560, 1440)) -> Path:
    w, h = size
    img = _field(size, top=(44, 54, 88)).convert("RGBA")
    _vignette(img, 0.46)

    # Scenery lives outside the safe strip: a window at the left, breeze lines
    # across the top and bottom, and a small gear sketch at the right.
    _window_light(img, w * 0.055, h * 0.17, w * 0.135, h * 0.40)
    _breeze(img, [(w * 0.03, h * 0.13, w * 0.97, h * 0.030),
                  (w * 0.05, h * 0.86, w * 0.95, h * 0.034),
                  (w * 0.10, h * 0.94, w * 0.90, h * 0.024)])
    _headphone(img, w * 0.905, h * 0.30, min(w, h) * 0.052, color=SAGE)
    # A coffee cup beside the headphones — the brief's desk, kept to one prop.
    cup = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dc = ImageDraw.Draw(cup)
    cx, cy, cr = w * 0.905, h * 0.77, min(w, h) * 0.046
    dc.rounded_rectangle([cx - cr, cy - cr * 0.62, cx + cr, cy + cr * 0.92],
                         radius=cr * 0.24, outline=TERRACOTTA + (230,),
                         width=max(3, int(cr * 0.16)))
    dc.arc([cx + cr * 0.62, cy - cr * 0.42, cx + cr * 1.72, cy + cr * 0.68],
           start=285, end=75, fill=TERRACOTTA + (230,),
           width=max(3, int(cr * 0.16)))
    # Two thin steam curls so the cup reads as hot, not as a stray box.
    for k, dx in enumerate((-0.35, 0.30)):
        steam = []
        for i in range(41):
            t = i / 40
            steam.append((cx + dx * cr + math.sin(t * math.pi * 2.1) * cr * 0.16,
                          cy - cr * 0.78 - t * cr * 1.05))
        dc.line(steam, fill=SILVER + (150 - k * 40,), width=max(2, int(cr * 0.10)))
    img.alpha_composite(cup)

    draw = ImageDraw.Draw(img)
    word = _font(LATIN_FONT, 132, bold=True)
    tag = _font(THAI_FONT, 56, bold=True)
    sub = _font(THAI_FONT, 38)

    def center(text, font, y, fill, shadow=True):
        tw = draw.textlength(text, font=font)
        x = (w - tw) / 2
        if shadow:
            draw.text((x + 3, y + 3), text, font=font, fill=(0, 0, 0, 150))
        draw.text((x, y), text, font=font, fill=fill)

    # Everything readable inside the safe strip (y 509..931): mark, wordmark,
    # one Thai tagline. The posting-schedule line was cut, per the advisors.
    _soundwave_A(img, w * 0.5, 588, 64, color=CORAL, width_frac=0.05)
    center(BRAND, word, 606, CREAM + (255,))
    draw.line([(w * 0.5 - 250, 756), (w * 0.5 + 250, 756)], fill=CORAL + (210,), width=3)
    center(TAGLINE, tag, 768, CREAM + (238,))
    center(SUB, sub, 846, SILVER + (205,), shadow=False)

    out = ROOT / "channel" / "banner-pro-2560x1440.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def make_facebook_cover(size: tuple[int, int] = (1640, 624)) -> Path:
    """Page cover. The Page avatar sits over the lower-centre, so keep it clear."""
    w, h = size
    img = _field(size, top=(46, 56, 90)).convert("RGBA")
    _vignette(img, 0.42)
    _window_light(img, w * 0.02, h * 0.16, w * 0.11, h * 0.46)
    _breeze(img, [(w * 0.03, h * 0.12, w * 0.97, h * 0.026),
                  (w * 0.05, h * 0.88, w * 0.95, h * 0.030)])
    _headphone(img, w * 0.92, h * 0.34, min(w, h) * 0.075, color=SAGE)
    draw = ImageDraw.Draw(img)
    word = _font(LATIN_FONT, 92, bold=True)
    tag = _font(THAI_FONT, 44, bold=True)
    sub = _font(THAI_FONT, 31)
    # Left-aligned so the centre (avatar zone) stays empty.
    _soundwave_A(img, w * 0.14, h * 0.44, 68, color=CORAL, width_frac=0.07)
    draw.text((w * 0.22, h * 0.22), BRAND, font=word, fill=CREAM + (255,))
    draw.text((w * 0.22, h * 0.55), TAGLINE, font=tag, fill=CREAM + (238,))
    draw.text((w * 0.22, h * 0.74), SUB, font=sub, fill=SILVER + (205,))
    draw.line([(w * 0.22, h * 0.51), (w * 0.22 + 420, h * 0.51)],
              fill=CORAL + (205,), width=3)
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
