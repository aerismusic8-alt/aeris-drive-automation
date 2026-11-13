#!/usr/bin/env python3
"""Post a rendered story Reel to the AERIS Music Facebook Page.

The posting mechanics are the ones `music938-1/scripts/crosspost.py` proved live
against the Business Suite Reels composer (native file chooser, three steps,
"แชร์เลย" is the publish button, buttons repeat so click the last match). They are
re-used rather than re-derived, because each of those facts cost a failed post to
learn.

What is new here is only the caption: a story Reel is not a song, so it carries a
story caption (hook + follow ask + the theme's hashtags), not the song caption.

Rule #1: the post runs through the signed-in cloud desktop, so it costs nothing.

    python3 ops/post_story_reel.py --plan --video /tmp/reel01/horror-01.mp4
    python3 ops/post_story_reel.py --post --video /tmp/reel01/horror-01.mp4 \
        --title "เสียงเคาะประตูตอนตีสาม" --theme horror
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "music938-1", "scripts"))

CDP = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222")
PAGE_ID = "61595890900382"
ASSET_ID = "1349201551618019"
UPLOAD = ("https://business.facebook.com/latest/reels_composer/"
          f"?ref=biz_web_home_create_reel&asset_id={ASSET_ID}")

HASHTAGS = {
    "horror": "#เรื่องผี #เรื่องเล่าหลอน #ผีไทย #เล่าเรื่องผี #AERISMusic",
    "lesson": "#ข้อคิดชีวิต #เรื่องเล่าให้แง่คิด #กำลังใจ #AERISMusic",
    "humour": "#ตลก #ชีวิตประจำวัน #มีม #ขำ ๆ #AERISMusic",
}
FOLLOW_ASK = "กดติดตามเพจไว้เลย"
FOLLOW_PROMISE = "เรื่องเล่าใหม่ทุกวัน"


def caption(title: str, theme: str) -> str:
    tags = HASHTAGS.get(theme, HASHTAGS["lesson"])
    return (f"{title}\n"
            f"👻 ฟังจบแล้วขนลุกไหม? คอมเมนต์บอกหน่อย\n"
            f"❤️ {FOLLOW_ASK} · {FOLLOW_PROMISE}\n"
            f"🔔 กด See First ไว้ จะได้ไม่พลาดตอนต่อไป\n"
            f"{tags}")


def _abort(page, why: str) -> None:
    shot = Path("/tmp/story-reel-fail.png")
    try:
        page.screenshot(path=str(shot))
    except Exception:
        pass
    print(f"    abort: {why}  (screenshot {shot})")


def _js_click_text(page, labels) -> bool:
    for label in labels:
        hit = page.evaluate("""(label) => {
          const els = [...document.querySelectorAll('*')]
            .filter(e => (e.innerText || '').trim() === label);
          for (let i = els.length - 1; i >= 0; i--) {
            let node = els[i];
            for (let k = 0; k < 8 && node; k++) {
              if (node.tagName === 'BUTTON' || node.getAttribute('role') === 'button') {
                node.click();
                return 'ok';
              }
              node = node.parentElement;
            }
          }
          return 'miss';
        }""", label)
        if hit == "ok":
            return True
    return False


def _fill_caption(page, box, text: str) -> bool:
    box.evaluate("el => { el.focus(); el.click(); }")
    page.wait_for_timeout(300)
    page.keyboard.press("Control+A")
    page.keyboard.press("Delete")
    page.wait_for_timeout(300)
    page.keyboard.insert_text(text)
    page.wait_for_timeout(1500)
    return text[:20] in box.inner_text()


def post(video: Path, text: str) -> str | None:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.connect_over_cdp(CDP)
        ctx = b.contexts[0]
        page = ctx.new_page()
        page.goto(UPLOAD, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(7000)
        if "login" in page.url.split("?")[0]:
            _abort(page, "not signed in")
            return None
        _js_click_text(page, ["ปิด", "Close"])
        page.wait_for_timeout(1500)

        chosen: dict = {}
        page.once("filechooser",
                  lambda fc: (fc.set_files(str(video)), chosen.update(ok=1)))
        if not _js_click_text(page, ["เพิ่มวิดีโอ", "Add video"]):
            _abort(page, "upload control not found")
            return None
        for _ in range(40):
            page.wait_for_timeout(500)
            if chosen.get("ok"):
                break
        if not chosen.get("ok"):
            _abort(page, "file chooser never opened")
            return None

        page.wait_for_selector('[contenteditable="true"]', timeout=120000)
        page.wait_for_timeout(2500)
        box = page.locator('[contenteditable="true"]').first
        if not _fill_caption(page, box, text):
            _abort(page, "caption did not land")
            return None

        for _ in range(2):
            if not _js_click_text(page, ["ถัดไป", "Next"]):
                _abort(page, "next not found")
                return None
            page.wait_for_timeout(7000)

        # The header "แชร์" is the tab that reveals the distribution options; the
        # real publish button is the footer "แชร์เลย". Clicking the tab first is
        # the order that published successfully on 2026-11-13, so it is the
        # primary path; the direct click is only a fallback if the tab is gone.
        if not _js_click_text(page, ["แชร์"]):
            _abort(page, "share tab not found")
            return None
        page.wait_for_timeout(2500)
        try:
            page.get_by_role("button", name="แชร์เลย", exact=True).last.click(
                timeout=8000, force=True)
        except Exception:
            _abort(page, "publish button not found")
            return None
        try:
            page.wait_for_selector("text=กำลังประมวลผลคลิป Reels", timeout=30000)
        except Exception:
            if "reels_composer" in page.url:
                _abort(page, "publish not confirmed")
                return None
        page.wait_for_timeout(6000)
        url = page.url
        page.close()
        return url


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--video", required=True)
    ap.add_argument("--title", default="เรื่องเล่า")
    ap.add_argument("--theme", default="horror", choices=sorted(HASHTAGS))
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--post", action="store_true")
    a = ap.parse_args()

    video = Path(a.video)
    text = caption(a.title, a.theme)
    print(f"video  : {video}  ({video.stat().st_size//1024 if video.exists() else 0} KB)")
    print(f"caption:\n{text}")
    if a.plan or not a.post:
        return 0
    if not video.exists():
        print("video missing")
        return 2
    url = post(video, text)
    if not url:
        print("POST FAILED")
        return 1
    print(f"posted: {url}")
    record = {"title": a.title, "theme": a.theme, "video": str(video), "url": url}
    out = Path(ROOT) / "aeris938-2" / "work" / "story-posts.json"
    hist = json.loads(out.read_text(encoding="utf-8")) if out.exists() else []
    hist.append(record)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(hist, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
