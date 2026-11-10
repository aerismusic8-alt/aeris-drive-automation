#!/usr/bin/env python3
"""The absurdist identity for the Facebook + TikTok surfaces.

K (2026-11-09): "อยากให้ทำช่อง fb tk แบบไม่ต้องสนใจแบบแปนอะไรแล้ว เอาแบบสุดโต่ง
แต่ไม่ผิดกฏ บ้าๆบอๆหลุดโลกไปเลย แบบศิลปะขั้นหลุดโลกไปเลย ทำแบบไม่ต้องหวังอะไรแล้ว
ขายงานไอเดียบ้าๆของเราที่ไม่มีใครทำ" — go extreme, absurd, unhinged-art on FB and
TikTok, but never break the rules; stop chasing a tidy "plan" and sell the idea
itself, the one nobody else is doing.

So this module is the single source of truth for that identity: the slogan, the
recurring ritual, the absurd captions and the guardrails that keep "unhinged"
from meaning "banned". The advisor panel (duck + pollinations, 2026-11-09,
quorum PASS) was unanimous on the shape:

  * do it, but keep ONE recognizable rule so the strangeness reads as an
    intentional art project, not random noise;
  * keep every clip short (< 30 s) and never mass-produce look-alikes — the
    single biggest risk is a reach-killing "low-quality / spammy" flag, not an
    outright ban;
  * disclose the AI content every time;
  * leave YouTube as the tidy music library, and let it stay the place a
    stranger goes to actually hear the songs.

Four surfaces, four jobs, one catalogue:
  YouTube   — the library (full tracks, compilations, the sleep loop). Safe.
  Facebook  — the gallery. Absurdist art, curated, one idea a post.
  TikTok    — the experiment. Same absurdism, fastest and most raw.
  Shopee    — the funnel. Unchanged; the disclosure rules still apply.

Rule #1 still holds: everything here is free. The art is ffmpeg filters on the
covers we already own; nothing is downloaded and nothing is paid for.
"""
from __future__ import annotations

# ── the identity ──────────────────────────────────────────────────────────────
# The one-line promise the panel asked for: not a mood word, a *rule* a stranger
# can recognise across every post. Thai, no emoji (the burned font is Noto Sans
# Thai with no emoji glyph — an emoji renders as tofu).

NAME = "AERIS"
SLOGAN = "AERIS — เพลงไทยที่หลุดโลก"          # the wordmark subtitle
PROJECT = "ศิลปะเสียงหลุดโลก"                  # what the project calls itself

# The recurring ritual, stated in Thai. Both advisors said the same thing: the
# absurdity only retains an audience if it is *a rule* — "every post turns one
# ordinary Thai thing into one impossible feeling" — and then asks the viewer to
# play. This is that rule, and it is what turns noise into a movement.
RITUAL = "ของธรรมดา 1 อย่าง → ความรู้สึกที่เป็นไปไม่ได้ 1 อย่าง"
RITUAL_ASK = "ของธรรมดาอะไรอยากให้เราแปลงเป็นเพลงต่อ? คอมเมนต์มาเลย"

# The AI disclosure. COMPLIANCE.md requires synthetic content be disclosed; the
# burned font cannot draw an emoji, so this stays plain Thai.
AI_NOTE = "เสียงร้องและภาพสร้างด้วย AI"

