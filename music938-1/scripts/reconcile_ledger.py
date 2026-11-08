#!/usr/bin/env python3
"""One-shot: reconcile the release ledger with what is actually on the channel.

The release-ledger bug (daily_release.py returning on rc==3 before writing the
ledger) left the ledger on `main` describing a channel that no longer exists:

* six rows point at videos that were deleted in earlier cleanups (5 karaoke +
  one duplicate Short), and
* the two surviving affiliate product cards are on the channel but in NO ledger
  row, so the rail plans and re-uploads them on every run.

This fetches the ledger from `main`, retires the dead rows, records the two live
cards, and writes it back through the Contents API. It is idempotent: run twice
and the second run changes nothing.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))
import release  # noqa: E402

REPO = "aerismusic8-alt/aeris-drive-automation"
LEDGER = "music938-1/work/release-state.json"
API = "https://api.github.com"

# Videos that are gone from the channel but still "live" in the ledger.
DEAD = {
    "ohmKsjI5Sq8", "4xcbYYhFP3A", "MEwzH-g07kA",
    "jgBTOGWyBp8", "t6NIvNjJtEQ", "zNqUTtCaYxY",
}
# The two best-viewed affiliate cards that survived the duplicate cleanup.
SURVIVING_CARDS = {"X3A5PMMNgfU": "hp-budget-01", "y-Y2DNmopHk": "hp-anc-02"}


def token() -> str:
    tok = os.environ.get("AX_GH_TOKEN")
    if not tok:
        raise SystemExit("no AX_GH_TOKEN")
    return tok


def api(path, tok, method="GET", data=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(data).encode() if data is not None else None,
        method=method,
        headers={"Authorization": f"token {tok}",
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "ax-ledger-reconcile"})
    with urllib.request.urlopen(req, timeout=60) as r:
        txt = r.read().decode()
        return r.status, (json.loads(txt) if txt else {})


def main() -> int:
    tok = token()
    st, cur = api(f"/repos/{REPO}/contents/{LEDGER}?ref=main", tok)
    if st != 200:
        print(f"cannot read ledger: {st} {cur}", file=sys.stderr)
        return 1
    sha = cur["sha"]
    state = json.loads(base64.b64decode(cur["content"]))

    changed = 0
    for r in state["released"]:
        if r.get("video_id") in DEAD and not r.get("retired_at"):
            r["retired_at"] = "2026-11-08T09:30:00+00:00"
            changed += 1

    # A card is "done" when a row with its (id, affiliate, variant) key exists.
    have = {(r["slug"], r["kind"], r.get("variant", "")) for r in state["released"]}
    for vid, card_id in SURVIVING_CARDS.items():
        key = (card_id, "affiliate", f"short-aff-{card_id}")
        if key in have:
            continue
        state["released"].append({
            "slug": card_id, "kind": "affiliate",
            "variant": f"short-aff-{card_id}", "video_id": vid,
            "at": "2026-11-07T15:20:36+00:00", "public": True,
            "thumb_ok": True, "playlist_ok": True,
        })
        changed += 1

    if not changed:
        print("ledger already reconciled; nothing to do")
        return 0

    body = {"message": "release: reconcile ledger with the live channel "
                       "(retire deleted rows, record the surviving affiliate cards)",
            "content": base64.b64encode(
                json.dumps(state, ensure_ascii=False, indent=1).encode()).decode(),
            "branch": "main", "sha": sha}
    st, res = api(f"/repos/{REPO}/contents/{LEDGER}", tok, "PUT", body)
    print(f"ledger write: {st} {res.get('commit', {}).get('sha', res.get('error', ''))}")
    print(f"changed {changed} row(s)")
    return 0 if st in (200, 201) else 1


if __name__ == "__main__":
    raise SystemExit(main())
