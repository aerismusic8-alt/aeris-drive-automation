#!/usr/bin/env python3
"""List every upload on a channel with its id, title and privacy, as JSON.

`yt_auth.py videos` prints a human table; this keeps the ids so a later step can
act on an exact video. Writes ops/out/<ch>-uploads.json.

    python3 ops/yt_list_videos.py ch3
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yt_auth  # noqa: E402

OUT = Path(__file__).resolve().parent / "out"


def main() -> int:
    ch = sys.argv[1] if len(sys.argv) > 1 else "ch3"
    tok = yt_auth.access_token(ch)
    ids = yt_auth.all_upload_ids(tok)
    rows = []
    for i in range(0, len(ids), 50):
        batch = ids[i:i + 50]
        st, body = yt_auth.api_get("videos", tok, part="snippet,status,statistics",
                                   id=",".join(batch))
        for v in body.get("items", []):
            sn, stt, stats = v["snippet"], v["status"], v.get("statistics", {})
            rows.append({
                "id": v["id"],
                "title": sn["title"],
                "published": sn["publishedAt"],
                "privacy": stt["privacyStatus"],
                "views": int(stats.get("viewCount", 0)),
                "url": f"https://youtu.be/{v['id']}",
            })
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{ch}-uploads.json"
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=2))
    print(f"{len(rows)} videos -> {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
