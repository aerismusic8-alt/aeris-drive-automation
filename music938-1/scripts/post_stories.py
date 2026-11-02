"""Post the AERIS Music Story cards to Facebook Stories and YouTube community.

Facebook Stories has a dedicated composer at `/stories/create/`: one file input,
then a share button. The caption is optional and the card already carries the
text, so this stays a two-step flow.

YouTube has no Story; the equivalent reach is a **community post**. It is posted
through the Studio UI because the Data API's `community` write surface needs
approval this app does not have.

Run:
    python3 scripts/post_stories.py --plan
    python3 scripts/post_stories.py --facebook --limit 3
"""
from __future__ import annotations
import os

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from common import ROOT

STORIES = ROOT / "library" / "stories"
STATE = ROOT / "work" / "story-state.json"

FB_CREATE = "https://www.facebook.com/stories/create/"


def _load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text())
    return {"posted": {}}


def _save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2))


def _pending(cards: list[Path], state: dict, platform: str) -> list[Path]:
    done = state["posted"]
    return [c for c in cards if f"{platform}:{c.name}" not in done]


def _js_click_text(page, labels: list[str]) -> bool:
    """Click a button by its visible text, from inside the page.

    Facebook layers a transparent div over its controls, so Playwright's own
    click is refused with "subtree intercepts pointer events".
    """
    js = """(labels) => {
      const els = [...document.querySelectorAll('div[role=button],button,[aria-label]')];
      for (const el of els) {
        const t = (el.innerText || el.getAttribute('aria-label') || '').trim();
        if (labels.some(l => t === l || t.includes(l))) { el.click(); return t; }
      }
      return null;
    }"""
    return bool(page.evaluate(js, labels))


def post_facebook(page, card: Path) -> str | None:
    page.goto(FB_CREATE, wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(5000)
    if "login" in page.url:
        return None
    # The composer has no visible file input until the media tile is clicked,
    # so drive the chooser rather than set_input_files.
    try:
        with page.expect_file_chooser(timeout=10000) as fc:
            page.get_by_text("สร้างสตอรี่รูปภาพหรือวิดีโอ").first.click()
        fc.value.set_files(str(card))
    except Exception:
        return None
    page.wait_for_timeout(12000)

    # The editor is open on the card; share it.
    if not _js_click_text(page, ["แชร์ไปยังสตอรี่", "แชร์สตอรี่", "Share to story"]):
        return None
    page.wait_for_timeout(10000)
    return page.url


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--facebook", action="store_true")
    ap.add_argument("--limit", type=int, default=3)
    args = ap.parse_args()

    cards = sorted(STORIES.glob("*.jpg"))
    if not cards:
        raise SystemExit("no story cards; run scripts/make_stories.py --all")
    state = _load_state()
    todo = _pending(cards, state, "facebook")
    print(f"{len(cards)} cards, {len(cards) - len(todo)} posted, {len(todo)} pending")

    if args.plan or not args.facebook:
        for c in todo[:args.limit]:
            print("  would post:", c.name)
        return 0

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        b = p.chromium.connect_over_cdp(os.environ.get("AERIS_CDP", "http://127.0.0.1:9222"))
        ctx = b.contexts[0]
        page = ctx.new_page()
        n = 0
        for card in todo[:args.limit]:
            print("  posting facebook story:", card.name)
            url = post_facebook(page, card)
            if url:
                state["posted"][f"facebook:{card.name}"] = {
                    "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "url": url,
                }
                _save_state(state)
                print("    posted ->", url[:70])
                n += 1
            else:
                print("    failed (no share control)")
        print(f"posted {n}/{min(len(todo), args.limit)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
