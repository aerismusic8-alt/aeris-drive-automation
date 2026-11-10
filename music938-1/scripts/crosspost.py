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
import contextlib
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))
sys.path.insert(0, str(ROOT.parent / "ops"))  # fb_graph / tiktok_api live here

import browser as B  # noqa: E402
import monetize  # noqa: E402
import release  # noqa: E402

try:  # the headless API posters; absent only on a very old checkout
    import fb_graph  # noqa: E402
except Exception:  # noqa: BLE001
    fb_graph = None
try:
    import tiktok_api  # noqa: E402
except Exception:  # noqa: BLE001
    tiktok_api = None

WORK = ROOT / "work"
SHORTS = ROOT / "library" / "shorts"
AFF_SHORTS = ROOT / "library" / "affiliate"
SURREAL = ROOT / "library" / "surreal"
MOODS = ROOT / "library" / "moods"
COVERS = ROOT / "library" / "covers"
QUEUE = WORK / "crosspost-queue.json"

# How far apart freshly merged items are spread through the backlog. At the
# per-surface cadence (~3-4 posts/day) one item every 8 positions reaches the
# first new clip in about a day, so a newly rendered lane is live now rather
# than weeks out; see `merge_queue`.
NEW_FORMAT_EVERY = 8
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


def caption(slug: str, platform: str, hook: int = 0, kind: str = "song") -> str:
    h = release.parse_lyrics(slug)
    title = h.get("TITLE", slug)
    tagline = release.TAGLINE.get(h.get("MOOD", "calm"), release.TAGLINE["calm"])
    # A karaoke clip of a song would otherwise caption exactly like that song's
    # first-hook Short — same title, same tagline, same ask — which reads as a
    # duplicate post and the "captions are all distinct" test catches it. It is a
    # different offer (sing along vs listen), so it gets its own series label and
    # its own ask.
    if kind == "karaoke":
        series = f"{title} | คาราโอเกะร้องตาม"
        ask = "🎤 อยากลองร้องไหม? กดบันทึกไว้ร้องตามได้เลย"
    else:
        # The 2026-11-05 advisor panel (3/3): the numbered "(ท่อน N)" tag made the
        # profile read as "part N of 3" of the same clip. It is replaced by the
        # series label, which is the recurring reason to watch; the chorus still
        # differs between the three files.
        series = f"{title} | {release.hook_title(hook or 1)}"
        # A different prompt per chorus, so the three files of one song are three
        # distinct posts rather than three copies. See release.HOOK_ANGLES.
        ask = release.hook_angle(hook or 1)
    if platform == "facebook":
        # Reels leans on fewer hashtags than TikTok; spend the words on the hook.
        # The caption carries the Page's own Shopee tracking link (Sub_id
        # "facebook") so a Reel's sale is attributed to Facebook. Both surfaces
        # truncate the caption, so the product link and the follow ask sit in the
        # first two lines and the hashtags go last.
        shopee = monetize.link("facebook")
        return (f"{series}\n"
                f"🎵 {tagline}\n"
                f"{release.LABEL}\n"
                f"❤️ กดติดตามเพจ · ของน่าซื้อ 👉 {shopee}\n"
                f"🎬 ดูใหม่ทุกวัน: YouTube {YOUTUBE_HANDLE} · TikTok {TIKTOK_HANDLE}\n"
                f"💬 {ask}\n"
                f"#เพลงไทย #เพลงใหม่ #ร้องต่อไหม #AERISMusic #ค่ายเพลงAI")
    shopee = monetize.link("tiktok")
    return (f"{series}\n"
            f"🎵 {tagline}\n"
            f"{release.LABEL}\n"
            f"🎧 กดติดตาม · ของน่าซื้อ 👉 {shopee}\n"
            f"🎬 ฟังเต็ม ๆ ได้ที่ YouTube {YOUTUBE_HANDLE} · เพจ FB AERIS Music\n"
            f"💬 {ask}\n"
            f"#fyp #เพลงไทย #เพลงใหม่ #ร้องต่อไหม #TikTokเพลงไทย #ค่ายเพลงAI")


