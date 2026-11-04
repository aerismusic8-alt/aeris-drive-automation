#!/usr/bin/env python3
"""Fetch the 4 stems for every rendered song in one browser session.

`flow_song._stems` captures the app's Supabase bearer off a real request, so one
page can serve every clip. Doing it per song would re-open a page each time.

    python3 scripts/fetch_stems.py            # every song with a clipmeta
    python3 scripts/fetch_stems.py 02 03      # only these slugs' prefixes
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "aeris938-1" / "scripts"))
import browser as B  # noqa: E402
import flow_song as F  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    only = set(sys.argv[1:])
    metas = sorted((ROOT / "library" / "songs").glob("clipmeta-*.json"))
    jobs = []
    for m in metas:
        slug = m.stem.replace("clipmeta-", "")
        if only and slug[:2] not in only:
            continue
        dest = ROOT / "work" / slug / "stems" / "vocals.m4a"
        if dest.exists():
            print(f"skip {slug} (stems present)")
            continue
        jobs.append((slug, json.loads(m.read_text())["id"]))
    if not jobs:
        print("nothing to fetch")
        return 0

    with sync_playwright() as p:
        br, ctx = B.connect(p)
        page = ctx.new_page()
        for slug, cid in jobs:
            try:
                got = F._stems(page, cid, ROOT / "work" / slug / "stems")
                print(f"{slug}: {'ok' if got else 'FAILED'}", flush=True)
            except Exception as e:  # keep going; one bad clip must not stop the batch
                print(f"{slug}: error {type(e).__name__}: {e}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
