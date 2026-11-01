#!/usr/bin/env python3
"""Cross-post the pack's vertical Shorts to Facebook Reels and TikTok.

The pack already renders 57 9:16 Shorts (make_short.py) for the YouTube
discovery rail. Those same files are what Reels and TikTok want, so this rail
re-uses them instead of re-rendering. It drives the signed-in cloud desktop:
neither app offers a free posting API for this account, so a real browser is the
only free route (Rule #1 — free only).

Posting is not a render: a wrong caption or a duplicate is visible to the
audience, so this is deliberately conservative.

  * The queue is a file (work/crosspost-queue.json), one item per
    (platform, short). It is built from what is already on disk.
  * `--plan` prints what would post; `--post` actually posts; `--limit N` caps a
    run so a bad first attempt cannot flood a feed.
  * A posted item is recorded in work/crosspost-state.json and never re-posted.
  * If the desktop is not signed in to that platform, the item stays pending and
    is reported — never silently marked done.

Usage:
    python3 scripts/crosspost.py --plan
    python3 scripts/crosspost.py --probe            # is the desktop signed in?
    python3 scripts/crosspost.py --post --platform tiktok --limit 1
    python3 scripts/crosspost.py --status
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))

import browser as B  # noqa: E402
import release  # noqa: E402

WORK = ROOT / "work"
SHORTS = ROOT / "library" / "shorts"
QUEUE = WORK / "crosspost-queue.json"
STATE = WORK / "crosspost-state.json"

# The upload entry points. Kept here so a UI change is a one-line fix.
#
# Facebook posts through the Page-scoped Reels composer in Meta Business Suite.
# The plain `facebook.com/reels/create/` composer posts as the personal profile,
# which is not the brand surface, so it is deliberately not used.
FACEBOOK_PAGE_ID = "1349201551618019"

PLATFORMS = {
    "tiktok": {
        "label": "TikTok",
        "upload": "https://www.tiktok.com/tiktokstudio/upload?from=upload",
        "login_marker": "tiktok.com/login",
        "state_key": "tiktok",
    },
    "facebook": {
        "label": "Facebook Reels (Page)",
        "upload": ("https://business.facebook.com/latest/reels_composer/"
                   f"?ref=biz_web_home_create_reel&asset_id={FACEBOOK_PAGE_ID}"),
        "login_marker": "/login",
        # A distinct state key: the 60 Reels posted before the Page existed went
        # to the personal profile, so they must not count as Page posts.
        "state_key": "facebook-page",
    },
}


# --- captions ---------------------------------------------------------------

def caption(slug: str, platform: str) -> str:
    h = release.parse_lyrics(slug)
    title = h.get("TITLE", slug)
    tagline = release.TAGLINE.get(h.get("MOOD", "calm"), release.TAGLINE["calm"])
    if platform == "facebook":
        # Reels leans on fewer hashtags than TikTok; spend the words on the hook.
        return (f"{title} 🎵\n{tagline}\n\n"
                f"ฟังเพลงไทยเพราะ ๆ ได้ที่ช่อง AERIS Music 🎧\n"
                f"#เพลงไทย #เพลงใหม่ #เพลงเพราะ #AERISMusic")
    return (f"{title} 🎵 {tagline}\n"
            f"#fyp #เพลงไทย #เพลงใหม่ #เพลงเพราะ #TikTokเพลงไทย")


# --- queue ------------------------------------------------------------------

def _slug_of(short: Path) -> str:
    # short-song-h1-01-khon-di-thi-chak-pai -> 01-khon-di-thi-chak-pai
    s = short.stem[len("short-song-"):] if short.stem.startswith("short-song-") else short.stem
    return re.sub(r"^h\d+-", "", s)


def build_queue() -> list[dict]:
    items = []
    for short in sorted(SHORTS.glob("short-*.mp4")):
        slug = _slug_of(short)
        rel = str(short.relative_to(ROOT))
        for platform, cfg in PLATFORMS.items():
            items.append({
                "id": f"{cfg['state_key']}:{short.stem}",
                "platform": platform,
                "slug": slug,
                "video": rel,
                "caption": caption(slug, platform),
            })
    return items


def load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {"posted": {}}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def pending(queue: list[dict], state: dict, platform: str | None) -> list[dict]:
    done = state.get("posted", {})
    return [it for it in queue
            if it["id"] not in done and (platform is None or it["platform"] == platform)]


# --- desktop -----------------------------------------------------------------

def _connect():
    from playwright.sync_api import sync_playwright
    return sync_playwright()


def _signed_in(page) -> bool:
    url = page.url.lower()
    return "/login" not in url and "login" not in url.split("?")[0]


def probe() -> int:
    """Report, per platform, whether the desktop reaches the upload page signed in."""
    rc = 0
    with _connect() as p:
        br, ctx = B.connect(p)
        for name, cfg in PLATFORMS.items():
            pg = ctx.new_page()
            try:
                pg.goto(cfg["upload"], wait_until="domcontentloaded", timeout=60000)
                pg.wait_for_timeout(4000)
                ok = _signed_in(pg)
                shot = WORK / f"probe-{name}.png"
                pg.screenshot(path=str(shot))
                print(f"{'OK ' if ok else 'OUT'} {name:9} {pg.url}")
                if not ok:
                    rc = 1
            except Exception as exc:  # noqa: BLE001
                print(f"ERR {name:9} {exc}")
                rc = 1
            finally:
                pg.close()
    return rc


def _abort(page, name: str, why: str) -> None:
    shot = WORK / f"crosspost-fail-{name}.png"
    page.screenshot(path=str(shot))
    print(f"    abort: {why}  (screenshot {shot.name})")


def _js_click_text(page, labels) -> bool:
    """Click the nearest button ancestor of an element whose text is in `labels`.

    FB wraps its controls in div[role=button] that Playwright refuses to click
    (an overlay intercepts pointer events), so a real click must be dispatched
    from inside the page.
    """
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
    """Focus the editor from inside the page, clear it, then insert the caption.

    Two FB/TikTok traps: a transparent overlay refuses a plain Playwright click,
    and TikTok pre-fills the box with the file name while keyboard.type() drops
    Thai codepoints. So focus via JS, select-all, and insert_text (atomic).
    """
    box.evaluate("el => { el.focus(); el.click(); }")
    page.wait_for_timeout(300)
    page.keyboard.press("Control+A")
    page.keyboard.press("Delete")
    page.wait_for_timeout(300)
    page.keyboard.insert_text(text)
    page.wait_for_timeout(1500)
    return text[:20] in box.inner_text()


def post_tiktok(page, video: Path, text: str) -> str | None:
    page.goto(PLATFORMS["tiktok"]["upload"], wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(4000)
    if not _signed_in(page):
        return None
    page.locator('input[type="file"]').first.set_input_files(str(video))
    # The editor appears once the file is accepted; the caption box is a
    # contenteditable draft editor.
    page.wait_for_selector('[contenteditable="true"]', timeout=180000)
    page.wait_for_timeout(3000)
    box = page.locator('[contenteditable="true"]').first
    if not _fill_caption(page, box, text):
        _abort(page, "tiktok", "caption did not land in the editor")
        return None
    if not _js_click_text(page, ["Post", "โพสต์"]):
        _abort(page, "tiktok", "Post button not found")
        return None
    page.wait_for_timeout(10000)
    return page.url


def post_facebook(page, video: Path, text: str) -> str | None:
    """Post one Reel to the AERIS Music Page through the Business Suite composer.

    Four facts this encodes, each verified live:
      * The composer's upload control opens a **native file chooser**, so the file
        must be handed to `filechooser`, not to `input.set_input_files`.
      * The composer is **three steps**: caption -> edit/trim -> publish. Two
        "ถัดไป" (Next) clicks reach the publish screen, where the real button is
        "แชร์เลย" (Share now); the header "แชร์" is only a stage label.
      * An onboarding banner ("เรากำลังทำให้วิธีการสร้างของคุณง่ายขึ้น") covers the
        page and must be dismissed first, or the upload control is unclickable.
      * Buttons repeat across the header/footer, so click the *last* match.
    """
    page.goto(PLATFORMS["facebook"]["upload"], wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(7000)
    if not _signed_in(page):
        return None
    _js_click_text(page, ["ปิด", "Close"])
    page.wait_for_timeout(1500)

    chosen: dict = {}
    page.once("filechooser", lambda fc: (fc.set_files(str(video)), chosen.update(ok=1)))
    if not _js_click_text(page, ["เพิ่มวิดีโอ", "Add video"]):
        _abort(page, "facebook", "upload control not found")
        return None
    for _ in range(40):
        page.wait_for_timeout(500)
        if chosen.get("ok"):
            break
    if not chosen.get("ok"):
        _abort(page, "facebook", "file chooser never opened")
        return None

    page.wait_for_selector('[contenteditable="true"]', timeout=120000)
    page.wait_for_timeout(2500)
    box = page.locator('[contenteditable="true"]').first
    if not _fill_caption(page, box, text):
        _abort(page, "facebook", "caption did not land in the editor")
        return None

    for step in ("ถัดไป", "ถัดไป"):
        if not _js_click_text(page, [step, "Next"]):
            _abort(page, "facebook", f"{step} not found")
            return None
        page.wait_for_timeout(7000)

    # Publish is the *footer* "แชร์"; the header "แชร์" is only the stage label and
    # the header "แชร์เลย" sits off-screen. A JS click lands on the header button
    # and silently does nothing, so force a real click on the last match.
    try:
        page.get_by_role("button", name="แชร์", exact=True).last.click(timeout=8000, force=True)
    except Exception:  # noqa: BLE001
        _abort(page, "facebook", "publish button not found")
        return None
    # Success is the "กำลังประมวลผลคลิป Reels" dialog, not a URL change.
    try:
        page.wait_for_selector("text=กำลังประมวลผลคลิป Reels", timeout=30000)
    except Exception:  # noqa: BLE001
        _abort(page, "facebook", "publish not confirmed")
        return None
    page.wait_for_timeout(6000)
    return page.url


POSTERS = {"tiktok": post_tiktok, "facebook": post_facebook}


def post(platform: str, limit: int) -> int:
    state = load_state()
    queue = build_queue()
    todo = pending(queue, state, platform)[:limit]
    if not todo:
        print("nothing pending")
        return 0
    posted = 0
    with _connect() as p:
        br, ctx = B.connect(p)
        for it in todo:
            video = ROOT / it["video"]
            # A fresh pod has no library/, so pull the Short from the media
            # release on demand rather than skipping the post.
            if not video.exists():
                video = release.fetch_media(video)
            if not video.exists():
                print(f"  skip {it['id']}: {video} missing")
                continue
            pg = ctx.new_page()
            try:
                print(f"  posting {it['id']} ...", flush=True)
                url = POSTERS[it["platform"]](pg, video, it["caption"])
                if url is None:
                    print(f"  {it['id']}: not signed in — left pending")
                    continue
                state.setdefault("posted", {})[it["id"]] = {
                    "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "url": url,
                }
                save_state(state)
                posted += 1
                print(f"  {it['id']}: posted -> {url}")
            except Exception as exc:  # noqa: BLE001
                _abort(pg, it["platform"], str(exc))
                print(f"  {it['id']}: FAILED {exc}")
            finally:
                pg.close()
    print(f"posted {posted}/{len(todo)}")
    return 0 if posted else 1


# --- cli --------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="show what would post")
    ap.add_argument("--probe", action="store_true", help="is the desktop signed in?")
    ap.add_argument("--post", action="store_true", help="actually post")
    ap.add_argument("--status", action="store_true", help="counts by platform")
    ap.add_argument("--platform", choices=sorted(PLATFORMS), default=None)
    ap.add_argument("--limit", type=int, default=1)
    ap.add_argument("--rebuild-queue", action="store_true")
    args = ap.parse_args()

    if args.probe:
        return probe()
    if args.rebuild_queue or not QUEUE.exists():
        q = build_queue()
        QUEUE.parent.mkdir(parents=True, exist_ok=True)
        QUEUE.write_text(json.dumps(q, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"queue: {len(q)} items -> {QUEUE.name}")
        if not (args.plan or args.post or args.status):
            return 0
    queue = json.loads(QUEUE.read_text(encoding="utf-8"))
    state = load_state()
    if args.status:
        for plat in PLATFORMS:
            total = sum(1 for it in queue if it["platform"] == plat)
            done = sum(1 for it in queue if it["platform"] == plat
                       and it["id"] in state.get("posted", {}))
            print(f"{plat:9} {done}/{total} posted")
        return 0
    if args.plan:
        todo = pending(queue, state, args.platform)
        print(f"{len(todo)} pending" + (f" for {args.platform}" if args.platform else ""))
        for it in todo[:args.limit if args.limit else 20]:
            print(f"  {it['id']}\n    {it['caption'].splitlines()[0]}")
        return 0
    if args.post:
        return post(args.platform or "tiktok", args.limit)
    ap.error("choose --plan, --probe, --post or --status")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
