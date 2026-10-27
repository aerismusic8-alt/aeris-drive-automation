"""Song generation through the signed-in Google Flow Music web app.

Flow Music is login-only, so this drives the already-authenticated session on
the cloud desktop. One song is generated per call and the audio is filed in the
music library with its own manifest entry, so a later episode can reuse a track
by mood instead of regenerating it.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library  # noqa: E402
from browser import LoginRequired, connect, login_instructions, looks_signed_out  # noqa: E402

APP = "Google Flow Music"
URL = "https://www.flowmusic.app/"
CREATE_URL = "https://www.flowmusic.app/session?t=true"

AUDIO_SELECTOR = "audio"
DOWNLOAD_LABELS = ("download", "ดาวน์โหลด", "save")


def _already_logged_in(page) -> bool:
    body = page.inner_text("body").lower()
    if "welcome to the studio" in body and "get started" in body:
        return False
    if "sign up" in body and "log in" in body and "create song" not in body:
        return False
    return True


def generate(prompt: str, key: str, *, timeout: float = 600.0, force: bool = False,
             instrumental: bool = True) -> dict:
    existing = library.find("music", key)
    if existing and not force:
        return {"status": "REUSED", "entry": existing}

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser, context = connect(p)
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(CREATE_URL, wait_until="domcontentloaded", timeout=60_000)
        page.wait_for_timeout(4000)

        if not _already_logged_in(page):
            raise LoginRequired(login_instructions(APP))

        # Pick the instrumental path when asked, so a song does not arrive with
        # vocals that would fight the narration.
        if instrumental:
            for label in ("Instrumental", "instrumental", "Just for fun"):
                loc = page.locator(f"text={label}").first
                if loc.count():
                    try:
                        loc.click(timeout=4000)
                        page.wait_for_timeout(1200)
                        break
                    except Exception:
                        pass

        box = page.locator("textarea, div[contenteditable='true'], input[type='text']").first
        box.click(timeout=20_000)
        box.type(prompt, delay=15)
        page.wait_for_timeout(800)
        page.keyboard.press("Enter")

        # A generated song becomes an <audio> element with a real src.
        deadline = time.time() + timeout
        src = None
        while time.time() < deadline:
            src = page.evaluate(
                "() => { const a = document.querySelector('audio');"
                "        return a && (a.currentSrc || a.src) || null; }"
            )
            if src and len(src) > 60:
                break
            page.wait_for_timeout(3000)
        if not src or len(src) <= 60:
            raise TimeoutError(
                "no audio element appeared within the timeout; the song may still "
                "be rendering. Re-run with --force once it is finished."
            )

        out = library.KINDS["music"] / f"{library.entry_id('music', key)}.mp3"
        out.parent.mkdir(parents=True, exist_ok=True)
        try:
            resp = page.request.get(src)
            out.write_bytes(resp.body())
        except Exception:
            from browser import save_blob
            save_blob(page, src, out)

    if not out.exists() or out.stat().st_size == 0:
        raise RuntimeError("song download produced an empty file")
    entry = library.add("music", key, out, source="flowmusic-web", prompt=prompt,
                        provider="flowmusic.app", instrumental=instrumental)
    return {"status": "CREATED", "entry": entry}


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate one song via Google Flow Music")
    ap.add_argument("key", help="stable library key, e.g. story1-mood-calm")
    ap.add_argument("prompt", help="mood / style description for the song")
    ap.add_argument("--with-vocals", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    try:
        result = generate(args.prompt, args.key, force=args.force,
                          instrumental=not args.with_vocals)
    except LoginRequired as exc:
        print(str(exc), file=sys.stderr)
        return 3
    print(json.dumps(result, ensure_ascii=False, indent=2) if args.json
          else f"{result['status']}: {result['entry']['file']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