def photo_caption(slug: str, platform: str = "facebook") -> str:
    """Caption for a single-photo post (a song's cover art).

    A photo is the visual identity of the song, not another cut of the clip, so
    it leads with the title and the artwork and asks for the follow rather than
    replaying the Reel's chorus prompt. Distinct from the song's Reel caption on
    purpose, so the two do not read as a duplicate post.
    """
    h = release.parse_lyrics(slug)
    title = h.get("TITLE", slug)
    tagline = release.TAGLINE.get(h.get("MOOD", "calm"), release.TAGLINE["calm"])
    shopee = monetize.link("facebook")
    return (f"🎨 {title}\n"
            f"🎵 {tagline}\n"
            f"{release.LABEL}\n"
            f"❤️ กดติดตามเพจ ฟังเพลงใหม่ทุกวัน\n"
            f"🎧 ฟังเต็ม ๆ: YouTube {YOUTUBE_HANDLE} · TikTok {TIKTOK_HANDLE}\n"
            f"🛒 ของน่าซื้อ 👉 {shopee}\n"
            f"#เพลงไทย #เพลงใหม่ #AERISMusic #ค่ายเพลงAI")


def link_caption(product: dict, platform: str = "facebook") -> str:
    """Caption for a link post: the product card as a clickable link.

    The link post is the one format whose whole job is the click, so it leads
    with the buying points and the URL and carries the mandatory disclosure. At
    most one a day (see `_link_ok`), so the feed does not become an ad wall.
    """
    title = product["title"]
    price = product.get("price", "")
    bullets = " · ".join(product.get("bullets", [])[:3])
    url = monetize.link("facebook")
    stag = "#" + product.get("search", "หูฟังบลูทูธ").replace(" ", "")
    return (f"🛒 {title} {price}".strip() + "\n"
            f"• {bullets}\n"
            f"👉 ดูราคา/สั่งซื้อ: {url}\n"
            f"⚠️ โฆษณา · ได้ค่าคอมมิชชันจากการซื้อผ่านลิงก์นี้\n"
            f"🎵 เพลงจาก AERIS Music\n"
            f"{stag} #หูฟังบลูทูธ #Shopee #AERISMusic")


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
        if item.get("kind") == "affiliate":
            # A product card's caption comes from the affiliate module, not from
            # a lyric header, so it must be rebuilt through that path.
            try:
                import make_affiliate_short as aff
                by_id = {p["id"]: p for p in aff.load_products()}
                product = by_id.get(item["slug"])
                want = aff.caption(product, item["platform"]) if product else item["caption"]
            except ImportError:
                want = item["caption"]
        elif item.get("kind") == "photo":
            want = photo_caption(item["slug"], item["platform"])
        elif item.get("kind") == "surreal":
            try:
                import surreal
                want = surreal.caption(item["slug"], item["platform"])
            except ImportError:
                want = item["caption"]
        elif item.get("kind") == "mood":
            try:
                want = mood_caption(item["slug"], item["platform"])
            except Exception:  # noqa: BLE001
                want = item["caption"]
        elif item.get("kind") == "link":
            try:
                import make_affiliate_short as aff
                by_id = {p["id"]: p for p in aff.load_products()}
                product = by_id.get(item["slug"])
                want = link_caption(product) if product else item["caption"]
            except ImportError:
                want = item["caption"]
        else:
            # The committed backlog predates the `kind` field, so infer it from
            # the video path rather than defaulting every item to a song caption.
            kind = item.get("kind") or (
                "karaoke" if "short-karaoke-" in Path(item["video"]).stem else "song")
            want = caption(item["slug"], item["platform"], item.get("hook", 0), kind)
            item["kind"] = kind
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
    # short-karaoke-01-khon-di-thi-chak-pai -> 01-khon-di-thi-chak-pai
    stem = short.stem
    for prefix in ("short-song-", "short-karaoke-"):
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
            break
    return re.sub(r"^h\d+-", "", stem)


def _hook_of(stem: str) -> int:
    """short-song-h2-01-... -> 2. The chorus index a Short was cut from.

    A karaoke Short carries no hook index (one per song), so it returns 0 and
    the caption falls back to the karaoke series label.
    """
    m = re.match(r"short-(?:song|karaoke)-h(\d+)-", stem)
    return int(m.group(1)) if m else 0


