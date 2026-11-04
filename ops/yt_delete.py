#!/usr/bin/env python3
"""Delete uploads on a channel by id (or by a title substring), dry-run first.

Deletion is irreversible, so this prints what it will remove and only acts with
`--yes`. It is the one-off tool for pulling the karaoke videos off the channel;
day-to-day publishing never deletes.

    python3 ops/yt_delete.py ch3 --match คาราโอเกะ          # dry run
    python3 ops/yt_delete.py ch3 --match คาราโอเกะ --yes    # delete
    python3 ops/yt_delete.py ch3 --id jgBTOGWyBp8 --yes
"""
from __future__ import annotations

import argparse
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yt_auth  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ch")
    ap.add_argument("--match", help="delete uploads whose title contains this")
    ap.add_argument("--id", action="append", default=[], help="delete this video id")
    ap.add_argument("--yes", action="store_true", help="actually delete")
    a = ap.parse_args()

    tok = yt_auth.access_token(a.ch)
    targets = list(a.id)
    if a.match:
        ids = yt_auth.all_upload_ids(tok)
        for i in range(0, len(ids), 50):
            st, body = yt_auth.api_get("videos", tok, part="snippet",
                                       id=",".join(ids[i:i + 50]))
            for v in body.get("items", []):
                if a.match in v["snippet"]["title"]:
                    targets.append(v["id"])

    if not targets:
        print("nothing matched")
        return 0
    for vid in targets:
        print(f"{'DELETE' if a.yes else 'would delete'} {vid}  https://youtu.be/{vid}")
    if not a.yes:
        print(f"\n{len(targets)} video(s); re-run with --yes to delete")
        return 0

    for vid in targets:
        # DELETE must carry no body here: the sandbox proxy rejects a DELETE with
        # one, and yt_auth.api_request always sends a JSON payload.
        req = urllib.request.Request(
            f"{yt_auth.API}/videos?id={vid}",
            headers={"Authorization": f"Bearer {tok}"}, method="DELETE")
        try:
            with urllib.request.urlopen(req, timeout=60) as f:
                ok = f.status == 204
                body = ""
        except urllib.error.HTTPError as e:
            ok, body = False, f"{e.code} {e.read().decode(errors='replace')[:160]}"
        print(f"{'deleted' if ok else 'FAILED'} {vid}" + ("" if ok else f" {body}"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
