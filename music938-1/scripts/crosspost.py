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
import calendar
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))

import browser as B  # noqa: E402
import monetize  # noqa: E402
import release  # noqa: E402

WORK = ROOT / "work"
SHORTS = ROOT / "library" / "shorts"
AFF_SHORTS = ROOT / "library" / "affiliate"
QUEUE = WORK / "crosspost-queue.json"
STATE = WORK / "crosspost-state.json"

# The upload entry points. Kept here so a UI change is a one-line fix.
#
# Facebook posts through the Page-scoped Reels composer in Meta Business Suite.
# The plain `facebook.com/reels/create/` composer posts as the personal profile,
# which is not the brand surface, so it is deliberately not used.
# The Page id is the public one (61595890900382), the same one profile_setup.py
# and social_stats.py use. It is NOT the Business Suite asset id
# (1349201551618019) that appears in the composer URL: building the Reels list
# from the asset id yields "page not available" and the post URL can never be
# read back. Verified 2026-11-04.
FACEBOOK_PAGE_ID = "61595890900382"
FACEBOOK_ASSET_ID = "1349201551618019"

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
                   f"?ref=biz_web_home_create_reel&asset_id={FACEBOOK_ASSET_ID}"),
        "login_marker": "/login",
        # A distinct state key: the 60 Reels posted before the Page existed went
        # to the personal profile, so they must not count as Page posts.
        "state_key": "facebook-page",
    },
}


# --- captions ---------------------------------------------------------------

# Cross-promotion: the four surfaces are one audience split across apps, so a
# viewer who found us on one is told where the others are. Handles, not links —
# a raw URL in a caption reads as spam and Facebook suppresses it.
YOUTUBE_HANDLE = "@aerismusicth"
TIKTOK_HANDLE = "@aeris.music4"


def caption(slug: str, platform: str, hook: int = 0) -> str:
    h = release.parse_lyrics(slug)
    title = h.get("TITLE", slug)
    tagline = release.TAGLINE.get(h.get("MOOD", "calm"), release.TAGLINE["calm"])
    # A song yields three Shorts, one per chorus. They are different files but
    # the same title and mood, so without this they would carry a byte-identical
    # caption and read as the same post three times on the profile.
    tag = f" (ท่อน {hook})" if hook > 1 else ""
    if platform == "facebook":
        # Reels leans on fewer hashtags than TikTok; spend the words on the hook.
        # The caption carries the Page's own Shopee tracking link (Sub_id
        # "facebook") so a Reel's sale is attributed to Facebook. Both surfaces
        # truncate the caption, so the product link and the follow ask sit in the
        # first two lines and the hashtags go last.
        shopee = monetize.link("facebook")
        return (f"{title} 🎵 {tagline}{tag}\n"
                f"{release.LABEL}\n"
                f"❤️ กดติดตามเพจ · ของน่าซื้อ 👉 {shopee}\n"
                f"🎬 ดูใหม่ทุกวัน: YouTube {YOUTUBE_HANDLE} · TikTok {TIKTOK_HANDLE}\n"
                f"💬 เพลงนี้เตือนถึงใคร คอมเมนต์บอกกันได้เลย\n"
                f"#เพลงไทย #เพลงใหม่ #เพลงเพราะ #AERISMusic #ค่ายเพลงAI")
    shopee = monetize.link("tiktok")
    return (f"{title} 🎵 {tagline}{tag}\n"
            f"{release.LABEL}\n"
            f"🎧 กดติดตาม · ของน่าซื้อ 👉 {shopee}\n"
            f"🎬 ฟังเต็ม ๆ ได้ที่ YouTube {YOUTUBE_HANDLE} · เพจ FB AERIS Music\n"
            f"💬 เพลงนี้เตือนถึงใคร พิมพ์ชื่อไว้ได้เลย\n"
            f"#fyp #เพลงไทย #เพลงใหม่ #เพลงเพราะ #TikTokเพลงไทย #ค่ายเพลงAI")


