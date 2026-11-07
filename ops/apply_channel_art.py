#!/usr/bin/env python3
"""Set the AERIS Music banner through the YouTube Data API — no Studio, no K.

The channel avatar cannot be set over the API (YouTube exposes no avatar write),
but the **banner** can, and that is the piece with all the brand information in it.
The OAuth rail already carries the full `youtube` scope, so this is unattended.

    python3 ops/apply_channel_art.py --dry-run   # upload, print the URL, no write
    python3 ops/apply_channel_art.py             # upload and set the banner

Two API facts this depends on, both learned in this sandbox:

* `channelBanners.insert` is a POST, and this proxy 404s a bare POST to
  `www.googleapis.com` — but uploads go to `www.googleapis.com/upload`, which is
  served normally, so the upload works.
* `channels.update` replaces the whole `brandingSettings`, so the current one is
  read first and only `image.bannerExternalUrl` is changed. A bare PUT would drop
  the description, keywords and country.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yt_auth  # noqa: E402

CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"
ROOT = Path(__file__).resolve().parent.parent
BANNER = ROOT / "music938-1" / "channel" / "banner-pro-2560x1440.png"
UPLOAD = "https://www.googleapis.com/upload/youtube/v3/channelBanners/insert"


def upload_banner(token: str, path: Path) -> str:
    """Upload the image and return the URL YouTube stores for it."""
    data = path.read_bytes()
    req = urllib.request.Request(
        UPLOAD + "?uploadType=media",
        data=data,
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "image/png",
                 "Content-Length": str(len(data))},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as f:
            body = json.loads(f.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"banner upload failed {e.code}: {e.read().decode()[:400]}")
    url = body.get("url", "")
    if not url:
        raise SystemExit(f"banner upload returned no url: {body}")
    return url


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="upload the banner but do not change the channel")
    ap.add_argument("--file", default=str(BANNER))
    a = ap.parse_args()

    path = Path(a.file)
    if not path.exists():
        raise SystemExit(f"no such file: {path} (run scripts/brand_pro.py first)")

    tok = yt_auth.access_token("ch3")
    st, cur = yt_auth.api_get("channels", tok, part="brandingSettings", id=CHANNEL_ID)
    if st != 200:
        raise SystemExit(f"cannot read brandingSettings: {st} {str(cur)[:200]}")
    bs = cur["items"][0]["brandingSettings"]
    old = (bs.get("image") or {}).get("bannerExternalUrl", "")
    print("old banner:", old or "(none)")

    url = upload_banner(tok, path)
    print("uploaded:", url)

    if a.dry_run:
        print("dry-run: banner uploaded, channel not changed")
        return 0

    bs.setdefault("image", {})["bannerExternalUrl"] = url
    # channels.update is a full replace, so refuse to write a stripped settings
    # blob — a bare PUT once dropped the description this channel relies on.
    if not bs.get("channel", {}).get("description"):
        raise SystemExit("refusing to PUT: brandingSettings has no description")
    st, res = yt_auth.api_request("channels", tok,
                                  {"id": CHANNEL_ID, "brandingSettings": bs},
                                  method="PUT", part="brandingSettings")
    if st != 200:
        print(f"FAILED {st}: {str(res)[:300]}")
        return 1
    got = (res["brandingSettings"].get("image") or {}).get("bannerExternalUrl", "")
    print("banner now:", got or "(empty)")
    print("description kept:", bool(res["brandingSettings"]["channel"].get("description")))
    return 0 if got else 1


if __name__ == "__main__":
    raise SystemExit(main())
