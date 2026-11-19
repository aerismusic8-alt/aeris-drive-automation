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
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "ops"))
sys.path.insert(0, str(ROOT / "scripts"))

import release  # noqa: E402
import yt_auth  # noqa: E402
import yt_quota  # noqa: E402
from yt_publish import set_thumbnail  # noqa: E402

LEDGER = "music938-1/work/release-state.json"

# YouTube's per-account thumbnail upload window is undocumented; a few
# seconds between calls keeps a backlog run under it.
THUMB_PACE_SECONDS = 3.0


def write_ledger(content: bytes) -> bool:
    """Write the ledger back to the repository through the Contents API.

    This step cannot lean on `daily_release.py` to do it: on a day whose upload
    slots are already spent, `release.py` returns 3 and the driver returns before
    its own write-back, so a repair recorded only in the working copy would be
    lost at the end of the job — and the same videos would be "repaired" again
    every run.

    Delegates to `daily_release.write_ledger`, which merges into the version on
    `main` and skips a no-op write. Writing a bare local snapshot here is what
    clobbered the 2026-11-08 release rows: the repair step's checkout predated
    the release step's own write, so its PUT dropped three just-recorded songs.
    """
    import daily_release  # the Contents API helper, the merge, and the token
    return daily_release.write_ledger(
        daily_release.token(), content,
        "release: ledger after thumbnail/playlist repairs")


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


def live_thumbnail_passes(video_id: str, path, token: str) -> bool | None:
    """Is the thumbnail already on YouTube the one we would upload, and is it good?

    The ledger records a repair only if the run reached `save_state`, so a batch
    that died mid-way leaves `thumb_ok: false` on videos whose art is already
    live. Re-uploading those spends quota and trips the per-account upload window
    for no gain. This reads the live thumbnail and runs it through the same floor
    the upload gate uses, so a stale `false` is corrected without a write.
    `None` means the check itself failed, which must never be read as "good".
    """
    import io
    import urllib.error
    import urllib.parse
    import urllib.request

    import thumb_standard
    from PIL import Image

    q = urllib.parse.urlencode({"part": "snippet", "id": video_id})
    req = urllib.request.Request(f"https://www.googleapis.com/youtube/v3/videos?{q}",
                                 headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            items = json.load(r).get("items", [])
    except urllib.error.HTTPError as e:
        print(f"live lookup failed: HTTP {e.code}", file=sys.stderr)
        return None
    if not items:
        return None
    thumbs = items[0]["snippet"]["thumbnails"]
    url = (thumbs.get("maxres") or thumbs.get("standard") or thumbs.get("high") or {}).get("url")
    if not url:
        return None
    try:
        raw = urllib.request.urlopen(url, timeout=60).read()
        live = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception:
        return None
    # The live file is what a viewer sees, so gate that file rather than our local
    # copy: a bad upload must not be mistaken for a good one.
    tmp = Path(f"/tmp/live-{video_id}.jpg")
    try:
        live.save(tmp, "JPEG", quality=95)
        thumb_standard.assert_ok(str(tmp))
    except SystemExit:
        return False
    finally:
        tmp.unlink(missing_ok=True)

    # Passing the floor only proves it is a good frame; compare it to the art we
    # intended, or YouTube's auto frame would also pass on a busy video.
    if not path or not Path(path).exists():
        return None
    mine = Image.open(path).convert("RGB").resize(live.size)
    a, b = live.tobytes()[::97], mine.tobytes()[::97]
    diff = sum(abs(x - y) for x, y in zip(a, b)) / max(1, len(a))
    return diff < 12


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--limit", type=int, default=0, help="stop after N repairs")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--reconcile", action="store_true",
                    help="record repairs already live on YouTube instead of uploading")
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
    need_each = 1 if args.reconcile else yt_quota.UNITS_PER_RELEASE
    if not args.dry_run:
        room = yt_quota.remaining() // need_each
        if room < len(todo):
            print(f"pool has room for {room} of {len(todo)} repair(s) today; "
                  f"the rest waits for the next Pacific day")
            todo = todo[:room]

    tok = None if args.dry_run else yt_auth.access_token(args.ch)
    fixed = 0
    state_dirty = False
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
            elif args.reconcile:
                live = live_thumbnail_passes(e["video_id"], path, tok)
                if live:
                    print(f"  {e['slug']}: already live and passing, recorded")
                    e["thumb_ok"] = True
                    changed = True
                elif live is False:
                    print(f"  {e['slug']}: live thumbnail still needs a repair")
                else:
                    print(f"  {e['slug']}: could not read the live thumbnail, left pending",
                          file=sys.stderr)
            else:
                try:
                    code, _ = set_thumbnail(e["video_id"], str(path), tok)
                except SystemExit as exc:
                    # A thumbnail below the floor is a per-asset problem. Letting it
                    # escape aborts the run before save_state, which throws away the
                    # repairs already made (and re-spends quota on them next time).
                    print(f"  {e['slug']}: skipped, {exc}", file=sys.stderr)
                    yt_quota.record("thumbnails.set")
                    continue
                print(f"  thumb {e['slug']} ({e['video_id']}): HTTP {code}")
                yt_quota.record("thumbnails.set")
                if code == 403:
                    print("quota spent; the rest waits for a fresh Pacific day")
                    break
                if code == 429:
                    # Per-caller rate limit, not the quota pool: keep hammering and
                    # the limit extends. Stop and let the next run take the rest.
                    print("rate limited (429); the rest waits for the next run")
                    break
                if code == 200:
                    e["thumb_ok"] = True
                    changed = True
                    # YouTube also caps thumbnail uploads per account per window
                    # (reason `uploadRateLimitExceeded`). Pace the batch so a
                    # 21-item backlog does not trip that limit on its own.
                    time.sleep(THUMB_PACE_SECONDS)
        if e.get("playlist_ok") is False and not args.dry_run and not args.reconcile:
            key = f"{args.ch}:{e['kind']}"
            # Create the playlist if the state has no id for it. The 2026-11-09
            # affiliate uploads recorded `playlist_ok: false` because the create
            # itself was refused on a spent pool, and the id was never stored —
            # a repair that only looks up an id can then never clear those rows.
            pid = state.get("playlists", {}).get(key) \
                or release.ensure_playlist(state, e["kind"], args.ch)
            # A freshly created playlist id must be persisted even if the insert
            # below fails, or the next run creates a duplicate playlist.
            if state.get("playlists", {}).get(key):
                state_dirty = True
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
            # Record each repair as it lands: an exception later in the batch must
            # not discard repairs that already spent quota on YouTube's side.
            if not args.dry_run:
                release.save_state(state)
    if not args.dry_run and (fixed or state_dirty):
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