# ── the closed vocabulary ─────────────────────────────────────────────────────
# A surreal premise is written as `<ordinary Thai thing>` + `<impossible feeling>`
# and every one is drawn from these two closed lists, so a caption can never
# drift into a real-world claim. Same reason the affiliate cards have a banned-
# claim guard: an absurd line that accidentally asserts something checkable
# ("you will get rich", "this cures X") is a rules risk, and the panel named that
# as the trap. Randomness here is *bounded*.
ORDINARY = (
    "ตู้เย็น", "พัดลมเพดาน", "กะละมัง", "ส้มตำจานสุดท้าย", "หมาแถวบ้าน",
    "เสาไฟฟ้าหน้าปากซอย", "มอเตอร์ไซค์รับจ้าง", "ตุ๊กตาไล่ฝน", "ร้านก๋วยเตี๋ยวป้า",
    "รองเท้าแตะคู่โปรด", "หน้าต่างรถเมล์", "นาฬิกาปลุกที่ตายไปแล้ว",
    "พระจันทร์", "ปลากัดในโหล", "ถังน้ำแข็งเซเว่น", "ป้ายรถเมล์เก่า ๆ",
)
IMPOSSIBLE = (
    "ความคิดถึงที่ไม่เคยส่งถึง", "ความเหงาที่มีขา", "ความฝันที่ลืมรหัส",
    "เวลาเดินถอยหลัง", "ความรักที่ก่อสร้างไม่เสร็จ", "เสียงหัวใจที่ดังเป็นก้อง",
    "ความจำที่ถูกเก็บในตู้เย็น", "คำลาที่ลอยขึ้นฟ้า", "ความหวังที่ยังไม่ตื่น",
    "ความคิดถึงที่ทอดไข่ได้", "ความเศร้าที่นั่งรถเมล์ผิดสาย",
)

# ── guardrails ────────────────────────────────────────────────────────────────
# Forbidden substrings: over-claims and regulated categories. A caption line
# carrying one is refused by `claim_problem`, not published. This list is about
# *claims we make*, not about words a sad Thai song is allowed to contain — the
# first draft also banned "ตาย"/"ฆ่า", which collided with a legitimate song
# title and blocked the whole gallery. Words that are normal in lyrics are not
# claims and are not a platform risk here.
BANNED = (
    "รวยแน่นอน", "กำไร", "ลงทุน", "การันตี", "100%", "หายป่วย", "รักษาโรค",
    "ยาเสพติด", "พนัน", "เดิมพัน", "โป๊", "อนาจาร", "ฟรีเงิน", "กู้เงิน",
)

# ── the posting identity is per-surface ───────────────────────────────────────
# Facebook is the gallery and TikTok is the lab; YouTube stays the library. The
# handles are here so a caption never hard-codes one.
HANDLES = {
    "youtube": "@aerismusicth",
    "tiktok": "@aeris.music4",
    "facebook": "AERIS Music",
}


# ── the exhibits ──────────────────────────────────────────────────────────────
# Each song becomes one "exhibit" in the museum: an ordinary thing and an
# impossible feeling, paired deterministically from the song slug so the caption
# is stable across renders and the same song never gets two different premises.
# The pairing uses the slug's own bytes, not `random`, so a rebuild on a fresh
# pod produces the identical exhibit.

def _seed(text: str) -> int:
    n = 0
    for ch in text:
        n = (n * 131 + ord(ch)) % (2 ** 31)
    return n


