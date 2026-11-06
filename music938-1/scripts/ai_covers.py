#!/usr/bin/env python3
"""AI-generated cover art: Gemini paints the scene, PIL sets the Thai title.

K (2026-11-06): "ภาพปกใช้ gemini สร้างได้ไหม เขียนพรอมแล้วให้สร้างข้อความด้วย ให้มัน
ดูแปลก ดูทันสมัย ดูอลังการ" — the old covers were one deterministic gradient with a
ring motif, so every song looked like the same record.

The advisor panel's answer, and the reason this is two steps rather than one:

* Ask Gemini to *draw Thai letters* and it misspells them. The spelling is the
  one thing a cover must get right, so the title is never left to the model.
* Gemini is good at the part PIL is bad at — a strange, modern, cinematic scene.

So: Gemini renders a text-free 16:9 background from an art-direction prompt, and
Pillow composites the title in Noto Sans Thai on top. The art direction is picked
per song, so no two covers share a scene.

    python3 scripts/ai_covers.py --list                 # the art directions
    python3 scripts/ai_covers.py --only 24-yut-mai-yom  # one song
    python3 scripts/ai_covers.py --only 24-yut-mai-yom --variant 2
    python3 scripts/ai_covers.py --preview --only ...   # write to work/, keep the live cover

Gemini needs the signed-in cloud desktop (see `.agents/skills/ax-cloud-desktop`);
with no login the run stops with a login link instead of pretending to work.
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
sys.path.insert(0, str(ROOT / "scripts"))

import common  # noqa: E402
import genres  # noqa: E402

sys.path.insert(0, str(REPO / "aeris938-1" / "scripts"))
import gemini_image  # noqa: E402

LIB = ROOT / "library"
COVERS = LIB / "covers"
THUMBS = LIB / "thumbs"
WORK = ROOT / "work"
THAI_FONT = str(ROOT / "fonts" / "NotoSansThai.ttf")
LATIN_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

THUMB_W, THUMB_H = 1280, 720

# One scene per direction. Deliberately no two are the same shape of image, so a
# grid of covers reads as a set of songs rather than one record recoloured.
ART_DIRECTIONS = [
    ("portal", "a colossal portal of concentric neon rings standing in a vast "
               "mirrored salt flat at dusk, a tiny lone silhouette before it, "
               "violet and coral light, volumetric haze"),
    ("chrome", "an impossible liquid-chrome landscape with floating geometric "
               "shards and shattered-glass reflections, pastel neon sky, "
               "retro-futuristic and dreamlike"),
    ("cosmos", "an enormous ringed planet filling the sky over a dark sea, golden "
               "particles rising like fireflies, a small figure dissolving into "
               "light at the horizon, cinematic"),
    ("temple", "a floating Thai temple of white and gold drifting in a violet "
               "nebula, long light beams, volumetric fog, surreal and majestic"),
    ("bloom", "an endless field of giant glowing lotus blossoms under a turquoise "
              "aurora, minimal and calm, soft depth of field, negative space"),
    ("shards", "abstract holographic glass shards suspended in dark space, "
               "iridescent chrome and rose-gold light, high-end album art"),
    ("train", "an old night train crossing a glowing bridge toward a distant city "
              "of light in the rain, long exposure streaks, nostalgic and strange"),
    ("rain", "a rain-soaked neon alley of a future Bangkok, floating lanterns, "
             "reflections on wet stone, a distant figure under an umbrella"),
]

# The panel was unanimous that the model must not write anything, and that the
# frame needs somewhere quiet to put the title afterwards.
PROMPT_SUFFIX = (
    " | style: surreal, retro-futuristic, premium album art, cinematic lighting, "
    "ultra detailed, rich colour grading, high dynamic range, sculptural studio "
    "lighting, subtle film grain. "
    "composition: exact 16:9 widescreen; one striking central subject placed on "
    "the RIGHT third; keep the LEFT third dark, simple and uncluttered as "
    "negative space for a title; strong contrast, crisp silhouette, readable as a "
    "small thumbnail. "
    "absolutely no text, no letters, no words, no numbers, no logo, no watermark, "
    "no border."
)

BADGE = "คาราโอเกะ"
MARK = "AERIS MUSIC"


def _font(path: str, size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont:
    try:
        font = ImageFont.truetype(path, size)
    except OSError as exc:
        raise FileNotFoundError(
            f"cannot load font {path}: {exc}. Run scripts/install-thai-font.sh."
        ) from exc
    if bold:
        try:
            font.set_variation_by_name("Bold")
        except (OSError, ValueError):
            pass
    return font


def _wrap(draw: ImageDraw.ImageDraw, text: str, font, max_w: int) -> list[str]:
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


def _cover_crop(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Scale-and-centre-crop to the target aspect, never letterbox."""
    tw, th = size
    sw, sh = img.size
    scale = max(tw / sw, th / sh)
    nw, nh = round(sw * scale), round(sh * scale)
    img = img.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - tw) // 2, (nh - th) // 2
    return img.crop((left, top, left + tw, top + th))


