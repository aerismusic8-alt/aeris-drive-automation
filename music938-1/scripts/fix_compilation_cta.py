#!/usr/bin/env python3
"""Repair the live compilation's description when it lost the revenue ask.

The compilation is the channel's most-watched video (268 views vs a 24 median,
2026-11-09) and it is the only long-form video whose description is clickable and
above the fold. Until 2026-11-09 `compilation_description()` wrote no subscribe
and no Shopee link at all, so the one video with real reach carried no way to
convert. The advisor panel that day (duck + pollinations) put the CTA on the
existing top video first, before building anything new: it is free, it is fast,
and it tells us whether the 0-click funnel is an audience-product *fit* problem
rather than a card-count problem.

This re-reads the live description, inserts the CTA block when it is missing, and
leaves everything else — the chapter timestamps the `(เลือกเพลงฟังได้)` title
promises — untouched. Idempotent: a second run finds the ask present and writes
nothing. The previous description is saved to work/description-backup.json so the
change is reversible.

    python3 scripts/fix_compilation_cta.py           # dry run
    python3 scripts/fix_compilation_cta.py --apply   # write
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parent / "ops"))

import yt_auth  # noqa: E402
import monetize  # noqa: E402

WORK = ROOT / "work"
BACKUP = WORK / "description-backup.json"
STATE = WORK / "compilation-state-compilation.json"


def _needs_cta(desc: str) -> bool:
    """True when the description still lacks the subscribe-first ask.

    The ask's first line is the tell: `refresh_description` inserts the whole
    block at once, so its absence means the block is missing.
    """
    first = monetize.cta("youtube").splitlines()
    return bool(first) and first[0] not in desc


def _insert_cta(desc: str, cta: str) -> str:
    """Upgrade a live description with the canonical `monetize.refresh_description`.

    That function is the single description writer: it re-points the old
    homepage link, drops the superseded page-first CTA block, and inserts the
    subscribe-first ask before the fold — all idempotently. Delegating here keeps
    one writer instead of two that can drift.
    """
    return monetize.refresh_description(desc, "youtube")


def main() -> int:
    apply = "--apply" in sys.argv
    if not STATE.exists():
        print("no compilation state file — nothing to repair")
        return 0
    vid = json.loads(STATE.read_text()).get("video_id")
    if not vid:
        print("compilation state carries no video_id — nothing to repair")
        return 0

    tok = yt_auth.access_token("ch3")
    st, body = yt_auth.api_get("videos", tok, part="snippet", id=vid)
    items = body.get("items", [])
    if not items:
        print(f"video {vid} not found (HTTP {st})")
        return 1
    sn = items[0]["snippet"]
    desc = sn.get("description", "")

    if not _needs_cta(desc):
        print(f"{vid}: CTA already present — nothing to do")
        return 0

    cta = monetize.cta("youtube")
    if not cta:
        print("monetize.cta() returned nothing — not writing a partial repair")
        return 1
    new_desc = _insert_cta(desc, cta)
    print(f"{vid}  {sn['title'][:50]}")
    print(f"   description: {len(desc)} -> {len(new_desc)} chars")
    print("   --- inserted ---")
    print("   " + cta.replace("\n", "\n   "))
    if not apply:
        print("\ndry run — pass --apply to write")
        return 0

    backup = {}
    if BACKUP.exists():
        backup = {r["id"]: r for r in json.loads(BACKUP.read_text())}
    backup.setdefault(vid, {"id": vid, "description": desc,
                            "title": sn["title"]})
    st, r = yt_auth.api_request(
        "videos", tok,
        {"id": vid, "snippet": {
            "title": sn["title"],
            "description": new_desc,
            "tags": sn.get("tags", []),
            "categoryId": sn.get("categoryId", "10"),
            "defaultLanguage": sn.get("defaultLanguage", "th"),
        }},
        part="snippet",
    )
    print(f"   -> HTTP {st}" + ("" if st == 200 else f" {r}"))
    if st == 200:
        BACKUP.write_text(json.dumps(list(backup.values()), ensure_ascii=False,
                                     indent=1), encoding="utf-8")
        print(f"backup -> {BACKUP}")
    return 0 if st == 200 else 1


if __name__ == "__main__":
    raise SystemExit(main())
