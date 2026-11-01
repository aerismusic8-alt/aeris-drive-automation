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
PLATFORMS = {
    "tiktok": {
        "label": "TikTok",
        "upload": "https://www.tiktok.com/tiktokstudio/upload?from=upload",
        "login_marker": "tiktok.com/login",
    },
    "facebook": {
        "label": "Facebook Reels",
        "upload": "https://www.facebook.com/reels/create/",
        "login_marker": "/login",
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
        for platform in PLATFORMS:
            items.append({
                "id": f"{platform}:{short.stem}",
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


def post_tiktok(page, video: Path, text: str) -> str | None:
    page.goto(PLATFORMS["tiktok"]["upload"], wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(4000)
    if not _signed_in(page):
        return None
    page.set_input_files('input[type="file"]', str(video))
    # The editor appears once the file is accepted; the caption box is a
    # contenteditable draft editor.
    page.wait_for_selector('[contenteditable="true"]', timeout=180000)
    page.wait_for_timeout(3000)
    box = page.locator('[contenteditable="true"]').first
    box.click()
    page.keyboard.type(text)
    page.wait_for_timeout(1500)
    got = box.inner_text()
    if text[:20] not in got:
        _abort(page, "tiktok", "caption did not land in the editor")
        return None
    page.get_by_role("button", name=re.compile(r"^Post", re.I)).first.click()
    page.wait_for_timeout(8000)
    return page.url


def post_facebook(page, video: Path, text: str) -> str | None:
    page.goto(PLATFORMS["facebook"]["upload"], wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(4000)
    if not _signed_in(page):
        return None
    page.set_input_files('input[type="file"]', str(video))
    page.wait_for_selector('div[contenteditable="true"], div[role="textbox"]', timeout=180000)
    page.wait_for_timeout(3000)
    box = page.locator('div[contenteditable="true"], div[role="textbox"]').first
    box.click()
    page.keyboard.type(text)
    page.wait_for_timeout(1500)
    got = box.inner_text()
    if text[:20] not in got:
        _abort(page, "facebook", "caption did not land in the editor")
        return None
    # Reels advances through Next until a final Publish appears.
    for _ in range(3):
        nxt = page.get_by_role("button", name=re.compile(r"^(Next|Publish|Post)", re.I))
        if not nxt.count():
            break
        nxt.first.click()
        page.wait_for_timeout(5000)
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
