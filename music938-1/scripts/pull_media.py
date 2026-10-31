#!/usr/bin/env python3
"""Restore music938-1's gitignored media from the `media-938` release assets.

A fresh pod has an empty `library/`; this pulls the songs, karaoke mixes, Shorts,
covers and thumbnails back so `release.py` can upload them. A file that is
already present with the right size is left alone, so this is cheap to re-run.

    python3 scripts/pull_media.py                 # everything missing
    python3 scripts/pull_media.py --only karaoke  # one group
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "library"
REPO = "aerismusic8-alt/aeris-drive-automation"
API = "https://api.github.com"


def group_of(name: str) -> str | None:
    """Which library subdir an asset belongs in, or None to ignore it."""
    if name.endswith(".mp3") or name.endswith(".wav"):
        return "songs"
    if name.startswith("karaoke-") and name.endswith(".mp4"):
        return "karaoke"
    if name.startswith("short-") and name.endswith(".mp4"):
        return "shorts"
    if name.startswith("cover-") and name.endswith(".jpg"):
        return "covers"
    if name.startswith("thumb-") and name.endswith(".png"):
        return "thumbs"
    return None


def token() -> str | None:
    tok = os.environ.get("AX_GH_TOKEN")
    if not tok:
        f = Path(os.environ.get("AX_GH_TOKEN_FILE", "/workspace/ax-tools/ar-identity/gh-token"))
        if f.exists():
            tok = f.read_text().strip()
    return tok or None


def assets(tok: str | None) -> list[dict]:
    out: list[dict] = []
    page = 1
    while True:
        url = f"{API}/repos/{REPO}/releases/tags/media-938"
        req = urllib.request.Request(url, headers={"User-Agent": "ax-media-pull",
                                                   "Accept": "application/vnd.github+json"})
        if tok:
            req.add_header("Authorization", f"token {tok}")
        with urllib.request.urlopen(req, timeout=60) as r:
            rid = json.load(r)["id"]
        break
    while True:
        url = f"{API}/repos/{REPO}/releases/{rid}/assets?per_page=100&page={page}"
        req = urllib.request.Request(url, headers={"User-Agent": "ax-media-pull",
                                                   "Accept": "application/vnd.github+json"})
        if tok:
            req.add_header("Authorization", f"token {tok}")
        with urllib.request.urlopen(req, timeout=60) as r:
            batch = json.load(r)
        out.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--only", help="only this group (songs, karaoke, shorts, covers, thumbs)")
    args = ap.parse_args()

    tok = token()
    got = skip = 0
    for a in assets(tok):
        g = group_of(a["name"])
        if not g or (args.only and g != args.only):
            continue
        dest = LIB / g / a["name"]
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists() and dest.stat().st_size == a["size"]:
            skip += 1
            continue
        req = urllib.request.Request(a["browser_download_url"],
                                     headers={"User-Agent": "ax-media-pull"})
        if tok:
            req.add_header("Authorization", f"token {tok}")
        with urllib.request.urlopen(req, timeout=300) as r, dest.open("wb") as fh:
            fh.write(r.read())
        got += 1
        print(f"  got {g}/{a['name']} ({a['size'] / 1e6:.1f} MB)")
    print(f"downloaded {got}, {skip} already present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
