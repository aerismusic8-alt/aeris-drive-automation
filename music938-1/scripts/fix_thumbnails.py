#!/usr/bin/env python3
"""Set the custom thumbnail on any release whose upload lost it to a quota 403.

`videos.insert` has its own 100/day bucket, but `thumbnails.set` draws on the
shared 10,000-unit Data API pool. Late in a Pacific day the pool is spent, so the
video uploads and its thumbnail request returns 403 — the video then keeps
YouTube's auto-generated frame forever. `release.py` records `thumb_ok` on each
ledger entry; this repairs the false ones once quota is fresh.

    python3 scripts/fix_thumbnails.py --dry-run
    python3 scripts/fix_thumbnails.py                 # ch3, all pending
    python3 scripts/fix_thumbnails.py --limit 3
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "ops"))
sys.path.insert(0, str(ROOT / "scripts"))

import release  # noqa: E402
import yt_auth  # noqa: E402
from yt_publish import set_thumbnail  # noqa: E402


def thumb_for(entry: dict) -> Path:
    kind, slug = entry["kind"], entry["slug"]
    names = []
    if entry.get("variant"):
        names.append(f"thumb-{entry['variant']}.png")
    names += [f"thumb-{kind}-{slug}.png", f"cover-{slug}.jpg"]
    for name in names:
        p = release.THUMBS / name
        if p.exists():
            return p
        p = release.COVERS / name
        if p.exists():
            return p
    # Not on this pod: pull it from the media release like release.py does.
    for name in names:
        try:
            got = release.fetch_media(release.THUMBS / name)
        except Exception:
            continue
        if got and got.exists():
            return got
    return None


def in_playlist(playlist_id: str, video_id: str, token: str) -> bool | None:
    """Is the video already in the playlist? None if the check itself failed.

    playlistItems.insert is not idempotent — inserting the same video twice
    leaves two identical rows — so a repair must look before it writes. The
    lookup costs 1 unit against 50 for the insert.
    """
    import urllib.error
    import urllib.parse
    import urllib.request
    q = urllib.parse.urlencode({"part": "id", "playlistId": playlist_id,
                                "videoId": video_id, "maxResults": 1})
    req = urllib.request.Request(
        f"https://www.googleapis.com/youtube/v3/playlistItems?{q}",
        headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return bool(json.load(r).get("items"))
    except urllib.error.HTTPError as e:
        print(f"playlist lookup failed: HTTP {e.code}", file=sys.stderr)
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--limit", type=int, default=0, help="stop after N repairs")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    state = release.load_state()
    # One pass, two repairs: the thumbnail and the playlist slot are both lost to
    # the same spent pool, and both cost quota, so they are done together while
    # the pool is fresh rather than in two scripts that could each be forgotten.
    todo = [e for e in state.get("released", [])
            if e.get("thumb_ok") is False or e.get("playlist_ok") is False]
    if not todo:
        print("no releases are missing a thumbnail or a playlist slot")
        return 0
    print(f"{len(todo)} release(s) need a repair")

    tok = None if args.dry_run else yt_auth.access_token(args.ch)
    fixed = 0
    for e in todo:
        if args.limit and fixed >= args.limit:
            break
        changed = False
        if e.get("thumb_ok") is False:
            path = thumb_for(e)
            if not path:
                print(f"  {e['slug']}: no thumbnail file on disk or on the release",
                      file=sys.stderr)
            elif args.dry_run:
                print(f"  would set {path.name} on {e['video_id']} ({e['slug']})")
                changed = True
            else:
                code, _ = set_thumbnail(e["video_id"], str(path), tok)
                print(f"  thumb {e['slug']} ({e['video_id']}): HTTP {code}")
                if code == 403:
                    print("quota spent; the rest waits for a fresh Pacific day")
                    break
                if code == 200:
                    e["thumb_ok"] = True
                    changed = True
        if e.get("playlist_ok") is False and not args.dry_run:
            key = f"{args.ch}:{e['kind']}"
            pid = state.get("playlists", {}).get(key)
            if not pid:
                print(f"  playlist {e['slug']}: no {key} playlist id in state",
                      file=sys.stderr)
            else:
                already = in_playlist(pid, e["video_id"], tok)
                if already:
                    e["playlist_ok"] = True
                    changed = True
                elif already is False and release.add_to_playlist(
                        pid, e["video_id"], args.ch):
                    e["playlist_ok"] = True
                    print(f"  playlist {e['slug']}: added to {pid}")
                    changed = True
        if changed:
            fixed += 1
    if not args.dry_run and fixed:
        release.save_state(state)
        print(f"{fixed} release(s) repaired and recorded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
