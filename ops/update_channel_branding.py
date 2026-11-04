#!/usr/bin/env python3
"""Set the AERIS Music channel description and keywords to the AI-label identity.

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

DESCRIPTION = """🤖 AERIS Music — ค่ายเพลง AI ของไทย

เราสร้างเพลงและเสียงร้องด้วย AI อย่างเปิดเผย ทุกเพลงคือผลงานที่ตั้งใจทำ
เนื้อร้องและทำนองใหม่ ไม่ใช่เพลงที่ผ่านมาแล้วผ่านไป

🎵 เพลงไทยทุกแนว — ลูกทุ่ง หมอลำ ป็อป เพื่อชีวิต เพลงเศร้า
🎧 ฟังเพลิน ฟังได้ทุกวัน
✨ โปร่งใส: ทุกเสียงร้องสร้างด้วย AI

▶️ กดติดตามเพื่อไม่พลาดเพลงใหม่
📱 TikTok: @aeris.music4
💬 Facebook: AERIS Music
🛍️ Shopee: https://th.shp.ee/6hv2uk89

#ค่ายเพลงAI #AIMusic #เพลงไทย #AERISMusic"""

KEYWORDS = ("เพลงไทย,เพลงใหม่,ศิลปินไทย,AERIS,ค่ายเพลง AI,AI music,"
            "เพลงลูกทุ่ง,หมอลำ,เพลงเพื่อชีวิต,เพลงเศร้า,เพลงเพราะ,เพลงฟังสบาย,"
            "thai music,thai song,ai music")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    tok = yt_auth.access_token("ch3")
    st, cur = yt_auth.api_get("channels", tok, part="brandingSettings", id=CHANNEL_ID)
    bs = cur["items"][0]["brandingSettings"]
    print("old description head:", repr(bs["channel"].get("description", "")[:70]))
    bs.setdefault("channel", {})["description"] = DESCRIPTION
    bs["channel"]["keywords"] = KEYWORDS

    if a.dry_run:
        print("dry-run: would PUT brandingSettings (description + keywords)")
        return 0

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


if __name__ == "__main__":
    raise SystemExit(main())