def _grade(img: Image.Image) -> Image.Image:
    """Push contrast and depth so the frame survives being seen at 210 px wide.

    A raw model still is flat and evenly lit: fine full-screen, muddy in the
    YouTube grid. A vignette and a bottom band do the work; the band is also
    where the title goes, so the two problems are one pass.
    """
    img = img.convert("RGB")
    w, h = img.size

    band = Image.new("L", (w, h), 0)
    bd = ImageDraw.Draw(band)
    top = int(h * 0.44)
    for y in range(top, h):
        t = (y - top) / max(1, h - top)
        bd.line([(0, y), (w, y)], fill=int(205 * (t ** 1.5)))
    img = Image.composite(Image.new("RGB", (w, h), (6, 6, 14)), img, band)

    vign = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vign)
    vd.ellipse([-w * 0.28, -h * 0.34, w * 1.28, h * 1.34], fill=255)
    vign = vign.filter(ImageFilter.GaussianBlur(w * 0.10))
    img = Image.composite(img, Image.new("RGB", (w, h), (4, 4, 10)), vign)
    return img


def _glow_text(base: Image.Image, xy: tuple[int, int], text: str, font,
               fill=(255, 255, 255, 255), glow=(120, 180, 255)) -> None:
    """Draw text with an outer glow and a hard shadow, so it reads on any scene."""
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.text(xy, text, font=font, fill=(*glow, 210))
    halo = layer.filter(ImageFilter.GaussianBlur(14))
    base.alpha_composite(Image.alpha_composite(halo, halo))
    sd = ImageDraw.Draw(base)
    sd.text((xy[0] + 3, xy[1] + 3), text, font=font, fill=(0, 0, 0, 170))
    sd.text(xy, text, font=font, fill=fill)


def _compose(bg: Image.Image, title: str, *, kind: str, subtitle: str = "") -> Image.Image:
    img = _grade(_cover_crop(bg, (THUMB_W, THUMB_H))).convert("RGBA")
    w, h = img.size

    title_font = _font(THAI_FONT, int(h * 0.150), bold=True)
    sub_font = _font(THAI_FONT, int(h * 0.050))
    mark_font = _font(LATIN_FONT, int(h * 0.046))
    badge_font = _font(THAI_FONT, int(h * 0.048), bold=True)

    d = ImageDraw.Draw(img)
    d.text((w * 0.050, h * 0.070), MARK, font=mark_font, fill=(255, 255, 255, 200))

    lines = _wrap(d, title, title_font, int(w * 0.88))
    lh = int(h * 0.175)
    y = int(h * (0.50 if len(lines) <= 2 else 0.40))
    for ln in lines[:3]:
        tw = d.textlength(ln, font=title_font)
        _glow_text(img, (int((w - tw) / 2), y), ln, title_font)
        y += lh

    if subtitle:
        sw = d.textlength(subtitle, font=sub_font)
        d.text(((w - sw) / 2, y + int(h * 0.01)), subtitle, font=sub_font,
               fill=(255, 255, 255, 205))

    if kind == "karaoke":
        tw = d.textlength(BADGE, font=badge_font)
        pad = h * 0.030
        bx, by = w - tw - pad * 3, h * 0.062
        d.rounded_rectangle([bx, by, bx + tw + pad * 2, by + h * 0.105],
                            radius=int(h * 0.030), fill=(255, 255, 255, 225))
        d.text((bx + pad, by + pad * 0.45), BADGE, font=badge_font, fill=(18, 18, 28, 255))

    d.line([(w * 0.30, h * 0.885), (w * 0.70, h * 0.885)],
           fill=(255, 255, 255, 100), width=2)
    return img.convert("RGB")