def pair(slug: str) -> tuple[str, str]:
    """The (ordinary thing, impossible feeling) this song is filed under."""
    s = _seed(slug)
    return ORDINARY[s % len(ORDINARY)], IMPOSSIBLE[(s // 7) % len(IMPOSSIBLE)]


def exhibit_no(slug: str) -> str:
    """A stable, silly catalogue number, e.g. `หอศิลป์-041`."""
    return f"หอศิลป์-{(_seed(slug) % 999) + 1:03d}"


def title_line(slug: str) -> str:
    """The exhibit's one-line title: `<thing> : <feeling>`."""
    thing, feeling = pair(slug)
    return f"{thing} : {feeling}"


def caption(slug: str, platform: str, song_title: str = "") -> str:
    """The museum-label caption. Thai, absurd, rule-safe, AI-disclosed.

    Shape (same on both surfaces, tuned per surface):
      line 1  the exhibit number + rule  — the recognisable ritual
      line 2  the exhibit title          — the absurd pairing
      line 3  the song it beds on
      line 4  the ask (play the game)
      line 5  the AI disclosure
      line 6  cross-surface handles, no raw links (Facebook suppresses URLs)
    """
    thing, feeling = pair(slug)
    no = exhibit_no(slug)
    head = f"{no} · {RITUAL}"
    body = f"{thing} : {feeling}"
    song = f"🎵 {song_title}" if song_title else ""
    if platform == "facebook":
        tail = (f"🎬 ดูคลิปอื่นที่ YouTube {HANDLES['youtube']} · "
                f"TikTok {HANDLES['tiktok']}")
    else:
        tail = (f"🎬 ดูเต็ม ๆ ที่ YouTube {HANDLES['youtube']} · "
                f"เพจ FB {HANDLES['facebook']}")
    lines = [head, body]
    if song:
        lines.append(song)
    lines += [f"💬 {RITUAL_ASK}", f"⚠️ {AI_NOTE}", tail,
              "#ศิลปะหลุดโลก #เพลงไทย #AERISMusic"]
    return "\n".join(lines)


def claim_problem(text: str) -> str | None:
    """Return the first banned substring in `text`, or None when it is safe."""
    for phrase in BANNED:
        if phrase in text:
            return phrase
    return None


# ── the front door (Page bio + pinned post) ───────────────────────────────────
# The Reels carry the absurdist caption, but a stranger who taps the Page lands
# on the bio and the pinned post first. Those stayed in the old "polite Thai
# ballad" voice ("เพลงเศร้า · เพื่อชีวิต · ลูกทุ่ง"), so the visitor saw a generic
# music page and left — the identity on the converting surface did not match the
# identity on the clip. Both are now built from the same constants above, so the
# front door and the exhibits can never drift apart again.
#
# The bio must still answer "what do I get if I follow?" in its first line (the
# 2026-11-06 panel's finding), so line 1 is the promise and the follow ask
# closes it. No emoji in the burned ASS, but the Page bio is plain text on
# Facebook, so the 🎵/👉 read fine here.

# Facebook caps the Page intro ("คำอธิบายตัวเอง") at 255 characters; a longer
# string makes the Save silently do nothing and the old bio stays. `tests/run.py`
# pins the limit so this cannot regress.
BIO_MAX = 255
BIO = (
    f"{SLOGAN}\n"
    f"{PROJECT} · {RITUAL}\n"
    "กดติดตามไว้ ดูของชิ้นถัดไปที่เราจะแปลง ❤️\n"
    f"▶️ YouTube {HANDLES['youtube']}\n"
    "🛒 ลิงก์พันธมิตร: https://s.shopee.co.th/2qVq75ACtW"
)

# The pinned "front door". A stranger reads this before any Reel, so it states
# the one rule that makes the strangeness read as a project rather than noise,
# shows two finished exhibits as proof, and asks the viewer to play.
WELCOME = (
    f"{SLOGAN}\n"
    f"ที่นี่คือ {PROJECT} — หอศิลป์ของเสียง\n"
    f"กติกามีข้อเดียว: {RITUAL}\n"
    "\n"
    "ตัวอย่างที่แขวนอยู่แล้ว:\n"
    "🪑 เสาไฟฟ้าหน้าปากซอย : เวลาเดินถอยหลัง\n"
    "🐟 ปลากัดในโหล : ความคิดถึงที่ทอดไข่ได้\n"
    "\n"
    f"💬 {RITUAL_ASK}\n"
    "กดติดตามไว้ ดูของชิ้นถัดไปที่เราจะแปลง 👇\n"
    f"⚠️ {AI_NOTE}"
)


# ── the idea feed (the "producer loop" entry point) ───────────────────────────
# `ideas()` is what a producer step consumes: one row per song, each with the
# absurd premise already resolved, so a renderer or a copywriter never has to
# invent an idea that might be unsafe. It is pure (no ffmpeg, no files), so the
# tests pin the whole gallery without paying for an encode.

def ideas(slugs: list[str], titles: dict[str, str] | None = None) -> list[dict]:
    """One exhibit per slug: the closed-vocabulary premise, ready to render."""
    titles = titles or {}
    out = []
    for slug in slugs:
        thing, feeling = pair(slug)
        out.append({
            "slug": slug,
            "no": exhibit_no(slug),
            "thing": thing,
            "feeling": feeling,
            "title": f"{thing} : {feeling}",
            "song": titles.get(slug, ""),
        })
    return out

