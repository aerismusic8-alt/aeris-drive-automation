#!/usr/bin/env python3
"""Append the monetization block to every live upload that lacks it.

`release.py` adds the Shopee/social footer to *new* uploads, but the 20 videos
that went up before the affiliate link existed have no footer, so the link
reaches nobody. This walks the uploads playlist and patches each description.

Idempotent: a description that already carries the affiliate link is skipped, so
a second run changes nothing. Writes only with --apply; the current values are
saved to work/monetize-backup.json (merged, never overwritten) so it is
reversible.

Usage:
  python3 scripts/apply_monetize.py            # dry run, print the diff
  python3 scripts/apply_monetize.py --apply    # write
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "ops"))
sys.path.insert(0, str(ROOT / "scripts"))

import monetize  # noqa: E402
import yt_auth  # noqa: E402

CHANNEL = "ch3"
CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"
BACKUP = ROOT / "work" / "monetize-backup.json"
MAX_DESC = 4900


def upload_ids(token: str) -> list[str]:
    _, ch = yt_auth._request(
        f"https://www.googleapis.com/youtube/v3/channels?part=contentDetails&id={CHANNEL_ID}",
        headers={"Authorization": f"Bearer {token}"})
    uploads = ch["items"][0]["contentDetails"]["relatedPlaylists"]["uploads"]
    ids, page = [], None
    while True:
        url = ("https://www.googleapis.com/youtube/v3/playlistItems"
               f"?part=snippet&playlistId={uploads}&maxResults=50")
        if page:
            url += f"&pageToken={page}"
        _, pl = yt_auth._request(url, headers={"Authorization": f"Bearer {token}"})
        ids += [i["snippet"]["resourceId"]["videoId"] for i in pl["items"]]
        page = pl.get("nextPageToken")
        if not page:
            return ids


def playlist_ids(token: str) -> list[str]:
    """Only the channel's own playlists are editable; Liked/Uploads are not."""
    ids, page = [], None
    while True:
        url = ("https://www.googleapis.com/youtube/v3/playlists?part=id"
               f"&channelId={CHANNEL_ID}&maxResults=50")
        if page:
            url += f"&pageToken={page}"
        _, r = yt_auth._request(url, headers={"Authorization": f"Bearer {token}"})
        ids += [it["id"] for it in r["items"]]
        page = r.get("nextPageToken")
        if not page:
            return ids


def patch_playlists(token: str, link: str, block: str, apply: bool) -> int:
    """The three channel playlists are a discovery surface with no footer."""
    ids = playlist_ids(token)
    _, r = yt_auth._request(
        "https://www.googleapis.com/youtube/v3/playlists?part=snippet&id=" + ",".join(ids),
        headers={"Authorization": f"Bearer {token}"})
    changed = 0
    for it in r["items"]:
        sn = it["snippet"]
        desc = sn.get("description", "")
        if link and link in desc:
            continue
        print(f"  + playlist {it['id']}  {sn['title'][:48]}")
        changed += 1
        if not apply:
            continue
        sn["description"] = (desc.rstrip() + "\n" + block)[:4900]
        code, resp = yt_auth._request(
            "https://www.googleapis.com/youtube/v3/playlists?part=snippet",
            data=json.dumps({"id": it["id"], "snippet": sn}, ensure_ascii=False).encode("utf-8"),
            headers={"Authorization": f"Bearer {token}",
                     "Content-Type": "application/json; charset=UTF-8"},
            method="PUT")
        if code != 200:
            print(f"    FAILED {code}: {str(resp)[:160]}")
    return changed


def main() -> int:
    apply = "--apply" in sys.argv
    token = yt_auth.access_token(CHANNEL)
    ids = upload_ids(token)
    print(f"{len(ids)} uploads on the channel")

    backup: dict = {}
    if BACKUP.exists():
        backup = json.loads(BACKUP.read_text(encoding="utf-8"))

    link = monetize.link("youtube")
    block = monetize.block("song")
    if not block.strip():
        raise SystemExit("no monetization links configured — nothing to add")

    changed = skipped = 0
    for i in range(0, len(ids), 50):
        batch = ids[i:i + 50]
        _, v = yt_auth._request(
            "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=" + ",".join(batch),
            headers={"Authorization": f"Bearer {token}"})
        for it in v["items"]:
            sn = it["snippet"]
            desc = sn.get("description", "")
            if link and link in desc:
                skipped += 1
                continue
            new = (desc.rstrip() + "\n" + block)[:MAX_DESC]
            print(f"  + {it['id']}  {sn['title'][:48]}")
            changed += 1
            if not apply:
                continue
            backup.setdefault(it["id"], {"description": desc})
            sn["description"] = new
            code, resp = yt_auth._request(
                "https://www.googleapis.com/youtube/v3/videos?part=snippet",
                data=json.dumps({"id": it["id"], "snippet": sn},
                                ensure_ascii=False).encode("utf-8"),
                headers={"Authorization": f"Bearer {token}",
                         "Content-Type": "application/json; charset=UTF-8"},
                method="PUT")
            if code != 200:
                print(f"    FAILED {code}: {str(resp)[:160]}")

    if apply:
        BACKUP.parent.mkdir(parents=True, exist_ok=True)
        BACKUP.write_text(json.dumps(backup, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"backup -> {BACKUP} ({len(backup)} entries)")
    print(f"{changed} to update, {skipped} already carry the link"
          + ("" if apply else "  (dry run — pass --apply)"))

    print("playlists:")
    pl = patch_playlists(token, link, block, apply)
    print(f"{pl} playlist(s) to update")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
