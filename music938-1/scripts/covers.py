"""Generate cover art for a song with PIL.

A cover is deterministic: the same slug and mood always produce the same image,
so a re-render can be compared against the recorded hash. The palette is chosen
from the song's mood, and the title is set in Noto Sans Thai.
"""
from __future__ import annotations

import colorsys
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from common import LIBRARY

THAI_FONT = "/usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf"
THAI_FONT_BOLD = "/usr/share/fonts/truetype/noto/NotoSansThai-Bold.ttf"
LATIN_FONT = "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"

# Mood -> (hue, saturation, value) anchors for the background gradient.
PALETTES = {
    "sad":     ((222, 0.55, 0.30), (268, 0.45, 0.16)),
    "calm":    ((200, 0.50, 0.34), (232, 0.40, 0.18)),
    "warm":    ((24, 0.62, 0.46), (344, 0.48, 0.22)),
    "hopeful": ((46, 0.58, 0.52), (168, 0.42, 0.24)),
    "mystic":  ((276, 0.55, 0.30), (196, 0.50, 0.16)),
    "epic":    ((12, 0.60, 0.40), (300, 0.50, 0.18)),
}


def _font(path: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def _hsv_rgb(h: float, s: float, v: float) -> tuple[int, int, int]:
    r, g, b = colorsys.hsv_to_rgb((h % 360) / 360.0, s, v)
    return int(r * 255), int(g * 255), int(b * 255)


def _gradient(size: tuple[int, int], c1: tuple[int, int, int],
              c2: tuple[int, int, int]) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        # Ease the blend so the light stays near the top.
        t = t * t
        row = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row
    return img


def _blobs(img: Image.Image, rng: random.Random, hue: float, n: int = 7) -> None:
    """Soft coloured circles, blurred, for depth behind the text."""
    w, h = img.size
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(n):
        cx = rng.uniform(0, w)
        cy = rng.uniform(0, h)
        r = rng.uniform(w * 0.10, w * 0.30)
        hh = (hue + rng.uniform(-40, 40)) % 360
        col = _hsv_rgb(hh, 0.55, rng.uniform(0.5, 0.85))
        a = rng.randint(30, 80)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (a,))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=w * 0.05))
    img.alpha_composite(layer)


def _vignette(img: Image.Image, strength: float = 0.55) -> None:
    w, h = img.size
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-w * 0.2, -h * 0.3, w * 1.2, h * 1.3], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=w * 0.12))
    dark = Image.new("RGBA", img.size, (0, 0, 0, int(255 * strength)))
    dark.putalpha(Image.composite(
        Image.new("L", img.size, 0), Image.new("L", img.size, int(255 * strength)),
        mask))
    img.alpha_composite(dark)


def _wrap(draw: ImageDraw.ImageDraw, text: str, font, max_w: int) -> list[str]:
    """Wrap Thai text on spaces, falling back to a hard break for long runs."""
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=font) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    out: list[str] = []
    for ln in lines:
        while draw.textlength(ln, font=font) > max_w and len(ln) > 1:
            cut = len(ln)
            while cut > 1 and draw.textlength(ln[:cut], font=font) > max_w:
                cut -= 1
            out.append(ln[:cut])
            ln = ln[cut:]
        out.append(ln)
    return out