def _meta(slug: str) -> dict:
    """Title / subtitle / mood / genre for a slug, from the lyric header."""
    f = ROOT / "lyrics" / f"{slug}.txt"
    hdr: dict[str, str] = {}
    if f.exists():
        for line in f.read_text(encoding="utf-8").splitlines():
            m = re.match(r"#\s*(TITLE|SUBTITLE|MOOD|GENRE)\s*:\s*(.+)", line)
            if m:
                hdr[m.group(1)] = m.group(2).strip()
                continue
            if line.strip() and not line.startswith("#"):
                break
    if "TITLE" not in hdr:
        for e in json.loads((LIB / "songs" / "manifest.json").read_text("utf-8"))["entries"]:
            if e["id"] == f"song-{slug}":
                hdr.setdefault("TITLE", e["title"])
                hdr.setdefault("MOOD", e.get("mood", "calm"))
                break
    return {"title": hdr.get("TITLE", slug), "subtitle": hdr.get("SUBTITLE", ""),
            "mood": hdr.get("MOOD", "calm"), "genre": hdr.get("GENRE", "")}


def _direction(slug: str, variant: int | None) -> tuple[str, str]:
    if variant is not None:
        return ART_DIRECTIONS[variant % len(ART_DIRECTIONS)]
    rng = random.Random(int.from_bytes(slug.encode("utf-8")[:8].ljust(8, b"\0"), "big"))
    return rng.choice(ART_DIRECTIONS)


def _prompt(slug: str, meta: dict, direction: str) -> str:
    mood = meta["mood"]
    genre = meta["genre"] or genres.palette_key(slug, mood)
    return (f"Album cover artwork for a Thai {genre} song. Mood: {mood}. "
            f"Scene: {direction}." + PROMPT_SUFFIX)


def build(slug: str, *, variant: int | None = None, preview: bool = False,
          force: bool = False) -> dict:
    meta = _meta(slug)
    name, direction = _direction(slug, variant)
    prompt = _prompt(slug, meta, direction)
    key = f"aicover-{slug}-{name}"
    # One still per fresh conversation: a single long Gemini chat slows down
    # enough by the tenth image that the render misses its timeout.
    res = gemini_image.generate(prompt, key, suffix="", force=force,
                                fresh=True, timeout=600.0)
    # library.add records a path relative to the aeris938-1 tree.
    png = REPO / "aeris938-1" / res["entry"]["file"]

    bg = Image.open(png)
    if preview:
        out = WORK / f"ai-cover-{slug}-{name}.jpg"
        _compose(bg, meta["title"], kind="song", subtitle=meta["subtitle"]).save(
            out, "JPEG", quality=92, optimize=True)
        return {"status": "PREVIEW", "file": str(out), "direction": name, "prompt": prompt}

    COVERS.mkdir(parents=True, exist_ok=True)
    THUMBS.mkdir(parents=True, exist_ok=True)
    cover = COVERS / f"cover-{slug}.jpg"
    _compose(bg, meta["title"], kind="song", subtitle=meta["subtitle"]).save(
        cover, "JPEG", quality=92, optimize=True)
    for kind in ("song", "karaoke"):
        _compose(bg, meta["title"], kind=kind).save(
            THUMBS / f"thumb-{kind}-{slug}.png", "PNG", optimize=True)
    return {"status": "CREATED", "cover": str(cover), "direction": name,
            "title": meta["title"], "prompt": prompt}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma-separated slugs")
    ap.add_argument("--all", action="store_true", help="every song in the manifest")
    ap.add_argument("--variant", type=int, default=None, help="force an art direction index")
    ap.add_argument("--preview", action="store_true", help="write to work/, keep the live cover")
    ap.add_argument("--force", action="store_true", help="regenerate even if the still exists")
    ap.add_argument("--list", action="store_true", help="show the art directions and exit")
    args = ap.parse_args()

    if args.list:
        for i, (name, text) in enumerate(ART_DIRECTIONS):
            print(f"  {i}: {name:8} {text[:72]}...")
        return 0

    if args.all:
        entries = json.loads((LIB / "songs" / "manifest.json").read_text("utf-8"))["entries"]
        slugs = [e["id"].removeprefix("song-") for e in entries]
    else:
        slugs = [s.strip() for s in args.only.split(",") if s.strip()]
    if not slugs:
        print("nothing to do: pass --only <slug> or --all", file=sys.stderr)
        return 2

    rc = 0
    for slug in slugs:
        try:
            r = build(slug, variant=args.variant, preview=args.preview, force=args.force)
            print(f"  {slug}: {r['status']} [{r['direction']}] -> "
                  f"{r.get('file') or r.get('cover')}")
        except Exception as exc:  # one bad song must not stop the batch
            print(f"  {slug}: FAILED {exc}", file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
