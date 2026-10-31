#!/usr/bin/env python3
"""Apply the competitor-derived title/description/tag shape to live ch3 videos.

Reads current metadata, computes the improved title per the rules measured in
COMPETITOR-ANALYSIS.md (no brand suffix, <=60 chars, keep the karaoke marker),
prints a dry-run diff, and only writes when --apply is passed. Old values are
recorded to work/live-metadata-backup.json first, so every change is reversible.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ops"))
import yt_auth  # noqa: E402

WORK = Path(__file__).resolve().parent.parent / "work"
BACKUP = WORK / "live-metadata-backup.json"
MAX_TITLE = 60
BRAND = re.compile(r"\s*\|\s*AERIS Music\s*$", re.IGNORECASE)


def clean_title(t: str) -> str:
    t = BRAND.sub("", t).strip()
    t = re.sub(r"\s{2,}", " ", t)
    if len(t) <= MAX_TITLE:
        return t
    # Trim at a word boundary, never mid-word, never past a bracket marker.
    cut = t[:MAX_TITLE]
    if " " in cut:
        cut = cut[: cut.rfind(" ")]
    return cut.rstrip(" -|—")


def main() -> int:
    apply = "--apply" in sys.argv
    tok = yt_auth.access_token("ch3")
    uploads = yt_auth.uploads_playlist(tok)
    ids = yt_auth.all_upload_ids(tok)

    st, body = yt_auth.api_get(
        "videos", tok, part="snippet,status,contentDetails", id=",".join(ids)
    )
    items = body.get("items", [])
    backup = []
    changed = 0
    for v in items:
        sn = v["snippet"]
        old_title = sn["title"]
        new_title = clean_title(old_title)
        if new_title == old_title:
            continue
        changed += 1
        backup.append({"id": v["id"], "title": old_title,
                       "description": sn.get("description", ""),
                       "tags": sn.get("tags", []),
                       "categoryId": sn.get("categoryId")})
        print(f"{v['id']}\n  OLD ({len(old_title):2}): {old_title}\n"
              f"  NEW ({len(new_title):2}): {new_title}")
        if apply:
            st, r = yt_auth.api_request(
                "videos", tok,
                {"id": v["id"], "snippet": {
                    "title": new_title,
                    "description": sn.get("description", ""),
                    "tags": sn.get("tags", []),
                    "categoryId": sn.get("categoryId", "10"),
                }},
                part="snippet",
            )
            print(f"  -> HTTP {st} {'' if st == 200 else r}")

    if apply and backup:
        BACKUP.write_text(json.dumps(backup, ensure_ascii=False, indent=1))
        print(f"\nbackup -> {BACKUP}")
    print(f"\n{changed} title(s) {'updated' if apply else 'would change'}"
          f" of {len(items)} videos")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
