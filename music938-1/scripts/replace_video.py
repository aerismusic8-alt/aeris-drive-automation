#!/usr/bin/env python3
"""Replace a published video whose render was wrong.

A bad clip cannot be fixed in place: YouTube has no "swap the file" call, so the
only route is upload the corrected file, then delete the old one. The old id
keeps its views, which is why this is a deliberate two-step and not a scripted
sweep — deleting first would throw away any watch time it earned.

Order matters and is enforced here: upload and confirm the new id exists *before*
deleting the old one, so a failed upload never leaves the channel with nothing.

    python3 scripts/replace_video.py --slug 01-khon-di-thi-chak-pai \\
        --kind song --old oliw1meKfcQ            # plan
    python3 scripts/replace_video.py --slug ... --kind song --old oliw1meKfcQ --yes
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPS = ROOT.parent / "ops"
STATE = ROOT / "work" / "release-state.json"
KARAOKE = ROOT / "library" / "karaoke"
COVERS = ROOT / "library" / "covers"

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(OPS))
import release  # noqa: E402
import yt_auth  # noqa: E402


def _publish(slug: str, kind: str, ch: str, video: Path) -> str | None:
    title, desc, tags = release.describe(slug, kind)
    desc_file = ROOT / "work" / f"release-{slug}-{kind}.txt"
    tags_file = ROOT / "work" / f"release-{slug}-{kind}.tags"
    desc_file.write_text(desc, encoding="utf-8")
    tags_file.write_text(",".join(tags), encoding="utf-8")

    thumb = ROOT / "library" / "thumbs" / f"thumb-{kind}-{slug}.png"
    if not thumb.exists():
        thumb = COVERS / f"cover-{slug}.jpg"

    cmd = [sys.executable, str(OPS / "yt_publish.py"), "--ch", ch,
           "--video", str(video), "--title", title,
           "--desc-file", str(desc_file), "--tags-file", str(tags_file),
           "--category", "10", "--privacy", "public"]
    if thumb.exists():
        cmd += ["--thumb", str(thumb)]
    proc = subprocess.run(cmd, text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        return None
    m = re.search(r"video id (\S+)", proc.stdout)
    return m.group(1) if m else None


def _drop_from_playlists(old_id: str, ch: str) -> None:
    """Remove the retired id from every playlist it sits in.

    Deleting a video leaves a `Deleted video` placeholder in each playlist that
    held it, so a replacement otherwise shows the track twice, once as a hole.
    """
    import urllib.error
    import urllib.request

    import yt_auth

    def _delete(path: str, params: dict) -> int:
        # A DELETE must carry no body: api_request serialises None to the
        # literal `null`, and Google answers 400 "Root element must be a
        # message". yt_video_delete.py learned this the same way.
        url = f"{yt_auth.API}/{path}?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {tok}"}, method="DELETE")
        try:
            with urllib.request.urlopen(req, timeout=120) as f:
                return f.status
        except urllib.error.HTTPError as e:
            return e.code

    tok = yt_auth.access_token(ch)
    st, body = yt_auth.api_get("playlists", tok, part="id", mine="true",
                               maxResults=50)
    if "items" not in body:
        return
    for pl in body["items"]:
        pid = pl["id"]
        st, items = yt_auth.api_get("playlistItems", tok, part="id,contentDetails",
                                    playlistId=pid, maxResults=50)
        for it in items.get("items", []):
            if it["contentDetails"]["videoId"] != old_id:
                continue
            st = _delete("playlistItems", {"id": it["id"]})
            print(f"  playlist {pid}: removed placeholder (HTTP {st})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--slug", required=True)
    ap.add_argument("--kind", required=True, choices=["song", "karaoke"])
    ap.add_argument("--old", required=True, help="the published id to retire")
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--yes", action="store_true", help="actually upload and delete")
    args = ap.parse_args()

    video = KARAOKE / f"{args.kind}-{args.slug}.mp4"
    if not video.exists():
        print(f"missing {video}; render it first", file=sys.stderr)
        return 2

    state = release.load_state()
    used = release.uploads_today(state)
    if used >= release.UPLOADS_PER_DAY:
        print(f"quota spent: {used}/{release.UPLOADS_PER_DAY} today. "
              f"A replace needs a free upload slot.", file=sys.stderr)
        return 3

    print(f"replace {args.kind} {args.slug}\n  old id  {args.old}\n"
          f"  new file {video} ({video.stat().st_size // 1024} KiB)\n"
          f"  quota   {used}/{release.UPLOADS_PER_DAY} used")
    if not args.yes:
        print("\ndry run — pass --yes to upload, then delete the old id")
        return 0

    new_id = _publish(args.slug, args.kind, args.ch, video)
    if not new_id:
        print("upload failed; the old video is untouched", file=sys.stderr)
        return 1
    print(f"uploaded {new_id}")

    # Only now is it safe to drop the old copy.
    proc = subprocess.run(
        [sys.executable, str(OPS / "yt_video_delete.py"), "apply", args.ch,
         args.old, "--yes", "--force"],
        text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        print(f"warning: {args.old} still published; delete it by hand",
              file=sys.stderr)

    state = release.load_state()
    # A replacement is a new video id, so the playlist still holds the retired
    # one. Re-add, or the catalogue silently loses the track.
    pid = release.ensure_playlist(state, args.kind, args.ch)
    if pid:
        release.add_to_playlist(pid, new_id, args.ch)
    _drop_from_playlists(args.old, args.ch)
    # A replacement spends an upload slot like any other, so it is appended
    # rather than folded into the old row: uploads_today() counts rows, and
    # editing the old `at` in place would hide the slot from the quota guard.
    for r in state["released"]:
        if r.get("video_id") == args.old:
            r["retired_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    state["released"].append({
        "slug": args.slug, "kind": args.kind, "variant": "",
        "video_id": new_id,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "public": True, "replaces": args.old,
    })
    release.save_state(state)
    print(f"ledger updated: {args.old} retired, {new_id} recorded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
