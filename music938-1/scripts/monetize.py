"""Read `channel/monetization.json` and build the description block.

Every outbound link the channel uses lives in that one file. A link that is
blank is skipped, so the block stays correct while an account (the Shopee
affiliate id, for instance) is still pending.

The block is short on purpose: YouTube shows roughly the first two lines before
"Show more", so the call to action has to survive truncation.
"""
from __future__ import annotations

import json
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


def block(kind: str = "song") -> str:
    """The monetization footer appended to a video description.

    `kind` lets a Short keep a tighter footer than a full song.
    """
    c = config()
    lines: list[str] = []

    if c.get("shopee_affiliate") or c.get("shopee_shop"):
        url = c.get("shopee_affiliate") or c.get("shopee_shop")
        lines.append("")
        lines.append("🛒 สนับสนุนช่องผ่าน Shopee (ลิงก์พันธมิตร):")
        lines.append(url)

    socials = [x for x in (_link("Facebook", c.get("facebook", "")),
                           _link("TikTok", c.get("tiktok", "")),
                           _link("YouTube", c.get("youtube", ""))) if x]
    if socials:
        lines.append("")
        lines.append("📱 ติดตาม AERIS Music:")
        lines.append(" · ".join(socials))

    return "\n".join(lines)
