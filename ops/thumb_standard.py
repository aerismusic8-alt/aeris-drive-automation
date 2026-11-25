#!/usr/bin/env python3
"""The thumbnail standard — a measurable floor for channel art (K, 2026-11-17).

K: "แม้กระทั่ง thumbnail ก็ต้องให้ได้มาตรฐาน 10/10". A thumbnail is not decoration;
it is the frame that decides whether a video is opened, so it is held to a floor
like every clip. This module measures a finished thumbnail and rejects one below
it; `ops/yt_publish.py` runs it before `thumbnails.set`, so a below-floor
thumbnail cannot reach a channel.

Thresholds are calibrated from the 203 real thumbnails on disk (2026-11-17), not
invented: a good poster has a wide tonal range (p95-p5 ~100-250), real detail
(edge fraction ~1-10 %), and a bright title that occupies ~0.7-19 % of the frame.
The floor sits just under the 25th percentile, so it catches a blank or failed
render without rejecting a legitimately dark, moody poster.

Everything is free (Rule #1): Pillow + numpy only, no key, no account.

    python3 ops/thumb_standard.py <thumb.png>          # check one
    python3 ops/thumb_standard.py <thumb.png> --json
"""
from __future__ import annotations

import argparse
import json
import os
import sys

FLOOR = {
    "max_bytes": 2_000_000,      # YouTube's hard cap for a custom thumbnail
    "min_width": 1280,           # 16:9 normal-video art
    "min_width_vertical": 1080,  # 9:16 Short art (matches the Short's own frame)
    "aspect": 16 / 9,            # normal-video art; a Short uses the frame itself
    "aspect_tol": 0.02,
    "dynamic_range_min": 40,     # p95 - p5 of luma; a flat render is < 40 (a dark
                                 # but real poster keeps its title and detail)
    "detail_pct_min": 0.20,      # edge fraction %; a blank frame is < 0.1
    "bright_pct_min": 0.10,      # the title ink; 0 means no legible text (a thin
                                 # Short caption measures ~0.15%, a blank frame 0)
    "bright_pct_max": 45.0,      # all-white = a failed flood fill
    "dark_pct_max": 97.0,        # all-black = a failed render
    "bright_luma": 165,          # title ink is gold (~192) or cream, not just white
    # The picture band: the middle of the frame, between the label at the top and
    # the ask at the foot. Every statistical rule above can pass on a frame whose
    # *picture* is missing — a flat grey panel with a title and a caption has
    # range, edges and ink — so the band is measured on its own. 2026-11-25: four
    # shipped surreal covers measured luma std 0.00 here (a mathematically flat
    # picture) while the worst legitimate cover measured 7.01, so the floor sits
    # at 4.0: it catches "no picture" without touching a dark, moody poster.
    "picture_std_min": 4.0,
    # A frame that is mostly one tone, row after row, is a failed render rather
    # than a design. Broken covers measured 88 % flat rows; the flattest real one
    # measured 52 %.
    "flat_rows_pct_max": 80.0,
}

# Vertical art is allowed for Shorts (1080x1920) but must still be real.
VERTICAL_ASPECT = 9 / 16
# The picture band, as a fraction of height: below this is the label band, above
# it is the ask band (see `make_surreal_short.build_ass`).
PICTURE_BAND = (0.32, 0.68)


def _deps():
    import numpy as np
    from PIL import Image, ImageFilter
    return np, Image, ImageFilter


def measure(path: str) -> dict:
    np, Image, ImageFilter = _deps()
    im = Image.open(path)
    im.load()
    w, h = im.size
    g = im.convert("L")
    a = np.asarray(g, dtype=np.float32)
    blur = np.asarray(g.filter(ImageFilter.GaussianBlur(4)), dtype=np.float32)
    p5, p95 = float(np.percentile(a, 5)), float(np.percentile(a, 95))
    top, bot = int(h * PICTURE_BAND[0]), int(h * PICTURE_BAND[1])
    band = a[top:bot]
    return {
        "format": (im.format or "").upper(),
        "width": w,
        "height": h,
        "aspect": round(w / h, 4),
        "bytes": os.path.getsize(path),
        "dynamic_range": round(p95 - p5, 1),
        "detail_pct": round(float((np.abs(a - blur) > 45).mean()) * 100, 2),
        "bright_pct": round(float((a > FLOOR["bright_luma"]).mean()) * 100, 2),
        "dark_pct": round(float((a < 35).mean()) * 100, 2),
        "picture_std": round(float(band.std()), 2),
        "flat_rows_pct": round(float((a.std(axis=1) < 6).mean()) * 100, 1),
    }


