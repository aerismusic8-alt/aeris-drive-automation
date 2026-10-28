#!/usr/bin/env python3
"""Generate one song in Flow Music and save the MP3. Run after the operator signed in.

    python3 flowmusic_download.py "warm thai folk, bamboo flute, 60 bpm, no vocals" out.mp3

Three things this handles that a naive script does not:

1. flowmusic.app needs its own session even when Google is signed in. Signed in to
   Google but with no session, the page shows `Create a song` and 0 input boxes. The
   button has to be clicked first.
2. The render is minutes, not seconds. Progress reaches 100% before the audio is
   ready, so the finish signal is the duration readout leaving `0:00`.
3. Download is a submenu (`Download video` / `Get stems` / `M4A` / `MP3` / `WAV`) and
   the `MP3` entry is a `div`, not a button — `locator.click()` times out on it.
   `Browser.setDownloadBehavior` with an explicit path plus a JS click works.

Verified 2026-10-28: produced "Bedtime Thai Folk", 3:00, 3.7 MB, 165 kbps.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

CDP = "http://127.0.0.1:9222"
SESSION = "https://www.flowmusic.app/session?t=true"


def wait_for_song(page, timeout_s: int = 420) -> str:
    """Return the song title once its duration readout moves off 0:00."""
    deadline = time.time() + timeout_s
    title = None
    while time.time() < deadline:
        page.wait_for_timeout(5000)
        body = page.inner_text("body")
        m = None
        for pat in (r"([^\n]{3,60})\n\s*\d+:\d{2}\n\s*\d+:\d{2}",):
            import re
            m = re.search(pat, body)
        if m:
            title = m.group(1).strip()
        durs = page.evaluate(
            """() => Array.from(document.querySelectorAll('*'))
                 .filter(e => e.children.length === 0)
                 .map(e => (e.innerText || '').trim())
                 .filter(t => /^\\d+:\\d{2}$/.test(t))"""
        )
        progress = [d for d in durs if d != "0:00"]
        if title and progress and len(progress) >= 2:
            print(f"[+] rendered: {title} ({progress[0]}/{progress[1]})")
            return title
    raise TimeoutError("song did not finish rendering in time")


def download(page, title: str, out: Path) -> Path:
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="fmdl-"))
    ctx = page.context
    cdp = ctx.new_cdp_session(page)
    cdp.send("Browser.setDownloadBehavior",
             {"behavior": "allow", "downloadPath": str(tmp)})

    page.keyboard.press("Escape")
    page.wait_for_timeout(600)
    page.locator(f"button[aria-label='More options for {title}']").first.click(timeout=10000)
    page.wait_for_timeout(1200)
    page.locator("[role=menuitem]:has-text('Download')").first.hover()
    page.wait_for_timeout(1500)
    clicked = page.evaluate(
        """() => {
             const el = [...document.querySelectorAll('*')]
               .find(e => e.children.length === 0 && (e.innerText || '').trim() === 'MP3');
             if (!el) return 'no MP3 node';
             let n = el;
             for (let i = 0; i < 4 && n; i++) {
               if (n.getAttribute('role') === 'menuitem' || n.tagName === 'BUTTON') {
                 n.click(); return 'clicked ' + n.tagName;
               }
               n = n.parentElement;
             }
             el.click(); return 'clicked leaf';
           }"""
    )
    print("[+]", clicked)
    deadline = time.time() + 120
    while time.time() < deadline:
        files = [f for f in tmp.iterdir() if f.suffix.lower() in (".mp3", ".m4a", ".wav")]
        if files and not any(f.name.endswith(".crdownload") for f in tmp.iterdir()):
            src = max(files, key=lambda f: f.stat().st_size)
            if src.stat().st_size > 100_000:
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(src.read_bytes())
                print(f"[+] saved {out} ({out.stat().st_size} bytes)")
                return out
        time.sleep(3)
    raise TimeoutError("download did not appear")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("prompt")
    ap.add_argument("out", type=Path)
    ap.add_argument("--timeout", type=int, default=420)
    args = ap.parse_args()

    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.connect_over_cdp(CDP)
        page = b.contexts[0].pages[0]
        page.goto(SESSION, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(5000)
        for lbl in ("OK, got it",):
            loc = page.locator(f"button:has-text('{lbl}')").first
            if loc.count():
                try:
                    loc.click(timeout=3000)
                    page.wait_for_timeout(600)
                except Exception:
                    pass
        box = page.locator("textarea[placeholder='Ask Producer...']").first
        if not box.count():
            btn = page.locator("button:has-text('Create a song')").first
            if btn.count():
                btn.click(timeout=8000)
                page.wait_for_timeout(6000)
            box = page.locator("textarea[placeholder='Ask Producer...']").first
        if not box.count():
            print("no composer — the browser is not signed in to flowmusic.app",
                  file=sys.stderr)
            return 2
        box.click(timeout=15000)
        box.fill(args.prompt)
        page.wait_for_timeout(800)
        page.locator("button[aria-label='Send message']").first.click(timeout=10000)
        print("[+] prompt sent; rendering (this takes minutes)")
        title = wait_for_song(page, args.timeout)
        download(page, title, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
