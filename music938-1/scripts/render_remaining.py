#!/usr/bin/env python3
"""Render the songs that have no audio yet, a few at a time.

Flow Music's free tier runs out of credits after a handful of songs ("You're out
of credits"), after which its Generate button is disabled and `flow_song.py`
fails with a click timeout. Rule #1 forbids paying, so the remaining songs wait
for the free quota to reset and are rendered in small batches.

This is the resumable driver: it renders every lyric that has no
`library/songs/song-<slug>.mp3` yet, up to `--limit`, and stops early if the
quota is already spent (so a cron can call it repeatedly without burning time).

    python3 scripts/render_remaining.py            # next 4, default
    python3 scripts/render_remaining.py --limit 3
    python3 scripts/render_remaining.py --list     # what is left, do nothing
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
# browser.py (the CDP helper) lives with the sibling aeris938-1 pack.
sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))

LYRICS = ROOT / "lyrics"
SONGS = ROOT / "library" / "songs"


def all_slugs() -> list[str]:
    return sorted(p.stem for p in LYRICS.glob("*.txt"))


def pending() -> list[str]:
    return [s for s in all_slugs() if not (SONGS / f"song-{s}.mp3").exists()]


def quota_status() -> str:
    """One of 'out' (free credits spent), 'ok', or 'logged_out'.

    'out' means Flow disabled the Generate button; 'logged_out' means the Google
    session expired and only the operator can sign back in.
    """
    import browser as B
    import flow_song as F
    from playwright.sync_api import sync_playwright

    with sync_playwright() as pw:
        _, ctx = B.connect(pw)
        for pg in list(ctx.pages):
            if "flowmusic.app" in pg.url:
                try:
                    pg.close()
                except Exception:
                    pass
        p = ctx.new_page()
        p.goto(F.SESSION_URL, wait_until="domcontentloaded", timeout=60_000)
        p.wait_for_timeout(6000)
        if "Free to start with a Google Account" in p.inner_text("body"):
            p.close()
            return "logged_out"
        F._open_compose(p)
        p.wait_for_timeout(2500)
        spent = "out of credits" in p.inner_text("body").lower()
        p.close()
    return "out" if spent else "ok"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=4, help="songs this run")
    ap.add_argument("--list", action="store_true", help="show the queue and exit")
    ap.add_argument("--check", action="store_true", help="only test the quota")
    args = ap.parse_args()

    left = pending()
    print(f"{len(left)} song(s) without audio; {len(all_slugs())} total")
    for s in left:
        print(f"  {s}")
    if args.list:
        return 0

    if args.check:
        st = quota_status()
        print({"out": "Flow Music: OUT OF CREDITS",
               "logged_out": "Flow Music: LOGGED OUT — operator must sign in",
               "ok": "Flow Music: credits available"}[st])
        return {"out": 2, "logged_out": 3, "ok": 0}[st]
    if left:
        st = quota_status()
        if st != "ok":
            print(f"Flow Music: {st.upper()} — nothing rendered", file=sys.stderr)
            return 2 if st == "out" else 3
    if not left:
        print("nothing to render")
        return 0

    rc = 0
    for slug in left[: args.limit]:
        print(f"=== render {slug} ===")
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "flow_song.py"), slug, "--force"],
            capture_output=True, text=True)
        print((proc.stdout or "").strip().splitlines()[-1] if proc.stdout else "")
        if proc.returncode != 0:
            print((proc.stderr or "")[-300:], file=sys.stderr)
            rc = proc.returncode
            break
    print(f"done; {len(pending())} still pending")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
