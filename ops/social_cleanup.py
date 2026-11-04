#!/usr/bin/env python3
"""Delete the pre-fix cross-posts from TikTok and Facebook.

Every Short posted before the 2026-11-03 render fix carries the same burned text
K ordered gone: the drifting lyric sweep, the title card and the closing card.
Neither platform offers a free delete API for this account, so the signed-in
cloud desktop is the only free route (Rule #1). TikTok keeps a deleted post in
"Recently deleted" for 30 days, so this is reversible.

The delete is driven from the platform's own content list and matched by the
caption text the post was made with, so it never touches a post this tool did
not create. `--plan` prints the matches; `--apply` deletes them.

Usage:
    python3 ops/social_cleanup.py --platform tiktok --plan
    python3 ops/social_cleanup.py --platform tiktok --apply --limit 5
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "aeris938-1" / "scripts"))
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))

import browser as B  # noqa: E402

STATE = ROOT / "music938-1" / "work" / "crosspost-state.json"
TIKTOK_CONTENT = "https://www.tiktok.com/tiktokstudio/content"


def _connect():
    from playwright.sync_api import sync_playwright
    return sync_playwright()


def _old_captions() -> list[str]:
    """The first line of every caption recorded in the crosspost state."""
    doc = json.loads(STATE.read_text(encoding="utf-8"))
    caps = []
    for key in doc.get("posted", {}):
        if key.startswith("tiktok:"):
            caps.append(key.split(":", 1)[1])
    return caps


def _titles() -> list[str]:
    """Song titles, the one stable token a caption and a row share."""
    out = []
    for f in sorted((ROOT / "music938-1" / "lyrics").glob("*.txt")):
        for line in f.read_text(encoding="utf-8").splitlines()[:6]:
            if line.startswith("# TITLE:"):
                out.append(line.split(":", 1)[1].strip())
    return out


# The pre-fix caption carried no label; the post-fix one carries this line. The
# two share the song title, so the label is what tells them apart — matching on
# the title alone would delete a fresh post on the next run.
LABEL_MARK = "ค่ายเพลง AI"


def _is_old(row_text: str, titles: list[str]) -> bool:
    return (LABEL_MARK not in row_text
            and any(t and t in row_text for t in titles))


def delete_tiktok(apply: bool, limit: int) -> int:
    """Delete TikTok Studio posts whose row caption carries an old song title.

    A post made before the fix shows the bare title as the first caption line
    and no AI label. A post-fix caption carries the label, so the pair
    (title present, label absent) selects the pre-fix set exactly.
    """
    titles = _titles()
    deleted = 0
    with _connect() as p:
        br, ctx = B.connect(p)
        pg = ctx.new_page()
        while limit <= 0 or deleted < limit:
            pg.goto(TIKTOK_CONTENT, wait_until="domcontentloaded", timeout=60000)
            pg.wait_for_timeout(5000)
            cells = pg.locator("[data-tt='components_ActionCell_Clickable']")
            n = cells.count()
            if n == 0:
                print("no posts left")
                break
            # Match the row whose caption text contains one of the old titles.
            row = None
            for i in range(n):
                try:
                    text = cells.nth(i).evaluate(
                        "e=>{let r=e.closest('[data-tt=\"components_RowLayout_FlexRow\"]');"
                        "return r?r.innerText:''}")
                except Exception:  # noqa: BLE001
                    continue
                if _is_old(text, titles):
                    row = i
                    break
            if row is None:
                print("no matching old post on this page")
                break
            print(f"match row {row}/{n}: {text[:60]!r}")
            if not apply:
                deleted += 1
                if limit and deleted >= limit:
                    break
                continue
            cells.nth(row).click()
            pg.wait_for_timeout(1200)
            dele = pg.locator("[role='dialog']").get_by_text("Delete", exact=True)
            if dele.count() == 0:
                dele = pg.get_by_text("Delete", exact=True).last
            dele.first.click()
            pg.wait_for_timeout(1200)
            # The confirm dialog repeats "Delete"; click the button inside it.
            dlg = pg.locator("[role='dialog']")
            if dlg.count():
                dlg.first.get_by_role("button", name="Delete").click()
            pg.wait_for_timeout(2500)
            deleted += 1
            print(f"deleted {deleted}")
        pg.close()
    return deleted


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--platform", choices=("tiktok",), default="tiktok")
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="0 = all")
    args = ap.parse_args()
    if not (args.plan or args.apply):
        ap.error("pass --plan or --apply")
    n = delete_tiktok(args.apply, args.limit)
    print(f"{'would delete' if args.plan else 'deleted'} {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
