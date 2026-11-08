"""Read `channel/monetization.json` and build the description block.

Every outbound link the channel uses lives in that one file. A link that is
blank is skipped, so the block stays correct while an account (the Shopee
affiliate id, for instance) is still pending.

The block is short on purpose: YouTube shows roughly the first two lines before
"Show more", so the call to action has to survive truncation.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from common import ROOT

CONFIG = ROOT / "channel" / "monetization.json"

CACHE: dict | None = None


def config() -> dict:
    global CACHE
    if CACHE is None:
        if CONFIG.exists():
            CACHE = json.loads(CONFIG.read_text(encoding="utf-8"))
        else:
            CACHE = {}
    return CACHE


def _link(label: str, url: str) -> str:
    return f"{label}: {url}" if url else ""


def link(surface: str = "") -> str:
    """The Shopee affiliate link for a surface, falling back to the default.

    A short link (`th.shp.ee/...`) drops a `sub_id` query parameter — verified
    against the live redirect — so attribution only works with the longer
    `s.shopee.co.th/...?sub_id=<surface>` links minted in the affiliate
    dashboard. Those live under `shopee_links`; until they exist, every surface
    falls back to the plain `shopee_affiliate` link.
    """
    c = config()
    per = c.get("shopee_links") or {}
    if surface and per.get(surface):
        return per[surface]
    return c.get("shopee_affiliate") or c.get("shopee_shop") or ""


def cta(surface: str = "youtube") -> str:
    """The above-the-fold call to action for a description.

    Three actions, in priority order. First the YouTube subscribe: the stated
    gate is 1,000 *YouTube* subscribers, but until 2026-11-08 the only ask above
    the fold sent the viewer off-platform to the Facebook Page, so the channel
    never asked for the one action that advances the goal. A subscribe is one
    tap, in-platform, and free. Then the Page, which still matters for the
    commission offer. Then the product link, which used to be the whole CTA and
    earned nothing from the bottom of the description.

    Returns "" when nothing is configured, so a description degrades cleanly.
    """
    c = config()
    yt = c.get("youtube", "")
    page = c.get("facebook", "")
    shopee = link(surface)
    lines = []
    if yt:
        sub = yt if "sub_confirmation" in yt else yt + "?sub_confirmation=1"
        lines.append(f"🔔 กดติดตามช่อง (Subscribe) 👉 {sub}")
    if page:
        lines.append(f"❤️ กดติดตามเพจ Facebook 👉 {page}")
    if shopee:
        lines.append(f"🛒 ของน่าซื้อ 👉 {shopee}")
    return "\n".join(lines)


_S_SHOPEE = re.compile(r"https://s\.shopee\.co\.th/\w+")

# The CTA line the first 22 uploads carry. It asked only for a channel subscribe
# and buried the Page, so `refresh_description` replaces it rather than leaving a
# description with two different follow asks.
_OLD_CTA = re.compile(r"^🎧 ฟังเพลิน ๆ แล้วกดติดตามช่องนะครับ · ของน่าซื้อ 👉 https://\S+$", re.M)

# The Page-first CTA block (2026-11-05..2026-11-08): a Page follow and the
# product link, with no YouTube subscribe ask. `refresh_description` drops it so
# the subscribe-first block replaces it instead of leaving two follow asks.
_OLD_PAGE_CTA = re.compile(
    r"^❤️ กดติดตามเพจ Facebook 👉 \S+\n🛒 ของน่าซื้อ 👉 \S+\n?", re.M)


def refresh_description(desc: str, surface: str = "youtube",
                        with_offer: bool = False) -> str:
    """Upgrade a live description in place: new link, and the CTA up top.

    `release.describe` only shapes *new* uploads; the videos already live carry
    the old homepage link at the very bottom. This rewrites one of those: every
    `s.shopee.co.th` link becomes this surface's current product link, the old
    channel-only CTA is dropped, and the new Page-first CTA is inserted after the
    first paragraph (before the fold) if it is missing. Idempotent — a
    description already carrying both changes comes back equal.

    `with_offer` appends the paid commission offer. It is off by default and the
    caller turns it on only for long-form uploads: a Short's description is
    barely read, so a sales pitch there adds noise and can read as spam.
    """
    shopee = link(surface)
    line = cta(surface)
    sub_line = line.splitlines()[0] if line else ""
    if shopee:
        desc = _S_SHOPEE.sub(shopee, desc)
    desc = _OLD_CTA.sub("", desc)
    # The Page-first block carries the same Page and product links as the new
    # block, so it must go or the description would ask twice and still never
    # ask for the YouTube subscribe. Only strip it while the subscribe ask is
    # absent: the Page and product lines are adjacent in the *new* block too, so
    # an unguarded second pass would strip them and re-insert the block, leaving
    # a duplicate subscribe line.
    if sub_line and sub_line not in desc:
        desc = _OLD_PAGE_CTA.sub("", desc)
    desc = re.sub(r"\n{3,}", "\n\n", desc)
    if with_offer:
        offer = commission_block().strip()
        if offer and offer.splitlines()[0] not in desc:
            desc = desc.rstrip() + "\n\n" + offer
    if not line or line in desc:
        return desc
    parts = desc.split("\n\n", 1)
    if len(parts) == 2:
        return f"{parts[0]}\n{line}\n\n{parts[1]}"
    return f"{desc}\n{line}"


def commission_block() -> str:
    """The paid custom-song offer, or "" until it is configured.

    Kept separate from `block()` because it is an offer, not a link list, and it
    should sit above the socials footer where a viewer still reads. The 2026-11-07
    advisor panel made this the first revenue action: before the follower gates
    there is no way for an interested viewer to pay, and this creates one.
    """
    text = (config().get("commission") or {}).get("text", "").strip()
    return f"\n\n{text}" if text else ""


def block(kind: str = "song") -> str:
    """The monetization footer appended to a video description.

    `kind` lets a Short keep a tighter footer than a full song.
    """
    c = config()
    lines: list[str] = []

    shopee = link("youtube")
    if shopee:
        lines.append("")
        lines.append("🛒 สนับสนุนช่องผ่าน Shopee (ลิงก์พันธมิตร):")
        lines.append(shopee)

    socials = [x for x in (_link("Facebook", c.get("facebook", "")),
                           _link("TikTok", c.get("tiktok", "")),
                           _link("YouTube", c.get("youtube", ""))) if x]
    if socials:
        lines.append("")
        lines.append("📱 ติดตาม AERIS Music:")
        lines.append(" · ".join(socials))

    return "\n".join(lines)
