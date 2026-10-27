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
from browser import LoginRequired, connect, login_instructions, looks_signed_out  # noqa: E402

APP = "Gemini (gemini.google.com)"
URL = "https://gemini.google.com/app"
IMAGE_PROMPT_SUFFIX = (
    " ภาพแนวภาพยนตร์ แสงนุ่ม โทนสีอบอุ่น องค์ประกอบกว้าง 16:9 "
    "ความละเอียดสูง ไม่มีข้อความ ไม่มีลายน้ำ"
)


# The generated stills, found by size rather than by URL. Gemini serves them from
# short `blob:` URLs (~67 chars), so a "long URL means an image" test never
# matches; and a URL is revoked once its image has loaded, so it cannot be
# fetched afterwards. Both facts push the same way: locate the element, then read
# the pixels out of a canvas.
#
# Every still in the conversation stays on the page, so "the newest one" is the
# last match, never the first -- `.find()` returns the oldest and silently hands
# back the previous scene's picture. The count is taken before the prompt is sent
# so a new one can be told apart from the ones already there.
_STILLS_JS = """() => Array.from(document.images)
  .filter(x => {
    const s = x.currentSrc || x.src || '';
    return s.startsWith('blob:') && x.naturalWidth >= 500 && x.naturalHeight >= 300;
  })
  .map(x => ({w: x.naturalWidth, h: x.naturalHeight}))"""

# A cheap fingerprint of the newest still: drawn small into a canvas and folded
# into one number. Cheap enough to poll every few seconds, and it keeps changing
# while the picture is still being drawn.
_FINGERPRINT_JS = """() => {
  const a = Array.from(document.images).filter(x => {
    const s = x.currentSrc || x.src || '';
    return s.startsWith('blob:') && x.naturalWidth >= 500 && x.naturalHeight >= 300;
  });
  const i = a[a.length - 1];
  if (!i) return null;
  const w = 64, h = Math.max(1, Math.round(64 * i.naturalHeight / i.naturalWidth));
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  ctx.drawImage(i, 0, 0, w, h);
  const d = ctx.getImageData(0, 0, w, h).data;
  let s = 0;
  for (let k = 0; k < d.length; k += 4) s = (s * 31 + d[k] + d[k+1] * 3 + d[k+2] * 7) >>> 0;
  return {n: a.length, fp: s, w: i.naturalWidth, h: i.naturalHeight};
}"""

_GRAB_LAST_JS = """() => {
  const a = Array.from(document.images).filter(x => {
    const s = x.currentSrc || x.src || '';
    return s.startsWith('blob:') && x.naturalWidth >= 500 && x.naturalHeight >= 300;
  });
  const i = a[a.length - 1];
  if (!i) return null;
  const c = document.createElement('canvas');
  c.width = i.naturalWidth; c.height = i.naturalHeight;
  c.getContext('2d').drawImage(i, 0, 0);
  return c.toDataURL('image/png');
}"""

# How many identical fingerprints in a row count as "finished", and how far apart.
STABLE_SAMPLES = 3
SAMPLE_SECONDS = 5.0


def _still_count(page) -> int:
    return len(page.evaluate(_STILLS_JS))


def _wait_for_new_image(page, before_count: int, timeout: float = 900.0) -> dict | None:
    """Wait until a new still has appeared and stopped changing.

    Completion cannot be read off the page text: Gemini leaves a "generating"
    label on screen after the picture is done, so that marker never clears and
    gating on it times out on a finished image. The element alone is not enough
    either, because it is added while still being drawn. So the newest still is
    sampled until its pixels hold steady for a few reads.
    """
    deadline = time.time() + timeout
    last_fp, stable, size = None, 0, None
    while time.time() < deadline:
        now = page.evaluate(_FINGERPRINT_JS)
        if now and now["n"] > before_count:
            size = {"w": now["w"], "h": now["h"]}
            stable = stable + 1 if now["fp"] == last_fp else 1
            last_fp = now["fp"]
            if stable >= STABLE_SAMPLES:
                return size
        if looks_signed_out(page.inner_text("body")):
            return None
        page.wait_for_timeout(int(SAMPLE_SECONDS * 1000))
    return None


def _grab_image(page) -> bytes:
    """Read the newest rendered still out of a canvas.

    `fetch()` on the blob URL fails with "Failed to fetch": the URL is revoked by
    the time the image is on screen. Drawing the already-decoded element into a
    canvas reads the pixels without touching the URL.
    """
    import base64

    data_url = page.evaluate(_GRAB_LAST_JS)
    if not data_url:
        raise RuntimeError("the generated image element disappeared before it could be read")
    return base64.b64decode(data_url.split(",", 1)[1])


def generate(prompt: str, key: str, *, timeout: float = 420.0, force: bool = False,
             fresh: bool = False) -> dict:
    existing = library.find("img", key)
    if existing and not force:
        return {"status": "REUSED", "entry": existing}

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser, context = connect(p)
        page = context.pages[0] if context.pages else context.new_page()
        # The tab keeps one long conversation. After a dozen stills it is heavy
        # enough that the next render can miss the timeout, so a retry starts a
        # clean conversation rather than appending to the slow one.
        if fresh or URL not in (page.url or ""):
            page.goto(URL, wait_until="domcontentloaded", timeout=60_000)
        page.wait_for_timeout(3500)

        body = page.inner_text("body")
        if "ลงชื่อเข้าใช้เพื่อ" in body and "สร้างรูปภาพ" in body:
            raise LoginRequired(login_instructions(APP))

        before_count = _still_count(page)

        box = page.locator("div[contenteditable='true'], textarea").first
        box.click(timeout=15_000)
        box.type(prompt + IMAGE_PROMPT_SUFFIX, delay=12)
        page.wait_for_timeout(600)
        page.keyboard.press("Enter")

        # A still takes minutes, not seconds: Gemini renders it in stages and
        # leaves the element on screen while it is still working, so waiting on
        # the element alone captures a partial frame. The marker gates that.
        size = _wait_for_new_image(page, before_count, timeout=timeout)
        if size is None:
            tail = page.inner_text("body")[-600:]
            if looks_signed_out(tail):
                raise LoginRequired(login_instructions(APP))
            raise TimeoutError(
                "no finished image appeared; Gemini may have answered with text instead. "
                f"page tail: {tail!r}"
            )

        data = _grab_image(page)
        out = library.KINDS["img"] / f"{library.entry_id('img', key)}.png"
        out.write_bytes(data)

    entry = library.add("img", key, out, source="gemini-web", prompt=prompt,
                        provider="gemini.google.com", bytes_written=len(data),
                        width=size["w"], height=size["h"])
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