def _kind_of(short: Path) -> str:
    """`karaoke` for a sing-along clip, `song` otherwise."""
    return "karaoke" if short.stem.startswith("short-karaoke-") else "song"


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


def song_items() -> list[dict]:
    """The song-chorus Shorts, one per surface. The supporting layer now.

    These used to be the whole FB/TK rotation. K (2026-11-09) had the old system
    torn down in favour of the absurd exhibit, so they are folded in as the varied
    layer behind it rather than leading the queue.
    """
    items = []
    for short in sorted(SHORTS.glob("short-*.mp4")):
        slug = _slug_of(short)
        rel = str(short.relative_to(ROOT))
        hook = _hook_of(short.stem)
        kind = _kind_of(short)
        for platform, cfg in PLATFORMS.items():
            items.append({
                "id": f"{cfg['state_key']}:{short.stem}",
                "platform": platform,
                "slug": slug,
                "hook": hook,
                "kind": kind,
                "video": rel,
                "caption": caption(slug, platform, hook, kind),
            })
    return items


def build_queue() -> list[dict]:
    """The FB/TK queue, led by the new absurd-exhibit format.

    K (2026-11-09): tear down the old rotation and adopt the new format. So the
    exhibit is the primary lane — it leads the queue and is the largest share —
    and the song Shorts, the mood beds and the funnel formats fold in behind it.
    The lead matters because the committed queue is what actually posts, and an
    appended lane (how the exhibits arrived before) sat weeks out and never ran.
    """
    # The new format leads. One exhibit after every item of the song layer, so the
    # two alternate and an exhibit is reached within the first post of a run.
    base = interleave(surreal_items(), song_items(), every=1, chunk=1)
    # The mood clips — the real-instrument beds K approved (2026-11-09) — one at a
    # time and spaced, so six clips that share a shape do not land as a burst.
    base = interleave(base, mood_items(), every=4, chunk=1)
    # One product card pair (both surfaces) after every 6 items — the ~25% product
    # share PLAN-30D-AI asks for, still reaching the first affiliate post on day one.
    base = interleave(base, affiliate_items(), every=6, chunk=2)
    # Facebook also gets a cover-art photo and a Shopee link post, so its feed is
    # not wall-to-wall Reels (advisor panel 2026-11-05: Reel for reach, photo for
    # identity, <=1 link a day). A photo lands after every 3 items and a link after
    # every 8, which at the post cadence is well under one link a day.
    base = interleave(base, photo_items(), every=3, chunk=1)
    return interleave(base, link_items(), every=8, chunk=1)


def photo_items() -> list[dict]:
    """Cover-art photo posts, Facebook only.

    A photo is a feed post, not a Reel, and the TikTok API path only publishes
    video — so this format exists only where it can actually be posted. The
    image lives in `library/covers/`, gitignored like every other asset, so on a
    fresh pod the image is pulled from the media release by `fetch_media`.
    """
    items = []
    for cov in sorted(COVERS.glob("cover-*.jpg")):
        slug = cov.stem[len("cover-"):]
        items.append({
            "id": f"facebook-page:photo-{slug}",
            "platform": "facebook",
            "slug": slug,
            "hook": 0,
            "kind": "photo",
            "image": str(cov.relative_to(ROOT)),
            "caption": photo_caption(slug),
        })
    return items


def link_items() -> list[dict]:
    """Shopee link posts, Facebook only. One per product, guarded to <=1/day.

    The link post is the format whose whole job is the click, so it is the one
    that must not repeat too often; the cadence guard in `post()` enforces the
    daily ceiling on top of this spacing.
    """
    try:
        import make_affiliate_short as aff
    except ImportError:
        return []
    items = []
    for product in aff.load_products():
        items.append({
            "id": f"facebook-page:link-{product['id']}",
            "platform": "facebook",
            "slug": product["id"],
            "hook": 0,
            "kind": "link",
            "link": monetize.link("facebook"),
            "caption": link_caption(product),
        })
    return items


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


