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
    """A one-line call to action that survives YouTube's "Show more" fold.

    YouTube shows roughly the first two lines of a description before truncating,
    so the affiliate link has to sit *above* the longer footer, not at its end.
    Returns "" when no link is configured, so the description degrades cleanly.
    """
    shopee = link(surface)
    if not shopee:
        return ""
    return f"🎧 ฟังเพลิน ๆ แล้วกดติดตามช่องนะครับ · ของน่าซื้อ 👉 {shopee}"


_S_SHOPEE = re.compile(r"https://s\.shopee\.co\.th/\w+")


def refresh_description(desc: str, surface: str = "youtube") -> str:
    """Upgrade a live description in place: new link, and the CTA up top.

    `release.describe` only shapes *new* uploads; the videos already live carry
    the old homepage link at the very bottom. This rewrites one of those: every
    `s.shopee.co.th` link becomes this surface's current product link, and the
    CTA is inserted after the first paragraph (before the fold) if it is missing.
    Idempotent — a description already carrying both changes comes back equal.
    """
    shopee = link(surface)
    line = cta(surface)
    if shopee:
        desc = _S_SHOPEE.sub(shopee, desc)
    if not line or line in desc:
        return desc
    parts = desc.split("\n\n", 1)
    if len(parts) == 2:
        return f"{parts[0]}\n{line}\n\n{parts[1]}"
    return f"{desc}\n{line}"


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
