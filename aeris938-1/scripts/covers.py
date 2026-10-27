"""Per-story cover art.

Every story gets its own cover, and the cover must be legible at thumbnail size:
title first, then the image behind it. The title is drawn with a real Thai font
through PIL, which needs raqm for correct mark positioning; without raqm the
tone marks land in the wrong place, so that is checked rather than assumed.
"""
from __future__ import annotations

import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, features

WIDTH, HEIGHT = 1280, 720

# Fonts that ship with fonts-thai-tlwg / Noto and cover Thai properly.
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/tlwg/Loma-Bold.ttf",
    "/usr/share/fonts/truetype/tlwg/Garuda-Bold.ttf",
    "/usr/share/fonts/truetype/tlwg/Norasi-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansThai-Bold.ttf",
]


def require_thai_shaping() -> None:
    if not features.check("raqm"):
        raise RuntimeError(
            "PIL was built without raqm; Thai tone marks will be misplaced. "
            "Install libraqm and a PIL build with raqm support."
        )


def pick_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    raise FileNotFoundError("no Thai-capable font found; tried: " + ", ".join(FONT_CANDIDATES))


def _backdrop(image: Path | None) -> Image.Image:
    if image is not None and Path(image).exists():
        base = Image.open(image).convert("RGB")
        # Fill the frame, then grade: saturation up first, vignette after, or the
        # darkening drains the colour and the cover reads grey.
        ratio = max(WIDTH / base.width, HEIGHT / base.height)
        base = base.resize((int(base.width * ratio) + 1, int(base.height * ratio) + 1),
                           Image.LANCZOS)
        left = (base.width - WIDTH) // 2
        top = (base.height - HEIGHT) // 2
        base = base.crop((left, top, left + WIDTH, top + HEIGHT))
        base = ImageEnhance.Color(base).enhance(1.35)
        base = ImageEnhance.Contrast(base).enhance(1.06)
    else:
        base = Image.new("RGB", (WIDTH, HEIGHT), (18, 18, 26))

    # Bottom scrim so the title always has contrast to sit on.
    scrim = Image.new("L", (WIDTH, HEIGHT), 0)
    sd = ImageDraw.Draw(scrim)
    for y in range(int(HEIGHT * 0.42), HEIGHT):
        t = max(0.0, (y - HEIGHT * 0.42) / (HEIGHT * 0.58))
        sd.line([(0, y), (WIDTH, y)], fill=int(215 * min(1.0, t ** 1.35)))
    base = Image.composite(Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0)), base, scrim)

    # Vignette after grading.
    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse((-WIDTH * 0.25, -HEIGHT * 0.35, WIDTH * 1.25, HEIGHT * 1.35), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(120))
    return Image.composite(base, ImageEnhance.Brightness(base).enhance(0.62), mask)


def make_cover(title: str, out: Path, *, image: Path | None = None,
               subtitle: str | None = None, accent: tuple[int, int, int] = (255, 190, 60),
               ) -> dict:
    require_thai_shaping()
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas = _backdrop(image)
    draw = ImageDraw.Draw(canvas)

    title_font = pick_font(92)
    sub_font = pick_font(38)

    lines = textwrap.wrap(title, width=18) or [title]
    line_h = 108
    block_h = line_h * len(lines)
    y = HEIGHT - 70 - block_h - (56 if subtitle else 0)

    for line in lines:
        w = draw.textlength(line, font=title_font)
        x = (WIDTH - w) / 2
        draw.text((x + 3, y + 3), line, font=title_font, fill=(0, 0, 0))
        draw.text((x, y), line, font=title_font, fill=(255, 255, 255))
        y += line_h

    if subtitle:
        w = draw.textlength(subtitle, font=sub_font)
        draw.text(((WIDTH - w) / 2 + 2, y + 2), subtitle, font=sub_font, fill=(0, 0, 0))
        draw.text(((WIDTH - w) / 2, y), subtitle, font=sub_font, fill=accent)

    canvas.save(out, "PNG", optimize=True)
    if not out.exists() or out.stat().st_size == 0:
        raise RuntimeError(f"cover was not written: {out}")
    return {"cover": str(out), "bytes": out.stat().st_size,
            "size": [WIDTH, HEIGHT], "title": title,
            "has_image": image is not None and Path(image).exists()}
