"""Generate vertical Story cards (1080x1920) for the AERIS Music pack.

A Story is the cheapest reach a channel has: it appears above the feed for 24 h
and costs one image. Each card is 9:16, carries the song title in Thai, the
hook line, and a "ฟังเต็ม" (listen in full) prompt, so a viewer knows exactly
what to do.

Two kinds are produced:

- `story-intro` — the pack announcement, one card.
- `story-<slug>` — one per song, built from the lyric header.

Run: python3 scripts/make_stories.py [--all]
"""
from __future__ import annotations

import argparse
import random
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from common import ROOT
from covers import (
    LATIN_FONT,
    THAI_FONT,
    _blobs,
    _font,
    _gradient,
    _highlight,
    _hsv_rgb,
    _vignette,
    _wrap,
)

SIZE = (1080, 1920)
LYRICS = ROOT / "lyrics"
OUT = ROOT / "library" / "stories"

MOOD_HUE = {
    "sad": 248, "calm": 208, "warm": 22, "hopeful": 46, "mystic": 274, "epic": 12,
}


def _parse_lyric(path: Path) -> dict:
    meta: dict[str, str] = {}
    hook = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"#\s*(\w+):\s*(.*)", line)
        if m:
            meta[m.group(1).upper()] = m.group(2).strip()
            continue
        s = line.strip()
        if s and not s.startswith("[") and not hook:
            hook = s
    return meta | {"hook": hook}


def _draw_story(title: str, hook: str, mood: str, kicker: str, foot: str,
                out: Path, seed: int) -> Path:
    hue = MOOD_HUE.get(mood, 250)
    rng = random.Random(seed)
    img = _gradient(SIZE, _hsv_rgb(hue, 0.60, 0.44), _hsv_rgb(hue + 18, 0.55, 0.09)).convert("RGBA")
    _blobs(img, rng, hue, n=9)
    _highlight(img, SIZE[0] * 0.5, SIZE[1] * 0.30, SIZE[0] * 0.7, 0.7)
    _vignette(img, 0.52)

    w, h = SIZE
    draw = ImageDraw.Draw(img)
    kick_font = _font(THAI_FONT, 44, bold=True)
    title_font = _font(THAI_FONT, 96, bold=True)
    hook_font = _font(THAI_FONT, 56)
    foot_font = _font(THAI_FONT, 46, bold=True)
    brand_font = _font(LATIN_FONT, 40, bold=True)

    def center(text, font, y, fill, shadow=True):
        tw = draw.textlength(text, font=font)
        x = (w - tw) / 2
        if shadow:
            draw.text((x + 4, y + 4), text, font=font, fill=(0, 0, 0, 160))
        draw.text((x, y), text, font=font, fill=fill)

    center("AERIS MUSIC", brand_font, int(h * 0.10), (255, 255, 255, 200))
    center(kicker, kick_font, int(h * 0.145), (255, 226, 150, 235))

    # Title block, wrapped and centred in the upper third.
    lines = _wrap(draw, title, title_font, int(w * 0.84))[:3]
    y = int(h * 0.30)
    for ln in lines:
        center(ln, title_font, y, (255, 255, 255, 255))
        y += int(title_font.size * 1.22)

    draw.line([(w * 0.5 - 120, y + 20), (w * 0.5 + 120, y + 20)],
              fill=(255, 255, 255, 120), width=3)
    y += 60

    if hook:
        for ln in _wrap(draw, hook, hook_font, int(w * 0.80))[:3]:
            center(ln, hook_font, y, (240, 238, 255, 225), shadow=False)
            y += int(hook_font.size * 1.25)

    # A clear call to action at the bottom, inside the safe area.
    center(foot, foot_font, int(h * 0.84), (255, 255, 255, 240))
    center("@aerismusicth", _font(LATIN_FONT, 38), int(h * 0.90), (220, 216, 255, 180), shadow=False)

    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out, "JPEG", quality=90, optimize=True)
    return out


def make_intro() -> Path:
    return _draw_story(
        title="รวมเพลงไทย 20 เพลง",
        hook="ฟังได้ทุกวัน มีคาราโอเกะให้ร้องตาม",
        mood="mystic",
        kicker="ชุดพิเศษ · ปล่อยใหม่",
        foot="กดติดตาม ฟังเต็มได้เลย 🎧",
        out=OUT / "story-intro.jpg",
        seed=938,
    )


def make_song(path: Path) -> Path:
    meta = _parse_lyric(path)
    title = meta.get("TITLE", path.stem)
    num = path.stem.split("-")[0]
    return _draw_story(
        title=title,
        hook=meta.get("hook", ""),
        mood=meta.get("MOOD", "calm"),
        kicker=f"เพลงที่ {num} · ฟังเต็มบน YouTube",
        foot="แตะเพื่อฟังเต็ม 🎵",
        out=OUT / f"story-{path.stem}.jpg",
        seed=int(num) if num.isdigit() else 1,
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="one card per song")
    args = ap.parse_args()

    made = [make_intro()]
    if args.all:
        for p in sorted(LYRICS.glob("*.txt")):
            made.append(make_song(p))
    for m in made:
        print("story:", m.name)
    print(f"{len(made)} cards -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
