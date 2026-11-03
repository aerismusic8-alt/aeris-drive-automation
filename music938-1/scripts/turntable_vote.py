#!/usr/bin/env python3
"""Earn free Flow Music credits by voting on the Turntable.

Flow's free tier runs out of credits after a handful of songs and the only free
top-up Google documents is the Turntable: listen to two samples and pick the one
that better matches the prompt. Each vote earns credits, so this is how the
remaining songs get rendered without paying (Rule #1).

The widget advertises its own shortcuts — Space play/pause, arrows select,
Enter vote, X skip — and they are the reliable way to drive it: the sample audio
is Web Audio, so there is no <audio> element to press, and clicking a side card
toggles playback instead of selecting it.

    python3 scripts/turntable_vote.py            # 10 votes
    python3 scripts/turntable_vote.py --rounds 20
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))


def _progress(page) -> tuple[int, int]:
    m = re.search(r"(\d+)\s*/\s*(\d+)", page.inner_text("body"))
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def _times(page) -> tuple[str, str]:
    body = page.inner_text("body")
    a = re.search(r"SIDE A\s*\n+\s*(\d+:\d+)", body)
    b = re.search(r"SIDE B\s*\n+\s*(\d+:\d+)", body)
    return (a.group(1) if a else "?", b.group(1) if b else "?")


def run(rounds: int, listen_s: float, verbose: bool = True) -> int:
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
        p.set_viewport_size({"width": 1400, "height": 900})
        p.goto(F.SESSION_URL, wait_until="domcontentloaded", timeout=60_000)
        p.wait_for_timeout(6000)
        p.get_by_role("button", name="Turntable").first.click(timeout=8000)
        p.wait_for_timeout(5000)
        ok = p.get_by_role("button", name=re.compile("got it", re.I))
        if ok.count():
            try:
                ok.first.click(timeout=4000)
            except Exception:
                pass
        # Focus the widget without starting playback: clicking a side card would.
        try:
            p.get_by_text("Vote for the sample", exact=False).first.click(timeout=4000)
        except Exception:
            pass
        p.wait_for_timeout(500)

        done, total = _progress(p)
        if verbose:
            print(f"turntable: {done}/{total} at start")
        for i in range(rounds):
            if done >= total:
                break
            # The vote only unlocks after BOTH sides have played >=10s. Play A to
            # completion of the gate, pause, switch to B, play it, pause, vote.
            p.keyboard.press("Space")
            p.wait_for_timeout(int(listen_s * 1000))
            p.keyboard.press("Space")
            p.wait_for_timeout(700)
            p.keyboard.press("ArrowRight")
            p.wait_for_timeout(700)
            p.keyboard.press("Space")
            p.wait_for_timeout(int(listen_s * 1000))
            p.keyboard.press("Space")
            p.wait_for_timeout(700)
            p.keyboard.press("Enter")
            p.wait_for_timeout(4000)
            new_done, total = _progress(p)
            if verbose:
                a, b = _times(p)
                print(f"  vote {i + 1}: {new_done}/{total}  (A={a} B={b})")
            if new_done == done:
                # The vote did not take; skip this pair and try the next.
                p.keyboard.press("x")
                p.wait_for_timeout(3000)
                new_done, total = _progress(p)
            done = new_done
        if verbose:
            print(f"turntable: {done}/{total} done")
        p.screenshot(path=str(ROOT / "work" / "turntable-voted.png"))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rounds", type=int, default=10)
    ap.add_argument("--listen", type=float, default=12.0,
                    help="seconds to let each side play before voting")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    return run(args.rounds, args.listen, verbose=not args.quiet)


if __name__ == "__main__":
    raise SystemExit(main())
