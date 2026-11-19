#!/usr/bin/env python3
"""Vertical 9:16 stills for a clip, drawn by our own code instead of the network.

K (2026-11-19): "มีวัตถุดิบแล้วก็ทำคลิปต่อเลย งานสร้างภาพก็ทำสะสมไว้ในคลังเรื่อยๆ"
— the material is there, so make the clips; keep the art accumulating.

The blocker was `make_short.vertical_art`, which asked pollinations for twelve
stills per song. The free tier allows one image per 45 s per IP and answers a
burst with 402, and the fetch retries eight times with a 180 s timeout, so one
song could sit there for hours without printing a line. Measured on this pod:
the import succeeds, then the first request never returns.

`ops/genart.py` already draws real pictures from numpy with no model and no key.
At 1080x1920 it costs warp 0.7 s, tiles 0.2 s, flow 0.9 s, attr 6 s — so twelve
stills are seconds, not hours, and they are ours to license.

    python3 ops/clip_art.py --slug 44-party-khuen-ni-mai-yut-v44 --mood epic
    python3 ops/clip_art.py --list
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))

import genart  # noqa: E402

W, H = 1080, 1920

# One palette per mood, so a sad song is not painted in ember and a party is not
# painted in ash. `covers.PALETTES` is the authority on which moods exist; these
# are the genart ramps closest to each of them.
MOOD_PALETTE = {
    "sad": "dusk",
    "calm": "tide",
    "warm": "ember",
    "hopeful": "moss",
    "mystic": "orchid",
    "epic": "brass",
}
DEFAULT_PALETTE = "ash"

# `react` is excluded on purpose: it measures 53 s at this size, so twelve stills
# would cost ten minutes for a picture the other four draw in a second. It stays
# available for the print library, where the resolution is worth the wait.
CLIP_ALGOS = ("warp", "flow", "attr", "tiles")

# A still below this is a smear, not a picture. The print gate in genart asks
# for 1600 px because a print is inspected at arm's length; a phone frame is
# 1080 wide by definition, so the tonal floor is what carries over.
MIN_STD = 8.0
MIN_ENTROPY = 2.0
# Every construction measures 47-138 mean channel spread in this palette family;
# a grey frame lands under 1. A palette that genuinely wants to be monochrome
# does not exist here, so a low spread is a defect rather than a choice.
MIN_SAT = 20.0


def _seed(slug: str, i: int) -> int:
    """Deterministic per (song, index), so a re-render reproduces the clip.

    A hash rather than a counter: two songs must not walk the same sequence, and
    a re-run of one song must not depend on what was rendered before it.
    """
    h = hashlib.sha256(f"{slug}:{i}".encode()).digest()
    return 1000 + int.from_bytes(h[:4], "big") % 90000


def palette_for(mood: str | None) -> str:
    return MOOD_PALETTE.get((mood or "").lower(), DEFAULT_PALETTE)


def _gate(img: Image.Image) -> tuple[bool, str]:
    """Is this a usable 9:16 frame? Size, tone and colour all have to hold.

    The size check is not pedantry. The library already held pollinations files
    under these exact names, and they are 1024x576 — landscape. A cached-file
    path that only asked `exists()` accepted one and the clip was built from a
    sideways frame with the wrong palette; the eye reads that as "the art broke",
    not as "an old file was reused".
    """
    import numpy as np

    if img.size != (W, H):
        return False, f"{img.size[0]}x{img.size[1]} is not {W}x{H}"
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    sat = float((rgb.max(axis=2) - rgb.min(axis=2)).mean())
    if sat < MIN_SAT:
        return False, f"washed out (saturation {sat:.1f})"
    a = np.asarray(img.convert("L"), dtype=np.float32)
    n = a.size
    mean = float(a.mean())
    std = float(a.std())
    if std < MIN_STD:
        return False, f"flat (luma std {std:.1f})"
    hist = np.bincount(a.astype(np.uint8).ravel(), minlength=256).astype(np.float64)
    prob = hist[hist > 0] / n
    ent = float(-(prob * np.log2(prob)).sum())
    if ent < MIN_ENTROPY:
        return False, f"too few tones (entropy {ent:.2f})"
    return True, f"std {std:.1f} entropy {ent:.2f}"


def stills(slug: str, mood: str | None, count: int, out_dir: Path,
           log=print) -> list[Path]:
    """`count` distinct 9:16 stills for this song, drawn locally.

    Each index gets its own algorithm, palette-adjacent seed and a retry, so a
    collapsed draw is replaced rather than shipped. A still that fails twice is
    dropped; the caller gets fewer pictures, never a bad one.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    palette = palette_for(mood)
    got: list[Path] = []
    for i in range(count):
        p = out_dir / f"vert-{slug}-{i}.jpg"
        if p.exists():
            ok, _ = _gate(Image.open(p))
            if ok:
                got.append(p)
                continue
            p.unlink()
        for attempt in range(3):
            algo = CLIP_ALGOS[(i + attempt) % len(CLIP_ALGOS)]
            seed = _seed(slug, i + attempt * 101)
            try:
                img = genart.ALGOS[algo](W, H, seed, palette)
            except Exception as exc:  # a broken draw must not kill the render
                log(f"  [art] {algo} failed for {slug}#{i}: {exc}")
                continue
            ok, why = _gate(img)
            if not ok:
                log(f"  [art] {algo} seed {seed} rejected: {why}")
                continue
            img.convert("RGB").save(p, "JPEG", quality=92)
            got.append(p)
            break
    log(f"  [art] {len(got)}/{count} stills, palette {palette} ({mood or 'no mood'})")
    return got


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--slug")
    ap.add_argument("--mood")
    ap.add_argument("--count", type=int, default=12)
    ap.add_argument("--out", default=str(ROOT / "music938-1" / "library" / "vertical"))
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    if a.list:
        print("moods -> palettes")
        for m, p in MOOD_PALETTE.items():
            print(f"  {m:8s} {p}")
        print(f"  default  {DEFAULT_PALETTE}")
        print("algos:", ", ".join(CLIP_ALGOS))
        return 0
    if not a.slug:
        ap.error("--slug is required unless --list")
    got = stills(a.slug, a.mood, a.count, Path(a.out))
    print(f"{len(got)} still(s) in {a.out}")
    return 0 if got else 1


if __name__ == "__main__":
    raise SystemExit(main())
