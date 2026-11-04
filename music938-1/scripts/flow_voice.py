#!/usr/bin/env python3
"""Hand a reference voice to Google Flow Music and ask it to sing with it.

Flow's composer has an "Add audio or image" control whose audio input takes a
clip (<=40 MB). The clip shows up as a reference chip, and the producer chat can
then be told to use that voice. This script performs that hand-off and prints
what the producer answers, so we learn whether a new singer is reachable for
free before committing the whole pack to it.

    python3 scripts/flow_voice.py voice-inbox/k-voice-norm.mp3 \
        --prompt "ใช้เสียงนักร้องจากไฟล์นี้ร้องเพลงไทย..."

Nothing is downloaded here; this is the probe. Once the voice is proven, the
create/extend path in flow_song.py is reused for the real render.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "aeris938-1" / "scripts"))
import browser as B  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SESSION_URL = "https://www.flowmusic.app/session?t=true"

DEFAULT_PROMPT = (
    "ใช้เสียงนักร้องจากไฟล์เสียงที่แนบมานี้เป็นเสียงร้องหลัก "
    "ร้องเพลงไทยทำนองเศร้า จังหวะช้า ๆ คำร้องด้านล่าง "
    "[Verse]\nเดินย่างก้าวบนเส้นทาง\nที่มีร่องรอยความหลัง\n"
    "[Chorus]\nยังคิดถึงเธอทุกคืน\nยังฝันถึงเธอทุกวัน"
)


def _dismiss_overlays(page):
    for pat in ("OK, got it", "Got it", "Accept", "ตกลง"):
        loc = page.get_by_role("button", name=re.compile(pat, re.I))
        if loc.count():
            try:
                loc.first.click(timeout=3000)
            except Exception:
                pass
    page.wait_for_timeout(600)


def run(ref: Path, prompt: str) -> int:
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        for pg in list(ctx.pages):
            if "flowmusic.app" in pg.url:
                try:
                    pg.close()
                except Exception:
                    pass
        page = ctx.new_page()
        page.set_viewport_size({"width": 1400, "height": 900})
        page.goto(SESSION_URL, wait_until="domcontentloaded", timeout=60_000)
        page.wait_for_timeout(6000)
        if "Free to start with a Google Account" in page.inner_text("body"):
            raise B.LoginRequired(B.login_instructions("Google Flow Music"))
        _dismiss_overlays(page)

        page.locator('button[aria-label="Add audio or image"]').first.click(
            timeout=8000, force=True)
        page.wait_for_timeout(1500)
        inp = page.locator('input[aria-label="Upload audio file"]')
        if not inp.count():
            print("FAIL: no audio upload input")
            return 2
        inp.first.set_input_files(str(ref))
        print(f"uploaded {ref.name} ({ref.stat().st_size / 1048576:.1f} MB)")
        page.wait_for_timeout(8000)

        # The producer prompt is its own textarea ("Ask Producer..."), separate
        # from the Lyrics and Sound fields, and it has an explicit Send button.
        target = page.locator('textarea[aria-label="Chat message"]')
        if not target.count():
            print("FAIL: no composer prompt textarea found")
            return 3
        target.first.click(force=True)
        target.first.press_sequentially(prompt, delay=12)
        page.wait_for_timeout(1200)
        send = page.locator('button[aria-label="Send message"]')
        for attempt in range(6):
            if send.count() and not send.first.is_disabled():
                send.first.click()
                break
            page.wait_for_timeout(2000)
        print("sent prompt; waiting for the producer...")
        # The send can 429 (POST /__api/conversation). Poll for the message to
        # land rather than assuming one click is enough.
        landed = False
        for _ in range(15):
            page.wait_for_timeout(2000)
            if prompt[:12] in page.inner_text("body"):
                landed = True
                break
        print("message landed:", landed)
        page.wait_for_timeout(20000)
        page.screenshot(path=str(ROOT / "work" / "flow-voice-probe.png"), full_page=True)
        body = page.inner_text("body")
        # Trim to the interesting window around the prompt.
        i = body.find(prompt[:20])
        print("=== producer reply window ===")
        print((body[i:i + 1400] if i >= 0 else body[-1400:]).replace("\n", " | "))
        return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ref")
    ap.add_argument("--prompt", default=DEFAULT_PROMPT)
    a = ap.parse_args()
    return run(Path(a.ref), a.prompt)


if __name__ == "__main__":
    raise SystemExit(main())