def _aspect_ok(m: dict) -> bool:
    for want in (FLOOR["aspect"], VERTICAL_ASPECT):
        if abs(m["aspect"] - want) <= FLOOR["aspect_tol"]:
            return True
    return False


def _min_width(m: dict) -> int:
    if abs(m["aspect"] - VERTICAL_ASPECT) <= FLOOR["aspect_tol"]:
        return FLOOR["min_width_vertical"]
    return FLOOR["min_width"]


def check(path: str) -> list[tuple[str, bool, str]]:
    """Return [(name, ok, detail)]. Never raises on a bad file."""
    res: list[tuple[str, bool, str]] = []

    def add(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    try:
        m = measure(path)
    except Exception as e:  # noqa: BLE001
        add("readable image", False, str(e)[:120])
        return res
    add("readable image", True, f"{m['format']} {m['width']}x{m['height']}")

    add("is JPEG or PNG", m["format"] in ("JPEG", "PNG"), m["format"])
    add("under 2 MB", m["bytes"] <= FLOOR["max_bytes"],
        f"{m['bytes'] / 1024:.0f} KB")
    add("at least the min width", m["width"] >= _min_width(m),
        f"{m['width']} px (min {_min_width(m)})")
    add("16:9 or 9:16", _aspect_ok(m), f"aspect {m['aspect']:.3f}")
    add("wide tonal range", m["dynamic_range"] >= FLOOR["dynamic_range_min"],
        f"{m['dynamic_range']} (min {FLOOR['dynamic_range_min']})")
    add("has real detail", m["detail_pct"] >= FLOOR["detail_pct_min"],
        f"{m['detail_pct']}% edges (min {FLOOR['detail_pct_min']})")
    add("title is present", m["bright_pct"] >= FLOOR["bright_pct_min"],
        f"{m['bright_pct']}% bright (min {FLOOR['bright_pct_min']})")
    add("title is not a flood fill", m["bright_pct"] <= FLOOR["bright_pct_max"],
        f"{m['bright_pct']}% bright (max {FLOOR['bright_pct_max']})")
    add("not a black frame", m["dark_pct"] <= FLOOR["dark_pct_max"],
        f"{m['dark_pct']}% dark")
    add("the picture is really there",
        m["picture_std"] >= FLOOR["picture_std_min"],
        f"picture band std {m['picture_std']} (min {FLOOR['picture_std_min']})")
    add("not a flat panel", m["flat_rows_pct"] <= FLOOR["flat_rows_pct_max"],
        f"{m['flat_rows_pct']}% flat rows (max {FLOOR['flat_rows_pct_max']})")
    return res


def assert_ok(path: str) -> None:
    """Raise unless every rule passes. Used on the upload path."""
    failed = [n for n, ok, _ in check(path) if not ok]
    if failed:
        raise SystemExit("thumbnail below the standard: " + "; ".join(failed))


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("thumb")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    rows = check(a.thumb)
    if a.json:
        print(json.dumps([{"rule": n, "ok": ok, "detail": d} for n, ok, d in rows],
                         ensure_ascii=False, indent=2))
    else:
        for n, ok, d in rows:
            print(f"  {'ok  ' if ok else 'FAIL'} {n:26s} {d}")
    bad = [n for n, ok, _ in rows if not ok]
    print(f"\n{'PASS' if not bad else 'FAIL'} — {len(rows) - len(bad)}/{len(rows)} rules")
    return 0 if not bad else 1


if __name__ == "__main__":
    raise SystemExit(main())
