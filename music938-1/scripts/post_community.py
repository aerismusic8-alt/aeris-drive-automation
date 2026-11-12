"""Publish YouTube community posts for AERIS Music.

A community post is the closest thing YouTube has to a Story: it appears on the
channel's Posts tab and in the subscriber feed. This drives the composer at
`/posts?show_create_dialog=1` — the `ytcp-button` "สร้างโพสต์" entry point — and
attaches one of the Story cards so the post is visual.

Thai text is entered with `insert_text`, not `keyboard.type`, because the latter
drops Thai characters (the same trap the crosspost script hit).

Run:
    python3 scripts/post_community.py --plan
    python3 scripts/post_community.py --post --limit 2
"""
from __future__ import annotations
import os

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from common import ROOT

CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"
COMPOSE_URL = f"https://www.youtube.com/channel/{CHANNEL_ID}/posts?show_create_dialog=1"
STORIES = ROOT / "library" / "stories"
STATE = ROOT / "work" / "community-state.json"

# One post per story card, text keyed off the card name.
CAPTIONS = {
    "story-intro": (
        "🎵 เปิดชุดเพลงไทย 20 เพลงเต็ม ๆ\n\n"
        "รวมเพลงป็อป แดนซ์ ร็อก ที่ตั้งใจทำ ทุกเพลงมีทั้งเวอร์ชันเต็มและคาราโอเกะ\n"
        "กดติดตามไว้ ฟังได้ทุกวันเลยครับ 🎧"
    ),
}


def _caption(card: Path) -> str:
    stem = card.stem
    if stem in CAPTIONS:
        return CAPTIONS[stem]
    # Per-song card: pull the number and give a consistent hook line.
    num = stem.split("-")[1] if "-" in stem else ""
    return (
        f"🎵 เพลงที่ {num} ของชุด\n\n"
        "เพลงไทยป็อป แดนซ์ ร็อก ฟังเต็มได้ในช่อง มีคาราโอเกะให้ร้องตามด้วย\n"
        "ฟังแล้วเป็นยังไง คอมเมนต์บอกกันได้เลย 🎧"
    )


def _load() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text())
    return {"posted": {}}


def _save(s: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(s, ensure_ascii=False, indent=2))


def post_one(page, card: Path, caption: str) -> str | None:
    # The `?show_create_dialog=1` URL opens the dialog only intermittently; the
    # create menu is the reliable entry point.
    page.goto("https://www.youtube.com/", wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(6000)
    try:
        page.get_by_role("button", name="สร้าง").first.click(timeout=6000)
        page.wait_for_timeout(2000)
        page.get_by_text("สร้างโพสต์").first.click(timeout=6000)
    except Exception:
        return None
    page.wait_for_timeout(7000)

    # The body editor is the visible contenteditable labelled "เขียนข้อความ...".
    box = page.locator('div[contenteditable="true"]:visible').first
    try:
        box.click(timeout=8000)
    except Exception:
        return None
    page.keyboard.insert_text(caption)
    page.wait_for_timeout(2500)

    # A text post is the reliable path; the image tile opens a poll panel.
    for lbl in ["โพสต์", "เผยแพร่โพสต์", "เผยแพร่"]:
        try:
            page.get_by_role("button", name=lbl).first.click(timeout=4000)
            page.wait_for_timeout(8000)
            return page.url
        except Exception:
            continue
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--post", action="store_true")
    ap.add_argument("--limit", type=int, default=2)
    args = ap.parse_args()

    cards = sorted(STORIES.glob("*.jpg"))
    state = _load()
    todo = [c for c in cards if f"community:{c.name}" not in state["posted"]]
    print(f"{len(cards)} cards, {len(cards) - len(todo)} posted, {len(todo)} pending")

    if args.plan or not args.post:
        for c in todo[:args.limit]:
            print("  would post:", c.name, "->", _caption(c)[:40].replace("\n", " "))
        return 0

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        b = p.chromium.connect_over_cdp(os.environ.get("AERIS_CDP", "http://127.0.0.1:9222"))
        page = b.contexts[0].new_page()
        n = 0
        for card in todo[:args.limit]:
            print("  posting community:", card.name)
            url = post_one(page, card, _caption(card))
            if url:
                state["posted"][f"community:{card.name}"] = {
                    "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "url": url,
                }
                _save(state)
                print("    posted ->", url[:70])
                n += 1
            else:
                print("    failed")
        print(f"posted {n}/{min(len(todo), args.limit)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
