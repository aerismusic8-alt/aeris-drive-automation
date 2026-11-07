#!/usr/bin/env python3
"""Post a top-level comment on a video as the channel owner.

**Not usable yet.** The channel tokens carry only `.../auth/youtube`, and
commentThreads.insert needs `.../auth/youtube.force-ssl`. Every call returns
HTTP 403 `ACCESS_TOKEN_SCOPE_INSUFFICIENT`. This is kept because the code is
correct and the offer it carries is the panel's #1 revenue action: the moment K
re-mints a refresh token with force-ssl, this is how the offer gets pinned under
a video. Until then the offer reaches viewers through the description, which does
work (`scripts/apply_monetize.py --apply`).

Why a comment matters: it is the one place a viewer looks after the description,
and a comment written by the channel owner carries the creator badge and sits at
the top of the thread — the closest an API-only tool gets to a pin, because
YouTube's API does not expose pinning.

    python3 ops/yt_comment.py --ch ch3 --video=-sDCGTbdFwI --text-file offer.txt

Comment insert costs 50 units of the shared 10,000-unit daily pool.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import yt_auth  # noqa: E402

API = "https://www.googleapis.com/youtube/v3/commentThreads"


def post(ch: str, video: str, text: str, token: str | None = None) -> str:
    token = token or yt_auth.access_token(ch)
    body = json.dumps({
        "snippet": {
            "videoId": video,
            "topLevelComment": {"snippet": {"textOriginal": text}},
        }
    }, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        f"{API}?part=snippet", data=body,
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "application/json; charset=UTF-8"})
    try:
        d = json.load(urllib.request.urlopen(req, timeout=60))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise SystemExit(f"comment failed: HTTP {e.code}\n{detail}") from None
    return d["id"]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ch", required=True, choices=list(yt_auth.CHANNELS))
    ap.add_argument("--video", required=True)
    ap.add_argument("--text-file", required=True)
    args = ap.parse_args()
    text = Path(args.text_file).read_text(encoding="utf-8").strip()
    cid = post(args.ch, args.video, text)
    print(f"comment id {cid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