def make_thumbnail(slug: str, title: str, mood: str, *, kind: str = "song",
                   size: tuple[int, int] = (1280, 720)) -> Path:
    """A 16:9 thumbnail for a video.

    YouTube renders thumbnails at 16:9, so the square cover gets pillarboxed and
    loses the sides of the frame. This lays the title out for that frame, adds
    the artist mark, and badges a karaoke cut so the two videos are told apart at
    a glance in the grid.
    """
    mood = mood if mood in PALETTES else "calm"
    rng = random.Random(int.from_bytes(slug.encode("utf-8")[:8].ljust(8, b"\0"), "big"))
    (h1, s1, v1), (h2, s2, v2) = PALETTES[mood]

    img = _gradient(size, _hsv_rgb(h1, s1, v1), _hsv_rgb(h2, s2, v2)).convert("RGBA")
    _blobs(img, rng, h1)

    w, h = size
    ring = Image.new("RGBA", size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    cx, cy = w * rng.uniform(0.60, 0.80), h * 0.42
    for i, rr in enumerate((0.62, 0.50, 0.38)):
        r = h * rr
        rd.ellipse([cx - r, cy - r, cx + r, cy + r],
                   outline=(255, 255, 255, 30 - i * 7), width=max(2, int(h * 0.006)))
    img.alpha_composite(ring.filter(ImageFilter.GaussianBlur(1.5)))
    _vignette(img, 0.52)

    draw = ImageDraw.Draw(img)
    title_font = _font(THAI_FONT_BOLD, int(h * 0.135))
    sub_font = _font(THAI_FONT, int(h * 0.058))
    mark_font = _font(LATIN_FONT, int(h * 0.048))
    badge_font = _font(THAI_FONT_BOLD, int(h * 0.050))

    # Artist mark, top-left, inside the safe area.
    draw.text((w * 0.055, h * 0.075), "AERIS MUSIC", font=mark_font,
              fill=(255, 255, 255, 190))

    lines = _wrap(draw, title, title_font, int(w * 0.86))
    lh = int(h * 0.165)
    y = int(h * 0.40)
    for ln in lines[:3]:
        tw = draw.textlength(ln, font=title_font)
        x = (w - tw) / 2
        draw.text((x + 3, y + 3), ln, font=title_font, fill=(0, 0, 0, 160))
        draw.text((x, y), ln, font=title_font, fill=(255, 255, 255, 255))
        y += lh

    if kind == "karaoke":
        label = "คาราโอเกะ"
        tw = draw.textlength(label, font=badge_font)
        pad = h * 0.030
        bx, by = w - tw - pad * 3, h * 0.065
        draw.rounded_rectangle([bx, by, bx + tw + pad * 2, by + h * 0.105],
                               radius=int(h * 0.030), fill=(255, 255, 255, 220))
        draw.text((bx + pad, by + pad * 0.45), label, font=badge_font,
                  fill=(20, 20, 30, 255))

    draw.line([(w * 0.30, h * 0.855), (w * 0.70, h * 0.855)],
              fill=(255, 255, 255, 95), width=2)
    out = LIBRARY / "thumbs" / f"thumb-{kind}-{slug}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


def main() -> int:
    """Build a cover and both thumbnails for every lyric file."""
    import argparse
    import re as _re
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", default="", help="comma-separated slugs")
    args = ap.parse_args()
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    lyrics = Path(__file__).resolve().parent.parent / "lyrics"
    made = 0
    for f in sorted(lyrics.glob("*.txt")):
        slug = f.stem
        if only and slug not in only:
            continue
        hdr = {}
        for line in f.read_text(encoding="utf-8").splitlines():
            m = _re.match(r"#\s*(TITLE|SUBTITLE|MOOD)\s*:\s*(.+)", line)
            if m:
                hdr[m.group(1)] = m.group(2).strip()
                continue
            if line.strip() and not line.startswith("#"):
                break
        title, mood = hdr.get("TITLE", slug), hdr.get("MOOD", "calm")
        png = make_cover(slug, title, hdr.get("SUBTITLE", ""), mood)
        Image.open(png).convert("RGB").save(png.with_suffix(".jpg"),
                                            "JPEG", quality=92, optimize=True)
        png.unlink()
        make_thumbnail(slug, title, mood, kind="song")
        make_thumbnail(slug, title, mood, kind="karaoke")
        made += 1
        print(f"  {slug}: {title}")
    print(f"built covers + thumbnails for {made} song(s)")
    return 0


def make_cover(slug: str, title: str, subtitle: str, mood: str,
               size: tuple[int, int] = (1280, 1280)) -> Path:
    mood = mood if mood in PALETTES else "calm"
    rng = random.Random(int.from_bytes(slug.encode("utf-8")[:8].ljust(8, b"\0"), "big"))
    (h1, s1, v1), (h2, s2, v2) = PALETTES[mood]

    img = _gradient(size, _hsv_rgb(h1, s1, v1), _hsv_rgb(h2, s2, v2)).convert("RGBA")
    _blobs(img, rng, h1)

    # A ring motif, offset by the seed, ties the covers into a set.
    w, h = size
    ring = Image.new("RGBA", size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    cx = w * rng.uniform(0.30, 0.70)
    cy = h * rng.uniform(0.28, 0.44)
    for i, rr in enumerate((0.42, 0.34, 0.26)):
        r = w * rr
        rd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 26 - i * 6),
                   width=max(2, int(w * 0.004)))
    img.alpha_composite(ring.filter(ImageFilter.GaussianBlur(1.2)))

    _vignette(img, 0.50)

    draw = ImageDraw.Draw(img)
    title_font = _font(THAI_FONT_BOLD, int(w * 0.088))
    sub_font = _font(THAI_FONT, int(w * 0.030))
    tag_font = _font(LATIN_FONT, int(w * 0.022))

    lines = _wrap(draw, title, title_font, int(w * 0.84))
    lh = int(w * 0.108)
    y = int(h * 0.60)
    for ln in lines[:3]:
        tw = draw.textlength(ln, font=title_font)
        x = (w - tw) / 2
        draw.text((x + 3, y + 3), ln, font=title_font, fill=(0, 0, 0, 150))
        draw.text((x, y), ln, font=title_font, fill=(255, 255, 255, 255))
        y += lh

    if subtitle:
        y += int(h * 0.012)
        sw = draw.textlength(subtitle, font=sub_font)
        draw.text(((w - sw) / 2, y), subtitle, font=sub_font, fill=(255, 255, 255, 210))

    # A thin rule and a small label, kept away from the safe edges.
    draw.line([(w * 0.18, h * 0.86), (w * 0.82, h * 0.86)], fill=(255, 255, 255, 90), width=2)
    tag = "MUSIC938 · THAI SONG"
    tw = draw.textlength(tag, font=tag_font)
    draw.text(((w - tw) / 2, h * 0.885), tag, font=tag_font, fill=(255, 255, 255, 150))

    out = LIBRARY / "covers" / f"cover-{slug}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "PNG", optimize=True)
    return out


if __name__ == "__main__":
    raise SystemExit(main())
