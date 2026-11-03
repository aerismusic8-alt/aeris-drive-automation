#!/usr/bin/env python3
"""Export the cloud-desktop browser's Facebook + TikTok session as a Playwright
storage state, base64-encoded for a GitHub Actions secret.

Why: posting a Reel or a TikTok needs a signed-in browser, and the cloud desktop
that holds that login is a build-pod resource — it is not there at 03:00 when a
cron would run. GitHub Actions is the one always-on, free runner in this account
(the same machine that already runs the release and dashboard rails). This script
captures the session once, so a workflow can restore it and post without a pod.

The output is a **credential**: it is a live login for the AERIS Music Page and
TikTok account. Do not commit it, do not paste it into a public place. Set it as
a repository secret:

    python3 ops/save_storage_state.py | \
      gh secret set AERIS_STORAGE_STATE_B64 --repo aerismusic8-alt/aeris-drive-automation

Re-run it when the session dies (Facebook rejects a restored cookie after a
while); a fresh desktop sign-in is the only way to refresh it.
"""
from __future__ import annotations

import base64
import json
import sys

CDP = "http://127.0.0.1:9222"
# Every login-only surface a CI rail has to drive, so one sign-in and one export
# cover them all: Facebook + TikTok for posting, Shopee for the affiliate read,
# YouTube/Google for Studio (comments, analytics) and Flow Music for song
# generation. A surface missing here cannot be driven from Actions.
WANT = ("facebook.com", "tiktok.com", "shopee.co.th", "youtube.com",
        "google.com", "flowmusic.app")


def main() -> int:
    from playwright.sync_api import sync_playwright

    pw = sync_playwright().start()
    try:
        br = pw.chromium.connect_over_cdp(CDP)
        ctx = br.contexts[0] if br.contexts else br.new_context()
        state = ctx.storage_state()
    finally:
        pw.stop()

    cookies = [c for c in state.get("cookies", [])
               if any(w in c.get("domain", "") for w in WANT)]
    origins = [o for o in state.get("origins", [])
               if any(w in o.get("origin", "") for w in WANT)]
    if not cookies:
        print("no facebook/tiktok cookies in the desktop browser — is it signed "
              "in? (bootstrap.py --status, then sign in via noVNC)", file=sys.stderr)
        return 1
    blob = {"cookies": cookies, "origins": origins}
    print(f"# {len(cookies)} cookies, {len(origins)} origins", file=sys.stderr)
    sys.stdout.write(base64.b64encode(
        json.dumps(blob, separators=(",", ":")).encode()).decode())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
