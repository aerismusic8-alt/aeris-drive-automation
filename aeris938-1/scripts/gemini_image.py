"""Gemini image generation through the signed-in cloud desktop.

No API key is used: the prompt is typed into the Gemini web app on the cloud
desktop and the returned image is saved into the library. If the desktop is not
signed in, the run stops with a login link instead of pretending to work.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library  # noqa: E402
from browser import LoginRequired, connect, login_instructions, looks_signed_out, save_blob  # noqa: E402

APP = "Gemini (gemini.google.com)"
URL = "https://gemini.google.com/app"
IMAGE_PROMPT_SUFFIX = (
    " ภาพแนวภาพยนตร์ แสงนุ่ม โทนสีอบอุ่น องค์ประกอบกว้าง 16:9 "
    "ความละเอียดสูง ไม่มีข้อความ ไม่มีลายน้ำ"
)


def _wait_for_new_image(page, before: set[str], timeout: float = 180.0) -> str | None:
    """Wait for an image that was not on the page before the prompt was sent."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        srcs = page.evaluate(
            "() => Array.from(document.images).map(i => i.currentSrc || i.src)"
            "        .filter(s => s && s.length > 200)"
        )
        fresh = [s for s in srcs if s not in before]
        if fresh:
            return fresh[-1]
        if looks_signed_out(page.inner_text("body")):
            return None
        page.wait_for_timeout(1500)
    return None


def generate(prompt: str, key: str, *, timeout: float = 240.0, force: bool = False) -> dict:
    existing = library.find("img", key)
    if existing and not force:
        return {"status": "REUSED", "entry": existing}

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser, context = connect(p)
        page = context.pages[0] if context.pages else context.new_page()
        if URL not in (page.url or ""):
            page.goto(URL, wait_until="domcontentloaded", timeout=60_000)
        page.wait_for_timeout(3500)

        body = page.inner_text("body")
        if "ลงชื่อเข้าใช้เพื่อ" in body and "สร้างรูปภาพ" in body:
            raise LoginRequired(login_instructions(APP))

        before = set(page.evaluate(
            "() => Array.from(document.images).map(i => i.currentSrc || i.src)"
        ))

        box = page.locator("div[contenteditable='true'], textarea").first
        box.click(timeout=15_000)
        box.type(prompt + IMAGE_PROMPT_SUFFIX, delay=12)
        page.wait_for_timeout(600)
        page.keyboard.press("Enter")

        src = _wait_for_new_image(page, before, timeout=timeout)
        if src is None:
            tail = page.inner_text("body")[-600:]
            if looks_signed_out(tail):
                raise LoginRequired(login_instructions(APP))
            raise TimeoutError(
                "no new image appeared; Gemini may have answered with text instead. "
                f"page tail: {tail!r}"
            )

        ext = ".png" if src.startswith("data:image/png") else ".jpg"
        out = library.KINDS["img"] / f"{library.entry_id('img', key)}{ext}"
        size = save_blob(page, src, out)

    entry = library.add("img", key, out, source="gemini-web", prompt=prompt,
                        provider="gemini.google.com", bytes_written=size)
    return {"status": "CREATED", "entry": entry}


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate one image via Gemini web")
    ap.add_argument("key", help="stable library key, e.g. story1-scene3")
    ap.add_argument("prompt", help="what the image should show")
    ap.add_argument("--force", action="store_true", help="regenerate even if present")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    try:
        result = generate(args.prompt, args.key, force=args.force)
    except LoginRequired as exc:
        print(str(exc), file=sys.stderr)
        return 3
    print(json.dumps(result, ensure_ascii=False, indent=2) if args.json
          else f"{result['status']}: {result['entry']['file']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