def surreal_items() -> list[dict]:
    """The absurdist "exhibit" clips, captioned by the surreal identity module.

    K (2026-11-09): the FB/TK surfaces become an unhinged art project. Each clip
    is one song turned into a moving painting, filed as an exhibit. It carries
    the museum-label caption from `surreal.py`, which is the same on both
    surfaces except for the cross-promo line, so the identity reads as one
    project and not two feeds. The id is stable (`<state_key>:surreal-<slug>`),
    so a posted exhibit never re-enters.
    """
    try:
        import surreal
    except ImportError:
        return []
    if not SURREAL.exists():
        return []
    items = []
    for clip in sorted(SURREAL.glob("surreal-*.mp4")):
        slug = clip.stem[len("surreal-"):]
        for platform, cfg in PLATFORMS.items():
            items.append({
                "id": f"{cfg['state_key']}:{clip.stem}",
                "platform": platform,
                "slug": slug,
                "hook": 0,
                "kind": "surreal",
                "video": str(clip.relative_to(ROOT)),
                "caption": surreal.caption(slug, platform),
            })
    return items


def mood_caption(mood: str, platform: str) -> str:
    """Caption for a mood clip.

    A mood clip is instrumental, so there are no lyrics to quote and no chorus
    prompt to reuse; the caption sells the *feeling* and the listening occasion
    instead. Both surfaces carry the Shopee link and the AI-performance
    disclosure, because the music is a synthetic performance of a written
    arrangement (COMPLIANCE.md) even though the instruments are real.
    """
    import make_mood_short as M  # noqa: PLC0415

    info = M.MOODS[mood]
    title = f"เพลง{info['name']} (เครื่องดนตรีจริง)"
    if platform == "facebook":
        shopee = monetize.link("facebook")
        return (f"🎵 {title}\n"
                f"🎧 {info['tagline']}\n"
                f"{M.AI_NOTE}\n"
                f"❤️ กดติดตามเพจ · ของน่าซื้อ 👉 {shopee}\n"
                f"🎬 ดูใหม่ทุกวัน: YouTube {YOUTUBE_HANDLE} · TikTok {TIKTOK_HANDLE}\n"
                f"#เพลงบรรเลง #เพลงผ่อนคลาย #AERISMusic #ค่ายเพลงAI")
    shopee = monetize.link("tiktok")
    return (f"🎵 {title}\n"
            f"🎧 {info['tagline']}\n"
            f"{M.AI_NOTE}\n"
            f"🎧 กดติดตาม · ของน่าซื้อ 👉 {shopee}\n"
            f"🎬 ฟังเต็ม ๆ ได้ที่ YouTube {YOUTUBE_HANDLE} · เพจ FB AERIS Music\n"
            f"#fyp #เพลงบรรเลง #เพลงผ่อนคลาย #AERISMusic #TikTokเพลงไทย #ค่ายเพลงAI")


