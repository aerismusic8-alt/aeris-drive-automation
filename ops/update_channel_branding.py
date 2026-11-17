#!/usr/bin/env python3
"""Set the เพลงส้นทีนไรเนี่ย channel description and keywords to the AI-label identity.

`channels.update` replaces the whole `brandingSettings`, so the current one is
read first and only the fields named here are overwritten — a bare PUT would
silently drop the banner and the country.

    python3 ops/update_channel_branding.py --dry-run
    python3 ops/update_channel_branding.py
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yt_auth  # noqa: E402

CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"

DESCRIPTION = """🎵 เพลงส้นทีนไรเนี่ย — เพลงไทยใหม่ทุกวัน

รวมเพลงไทยป็อป แดนซ์ ร็อก เพลงเศร้า และเพลงให้กำลังใจ
เนื้อร้องและทำนองใหม่ สร้างด้วย AI อย่างเปิดเผย ทุกเพลงคือผลงานที่ตั้งใจทำ

🎵 เพลงไทยทุกแนว — ป็อป แดนซ์ ร็อก เพลงเศร้า เพลงให้กำลังใจ
🎧 ฟังเพลิน ฟังได้ทุกวัน
✨ โปร่งใส: ทุกเสียงร้องสร้างด้วย AI

▶️ กดติดตามเพื่อไม่พลาดเพลงใหม่
📱 TikTok: @aeris.music4
💬 Facebook: เพลงส้นทีนไรเนี่ย
🛍️ Shopee: https://th.shp.ee/6hv2uk89

#ค่ายเพลงAI #AIMusic #เพลงไทย #เพลงส้นทีนไรเนี่ย"""

KEYWORDS = ("เพลงไทย,เพลงใหม่,ศิลปินไทย,เพลงส้นทีนไรเนี่ย,ค่ายเพลง AI,"
            "AI music,เพลงป็อป,เพลงแดนซ์,เพลงร็อก,เพลงเศร้า,เพลงเพราะ,เพลงฟังสบาย,"
            "thai music,thai song,ai music")


def apply(dry_run: bool = False) -> int:
    """Apply the description + keywords. Idempotent; returns 0 on success.

    A daily rail calls this, and a no-op write still spends 50 units of the shared
    pool, so skip the PUT when the live text already matches.
    """
    tok = yt_auth.access_token("ch3")
    st, cur = yt_auth.api_get("channels", tok, part="brandingSettings", id=CHANNEL_ID)
    if st != 200:
        print(f"READ FAILED {st}: {str(cur)[:300]}")
        return 1
    bs = cur["items"][0]["brandingSettings"]
    ch = bs.setdefault("channel", {})
    print("old description head:", repr(ch.get("description", "")[:70]))

    if ch.get("description") == DESCRIPTION and ch.get("keywords") == KEYWORDS:
        print("already current — nothing to write")
        return 0

    ch["description"] = DESCRIPTION
    ch["keywords"] = KEYWORDS

    if dry_run:
        print("dry-run: would PUT brandingSettings (description + keywords)")
        return 0

    # A write only happens when the text differs, so it is rare; still, price it
    # in the shared ledger so `yt_quota.remaining()` reflects what was really spent.
    try:
        import yt_quota
        yt_quota.record("channels.update")
    except Exception:  # noqa: BLE001 — the ledger is best-effort, not the write
        pass

    st, res = yt_auth.api_request("channels", tok,
                                  {"id": CHANNEL_ID, "brandingSettings": bs},
                                  method="PUT", part="brandingSettings")
    if st != 200:
        print(f"FAILED {st}: {str(res)[:300]}")
        return 1
    got = res["brandingSettings"]["channel"]
    print("new description head:", repr(got.get("description", "")[:70]))
    print("keywords now:", got.get("keywords", "")[:80])
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    return apply(dry_run=a.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