def refresh_captions() -> int:
    """Rewrite the pending captions in the committed queue, leave posted ones.

    The queue is a committed artifact, so a caption change has to be applied to
    it in place — `--rebuild-queue` would enumerate `library/shorts/`, which is
    gitignored and empty on a fresh pod, and silently drop the backlog. Only
    items not yet posted are touched, so a past post keeps the caption it went
    out with. Returns the number of captions changed.
    """
    if not QUEUE.exists():
        return 0
    queue = json.loads(QUEUE.read_text(encoding="utf-8"))
    posted = load_state().get("posted", {})
    changed = 0
    for item in queue:
        if item["id"] in posted:
            continue
        want = caption(item["slug"], item["platform"], item.get("hook", 0))
        if item.get("caption") != want:
            item["caption"] = want
            changed += 1
    if changed:
        QUEUE.write_text(json.dumps(queue, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
    return changed


# --- queue ------------------------------------------------------------------

def _slug_of(short: Path) -> str:
    # short-song-h1-01-khon-di-thi-chak-pai -> 01-khon-di-thi-chak-pai
    s = short.stem[len("short-song-"):] if short.stem.startswith("short-song-") else short.stem
    return re.sub(r"^h\d+-", "", s)


def _hook_of(stem: str) -> int:
    """short-song-h2-01-... -> 2. The chorus index a Short was cut from."""
    m = re.match(r"short-song-h(\d+)-", stem)
    return int(m.group(1)) if m else 0


def interleave(primary: list[dict], secondary: list[dict], every: int,
               chunk: int = 1) -> list[dict]:
    """Fold `secondary` into `primary` so it is reached in days, not weeks.

    Appending the product cards put them behind every song Short, and at
    `DAILY_CAP` per surface that is an ~11-day wait before the first
    revenue-bearing post — the opposite of the goal. One card pair is inserted
    after every `every` items of `primary`.
    """
    if every < 1:
        raise ValueError("every must be >= 1")
    out, si = [], 0
    for i, item in enumerate(primary):
        out.append(item)
        if (i + 1) % every == 0 and si < len(secondary):
            out.extend(secondary[si:si + chunk])
            si += chunk
    out.extend(secondary[si:])
    return out


def build_queue() -> list[dict]:
    items = []
    for short in sorted(SHORTS.glob("short-*.mp4")):
        slug = _slug_of(short)
        rel = str(short.relative_to(ROOT))
        hook = _hook_of(short.stem)
        for platform, cfg in PLATFORMS.items():
            items.append({
                "id": f"{cfg['state_key']}:{short.stem}",
                "platform": platform,
                "slug": slug,
                "hook": hook,
                "video": rel,
                "caption": caption(slug, platform, hook),
            })
    # One product card pair (both surfaces) after every 4 queue items — 2 song
    # clips — so the first affiliate post lands on day one rather than after the
    # whole song backlog.
    return interleave(items, affiliate_items(), every=4, chunk=2)


def affiliate_items() -> list[dict]:
    """Product-card Shorts as queue items, captioned by the affiliate module.

    A product clip is a different kind of post from a song clip, so it carries
    its own caption (the product card's, with the per-surface link) rather than
    a song caption that happens to sit under a product video. The id is stable
    (`<state_key>:aff-<product-id>`), so once posted it never re-enters.
    """
    try:
        import make_affiliate_short as aff
    except ImportError:
        return []
    if not AFF_SHORTS.exists():
        return []
    by_id = {p["id"]: p for p in aff.load_products()}
    items = []
    for clip in sorted(AFF_SHORTS.glob("short-aff-*.mp4")):
        pid = clip.stem[len("short-aff-"):]
        product = by_id.get(pid)
        if not product:
            continue
        for platform, cfg in PLATFORMS.items():
            items.append({
                "id": f"{cfg['state_key']}:{clip.stem}",
                "platform": platform,
                "slug": pid,
                "hook": 0,
                "kind": "affiliate",
                "video": str(clip.relative_to(ROOT)),
                "caption": aff.caption(product, platform),
            })
    return items


def load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {"posted": {}}


def load_queue() -> list[dict]:
    """The queue to act on: the committed file if present, else a fresh build.

    `build_queue()` enumerates `library/shorts/`, which is gitignored and empty
    on a fresh pod — so rebuilding there yields only the handful of Shorts that
    happen to be on disk and silently drops the real backlog. The committed
    queue file is the backlog; prefer it and fall back to a build only when it
    is missing (first run, or after `--rebuild-queue`).
    """
    if QUEUE.exists():
        try:
            return json.loads(QUEUE.read_text(encoding="utf-8"))
        except ValueError:
            pass
    return build_queue()


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def pending(queue: list[dict], state: dict, platform: str | None) -> list[dict]:
    done = state.get("posted", {})
    return [it for it in queue
            if it["id"] not in done and (platform is None or it["platform"] == platform)]


# --- cadence ----------------------------------------------------------------

# A brand-new account that fires 60 clips in 98 minutes (the 2026-11-01 run,
# median gap 26 s) is the most plausible cause of the flat 0 views, so the rail
# now paces itself. The numbers are deliberately conservative and cheap to
# relax: one post per platform per interval, and a daily ceiling well under what
# a spam filter would notice.
MIN_GAP_SECONDS = 20 * 60
DAILY_CAP = 4


def _posted_times(state: dict, platform: str) -> list[float]:
    """Epoch seconds of every successful post on `platform`, from the state file.

    Posts are keyed by the platform's *state key*, which is not always the
    platform name: Facebook Page posts live under `facebook-page`, not
    `facebook` (the 60 pre-Page posts). Keying off the raw platform name made
    the cadence guard blind to every Page post — it compared against the legacy
    personal-profile posts and let a second Reel out 45 s later.
    """
    sk = PLATFORMS.get(platform, {}).get("state_key", platform)
    prefix = f"{sk}:"
    out = []
    for key, rec in state.get("posted", {}).items():
        if not key.startswith(prefix):
            continue
        try:
            out.append(_parse_ts(rec.get("at", "")))
        except ValueError:
            continue
    return sorted(out)


def _parse_ts(s: str) -> float:
    return calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ"))


def pace_ok(state: dict, platform: str, now: float | None = None) -> tuple[bool, str]:
    """May one more post go out on `platform` right now?

    Returns (allowed, reason). Two rules, both from the observed burst:
    at least MIN_GAP_SECONDS since the last post, and at most DAILY_CAP in the
    trailing 24 h.
    """
    now = time.time() if now is None else now
    times = _posted_times(state, platform)
    if times:
        since = now - times[-1]
        if since < MIN_GAP_SECONDS:
            wait = int(MIN_GAP_SECONDS - since)
            return False, f"last post {int(since)}s ago; wait {wait}s"
    day = [t for t in times if now - t < 86400]
    if len(day) >= DAILY_CAP:
        return False, f"{len(day)} posts in the last 24h (cap {DAILY_CAP})"
    return True, "ok"


# --- desktop -----------------------------------------------------------------

def _connect():
    from playwright.sync_api import sync_playwright
    return sync_playwright()


def _signed_in(page) -> bool:
    url = page.url.lower()
    return "/login" not in url and "login" not in url.split("?")[0]


def probe(platform: str | None = None) -> int:
    """Report, per platform, whether the desktop reaches the upload page signed in.

    Pass `platform` to ask about one surface. A rail that gates the whole run on
    "all surfaces signed in" stops posting to the healthy surface the moment one
    other login expires — the sessions are independent, so the caller can probe
    each and post to the ones that answer.
    """
    rc = 0
    names = [platform] if platform else list(PLATFORMS)
    with _connect() as p:
        br, ctx = B.connect(p)
        for name in names:
            cfg = PLATFORMS[name]
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

    # Publish is the footer "แชร์เลย" (Share now). "แชร์" is NOT the publish
    # button — it is the tab that reveals the share options, and clicking it
    # leaves the Reel unpublished. The old code clicked "แชร์" and then failed to
    # find the processing dialog, so every Facebook post was abandoned at the
    # last step while the log blamed the login. Verified live 2026-11-04: after
    # "แชร์เลย" the composer navigates to the content planner.
    _js_click_text(page, ["แชร์"])
    page.wait_for_timeout(2500)
    try:
        page.get_by_role("button", name="แชร์เลย", exact=True).last.click(timeout=8000, force=True)
    except Exception:  # noqa: BLE001
        _abort(page, "facebook", "publish button (แชร์เลย) not found")
        return None
    # Success is either the "กำลังประมวลผลคลิป Reels" dialog or a navigation away
    # from the composer (Meta now sends a published Reel to the content planner,
    # so the dialog is not guaranteed). Accepting both stops a real publish from
    # being reported as a failure — and, worse, retried into a duplicate.
    try:
        page.wait_for_selector("text=กำลังประมวลผลคลิป Reels", timeout=30000)
    except Exception:  # noqa: BLE001
        if "reels_composer" in page.url:
            _abort(page, "facebook", "publish not confirmed")
            return None
    page.wait_for_timeout(6000)
    return page.url


POSTERS = {"tiktok": post_tiktok, "facebook": post_facebook}

# Where each platform lists its own posts, newest first. `post_*` used to return
# `page.url`, which after publishing is the studio/composer page - so 114 of the
# first 122 records stored a URL that identifies nothing and the surface could
# not be checked afterwards. Reading the list gives the real post.
CONTENT_LIST = {
    "tiktok": "https://www.tiktok.com/tiktokstudio/content",
    # `/61595890900382/reels/` is the Page's Reels tab (verified 2026-11-04).
    # The old `profile.php?id=...&sk=reels` form returns "page not available"
    # with the asset id and never yielded a post URL.
    "facebook": f"https://www.facebook.com/{FACEBOOK_PAGE_ID}/reels/",
}


def newest_post_url(page, platform: str) -> str:
    """The URL of the most recent post on `platform`, or "" if it cannot be read.

    Best effort and never fatal: a URL that cannot be read is recorded as empty
    rather than as a page URL, so the state never again claims a post exists
    where it does not.
    """
    try:
        if platform == "tiktok":
            page.goto(CONTENT_LIST["tiktok"], wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(6000)
            for a in page.locator('a[href*="/video/"]').all():
                href = a.get_attribute("href") or ""
                if "/video/" in href:
                    return href if href.startswith("http") else f"https://www.tiktok.com{href}"
        elif platform == "facebook":
            page.goto(CONTENT_LIST["facebook"], wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(6000)
            for a in page.locator('a[href*="/reel/"]').all():
                href = a.get_attribute("href") or ""
                if re.search(r"/reel/\d+", href):
                    return href if href.startswith("http") else f"https://www.facebook.com{href}"
    except Exception:  # noqa: BLE001
        return ""
    return ""


def post(platform: str, limit: int) -> int:
    state = load_state()
    queue = load_queue()
    todo = pending(queue, state, platform)[:limit]
    if not todo:
        print("nothing pending")
        return 0
    allowed, why = pace_ok(state, platform)
    if not allowed:
        print(f"held back by cadence: {why}")
        return 1
    posted = 0
    with _connect() as p:
        br, ctx = B.connect(p)
        for it in todo:
            # Re-check before each item: one run must not be able to burst.
            allowed, why = pace_ok(load_state(), platform)
            if not allowed:
                print(f"stopping: {why}")
                break
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
                    print(f"  {it['id']}: not published — left pending "
                          f"(reason in the abort line above)")
                    continue
                real = newest_post_url(pg, it["platform"])
                if not real:
                    print(f"  {it['id']}: posted, but the post URL could not be read")
                state.setdefault("posted", {})[it["id"]] = {
                    "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "url": real,
                }
                save_state(state)
                posted += 1
                print(f"  {it['id']}: posted -> {real or '(url unknown)'}")
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
    ap.add_argument("--refresh-captions", action="store_true",
                    help="rewrite pending captions in the committed queue")
    args = ap.parse_args()

    if args.probe:
        return probe(args.platform)
    if args.refresh_captions:
        n = refresh_captions()
        print(f"refreshed {n} pending caption(s)")
        return 0
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
            ok, why = pace_ok(state, plat)
            print(f"{plat:9} {done}/{total} posted   cadence: "
                  f"{'ready' if ok else 'hold - ' + why}")
        return 0
    if args.plan:
        todo = pending(queue, state, args.platform)
        print(f"{len(todo)} pending" + (f" for {args.platform}" if args.platform else ""))
        for plat in (PLATFORMS if not args.platform else [args.platform]):
            ok, why = pace_ok(state, plat)
            print(f"  cadence {plat:9}: {'ready' if ok else 'hold - ' + why}")
        for it in todo[:args.limit if args.limit else 20]:
            print(f"  {it['id']}\n    {it['caption'].splitlines()[0]}")
        return 0
    if args.post:
        return post(args.platform or "tiktok", args.limit)
    ap.error("choose --plan, --probe, --post or --status")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
