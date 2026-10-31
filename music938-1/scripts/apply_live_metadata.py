#!/usr/bin/env python3
"""Fix the measurable metadata defects found in the live ch3 audit (2026-10-30).

Three defects the competitor scan says cost discovery:

  * four older uploads carry **zero tags** (music search has nothing to match on)
  * those same uploads sit in category 22 (People & Blogs); music belongs in 10
  * several titles still end in `| AERIS Music`, the shape the losing clips use
    (38.9% of sub-1k titles vs 8.0% of 100k+ titles)

Reads every upload, prints a dry-run diff, and writes only with --apply. Current
values are saved to work/live-metadata-backup.json (merged, never overwritten) so
every change is reversible. Idempotent: a second run changes nothing.
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
MUSIC_CATEGORY = "10"
BRAND = re.compile(r"\s*\|\s*AERIS Music\s*$", re.IGNORECASE)

BASE_TAGS = ["เพลงไทย", "เพลงใหม่", "ศิลปินไทย", "AERIS", "เพลงเพราะ",
             "เพลงฟังสบาย", "thai music", "thai song"]
ARTIST_TAGS = ["NAVIYA", "เพลงอินดี้", "indie pop", "เพลงป็อป"]


def clean_title(t: str) -> str:
    t = BRAND.sub("", t).strip()
    t = re.sub(r"\s{2,}", " ", t)
    if len(t) <= MAX_TITLE:
        return t
    cut = t[:MAX_TITLE]
    if " " in cut:
        cut = cut[: cut.rfind(" ")]
    return cut.rstrip(" -|—")


def wanted_tags(sn: dict, existing: list[str]) -> list[str]:
    """Fill a thin tag list without ever dropping a tag the uploader chose."""
    if len(existing) >= 6:
        return existing
    text = (sn["title"] + " " + sn.get("description", "")).lower()
    pool = list(existing)
    for t in BASE_TAGS + ARTIST_TAGS:
        if t.lower() in text or t.lower() in [x.lower() for x in pool]:
            if t not in pool:
                pool.append(t)
    for t in BASE_TAGS:
        if len(pool) >= 12:
            break
        if t not in pool:
            pool.append(t)
    return pool[:30]


def main() -> int:
    apply = "--apply" in sys.argv
    tok = yt_auth.access_token("ch3")
    ids = yt_auth.all_upload_ids(tok)
    st, body = yt_auth.api_get(
        "videos", tok, part="snippet,status", id=",".join(ids)
    )
    items = body.get("items", [])

    backup = {}
    if BACKUP.exists():
        for row in json.loads(BACKUP.read_text()):
            backup[row["id"]] = row
    changes = 0
    for v in items:
        sn = v["snippet"]
        old_tags = sn.get("tags", [])
        new_tags = wanted_tags(sn, old_tags)
        new_title = clean_title(sn["title"])
        old_cat = sn.get("categoryId", "")
        new_cat = MUSIC_CATEGORY if old_cat in ("22", "24", "27", "") else old_cat

        if new_title == sn["title"] and new_tags == old_tags and new_cat == old_cat:
            continue

        changes += 1
        backup.setdefault(v["id"], {
            "id": v["id"], "title": sn["title"],
            "description": sn.get("description", ""),
            "tags": old_tags, "categoryId": old_cat,
        })
        print(f"{v['id']}  {sn['title'][:46]}")
        if new_title != sn["title"]:
            print(f"   title: {len(sn['title'])} -> {len(new_title)} chars")
        if new_cat != old_cat:
            print(f"   category: {old_cat} -> {new_cat}")
        if new_tags != old_tags:
            print(f"   tags: {len(old_tags)} -> {len(new_tags)}")

        if apply:
            st, r = yt_auth.api_request(
                "videos", tok,
                {"id": v["id"], "snippet": {
                    "title": new_title,
                    "description": sn.get("description", ""),
                    "tags": new_tags,
                    "categoryId": new_cat,
                    "defaultLanguage": sn.get("defaultLanguage", "th"),
                }},
                part="snippet",
            )
            print(f"   -> HTTP {st}" + ("" if st == 200 else f" {r}"))

    if apply and changes:
        BACKUP.write_text(json.dumps(list(backup.values()), ensure_ascii=False, indent=1))
        print(f"\nbackup -> {BACKUP}")
    print(f"\n{changes} video(s) {'updated' if apply else 'would change'} of {len(items)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