def mood_items() -> list[dict]:
    """The real-instrument mood clips, captioned by `mood_caption`.

    K (2026-11-09) approved the six instrument beds and asked for clips. The id
    is stable (`<state_key>:mood-<mood>`), so a posted clip never re-enters. A
    fresh pod with no rendered clips adds none.
    """
    if not MOODS.exists():
        return []
    items = []
    for clip in sorted(MOODS.glob("mood-*.mp4")):
        mood = clip.stem[len("mood-"):]
        for platform, cfg in PLATFORMS.items():
            items.append({
                "id": f"{cfg['state_key']}:{clip.stem}",
                "platform": platform,
                "slug": mood,
                "hook": 0,
                "kind": "mood",
                "video": str(clip.relative_to(ROOT)),
                "caption": mood_caption(mood, platform),
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

# K (2026-11-09): "อัพเดทโพสต์ทุก 2-5 ชั่วโมง สลับเวลากันโพสต์ เอาให้เนียนเหมือนมนุษย์ทำ"
# — post every 2-5 hours, vary the times, make it look human.
#
# A brand-new account that fired 60 clips in 98 minutes (the 2026-11-01 run) is
# the most plausible cause of the flat views, so the rail paces itself. But a
# *fixed* gap is its own tell: a post every 120 minutes on the dot is as
# obviously automated as a burst. So the interval is drawn from a 2-5 h band per
# post, and the interval, the time of day and the daily count all vary the way a
# person's do.
MIN_GAP_SECONDS = 2 * 60 * 60
MAX_GAP_SECONDS = 5 * 60 * 60

# A hard ceiling, not the pacing. At a 2-5 h gap a surface naturally posts ~5-8
# times a day, so this only stops a retry storm or a manual burst from emptying
# a whole day's queue at once. It sits above the natural rate, so K's band is
# what paces the feed and this is only the safety net.
DAILY_CAP = 8
FACEBOOK_DAILY_CAP = 8

# At most one *link* post a day. A link post is the format that reads as an ad,
# so the rule is "never two links in a row, <=1 a day"; a photo or a Reel
# between links is what keeps the feed from looking like an ad wall.
LINK_DAILY_CAP = 1


def _seed(text: str) -> int:
    """A small stable hash, so a value drawn from an id is the same on every pod.

    The same trick `surreal._seed` uses: a rebuild on a fresh pod must produce
    the identical schedule, or the cadence would drift run to run.
    """
    n = 0
    for ch in text:
        n = (n * 131 + ord(ch)) % (2 ** 31)
    return n


def _gap_for(key: str) -> int:
    """The humanised interval to wait after the post keyed by `key`.

    Drawn from the post's own id, so it is stable for that post — a re-run waits
    the same amount and the guard does not flap — yet varies post to post, which
    is what stops the feed reading as a metronome.
    """
    if MAX_GAP_SECONDS <= MIN_GAP_SECONDS:
        return MIN_GAP_SECONDS
    return MIN_GAP_SECONDS + (_seed(key) % (MAX_GAP_SECONDS - MIN_GAP_SECONDS + 1))


def _daily_cap(platform: str) -> int:
    return FACEBOOK_DAILY_CAP if platform == "facebook" else DAILY_CAP


def _last_post_key(state: dict, platform: str) -> str | None:
    """The id of the newest post on `platform`, whose id seeds the next gap."""
    sk = PLATFORMS.get(platform, {}).get("state_key", platform)
    prefix = f"{sk}:"
    best, best_t = None, -1.0
    for key, rec in state.get("posted", {}).items():
        if not key.startswith(prefix):
            continue
        try:
            t = _parse_ts(rec.get("at", ""))
        except ValueError:
            continue
        if t > best_t:
            best_t, best = t, key
    return best


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


def pace_ok(state: dict, platform: str, now: float | None = None,
            kind: str | None = None) -> tuple[bool, str]:
    """May one more post go out on `platform` right now?

    Returns (allowed, reason). Two rules, both from the observed burst: at least
    the *humanised* gap since the last post (2-5 h, drawn from the last post's id
    so it varies post to post), and at most DAILY_CAP in the trailing 24 h. A
    `kind` of "link" adds a third: at most LINK_DAILY_CAP link posts a day,
    because that is the format that reads as an ad.
    """
    now = time.time() if now is None else now
    times = _posted_times(state, platform)
    if times:
        since = now - times[-1]
        gap = _gap_for(_last_post_key(state, platform) or f"{platform}:?")
        if since < gap:
            wait = int(gap - since)
            return False, (f"last post {int(since)}s ago; wait {wait}s "
                           f"(humanised gap {gap}s)")
    day = [t for t in times if now - t < 86400]
    cap = _daily_cap(platform)
    if len(day) >= cap:
        return False, f"{len(day)} posts in the last 24h (cap {cap})"
    if kind == "link":
        links = _posted_link_times(state, platform, now)
        if len(links) >= LINK_DAILY_CAP:
            return False, f"{len(links)} link posts in the last 24h (cap {LINK_DAILY_CAP})"
    return True, "ok"


def _posted_link_times(state: dict, platform: str, now: float) -> list[float]:
    """Epoch seconds of this platform's link posts in the trailing 24 h.

    A link post's id is `<state_key>:link-<product>`, so the id alone identifies
    the format without a separate ledger.
    """
    sk = PLATFORMS.get(platform, {}).get("state_key", platform)
    prefix = f"{sk}:link-"
    out = []
    for key, rec in state.get("posted", {}).items():
        if not key.startswith(prefix):
            continue
        try:
            t = _parse_ts(rec.get("at", ""))
        except ValueError:
            continue
        if now - t < 86400:
            out.append(t)
    return out


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
    # A surface with an API token is "signed in" without any browser: the probe
    # must not report a healthy API surface as dead just because the cookie
    # session it no longer uses has expired.
    api_names = {n for n in names if api_poster(n) is not None}
    # An API-only surface with no token is *parked*, not signed out: it will never
    # use the browser, so there is no session to check and no K sign-in to ask for.
    # Report it as its own state (rc 3) so the rail can stay green.
    parked = {n for n in names if n in API_ONLY and n not in api_names}
    for n in sorted(parked):
        print(f"PARKED {n:9} API-only; one-time token not set (no browser session)")
    if api_names:
        print(f"API-token surfaces (no browser needed): {', '.join(sorted(api_names))}")
    browser_names = [n for n in names if n not in api_names and n not in parked]
    if not browser_names:
        return 3 if parked else 0
    with _connect() as p:
        br, ctx = B.connect(p)
        for name in browser_names:
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

# Surfaces that post ONLY through their API. Facebook is here on purpose: its
# browser fallback was the one thing that kept pulling K back in — the cookie
# session dies every few weeks and restoring it is a K sign-in. With no token the
# rail parks the queue and says so; it never opens a browser for Facebook, so it
# never needs K again. `ops/k_free_status.py` reports it as a one-time setup.
API_ONLY = {"facebook"}

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


def _posted_urls(state: dict) -> set:
    """Every post URL already recorded, so the readback can skip them.

    A stored URL carries tracking params (`?notif_id=...&ref=notif`), so compare
    on the stable `/reel/<id>` or `/video/<id>` part — otherwise the same post
    looks new each time and the "skip seen" test never fires.
    """
    out = set()
    for rec in state.get("posted", {}).values():
        url = rec.get("url") or ""
        m = re.search(r"/(reel|video)/\d+", url)
        if m:
            out.add(m.group(0))
    return out


def newest_post_url(page, platform: str, seen: set | None = None) -> str:
    """The URL of the post that was just published, or "" if it cannot be read.

    Best effort and never fatal: a URL that cannot be read is recorded as empty
    rather than as a page URL, so the state never again claims a post exists
    where it does not.

    The list is *not* strictly newest-first, so taking the first link returned a
    reel that had already been posted (run 13 recorded run 12's URL). `seen`
    holds the URLs already in the state; the first link that is not in it is the
    new post.
    """
    seen = seen or set()

    def pick(locator, pattern, base):
        fallback = ""
        for a in locator.all():
            href = a.get_attribute("href") or ""
            m = re.search(pattern, href)
            if not m:
                continue
            url = href if href.startswith("http") else base + href
            # Compare the stable id, not the full URL: a stored URL carries
            # tracking params that a fresh one will not have.
            if m.group(0) not in seen:
                return url
            fallback = fallback or url
        return fallback

    try:
        if platform == "tiktok":
            page.goto(CONTENT_LIST["tiktok"], wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(6000)
            return pick(page.locator('a[href*="/video/"]'), r"/video/\d+",
                        "https://www.tiktok.com")
        elif platform == "facebook":
            page.goto(CONTENT_LIST["facebook"], wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(6000)
            return pick(page.locator('a[href*="/reel/"]'), r"/reel/\d+",
                        "https://www.facebook.com")
    except Exception:  # noqa: BLE001
        return ""
    return ""


def api_poster(platform: str):
    """Return the headless API poster for a surface, or None to use the browser.

    The API route exists so the rail does not need K to sign in when a cookie
    session dies. It is only used when its credentials are actually configured;
    otherwise the browser path runs exactly as before, so a missing token never
    breaks a run.
    """
    if platform == "facebook" and fb_graph is not None and fb_graph.available():
        return fb_graph.post_reel
    if platform == "tiktok" and tiktok_api is not None and tiktok_api.available():
        return tiktok_api.post_video
    return None


def _publish_api(platform: str, it: dict, media, api) -> str | None:
    """Publish one queue item through the headless API; return its public URL.

    Three formats share the Facebook surface: a Reel (video), a cover-art photo,
    and a Shopee link post (no file). The video path stays on the `api` callable
    `api_poster` already chose, so the TikTok route is untouched; only the two
    Facebook-only formats are special-cased here.
    """
    kind = it.get("kind") or "song"
    if platform == "facebook" and kind in ("photo", "link"):
        if kind == "photo":
            pid = fb_graph.post_photo(media, it["caption"])
        else:
            pid = fb_graph.post_link(it["caption"], it["link"])
        # A feed post id is "<page>_<post>"; the canonical permalink uses the
        # page node and the post half.
        return (f"https://www.facebook.com/{fb_graph.PAGE_ID}/posts/"
                f"{pid.split('_')[-1]}") if pid else None
    vid = api(media, it["caption"])
    if not vid:
        return None
    return (f"https://www.facebook.com/reel/{vid}" if platform == "facebook"
            else f"https://www.tiktok.com/@aeris.music4/video/{vid}")


def post(platform: str, limit: int) -> int:
    state = load_state()
    queue = load_queue()
    todo = pending(queue, state, platform)[:limit]
    if not todo:
        print("nothing pending")
        return 0
    # Base surface rules only (hourly gap + daily cap). The per-format link cap
    # is checked per item, so a link-blocked head of the queue does not abort a
    # run that could still post a photo or a Reel.
    allowed, why = pace_ok(state, platform)
    if not allowed:
        print(f"held back by cadence: {why}")
        return 1
    posted = 0
    api = api_poster(platform)
    if platform in API_ONLY and api is None:
        # Park, do not fall back to the browser. This is the deliberate end of the
        # K loop: a missing Facebook token holds the queue quietly and prints the
        # one-time setup, instead of driving a cookie session that dies and needs
        # K to sign in again. `--pending-count` still reports the backlog, so the
        # rail can tell "parked" from "empty".
        print(f"{platform}: parked — API-only surface, no token configured "
              f"({len(todo)} pending). One-time Meta System User token; see "
              f"docs/k-free-runbook.md. Not opening a browser.")
        return 3
    print(f"posting {platform} via {'Graph/Content API' if api else 'browser session'}")
    # With an API token there is no browser to launch at all — that is the point
    # of the API route, and it is what lets the rail run on a runner with no
    # Chromium and no cookie session.
    ctxmgr = contextlib.nullcontext(None) if api is not None else _connect()
    with ctxmgr as p:
        ctx = None if api is not None else B.connect(p)[1]
        for it in todo:
            kind = it.get("kind") or "song"
            # Re-check before each item: one run must not be able to burst.
            allowed, why = pace_ok(load_state(), platform, kind=kind)
            if not allowed:
                # A link post blocked by its own daily cap must not stall the
                # whole queue: skip it and keep going, or the rail posts nothing
                # for a day while photos and Reels sit ready behind it. Any other
                # hold (the hourly gap, or the surface cap) stops the run.
                if kind == "link" and "link posts" in why:
                    print(f"  skip {it['id']}: {why}")
                    continue
                print(f"stopping: {why}")
                break
            # A photo carries an image, a link carries no file at all, and every
            # other format is a video.
            if kind == "link":
                media = None
            else:
                media = ROOT / (it["image"] if kind == "photo" else it["video"])
                # A fresh pod has no library/, so pull the asset from the media
                # release on demand rather than skipping the post.
                if not media.exists():
                    media = release.fetch_media(media)
                if not media.exists():
                    print(f"  skip {it['id']}: {media} missing")
                    continue
            pg = ctx.new_page() if ctx is not None else None
            try:
                print(f"  posting {it['id']} ...", flush=True)
                if api is not None:
                    # The API returns an id; the browser poster returns the page
                    # URL it landed on. Normalise to a URL for the ledger.
                    url = _publish_api(platform, it, media, api)
                else:
                    url = POSTERS[it["platform"]](pg, media, it["caption"])
                if url is None:
                    print(f"  {it['id']}: not published — left pending "
                          f"(reason in the abort line above)")
                    continue
                real = url if api is not None else newest_post_url(pg, it["platform"], seen=_posted_urls(state))
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
                if pg is not None:
                    _abort(pg, it["platform"], str(exc))
                print(f"  {it['id']}: FAILED {exc}")
            finally:
                if pg is not None:
                    pg.close()
    print(f"posted {posted}/{len(todo)}")
    return 0 if posted else 1


# --- cli --------------------------------------------------------------------

def augment_formats() -> int:
    """Insert the Facebook-only photo and link formats into the committed queue.

    `build_queue()` enumerates gitignored media, so on a fresh pod it cannot
    reconstruct the committed song backlog — it would only see whatever happens
    to be on disk. This migrates the backlog in place instead: it keeps every
    existing item and its order, strips any photo/link items from a previous run
    (so it is idempotent), and re-inserts them interleaved. Returns the number of
    format items now in the queue.
    """
    if not QUEUE.exists():
        return 0
    cur = json.loads(QUEUE.read_text(encoding="utf-8"))
    base = [it for it in cur if it.get("kind") not in ("photo", "link")]
    base = interleave(base, photo_items(), every=3, chunk=1)
    base = interleave(base, link_items(), every=8, chunk=1)
    QUEUE.write_text(json.dumps(base, ensure_ascii=False, indent=2) + "\n",
                     encoding="utf-8")
    return len([it for it in base if it.get("kind") in ("photo", "link")])


def merge_queue(fresh: list[dict]) -> int:
    """Add items the queue does not yet carry, keep everything already in it.

    A plain rebuild enumerates `library/shorts/` and replaces the committed
    backlog, so new karaoke clips would silently drop the 83 pending posts. This
    adds only genuinely new (platform, video) pairs and never removes an item.

    The new items are *spread through* the backlog, not appended to it. Appending
    put a fresh format behind the whole pending queue, which at the post cadence
    is weeks away — the same trap `interleave` was written to fix for the product
    cards. Folding them in every `NEW_FORMAT_EVERY` positions reaches the first
    one in about a day, so a newly rendered lane is live now, not next month.
    Returns the number of items added.
    """
    if not QUEUE.exists():
        QUEUE.parent.mkdir(parents=True, exist_ok=True)
        QUEUE.write_text(json.dumps(fresh, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
        return len(fresh)
    try:
        cur = json.loads(QUEUE.read_text(encoding="utf-8"))
    except ValueError:
        cur = []
    seen = {it["id"] for it in cur}
    added = [it for it in fresh if it["id"] not in seen]
    if added:
        merged = interleave(cur, added, every=NEW_FORMAT_EVERY, chunk=1)
        QUEUE.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8")
    return len(added)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="show what would post")
    ap.add_argument("--probe", action="store_true", help="is the desktop signed in?")
    ap.add_argument("--post", action="store_true", help="actually post")
    ap.add_argument("--status", action="store_true", help="counts by platform")
    ap.add_argument("--pending-count", action="store_true",
                    help="print the number of pending posts for --platform "
                         "(or every platform); used by the rail to tell an "
                         "empty queue from a blocked one")
    ap.add_argument("--platform", choices=sorted(PLATFORMS), default=None)
    ap.add_argument("--limit", type=int, default=1)
    ap.add_argument("--rebuild-queue", action="store_true")
    ap.add_argument("--merge-queue", action="store_true",
                    help="append newly rendered Shorts without dropping the backlog")
    ap.add_argument("--augment-formats", action="store_true",
                    help="insert the Facebook photo/link formats into the queue")
    ap.add_argument("--refresh-captions", action="store_true",
                    help="rewrite pending captions in the committed queue")
    args = ap.parse_args()

    if args.probe:
        return probe(args.platform)
    if args.refresh_captions:
        n = refresh_captions()
        print(f"refreshed {n} pending caption(s)")
        return 0
    if args.augment_formats:
        n = augment_formats()
        print(f"queue: {n} photo/link item(s) present")
        return 0
    if args.merge_queue:
        n = merge_queue(build_queue())
        print(f"queue: added {n} new item(s)")
        return 0
    if args.rebuild_queue or not QUEUE.exists():
        q = build_queue()
        QUEUE.parent.mkdir(parents=True, exist_ok=True)
        QUEUE.write_text(json.dumps(q, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"queue: {len(q)} items -> {QUEUE.name}")
        if not (args.plan or args.post or args.status or args.pending_count):
            return 0
    queue = json.loads(QUEUE.read_text(encoding="utf-8"))
    state = load_state()
    if args.pending_count:
        plats = [args.platform] if args.platform else list(PLATFORMS)
        for plat in plats:
            print(len(pending(queue, state, plat)))
        return 0
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
