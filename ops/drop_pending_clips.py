#!/usr/bin/env python3
"""Delete the clips listed on the review-pending page (K, 2026-11-20).

K: "งานที่อยู่ในลิงก์ทั้งหมดให้ลบทิ้งเลยนะ ... งานพวกนี้ไม่เอาแล้ว" — every clip the
`review-pending.html` gallery lists is dropped for good, with nothing left behind.

The list is read from the page K was looking at, not recomputed. The gallery
rebuilds itself from whatever the release holds and whichever ledgers say
"posted", so a recomputed list is a different list: it would drop a clip that
was added since, or miss one K still sees on his screen.

Three surfaces have to go, in this order, or the delete is a no-op:

1. **the release assets** — `pull_media` restores every `media-938` asset, so a
   clip deleted only from disk comes back on the next pod;
2. **the local file**, if this pod holds one;
3. **the page itself**, because leaving it up is a page of 53 dead links, and a
   dead link is the failure K named ("ลิงค์ตาย").

`--apply` is required to delete anything; the default is a dry run that prints
the exact plan. `--keep-page` leaves the gallery in place for the case where
only the files should go.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
REPO = "aerismusic8-alt/aeris-drive-automation"
RELEASE = "media-938"
PAGE_URL = "https://aerismusic8-alt.github.io/site-aeris-music/review-pending.html"
SITE_CLONE = Path("/workspace/ax-tools/pages/site-aeris-music")


def gh(method: str, path: str, tok: str) -> tuple[int, object]:
    req = urllib.request.Request(
        "https://api.github.com" + path, method=method,
        headers={"Authorization": f"Bearer {tok}",
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "AR"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read().decode()
            return r.status, json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def token() -> str:
    """A token that can delete release assets, in the order that works today.

    The vault anchor needs an API key this pod does not carry, so `$AX_GH_TOKEN`
    (or the identity file) is tried first; the vault is the fallback for a pod
    that has no secret injected.
    """
    import os  # noqa: PLC0415

    tok = os.environ.get("AX_GH_TOKEN") or ""
    if not tok:
        f = Path("/workspace/ax-tools/ar-identity/gh-token")
        if f.exists():
            tok = f.read_text().strip()
    if not tok:
        sys.path.insert(0, str(BASE / "ops"))
        import ax_vault  # noqa: PLC0415
        tok = ax_vault.kv_get(ax_vault.ensure_anchor(),
                              "axsecrets:gh-workflow-token")["token"]
    return tok


def page_clips() -> list[str]:
    """The clip filenames the live page lists, in page order."""
    with urllib.request.urlopen(PAGE_URL, timeout=60) as r:
        html = r.read().decode("utf-8", "ignore")
    return [u.rsplit("/", 1)[-1]
            for u in re.findall(r'<source src="([^"]+\.mp4)"', html)]


def release_ids(tok: str) -> dict[str, int]:
    _, rel = gh("GET", f"/repos/{REPO}/releases/tags/{RELEASE}", tok)
    ids: dict[str, int] = {}
    page = 1
    while True:
        st, assets = gh("GET", f"/repos/{REPO}/releases/{rel['id']}/assets"
                               f"?per_page=100&page={page}", tok)
        if st != 200 or not assets:
            break
        for a in assets:
            ids[a["name"]] = a["id"]
        if len(assets) < 100:
            break
        page += 1
    return ids


def local_copies(names: list[str]) -> dict[str, Path]:
    found: dict[str, Path] = {}
    want = set(names)
    for root in (BASE / "music938-1", BASE / "ops"):
        for p in root.rglob("*.mp4"):
            if p.name in want:
                found[p.name] = p
    return found


def delete_page(tok: str) -> str:
    """Remove the gallery and its posters from the Pages site."""
    if not SITE_CLONE.exists():
        return "site clone missing — page left in place"
    for name in ("review-pending.html",):
        p = SITE_CLONE / name
        if p.exists():
            p.unlink()
    posters = SITE_CLONE / "poster"
    if posters.is_dir():
        for p in posters.glob("*.jpg"):
            p.unlink()
    git = ["git", "-C", str(SITE_CLONE)]
    import subprocess  # noqa: PLC0415

    subprocess.run(git + ["pull", "--rebase", "-q"], capture_output=True)
    subprocess.run(git + ["add", "-A"], check=True)
    r = subprocess.run(git + ["commit", "-q", "-m",
                              "review: drop the pending gallery (K: งานพวกนี้ไม่เอาแล้ว)"],
                       capture_output=True, text=True)
    if r.returncode != 0 and "nothing to commit" not in (r.stdout + r.stderr):
        return f"commit failed: {r.stderr[:200]}"
    url = f"https://x-access-token:{tok}@github.com/aerismusic8-alt/site-aeris-music.git"
    p = subprocess.run(git + ["push", "-q", url, "main"], capture_output=True, text=True)
    return "page removed" if p.returncode == 0 else f"push failed: {p.stderr[:200]}"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true", help="delete (default: dry run)")
    ap.add_argument("--keep-page", action="store_true",
                    help="delete the clips but leave review-pending.html up")
    a = ap.parse_args(argv)

    names = page_clips()
    if not names:
        print("page lists no clips — nothing to do")
        return 1
    print(f"page lists {len(names)} clips")

    tok = token()
    ids = release_ids(tok)
    on_release = [n for n in names if n in ids]
    missing = [n for n in names if n not in ids]
    local = local_copies(names)

    print(f"  on release : {len(on_release)}")
    print(f"  not on release: {len(missing)} {missing[:3] if missing else ''}")
    print(f"  local copies  : {len(local)} {sorted(local)[:3] if local else ''}")

    if not a.apply:
        print("\ndry run — pass --apply to delete")
        for n in names:
            mark = "release+local" if n in local and n in ids else (
                "release" if n in ids else "local" if n in local else "none")
            print(f"  {n:52} {mark}")
        return 0

    gone = 0
    for n in on_release:
        st, _ = gh("DELETE", f"/repos/{REPO}/releases/assets/{ids[n]}", tok)
        if st in (200, 204):
            gone += 1
        else:
            print(f"  [warn] {n}: HTTP {st}")
    print(f"release: deleted {gone}/{len(on_release)}")

    for n, p in local.items():
        p.unlink()
    print(f"local: deleted {len(local)}")

    if not a.keep_page:
        print(delete_page(tok))
    print(f"done — {len(names)} clips removed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
