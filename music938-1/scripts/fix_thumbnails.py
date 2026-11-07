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
import base64
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "ops"))
sys.path.insert(0, str(ROOT / "scripts"))

import release  # noqa: E402
import yt_auth  # noqa: E402
import yt_quota  # noqa: E402
from yt_publish import set_thumbnail  # noqa: E402

LEDGER = "music938-1/work/release-state.json"


def write_ledger(content: bytes) -> bool:
    """Write the ledger back to the repository through the Contents API.

    This step cannot lean on `daily_release.py` to do it: on a day whose upload
    slots are already spent, `release.py` returns 3 and the driver returns before
    its own write-back, so a repair recorded only in the working copy would be
    lost at the end of the job — and the same videos would be "repaired" again
    every run.
    """
    import base64 as _b64
    import daily_release  # the Contents API helper, and the token

    tok = daily_release.token()
    st, cur = daily_release.api(f"/repos/{daily_release.REPO}/contents/{LEDGER}", tok)
    sha = cur.get("sha") if st == 200 else None
    # Skip a no-op write. A run that repaired nothing (the pool was spent, so the
    # repair never ran) would otherwise add an empty "repairs" commit to main on
    # every tick — real history noise with nothing in it.
    if sha and cur.get("content"):
        try:
            if _b64.b64decode(cur["content"]) == content:
                print(f"{LEDGER} unchanged; no commit")
                return True
        except Exception:  # noqa: BLE001
            pass
    body = {"message": "release: ledger after thumbnail/playlist repairs",
            "content": base64.b64encode(content).decode(), "branch": "main"}
    if sha:
        body["sha"] = sha
    st, res = daily_release.api(f"/repos/{daily_release.REPO}/contents/{LEDGER}",
                                tok, "PUT", body)
    print(f"{LEDGER} write: {st}")
    return st in (200, 201)


def thumb_for(entry: dict) -> Path:
    kind, slug = entry["kind"], entry["slug"]
    names = []
    if entry.get("variant"):
        names.append(f"thumb-{entry['variant']}.png")
    names.append(f"thumb-{kind}-{slug}.png")
    if kind == "short":
        # A Short's vertical art is stored under the song slug, not the variant:
        # `thumb-short-song-<slug>.png` is the base frame the variants derive
        # from, and it is what the upload used before the variants existed.
        names.append(f"thumb-short-song-{slug}.png")
    else:
        # The square cover is the last resort for a song or karaoke, whose art is
        # 16:9. It is deliberately NOT a Short fallback: a square image on a
        # vertical Short is the wrong shape, so a Short with no vertical art is
        # reported as missing instead of being quietly given a cover.
        names.append(f"cover-{slug}.jpg")
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

    # Price the repair against the shared pool first, exactly as the release does.
    # A repair is 50 units for the thumbnail plus 50 for the playlist slot per
    # video, and it is the highest-value use of the pool: it fixes content that is
    # already live and already earning nothing. If the pool cannot cover the whole
    # backlog, repair what it can and leave the rest for tomorrow rather than
    # failing halfway on a 403.
    need_each = yt_quota.UNITS_PER_RELEASE
    if not args.dry_run:
        room = yt_quota.remaining() // need_each
        if room < len(todo):
            print(f"pool has room for {room} of {len(todo)} repair(s) today; "
                  f"the rest waits for the next Pacific day")
            todo = todo[:room]

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
                yt_quota.record("thumbnails.set")
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
                yt_quota.record("playlistItems.list")
                if already:
                    e["playlist_ok"] = True
                    changed = True
                elif already is False and release.add_to_playlist(
                        pid, e["video_id"], args.ch):
                    yt_quota.record("playlistItems.insert")
                    e["playlist_ok"] = True
                    print(f"  playlist {e['slug']}: added to {pid}")
                    changed = True
        if changed:
            fixed += 1
    if not args.dry_run and fixed:
        release.save_state(state)
        # Push the repaired ledger back so the next run does not repeat this.
        if os.environ.get("AX_GH_TOKEN"):
            write_ledger(release.STATE.read_bytes())
        print(f"{fixed} release(s) repaired and recorded")
    if not args.dry_run:
        yt_quota.commit("quota: repair run")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
