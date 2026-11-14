#!/usr/bin/env python3
"""Release music938-1 songs to the AERIS Music channel (ch3), on a plan.

Two hard limits decide the shape of this:

1. **YouTube Data API quota.** A project gets 10,000 units/day for most
   endpoints, and `videos.insert` is *not* one of them — it has its own default
   bucket of **100 calls/day** (verified against Google's quota docs,
   2026-11-05). So the 6/day cadence below is a choice for the creative test,
   not a ceiling. `--plan` shows the schedule before anything is sent.
2. **K reviews a channel's first work.** The first upload of the pack is a
   private draft for K to approve. Nothing is made public by this script unless
   `--public` is passed explicitly.

Each song is released as two videos, which doubles the catalogue for one set of
songs:
  * the **song** (vocal + backing) — the main release
  * the **karaoke** (backing only) — the sing-along version

    python3 scripts/release.py --plan                 # what would be released, when
    python3 scripts/release.py --plan --days 4
    python3 scripts/release.py --next --ch ch3        # upload the next one, private
    python3 scripts/release.py --next --public        # ... and make it public
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

import genres
import monetize

ROOT = Path(__file__).resolve().parent.parent
OPS = ROOT.parent / "ops"
sys.path.insert(0, str(OPS))
import yt_quota  # noqa: E402
LYRICS = ROOT / "lyrics"
SONGS = ROOT / "library" / "songs"
KARAOKE = ROOT / "library" / "karaoke"
COVERS = ROOT / "library" / "covers"
AFF_DIR = ROOT / "library" / "affiliate"
THUMBS = ROOT / "library" / "thumbs"
AFF_PRODUCTS = ROOT / "work" / "affiliate-products.json"
STATE = ROOT / "work" / "release-state.json"
PRIORITY = ROOT / "work" / "release-priority.json"

# The affiliate disclosure is mandatory on every card (COMPLIANCE.md).
AFF_DISCLOSURE = "ลิงก์พันธมิตร Shopee — เราอาจได้ค่าคอมมิชชัน"

# Six uploads a day is a *cadence choice*, not a quota wall. Google's default
# allocation gives `videos.insert` its own bucket of 100 calls/day, separate from
# the 10,000-unit pool — verified against the official quota docs on 2026-11-05.
# The old "10,000 / 1,600 = 6" rule was simply wrong, and the 2026-11-05 advisor
# panel (3/3) said the same: the ceiling is 100, so pick a cadence for the
# creative test, not for a limit that does not exist.
#
# 6 -> 2 on 2026-11-13. The measured result that forced the publishing HOLD: the
# posting rate went UP (4 -> 10 clips/day) while daily views fell (847 -> 0-19),
# 14 of 72 uploads sat at 0 views, and the whole channel earned 1 comment in 13
# days. The 2026-11-13 advisor panel (duck + pollinations, quorum PASS) named the
# same fix first: stop clearing the backlog, cap the pilot, and learn from a
# small batch instead of burning quota on output nobody watches. Volume was never
# the constraint -- retention is.
UPLOADS_PER_DAY = 2

# The wrong-render backlog must not eat the whole day. Product clips are the only
# content with a reason to buy, and nothing else on the channel produces a click
# on the Shopee link, so at least this many slots a day are held for them. The
# 2026-11-05 advisor panel (all five agreed) and Duck's caveat — a Short's
# description link may not be tappable — both say: publish the product clips
# first, and never let the replacement queue consume their slots. The backlog is
# a quality fix; it can wait one more day. The product test cannot.
#
# Lowered 2 -> 1 with the cadence cut (2026-11-13). With UPLOADS_PER_DAY = 2 a
# reserve of 2 would spend the *whole* day on product clips and publish no song
# at all, which starves the retention test this pilot exists to run. One slot
# still guarantees the funnel gets a clip every day while a song Short goes out
# beside it. The invariant that matters is `AFFILIATE_RESERVE < UPLOADS_PER_DAY`,
# and the test suite pins it.
AFFILIATE_RESERVE = 1

# Media is gitignored and a recycled pod has an empty library/, so the files a
# batch needs are fetched from the `media-938` release on demand. Downloading
# only the next batch's media (not the whole 500 MB) is what keeps an unattended
# run inside its sandbox budget.
MEDIA_REPO = "aerismusic8-alt/aeris-drive-automation"
MEDIA_RELEASE = "media-938"
_ASSET_CACHE: dict | None = None

# A song's release blurb is written from its own header, so the 20 descriptions
# stay consistent without being hand-copied 20 times.
TAGLINE = {
    "sad": "เพลงเศร้า ที่เข้าใจความเสียใจ",
    "warm": "เพลงอบอุ่น ฟังแล้วใจนุ่ม",
    "hopeful": "เพลงให้กำลังใจ เริ่มวันใหม่อีกครั้ง",
    "calm": "เพลงผ่อนคลาย ฟังสบายทุกเวลา",
    "mystic": "เพลงลึกลับ ชวนคิด ชวนฝัน",
    "epic": "เพลงทรงพลัง ปลุกใจให้ลุกขึ้นสู้อีกครั้ง",
}
HASHTAGS = ("#AERISMusic #เพลงไทย #ศิลปินไทย #เพลงใหม่ #เพลงป็อป "
            "#เพลงแดนซ์ #เพลงร็อก #เพลงเพราะ #ค่ายเพลงAI #AIMusic")

# The search-intent title tail, keyed by mood. The 2026-11-08 competitor scan
# (10 real Thai channels, no API quota): the winning music titles lead with *when*
# and *why* the listener wants the song — "ฟังเพลงไทยเพราะๆ ขับรถ ทำงาน อ่านหนังสือ
# คาเฟ่" — not an abstract mood word, because a searcher types their moment. This
# tail carries both the genre keyword and the occasion, so it replaces the mood
# tagline in the *title* (the tagline still opens the description). It is shorter
# than the tagline, which leaves room under the ~60-char truncation instead of
# spending it on a value line the title does not need.
TITLE_INTENT = {
    "sad": "เพลงเศร้าอกหัก ฟังตอนดึก",
    "warm": "เพลงอบอุ่น ฟังอยู่บ้าน",
    "hopeful": "เพลงให้กำลังใจ เริ่มวันใหม่",
    "calm": "เพลงฟังสบาย ขับรถ ทำงาน",
    "mystic": "เพลงชิลล์ ฟังยามค่ำคืน",
    "epic": "เพลงปลุกใจ ออกกำลังกาย",
}


def song_title(title_th: str, tagline: str, mood: str) -> str:
    """`<song> — <search intent>`, falling back to the tagline if it is too long.

    The intent tail is preferred because it names the genre and the moment a
    viewer searches for. A song whose title plus intent still runs past 60
    characters keeps the tagline instead, so nothing is ever truncated.
    """
    intent = TITLE_INTENT.get(mood, "")
    if intent and len(f"{title_th} — {intent}") <= 60:
        return f"{title_th} — {intent}"
    return f"{title_th} — {tagline}"


# One song yields three Shorts, one per chorus. The 2026-11-05 advisor panel
# (3/3) on the growth stall: a numbered "(ท่อนที่ 2)" label reads as "part 2 of
# the same clip" and gives a viewer no reason to watch this one — but so does
# dropping the number and repeating one caption three times. Each chorus instead
# gets a *different answerable prompt*, which is what the panel asked for and
# what keeps the three captions distinct.
HOOK_ANGLES = {
    1: "ท่อนนี้เตือนถึงใคร? คอมเมนต์บอกกันได้เลย",
    2: "ท่อนนี้ทำให้คิดถึงใคร? พิมพ์ชื่อไว้ได้เลย",
    3: "ถ้าให้ร้องต่อ ท่อนต่อไปควรพูดว่าอะไร? คอมเมนต์บอกได้เลย",
}
# The short form of the same prompt, for the title. Three choruses of one song
# would otherwise share one title and read as three copies of a clip.
HOOK_TITLES = {
    1: "ร้องต่อไหม?",
    2: "ท่อนนี้คิดถึงใคร?",
    3: "ร้องต่อท่อนต่อไป",
}


def hook_angle(hook: int) -> str:
    return HOOK_ANGLES.get(hook, HOOK_ANGLES[1])


def hook_title(hook: int) -> str:
    return HOOK_TITLES.get(hook, HOOK_TITLES[1])


# The one honest sentence every description carries. K (2026-11-04): the channel
# is an AI music label and must say so plainly. The old copy claimed the songs
# were "ร้องด้วยเสียงจริง" (sung by a real voice), which is false — the vocals are
# generated — and a viewer who noticed would be right to feel misled.
LABEL = "🤖 AERIS Music — ค่ายเพลง AI สร้างเพลงและเสียงร้องด้วย AI"

# The follow ask burned onto the end of every Short. Shorts are the channel's
# only reach tool and its description sits below the fold, so until now a viewer
# was never asked to follow anywhere they would see it. Text only, no emoji: the
# burned-in font is Noto Sans Thai, which has no emoji glyph and renders tofu.
# A short end card, not a whole-length banner — the 2026-11-09 advisor panel
# (duck + pollinations, quorum PASS) warned that a persistent button clutters the
# song and can cost retention, and retention is reach.
FOLLOW_ASK = "กดติดตาม AERIS Music"
# The second line of the card. Both advisors put a *reason to return* first among
# the things that turn a first-time viewer into a follower, and the channel does
# publish daily — so the ask names the reward instead of asking into the void.
# It also stays true: the daily release rail posts a new song every day.
FOLLOW_PROMISE = "เพลงใหม่ทุกวัน"


def parse_lyrics(slug: str) -> dict:
    """Read the `# KEY: value` header block off a lyric file."""
    hdr: dict[str, str] = {}
    text = (LYRICS / f"{slug}.txt").read_text(encoding="utf-8")
    for line in text.splitlines():
        m = re.match(r"#\s*(TITLE|SUBTITLE|KEY|MOOD|TEMPO|VOICE)\s*:\s*(.+)", line)
        if m:
            hdr[m.group(1)] = m.group(2).strip()
            continue
        if line.strip() and not line.startswith("#"):
            break
    return hdr


def lyric_block(slug: str) -> str:
    """The song's lyric, for the description — the one searchable thing a song has.

    Search is the only discovery surface still at 0% (studio read 2026-11-13:
    browse 53%, suggested 33%, channel page 7%, search 0%). A title carries about
    six words; the lyric carries the whole song, so a viewer who remembers a line
    and types it can find the upload. YouTube indexes the full description text,
    not only the visible part, so the block sits below the fold without losing
    that.

    Section tags (`[chorus]`) and the `# KEY:` header are dropped — nobody
    searches for those — and a repeated stanza (the chorus is identical every
    time) is kept once, so the block reads as a lyric rather than a wall.
    """
    path = LYRICS / f"{slug}.txt"
    if not path.exists():
        return ""
    stanzas: list[list[str]] = []
    cur: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s:
            if cur:
                stanzas.append(cur)
                cur = []
            continue
        if s.startswith("#") or (s.startswith("[") and s.endswith("]")):
            continue
        cur.append(s)
    if cur:
        stanzas.append(cur)
    seen: set[str] = set()
    out: list[str] = []
    for st in stanzas:
        key = "\n".join(st)
        if key in seen:
            continue
        seen.add(key)
        out.append(key)
    return "\n\n".join(out)


def all_slugs() -> list[str]:
    return sorted(f.stem for f in LYRICS.glob("*.txt"))


def _release_asset_names() -> set:
    """Names of the media on the release, or empty if it cannot be read."""
    try:
        return set(_media_assets().keys())
    except Exception as exc:  # offline, bad token: fall back to what is on disk
        print(f"release listing unavailable ({type(exc).__name__}); using disk only")
        return set()


def _have(name: str, disk: Path) -> bool:
    return disk.exists() or name in _release_asset_names()


def has_song(slug: str) -> bool:
    return _have(f"song-{slug}.mp3", SONGS / f"song-{slug}.mp3")


def is_retired(slug: str) -> bool:
    """True when the on-disk song came from the rejected Piper engine.

    A song rebuilt by `make_song.py` is a TTS voice reshaped to a melody, which
    K ordered destroyed; it must never reach an upload. The signature is checked
    on the local file only — a song whose audio is not on disk is judged by the
    release asset list, where it can only be a Flow render (the Piper engine
    never published there).
    """
    song = SONGS / f"song-{slug}.mp3"
    if not song.exists():
        return False
    try:
        import provenance
        return provenance.verdict(song) == "retired"
    except Exception as exc:  # ffmpeg missing: fail closed, not open
        print(f"provenance check unavailable for {slug} ({type(exc).__name__}); "
              f"skipping the song rather than risk the retired engine", file=sys.stderr)
        return True


def is_bed(slug: str) -> bool:
    """True when the on-disk file is our offline real-instrument bed, not a song.

    The produce lane's keyless master is a 44.1 kHz instrumental; a Flow render
    is 48 kHz. Releasing a bed would put an instrumental on the channel under a
    song title, which is the bug K caught on 2026-11-07. A file not on disk is
    judged as "not a bed": the release asset list only ever holds Flow renders.
    """
    song = SONGS / f"song-{slug}.mp3"
    if not song.exists():
        return False
    try:
        import provenance
        return provenance.is_bed(song)
    except Exception:  # ffmpeg missing: fail closed, do not risk a bed release
        return True


SHORTS = ROOT / "library" / "shorts"

# At most this many Shorts per song reach the plan. One song yields three chorus
# cuts, but in the current catalogue all three choruses carry the *same* lyric
# lines (verified on `01-khon-di-thi-chak-pai`: three `[chorus]` blocks, identical
# text), so the three cuts are the same clip with a different caption -- exactly
# what the 2026-11-13 advisor panel (duck) warned against: "don't publish three
# cuts that are essentially the same excerpt with minor changes". Publishing one
# is a creative choice; publishing three is volume for its own sake, and volume
# was measured to hurt (see UPLOADS_PER_DAY). Raise this only when a song's
# choruses actually differ.
SHORTS_PER_SONG = 1


def short_files(slug: str, mix: str = "song") -> list[Path]:
    """Every Short for a song: the -h1/-h2 hook cuts, or the plain name alone.

    The plain `short-<mix>-<slug>.mp4` is the single-hook render. A song with
    hook cuts also has that file from an older single-hook run, and it is the
    same first chorus under a different name — so it is dropped whenever a hook
    cut exists, or the rail uploads the first chorus twice.

    A name may come from the release rather than disk; the path is returned
    either way and downloaded when it is actually uploaded.
    """
    hooks = sorted(
        n for n in _release_asset_names()
        if n.startswith(f"short-{mix}-h") and n.endswith(f"-{slug}.mp4"))
    plain = f"short-{mix}-{slug}.mp4"
    names = hooks if hooks else [plain]
    seen: list[str] = []
    for n in names:
        if n not in seen and _have(n, SHORTS / n):
            seen.append(n)
    return [SHORTS / n for n in seen[:SHORTS_PER_SONG]]


def has_short(slug: str, mix: str = "song") -> bool:
    return bool(short_files(slug, mix))


def has_video(slug: str, mix: str) -> bool:
    return _have(f"{mix}-{slug}.mp4", KARAOKE / f"{mix}-{slug}.mp4")


def load_state() -> dict:
    if STATE.exists():
        try:
            return json.loads(STATE.read_text(encoding="utf-8"))
        except ValueError:
            pass
    return {"released": [], "playlists": {}}


def _live_ledger() -> dict | None:
    """The ledger on `main`, which is the only record of what is on YouTube.

    The scheduled release runs in a different sandbox and writes its ledger back
    to `main` through the Contents API. A build pod's local `work/` copy can be
    hours stale, and planning from it re-uploads videos that are already live.
    Union against this before planning; `None` (offline) falls back to local.
    """
    tok = os.environ.get("AX_GH_TOKEN")
    if not tok:
        f = Path(os.environ.get("AX_GH_TOKEN_FILE",
                                "/workspace/ax-tools/ar-identity/gh-token"))
        if f.exists():
            tok = f.read_text().strip()
    if not tok:
        return None
    url = (f"https://api.github.com/repos/{MEDIA_REPO}/contents/"
           f"music938-1/work/release-state.json?ref=main")
    try:
        req = urllib.request.Request(url, headers={
            "Authorization": f"token {tok}", "User-Agent": "ax-release",
            "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(base64.b64decode(json.load(r)["content"]))
    except Exception as exc:  # noqa: BLE001 - offline must not stop a release
        print(f"[warn] could not read the live ledger ({exc}); using local only",
              file=sys.stderr)
        return None


def merge_ledger(state: dict) -> dict:
    """Fold the live ledger into the local one, keyed by (slug, kind, variant).

    A local record wins on ties because it carries the `at`/`video_id` the local
    run just wrote; the live ledger adds anything another sandbox released.
    """
    live = _live_ledger()
    if not live:
        return state
    key = lambda r: (r.get("slug"), r.get("kind"), r.get("variant", ""))
    seen = {key(r) for r in state.get("released", [])}
    added = 0
    for r in live.get("released", []):
        if key(r) not in seen:
            state.setdefault("released", []).append(r)
            seen.add(key(r))
            added += 1
    if added:
        print(f"[i] merged {added} release(s) from the live ledger on main")
    for k, v in (live.get("playlists") or {}).items():
        state.setdefault("playlists", {}).setdefault(k, v)
    return state


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")


# The Data API quota resets at midnight Pacific, not midnight UTC. A day that
# starts at UTC midnight would overcount by 7 hours and refuse a legal upload.
QUOTA_TZ_OFFSET_HOURS = -7


def _quota_day(ts: datetime) -> str:
    return (ts.astimezone(timezone.utc)
            + timedelta(hours=QUOTA_TZ_OFFSET_HOURS)).strftime("%Y-%m-%d")


def uploads_today(state: dict) -> int:
    """Uploads already spent in the current Pacific quota day."""
    day = _quota_day(datetime.now(timezone.utc))
    used = 0
    for r in state.get("released", []):
        try:
            if _quota_day(datetime.fromisoformat(r["at"])) == day:
                used += 1
        except (KeyError, ValueError):
            continue
    return used


def affiliate_cards() -> list[dict]:
    """The product cards, read from the tracked work file (may be empty)."""
    if not AFF_PRODUCTS.exists():
        return []
    try:
        return json.loads(AFF_PRODUCTS.read_text(encoding="utf-8")).get("products", [])
    except ValueError:
        return []


def affiliate_file(card: dict) -> Path:
    """The rendered card clip. A fresh pod has no library/, so the path is
    returned even when absent and `fetch_media` pulls it from the release."""
    return AFF_DIR / f"short-aff-{card['id']}.mp4"


def affiliate_pending(state: dict | None = None) -> int:
    """Product cards still to publish. Zero once every card is live, so the
    reserve stops holding slots for work that is already done."""
    done = {(r.get("slug"), r.get("kind"))
            for r in (state or load_state()).get("released", [])}
    return sum(1 for c in affiliate_cards()
               if (c["id"], "affiliate") not in done)


def describe_affiliate(card: dict) -> tuple[str, str, list[str]]:
    """Title, description and tags for one product card on YouTube.

    Layout from the 2026-11-05 advisor panel (3/3, `consult-brief-affiliate-link-fold`):
    a URL in a Short's description — or a pinned comment — is **not tappable**,
    so the clickable route is the channel profile link. The first two lines, the
    only ones above "Show more", therefore carry the mandatory disclosure and a
    CTA pointing at the profile, with the tracked short URL kept as a copyable
    fallback and for attribution. The hook and bullets follow below the fold;
    the video already shows them on screen.
    """
    hookline = card.get("hookline") or card["title"]
    bullets = "\n".join(f"• {b}" for b in card.get("bullets", [])[:3])
    link = monetize.link("youtube")
    # Search-first packaging (2026-11-09). A Google Suggest pull showed
    # `ของน่าซื้อ` is a souvenir/gift term, not a headphone-buying term, so the
    # old tag reached nobody who was shopping. The title and the hashtags now
    # carry the card's real query (`card["search"]`), because on a zero-follower
    # channel search is the only free discovery path.
    title = f"{card['title']} | #Shorts"
    search = card.get("search", "หูฟังบลูทูธ")
    desc = (
        f"⚠️ {AFF_DISCLOSURE}\n"
        f"🛒 ดูสินค้า/สั่งซื้อ: กดลิงก์ Shopee ที่หน้าโปรไฟล์ช่อง 👉 {link}\n\n"
        f"🎬 {hookline}\n"
        f"{bullets}\n"
        f"🎵 เพลงจาก AERIS Music — ค่ายเพลง AI\n\n"
        f"#{search.replace(' ', '')} #หูฟังบลูทูธ #ยี่ห้อไหนดี #Shopee #AERISMusic #Shorts"
    )
    tags = [search, "หูฟังบลูทูธ", "หูฟัง", "ลำโพงบลูทูธ", "ยี่ห้อไหนดี",
            "รีวิวหูฟัง", "Shopee", "AERISMusic", "shorts"]
    return title[:100], desc[:4900], tags[:30]


def describe(slug: str, kind: str, variant: str = "") -> tuple[str, str, list[str]]:
    """Return (title, description, tags) for one release.

    `variant` distinguishes the hook cuts of one song, so three Shorts from the
    same song are three different uploads rather than a duplicate.

    Title shape is set from the competitor scan (2026-10-30, `work/competitors.json`):
    of 1,546 videos, the ones past 100k views averaged 47.9 characters and used
    `|` in only 8% of titles, while the sub-1k videos averaged 60.7 characters and
    used `|` in 38.9%. YouTube truncates past ~60 characters, so the tail is what
    gets cut first. The old titles appended `| AERIS Music` to every single
    release, which is the losing shape; the brand is already the channel name, so
    it is dropped from the Shorts and karaoke titles and the words are spent on
    searchable Thai instead.
    """
    h = parse_lyrics(slug)
    title_th = h.get("TITLE", slug)
    mood = h.get("MOOD", "calm")
    # A genre owns the tagline when the lyric declares one; a song without a
    # `# GENRE:` header keeps the mood tagline, so the first 20 are unchanged.
    tagline = genres.tagline_for(slug, mood, TAGLINE) or TAGLINE["calm"]
    extra_tags = genres.hashtags_for(slug)
    n = slug.split("-")[0]

    # The affiliate line sits near the top of the description, before YouTube's
    # "Show more" fold, so it is actually seen. See monetize.cta().
    CTA = monetize.cta("youtube")

    if kind == "short":
        # The 2026-11-05 advisor panel (3/3) on the growth stall: the old
        # "(ท่อนที่ N)" title made each upload read as "part N of 3" of the same
        # song, which gave a viewer no reason to watch *this* clip or follow.
        # The series label replaces it, and the sing-along prompt below gives the
        # comment box something answerable to ask for.
        hm = re.search(r"-h(\d+)-", variant)
        hk = int(hm.group(1)) if hm else 1
        title = f"{title_th} | {hook_title(hk)} #Shorts"
        angle = hook_angle(hk)
        desc = (
            f"🎵 {title_th} — {hook_title(hk)}\n"
            f"{tagline}\n\n"
            f"{angle} 👇\n\n"
            f"{LABEL}\n"
            f"{CTA}\n"
            f"🎧 ฟังเวอร์ชันเต็มได้ในช่อง\n\n"
            f"{HASHTAGS} #Shorts"
        )
    elif kind == "karaoke":
        title = f"{title_th} (คาราโอเกะ) ร้องตามได้"
        desc = (
            f"🎤 {title_th} — เวอร์ชันคาราโอเกะ (ไม่มีเสียงร้อง)\n\n"
            f"ร้องตามได้เลย! {tagline}\n"
            f"{LABEL}\n"
            f"{CTA}\n\n"
            f"🎵 เพลงที่ {int(n)} ในชุดเพลงไทยของ AERIS Music\n"
            f"🎧 ฟังเวอร์ชันเต็ม (มีเสียงร้อง) ได้ในช่อง\n\n"
            f"{HASHTAGS}"
        )
    else:
        title = song_title(title_th, tagline, mood)
        desc = (
            f"🎵 {title_th}\n\n"
            f"{tagline}\n"
            f"{LABEL}\n"
            f"{CTA}\n\n"
            f"เพลงที่ {int(n)} ในชุดเพลงไทยของ AERIS Music — เนื้อร้องและทำนองใหม่\n\n"
            f"🎧 ฟังเพลิน ฟังได้ทุกวัน\n\n"
            f"{HASHTAGS}"
        )
    # The lyric is the only large searchable body a song upload has, and search
    # was the one discovery surface still at 0%. Append it for the long-form song
    # and the karaoke cut (a sing-along is looked up by its lyric); a Short is too
    # small to carry a stanza block without burying the ask.
    if kind in ("song", "karaoke"):
        ly = lyric_block(slug)
        if ly:
            desc = f"{desc}\n\n📝 เนื้อเพลง\n\n{ly}"
    tags = ["เพลงไทย", "เพลงใหม่", "ศิลปินไทย", "AERIS", "เพลงเพราะ",
            "เพลงฟังสบาย", "ค่ายเพลง AI", "AI music", title_th, tagline,
            "thai music", "thai song"]
    tags += [t for t in extra_tags if t not in tags]
    # Every description carries the outbound links from channel/monetization.json.
    desc = desc.rstrip() + "\n" + monetize.block(kind)
    # The paid offer sits above the socials footer, on songs and compilations
    # only — a Short is too small to sell a commission in and it would push the
    # product link below the fold.
    if kind in ("song", "compilation"):
        desc = desc.rstrip() + monetize.commission_block()
    return title[:100], desc[:4900], tags[:30]


def playlist_for(kind: str) -> tuple[str, str]:
    """(title, description) of the playlist this kind of release belongs in."""
    if kind == "short":
        return ("ท่อนฮุก — เพลงไทยสั้น ๆ",
                "รวมท่อนฮุกของทุกเพลงในชุด ฟังสั้น ๆ ได้ใจความ\n\n"
                "AERIS Music · ค่ายเพลง AI")
    if kind == "karaoke":
        return ("คาราโอเกะ — ร้องตามได้ทุกเพลง",
                "รวมทุกเพลงในชุดเป็นเวอร์ชันคาราโอเกะ ไม่มีเสียงร้อง ร้องตามได้เลย\n\n"
                "AERIS Music · ค่ายเพลง AI")
    if kind == "affiliate":
        return ("รีวิว/ก่อนซื้อ — หูฟัง & ลำโพง (คลิปพร้อมลิงก์)",
                "รวมคลิปให้ความรู้ก่อนซื้อหูฟังและลำโพง พร้อมลิงก์พันธมิตร Shopee — "
                "ดูราคา/สั่งซื้อได้จากลิงก์ในคำอธิบาย\n\n"
                "AERIS Music · ค่ายเพลง AI")
    return ("เพลงไทย — รวมทุกเพลง",
            "รวมทุกเพลงไทยของ AERIS Music ป็อป แดนซ์ ร็อก เนื้อร้องและทำนองใหม่\n\n"
            "AERIS Music · ค่ายเพลง AI")


def ensure_playlist(state: dict, kind: str, ch: str) -> str | None:
    """Create the playlist once and remember its id in the state file."""
    title, desc = playlist_for(kind)
    key = f"{ch}:{kind}"
    if state.get("playlists", {}).get(key):
        return state["playlists"][key]

    sys.path.insert(0, str(OPS))
    import yt_auth  # noqa: E402
    import urllib.request  # noqa: E402
    import urllib.error  # noqa: E402
    tok = yt_auth.access_token(ch)
    body = json.dumps({
        "snippet": {"title": title[:150], "description": desc[:5000],
                    "defaultLanguage": "th"},
        "status": {"privacyStatus": "public"},
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://www.googleapis.com/youtube/v3/playlists?part=snippet,status",
        data=body, method="POST",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            pid = json.loads(r.read())["id"]
    except urllib.error.HTTPError as e:
        print(f"playlist create failed: HTTP {e.code} {e.read()[:200]}", file=sys.stderr)
        return None
    state.setdefault("playlists", {})[key] = pid
    print(f"created playlist {pid}: {title}")
    return pid


def add_to_playlist(playlist_id: str, video_id: str, ch: str) -> bool:
    sys.path.insert(0, str(OPS))
    import yt_auth  # noqa: E402
    import time  # noqa: E402
    import urllib.request  # noqa: E402
    import urllib.error  # noqa: E402
    tok = yt_auth.access_token(ch)
    body = json.dumps({
        "snippet": {"playlistId": playlist_id,
                    "resourceId": {"kind": "youtube#video", "videoId": video_id}},
    }).encode("utf-8")
    # A 409 SERVICE_UNAVAILABLE / 5xx here is transient — the video is already
    # uploaded, so losing the playlist row costs a discovery slot on a video that
    # is otherwise live. Retry those; a real 403 (quota) still returns at once so
    # the caller's reservation logic is not stalled.
    for attempt in range(3):
        req = urllib.request.Request(
            "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet",
            data=body, method="POST",
            headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as r:
                r.read()
            return True
        except urllib.error.HTTPError as e:
            detail = e.read()[:200]
            transient = e.code in (409, 500, 502, 503, 504)
            print(f"playlist insert failed: HTTP {e.code} {detail}", file=sys.stderr)
            if not transient or attempt == 2:
                return False
            time.sleep(2 * (attempt + 1))
        except Exception as exc:  # noqa: BLE001 - a socket blip must not lose the row
            print(f"playlist insert error: {exc}", file=sys.stderr)
            if attempt == 2:
                return False
            time.sleep(2 * (attempt + 1))
    return False


def pinned_songs() -> list[str]:
    """Songs K asked to publish next, in order (work/release-priority.json).

    A normal release is a rotation: one chorus per song per round, so a new song
    waits behind the whole catalogue. When K hands over one finished song and
    says "post it now", that rotation would delay it days. The pin moves the
    named song's items to the front of the *pending* queue only — it reorders,
    it does not add or skip anything, so the cadence and the ledger are
    untouched and the file can be emptied once the song is live.
    """
    try:
        data = json.loads(PRIORITY.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    songs = data.get("songs", data) if isinstance(data, dict) else data
    return [s for s in songs if isinstance(s, str)]


def _pin_front(todo: list[dict], pins: list[str]) -> list[dict]:
    """Move the pinned songs' items to the front of the pending queue.

    The rotation interleaves one Short per song per round, so a brand-new song
    waits behind the whole catalogue; K's "post it now" needs it ahead of that.
    The pin promotes the song's main release and its first Short, and leaves its
    remaining Shorts in their rotation slots — promoting all of them would put
    three takes of one song back to back, which the 2026-11-05 panel called a
    repost. It only reorders; nothing is added or skipped.
    """
    if not pins:
        return todo
    rank = {s: i for i, s in enumerate(pins)}
    front: list[dict] = []
    rest: list[dict] = []
    took_short: set[str] = set()
    for it in todo:
        s = it["slug"]
        if s in rank:
            if it["kind"] == "short" and s in took_short:
                rest.append(it)
                continue
            if it["kind"] == "short":
                took_short.add(s)
            front.append(it)
        else:
            rest.append(it)
    front.sort(key=lambda it: (rank[it["slug"]], 0 if it["kind"] == "song" else 1))
    return front + rest


def plan(days: int, shorts: bool = False, spread: float = 0,
         kind: str | None = None, slug: str | None = None) -> list[dict]:
    """Pair each built song with its karaoke into a dated release list.

    Shorts are discovery, not catalogue: a zero-subscriber channel gets no
    long-form impressions (AERIS Music's own numbers: 382 of 449 lifetime views
    came from Shorts, ~33 from long-form). They are planned first, so the
    audience exists before the watch-hour videos need one.
    """
    state = merge_ledger(load_state())
    done = {(r["slug"], r["kind"], r.get("variant", "")) for r in state["released"]}
    items: list[dict] = []
    # Product cards lead the queue. Every Short on the channel so far is a song,
    # and a song gives nobody a reason to buy, so the affiliate funnel had no
    # content of its own. One card per product goes out first, before the song
    # Shorts, so the purchase-intent clips are not buried behind the catalogue.
    for card in affiliate_cards():
        variant = f"short-aff-{card['id']}"
        if (card["id"], "affiliate", variant) in done:
            continue
        items.append({"slug": card["id"], "kind": "affiliate",
                      "video": affiliate_file(card), "variant": variant,
                      "card": card})
    # Build one group per song: its Shorts, then its long-form release. The
    # groups are then interleaved round-robin, so consecutive uploads are
    # *different* songs. The 2026-11-05 advisor panel (3/3) on the growth stall:
    # three numbered parts of one song back to back read as one clip reposted
    # and gave a viewer no reason to follow. With 10 songs pending, a round of
    # h1 is ten distinct songs on ten days, not one song three times a day.
    groups: list[list[dict]] = []
    # `song`, not `slug`: the function also takes a `slug` argument to select one
    # song, and a loop variable of the same name clobbered it, so --slug silently
    # filtered on the last song in the list and matched nothing.
    for song in all_slugs():
        if not has_song(song):
            continue
        if is_retired(song):
            # A rebuilt song is the rejected engine; it must not be uploaded.
            print(f"skip {song}: rebuilt by the retired Piper engine "
                  f"(see scripts/provenance.py)", file=sys.stderr)
            continue
        if is_bed(song):
            # An offline bed is a real-instrument instrumental, not a song. The
            # produce lane labels it `synth-bed` and it exists as raw material for
            # clips; releasing it would put an instrumental on the channel under a
            # song title — the "bed shipped as a song" bug K caught (2026-11-07).
            print(f"skip {song}: offline bed, not a sung song "
                  f"(see scripts/provenance.py)", file=sys.stderr)
            continue
        group = [{"slug": song, "kind": "short", "video": v, "variant": v.stem}
                 for v in short_files(song, "song")]
        # The main release only. The sing-along (karaoke) variant is retired
        # (K, 2026-11-03): its lyric sweep was estimated, not measured, and
        # drifted off the sung line, so it was ordered dropped. Already-live
        # karaoke videos stay up; nothing new is planned.
        if not shorts and has_video(song, "song"):
            group.append({"slug": song, "kind": "song",
                          "video": KARAOKE / f"song-{song}.mp4", "variant": ""})
        if group:
            groups.append(group)
    depth = max((len(g) for g in groups), default=0)
    for i in range(depth):
        for group in groups:
            if i < len(group):
                items.append(group[i])
    todo = [i for i in items if (i["slug"], i["kind"], i.get("variant", "")) not in done]
    if kind:
        # A song release is what K reviews; the queue interleaves the affiliate
        # cards and the Shorts first, so without this the long-form clip is
        # several uploads deep. Filtering keeps the cadence intact and just
        # chooses which pending item goes next.
        todo = [i for i in todo if i["kind"] == kind]
    if slug:
        todo = [i for i in todo if i["slug"] == slug]
    # A pin is only live while the song's main release is still pending: once it
    # is uploaded the file is inert, so the song's remaining Shorts fall back
    # into their rotation slots instead of leading every day.
    pending_songs = {i["slug"] for i in todo if i["kind"] == "song"}
    todo = _pin_front(todo, [s for s in pinned_songs() if s in pending_songs])
    start = datetime.now(timezone.utc)
    for i, item in enumerate(todo):
        if spread:
            # A 24h spread: consecutive items go out `spread` hours apart, so the
            # channel is active around the clock instead of bursting then going
            # quiet. YouTube publishes each on its own publishAt.
            item["when"] = start + timedelta(hours=i * spread)
            item["schedule"] = item["when"].strftime("%Y-%m-%dT%H:%M:%SZ")
        else:
            item["when"] = start + timedelta(days=i // UPLOADS_PER_DAY)
    return todo[: days * UPLOADS_PER_DAY] if days else todo


def progress(path: str | None, line: str) -> None:
    """Append one progress line, so an unattended run can report where it is."""
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"{datetime.now(timezone.utc).strftime('%H:%M:%S')} {line}\n")
    except OSError:
        pass


def _gh_headers(accept: str = "application/vnd.github+json") -> dict:
    tok = os.environ.get("AX_GH_TOKEN") or ""
    if not tok:
        f = Path(os.environ.get("AX_GH_TOKEN_FILE", "/workspace/ax-tools/ar-identity/gh-token"))
        if f.exists():
            tok = f.read_text().strip()
    h = {"User-Agent": "ax-release", "Accept": accept}
    if tok:
        h["Authorization"] = f"token {tok}"
    return h


def _media_assets() -> dict:
    """Name -> (download URL, size, asset id) for the media release.

    Fetched once per process. The asset id is kept because the release's
    `browser_download_url` 302-redirects to a separate CDN host that returns
    transient 504s under load — that is what killed the 2026-11-08 batch. The
    API's own `releases/assets/<id>` endpoint streams the same bytes with no
    redirect and measured ~35x faster (0.3s vs 10.9s), so `fetch_media`
    prefers it and keeps the browser URL as a fallback.
    """
    global _ASSET_CACHE
    if _ASSET_CACHE is not None:
        return _ASSET_CACHE
    import urllib.request
    hdrs = _gh_headers()
    base = f"https://api.github.com/repos/{MEDIA_REPO}/releases/tags/{MEDIA_RELEASE}"
    with urllib.request.urlopen(urllib.request.Request(base, headers=hdrs), timeout=60) as r:
        rid = json.load(r)["id"]
    out: dict = {}
    page = 1
    while True:
        url = f"https://api.github.com/repos/{MEDIA_REPO}/releases/{rid}/assets?per_page=100&page={page}"
        with urllib.request.urlopen(urllib.request.Request(url, headers=hdrs), timeout=60) as r:
            batch = json.load(r)
        for a in batch:
            out[a["name"]] = (a["browser_download_url"], a["size"], a["id"])
        if len(batch) < 100:
            break
        page += 1
    _ASSET_CACHE = out
    return out


def fetch_media(path: Path) -> Path:
    """Download one media file from the release if it is not on disk yet.

    The API asset endpoint is tried first, then the browser URL, and each is
    retried. A transient 504 from the media CDN used to escape as a traceback
    and abort the whole daily batch — the 2026-11-08 run uploaded nothing for
    exactly that reason. After the retries the file is left missing, which
    `release_one` turns into a clean rc 2 that the batch loop skips.
    """
    if path is None or path.exists():
        return path
    import time
    import urllib.request
    info = _media_assets().get(path.name)
    if not info:
        return path
    browser_url, size, asset_id = info
    api_url = (f"https://api.github.com/repos/{MEDIA_REPO}/releases/assets/{asset_id}")
    path.parent.mkdir(parents=True, exist_ok=True)
    attempts = [(api_url, _gh_headers("application/octet-stream")),
                (browser_url, {"User-Agent": "ax-release"})]
    last: Exception | None = None
    for attempt in range(3):
        url, hdrs = attempts[min(attempt, len(attempts) - 1)]
        try:
            with urllib.request.urlopen(urllib.request.Request(
                    url, headers=hdrs), timeout=300) as r:
                data = r.read()
            path.write_bytes(data)
            print(f"  fetched {path.name} ({size / 1e6:.1f} MB)")
            return path
        except Exception as exc:  # noqa: BLE001 - a CDN blip must not abort the batch
            last = exc
            if attempt < 2:
                time.sleep(5 * (attempt + 1))
    print(f"  could not fetch {path.name} after 3 tries ({last}); skipping",
          file=sys.stderr)
    return path


def release_one(item: dict, args) -> int:
    """Upload one planned item, schedule it if asked, and record it."""
    slug, kind = item["slug"], item["kind"]
    state = load_state()
    used = uploads_today(state)
    if used >= UPLOADS_PER_DAY:
        print(f"today's uploads are done: {used}/{UPLOADS_PER_DAY} already "
              f"made this Pacific day. This is the 6/day cadence, not a quota "
              f"wall — videos.insert has its own 100/day bucket. Try after "
              f"09:00 UTC.",
              file=sys.stderr)
        return 3
    if kind == "affiliate":
        title, desc, tags = describe_affiliate(item["card"])
    else:
        title, desc, tags = describe(slug, kind, item.get("variant", ""))
    video = item["video"]
    if not video or not video.exists():
        video = fetch_media(video)
    if not video or not video.exists():
        print(f"missing {kind} video for {slug}; render it with "
              f"make_karaoke.py {slug} --mix {kind}", file=sys.stderr)
        return 2

    desc_file = ROOT / "work" / f"release-{slug}-{kind}.txt"
    tags_file = ROOT / "work" / f"release-{slug}-{kind}.tags"
    desc_file.write_text(desc, encoding="utf-8")
    tags_file.write_text(",".join(tags), encoding="utf-8")
    # A 16:9 thumbnail, not the square cover: YouTube renders at 16:9 and would
    # pillarbox the cover. A Short's own frame is 9:16 and is used as-is, since
    # Shorts thumbnails are vertical.
    release_names = _release_asset_names()
    thumb = ROOT / "library" / "thumbs" / f"thumb-{kind}-{slug}.png"
    if item.get("variant"):
        vt = ROOT / "library" / "thumbs" / f"thumb-{item['variant']}.png"
        # The variant thumb may exist only on the release (a fresh pod has an
        # empty library/), so check the release list too before falling back to
        # the square cover, which is the wrong shape for a Short.
        if vt.exists() or vt.name in release_names:
            thumb = vt
    if not thumb.exists():
        thumb = fetch_media(thumb)
    if not thumb.exists():
        thumb = COVERS / f"cover-{slug}.jpg"
        if not thumb.exists():
            thumb = fetch_media(thumb)

    cmd = [sys.executable, str(OPS / "yt_publish.py"), "--ch", args.ch,
           "--video", str(video), "--title", title,
           "--desc-file", str(desc_file), "--tags-file", str(tags_file),
           "--category", "22" if kind == "affiliate" else "10",
           "--privacy", "public" if args.public else "private"]
    # A scheduled publish is how the channel stays active around the clock:
    # YouTube flips it to public at the given time without anything running here.
    when = args.schedule_at or item.get("schedule")
    if when:
        cmd += ["--schedule", when]
    if thumb.exists():
        cmd += ["--thumb", str(thumb)]
    print(" ".join(cmd))
    if args.dry_run:
        return 0

    import subprocess
    proc = subprocess.run(cmd, text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        # A channel-level cap, distinct from the API's 100/day insert bucket:
        # YouTube throttles how many videos an account may upload in a day and
        # returns `uploadLimitExceeded`. There is no point trying the rest of the
        # batch, and it is not a defect to report — treat it as the day being
        # done (rc 3), the same as a spent cadence, so the workflow stays green.
        if "uploadLimitExceeded" in proc.stdout or "uploadLimitExceeded" in proc.stderr:
            print("upload limit reached for today; stopping the batch", file=sys.stderr)
            return 3
        return proc.returncode
    m = re.search(r"video id (\S+)", proc.stdout)
    vid = m.group(1) if m else None
    # videos.insert has its own 100/day bucket, but thumbnails.set draws on the
    # shared 10,000-unit pool. On a spent day the video uploads (HTTP 200) and the
    # thumbnail returns 403, so the video goes live with YouTube's auto frame and
    # nothing retried it — a silent quality loss on every late-in-the-day upload.
    # Record the outcome so `fix_thumbnails.py` can repair it once quota is fresh.
    tm = re.search(r"thumbnail HTTP (\d+)", proc.stdout)
    thumb_ok = (tm.group(1) == "200") if tm else None
    if thumb_ok is not None:
        # Price the call whether it worked or not: a 403 still burned nothing,
        # but the ledger must reflect the *attempt* so the next worker's
        # pre-flight sees the pool as the API does.
        yt_quota.record("thumbnails.set")
    state = load_state()
    # A new release belongs in the right playlist, or the channel looks like a
    # pile of loose videos rather than a catalogue. Created lazily on first use.
    # playlistItems.insert draws on the same 10,000-unit pool as thumbnails.set,
    # so it fails for the same reason and is repaired by the same script.
    playlist_ok = None
    if vid:
        pid = ensure_playlist(state, kind, args.ch)
        playlist_ok = bool(pid) and add_to_playlist(pid, vid, args.ch)
        yt_quota.record("playlistItems.insert")
    state["released"].append({
        "slug": slug, "kind": kind, "variant": item.get("variant", ""),
        "video_id": vid,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "public": bool(args.public),
        "thumb_ok": thumb_ok,
        "playlist_ok": playlist_ok,
    })
    save_state(state)
    print(f"recorded in {STATE.relative_to(ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", action="store_true", help="show the schedule, send nothing")
    ap.add_argument("--days", type=int, default=0, help="limit the plan to N days")
    ap.add_argument("--next", action="store_true", help="release the first item in the plan")
    ap.add_argument("--count", type=int, default=1,
                    help="release this many items in one run (each scheduled in turn)")
    ap.add_argument("--shorts", action="store_true",
                    help="plan Shorts only (the discovery-first queue)")
    ap.add_argument("--kind", choices=("song", "short", "affiliate"),
                    help="release only this kind (e.g. the long-form song clips)")
    ap.add_argument("--slug", help="release only this song (one specific upload)")
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--public", action="store_true",
                    help="publish publicly; without it the upload stays private for K")
    ap.add_argument("--schedule-at", help="ISO8601 UTC to publish, e.g. 2026-10-31T15:00:00Z")
    ap.add_argument("--spread", type=float, default=0,
                    help="hours between the items of one batch (a 24h activity spread)")
    ap.add_argument("--progress-file",
                    help="append one line per action, so an unattended run can report progress")
    ap.add_argument("--quota-ok", action="store_true",
                    help="skip the shared-pool pre-flight (manual override; the "
                         "upload may then go live without its thumbnail)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    todo = plan(args.days, shorts=args.shorts, spread=args.spread, kind=args.kind,
                slug=args.slug)
    progress(args.progress_file, f"plan: {len(todo)} pending")
    if args.plan or not args.next:
        if not todo:
            print("nothing to release yet — no built songs found")
            print("(generation is window-gated; see scripts/watch.sh)")
            return 0
        print(f"{len(todo)} releases pending, {UPLOADS_PER_DAY}/day "
              f"(cadence choice; videos.insert bucket is 100/day):\n")
        for item in todo[:24]:
            kind = {"karaoke": "KARAOKE", "short": "SHORT  ",
                    "affiliate": "AFF    "}.get(item["kind"], "SONG   ")
            print(f"  {item['when']:%Y-%m-%d %H:%M}  {kind}  {item['slug']}")
        if len(todo) > 24:
            print(f"  ... and {len(todo) - 24} more")
        return 0

    # A batch is what keeps the channel active around the clock: each item is
    # scheduled `spread` hours after the previous, so the uploads cover the day
    # instead of landing together. Without --spread they all go out now.
    #
    # Reserve the shared pool BEFORE the first upload. `videos.insert` has its own
    # bucket, so an upload always succeeds — which is exactly the trap: on a spent
    # pool the video goes live with no thumbnail and no playlist row. Refusing to
    # start is the only outcome that does not leave a half-finished video behind.
    batch = todo[: args.count]
    need = len(batch) * yt_quota.UNITS_PER_RELEASE
    if not args.quota_ok and not yt_quota.reserve(
            need, purpose=f"release {len(batch)} item(s)", commit_it=not args.dry_run):
        left = yt_quota.remaining()
        print(f"shared quota pool too low: need {need} units for {len(batch)} "
              f"release(s), {left} left today. Holding the batch until the pool "
              f"resets at midnight Pacific — a video that cannot get its "
              f"thumbnail is a video nobody clicks.", file=sys.stderr)
        return 3

    rc = 0
    for i, item in enumerate(batch):
        if i:
            print(f"--- release {i + 1}/{args.count} ---")
        progress(args.progress_file,
                 f"release {i + 1}/{args.count} {item['kind']} {item['slug']}")
        rc = release_one(item, args)
        progress(args.progress_file, f"  -> rc {rc}")
        # rc 2 is one item whose media could not be fetched — a missing asset,
        # not a spent day. Skip it and try the next, or one bad thumbnail ends
        # the whole batch (the 2026-11-08 run uploaded nothing for exactly this
        # reason). rc 3 means the day's slots are gone, so the batch is over.
        if rc == 2:
            print(f"skipping {item['kind']} {item['slug']} (no media); "
                  f"continuing the batch", file=sys.stderr)
            rc = 0
            continue
        if rc != 0:
            break
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
