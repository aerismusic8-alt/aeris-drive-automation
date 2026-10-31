#!/usr/bin/env python3
"""Push music938-1's gitignored media to a GitHub Release as durable storage.

The songs, karaoke mixes, Shorts, covers and thumbnails are hundreds of MB and
stay out of git on purpose, so a recycled pod starts with an empty `library/`.
The release assets are what a fresh pod pulls from, which is what lets the daily
release automation keep the channel active without the original build host.

A file whose name is already an asset is skipped, so re-running a batch is cheap
and an interrupted upload resumes. The GitHub token is read from `AX_GH_TOKEN`
or a file, never hard-coded.

    python3 scripts/publish_media.py --dry-run
    python3 scripts/publish_media.py                 # upload what is missing
    python3 scripts/publish_media.py --release media-938
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

# Every gitignored media directory that a fresh pod needs to release a song.
# Order matters only for the progress printout.
SOURCES = [
    ("songs", "*.mp3"),
    ("songs", "*.wav"),
    ("karaoke", "*.mp4"),
    ("shorts", "*.mp4"),
    ("covers", "*.jpg"),
    ("thumbs", "*.png"),
]


def token() -> str:
    tok = os.environ.get("AX_GH_TOKEN")
    if not tok:
        f = Path(os.environ.get("AX_GH_TOKEN_FILE", "/workspace/ax-tools/ar-identity/gh-token"))
        if f.exists():
            tok = f.read_text().strip()
    if not tok:
        raise SystemExit("no AX_GH_TOKEN (and no token file). Set the secret or pass --token-file.")
    return tok


def api(path: str, tok: str, method="GET", data=None, raw=None, ctype="application/json"):
    url = path if path.startswith("http") else API + path
    body = raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
    req = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": f"token {tok}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "ax-media-publish",
        "Content-Type": ctype,
    })
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:300]}


def release_id(tag: str, tok: str) -> int:
    st, rel = api(f"/repos/{REPO}/releases/tags/{tag}", tok)
    if st != 200:
        st, rel = api(f"/repos/{REPO}/releases", tok, "POST", {
            "tag_name": tag,
            "name": "AERIS Music — media (song/karaoke/cover masters)",
            "body": "Durable media store for music938-1. Gitignored build output "
                    "lives here so a fresh pod can pull it.",
            "draft": False, "prerelease": False,
        })
        if st not in (200, 201):
            raise SystemExit(f"cannot create release {tag}: {st} {rel}")
    return rel["id"]


def existing_assets(rid: int, tok: str) -> dict[str, int]:
    out: dict[str, int] = {}
    page = 1
    while True:
        st, assets = api(f"/repos/{REPO}/releases/{rid}/assets?per_page=100&page={page}", tok)
        if st != 200 or not assets:
            break
        for a in assets:
            out[a["name"]] = a["size"]
        if len(assets) < 100:
            break
        page += 1
    return out


def wanted() -> list[Path]:
    files: list[Path] = []
    for sub, pat in SOURCES:
        files.extend(sorted((LIB / sub).glob(pat)))
    return files


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--release", default="media-938")
    ap.add_argument("--token-file", help="file holding the GitHub token")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if args.token_file:
        os.environ["AX_GH_TOKEN_FILE"] = args.token_file

    files = wanted()
    total = sum(f.stat().st_size for f in files)
    print(f"{len(files)} media files, {total / 1e6:.1f} MB")
    if args.dry_run:
        for f in files:
            print(f"  {f.relative_to(LIB)}  {f.stat().st_size / 1e6:.1f} MB")
        return 0

    tok = token()
    rid = release_id(args.release, tok)
    have = existing_assets(rid, tok)
    print(f"release {args.release} id={rid}, {len(have)} assets already there")

    up = skip = 0
    for f in files:
        size = f.stat().st_size
        if have.get(f.name) == size:
            skip += 1
            continue
        st, res = api(
            f"https://uploads.github.com/repos/{REPO}/releases/{rid}/assets?name={f.name}",
            tok, "POST", raw=f.read_bytes(), ctype="application/octet-stream")
        if st in (200, 201):
            up += 1
            print(f"  up {f.name} ({size / 1e6:.1f} MB)")
        else:
            print(f"  FAIL {f.name}: {st} {res}", file=sys.stderr)
    print(f"uploaded {up}, skipped {skip} already present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
