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
import time
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
    # Affiliate product cards are also `short-*`, so they must be tested before
    # the plain Shorts rule or they land in shorts/ and the rail never posts them.
    if name.startswith("short-aff-") and name.endswith(".mp4"):
        return "affiliate"
    if name.startswith("short-") and name.endswith(".mp4"):
        return "shorts"
    # The absurdist "exhibit" clips (K's FB/TK rebrand) live in their own group,
    # not shorts/, so the surreal lane and the song rail never cross.
    if name.startswith("surreal-") and name.endswith(".mp4"):
        return "surreal"
    # The live-concert takes (K's "เสียงแสดงสด" lane) also get their own group,
    # so a fresh pod can pull them back and the crosspost rail has a file to post.
    if name.startswith("concert-") and name.endswith(".mp4"):
        return "concert"
    # The six real-instrument mood clips. Without this the clips never come back
    # on a fresh pod, so `make_mood_short --once` re-renders all six every run
    # and the crosspost rail has no file to post.
    if name.startswith("mood-") and name.endswith(".mp4"):
        return "moods"
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


def _get(url: str, tok: str | None, *, accept: str, timeout: int,
         attempts: int = 4) -> bytes:
    """GET with a retry, for the endpoints that hiccup under load.

    `browser_download_url` 302-redirects to a separate CDN host that returns
    transient 504s, and the release API itself can 502/503. A single blip used
    to abort the whole pull (2026-11-09: a 504 on the first asset failed the
    compilation run before a single song was fetched). Retry the transient
    statuses only; a 4xx is real and returns at once.
    """
    last: Exception | None = None
    for attempt in range(attempts):
        req = urllib.request.Request(url, headers={"User-Agent": "ax-media-pull",
                                                   "Accept": accept})
        if tok:
            req.add_header("Authorization", f"token {tok}")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as exc:
            last = exc
            if exc.code not in (429, 500, 502, 503, 504) or attempt == attempts - 1:
                raise
            time.sleep(2 * (attempt + 1))
        except (urllib.error.URLError, TimeoutError) as exc:
            last = exc
            if attempt == attempts - 1:
                raise
            time.sleep(2 * (attempt + 1))
    raise last  # type: ignore[misc]


def assets(tok: str | None) -> list[dict]:
    out: list[dict] = []
    page = 1
    rid = json.loads(_get(f"{API}/repos/{REPO}/releases/tags/media-938", tok,
                          accept="application/vnd.github+json", timeout=60))["id"]
    while True:
        batch = json.loads(_get(
            f"{API}/repos/{REPO}/releases/{rid}/assets?per_page=100&page={page}",
            tok, accept="application/vnd.github+json", timeout=60))
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
        # Fetch through the release-asset API, not `browser_download_url`: the
        # latter 302-redirects to a CDN host that returns transient 504s under
        # load, which is what failed the 2026-11-09 compilation run.
        blob = _get(f"{API}/repos/{REPO}/releases/assets/{a['id']}", tok,
                    accept="application/octet-stream", timeout=300)
        dest.write_bytes(blob)
        got += 1
        print(f"  got {g}/{a['name']} ({a['size'] / 1e6:.1f} MB)")
    print(f"downloaded {got}, {skip} already present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
