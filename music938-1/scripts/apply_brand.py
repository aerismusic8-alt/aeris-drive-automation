"""Apply the channel identity to the AERIS Music YouTube channel.

Only the banner is reachable from the API. There is **no** YouTube Data API
endpoint for the channel avatar — Google exposes it only in Studio — so this
script uploads the banner and leaves the avatar file in `channel/` for the
operator (or the cloud-desktop browser) to set.

`channels.update` replaces the whole `brandingSettings`, so the current one is
read first and merged; sending only the image would silently drop the channel
description and keywords.

Run: python3 scripts/apply_brand.py [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from common import ROOT

CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"
BANNER = ROOT / "channel" / "banner-2560x1440.png"
AVATAR = ROOT / "channel" / "avatar-800x800.png"

API = "https://www.googleapis.com/youtube/v3"


def _access_token() -> str:
    cid = os.environ["YT_CLIENT_ID"]
    sec = os.environ["YT_CLIENT_SECRET"]
    rt = os.environ["YT_CH3_REFRESH_TOKEN"]
    data = urllib.parse.urlencode({
        "client_id": cid, "client_secret": sec,
        "refresh_token": rt, "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=data)
    return json.load(urllib.request.urlopen(req, timeout=30))["access_token"]


def _get(token: str, path: str) -> dict:
    req = urllib.request.Request(f"{API}/{path}",
                                 headers={"Authorization": f"Bearer {token}"})
    return json.load(urllib.request.urlopen(req, timeout=30))


def _put(token: str, path: str, body: dict) -> dict:
    req = urllib.request.Request(
        f"{API}/{path}", data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "application/json"}, method="PUT")
    return json.load(urllib.request.urlopen(req, timeout=30))


def upload_banner(token: str, image: Path) -> str:
    data = image.read_bytes()
    req = urllib.request.Request(
        f"https://www.googleapis.com/upload/youtube/v3/channelBanners/insert?uploadType=media",
        data=data,
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "image/png"}, method="POST")
    return json.load(urllib.request.urlopen(req, timeout=120))["url"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for p in (BANNER, AVATAR):
        if not p.exists():
            raise SystemExit(f"missing {p}; run scripts/brand.py first")
    print(f"banner {BANNER.stat().st_size // 1024} KB, avatar {AVATAR.stat().st_size // 1024} KB")

    if args.dry_run:
        print("dry-run: would upload the banner and merge brandingSettings")
        return 0

    token = _access_token()
    ch = _get(token, f"channels?part=brandingSettings&id={CHANNEL_ID}")
    bs = ch["items"][0]["brandingSettings"]
    print("current description head:", repr(bs["channel"]["description"][:60]))

    url = upload_banner(token, BANNER)
    print("banner uploaded ->", url[:80], "...")

    bs.setdefault("image", {})["bannerExternalUrl"] = url
    res = _put(token, "channels?part=brandingSettings",
               {"id": CHANNEL_ID, "brandingSettings": bs})
    got = res["brandingSettings"]["image"].get("bannerExternalUrl", "")
    print("banner now:", got[:80], "...")
    print("description kept:", repr(res["brandingSettings"]["channel"]["description"][:60]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
