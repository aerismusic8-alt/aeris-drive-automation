#!/usr/bin/env python3
"""Set the channel avatar through YouTube Studio on the cloud desktop.

YouTube exposes no API for a channel avatar, so the banner can be automated
(`ops/apply_channel_art.py`) but the avatar cannot. This drives the signed-in
Studio instead. It is best-effort by design: Studio's markup changes, and a
failure here must not look like a failure of the banner, which is already live.

    python3 ops/set_avatar_studio.py --shot-only   # just screenshot the page
    python3 ops/set_avatar_studio.py               # hover, upload, publish

Every step writes a screenshot to work/avatar-*.png so a failure is diagnosable
from the images rather than from a guess.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))
sys.path.insert(0, str(ROOT / "aeris938-1" / "scripts"))

import browser as B  # noqa: E402

CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"
IMAGES_URL = f"https://studio.youtube.com/channel/{CHANNEL_ID}/editing/images"
AVATAR = ROOT / "music938-1" / "channel" / "avatar-pro-800x800.png"
WORK = ROOT / "music938-1" / "work"


def _shot(page, name: str) -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    p = WORK / f"avatar-{name}.png"
    page.screenshot(path=str(p))
    return p


def _click_text(page, pattern: str) -> bool:
    return bool(page.evaluate("""(pat) => {
      const re = new RegExp(pat, 'i');
      const els = [...document.querySelectorAll('button, [role="button"], tp-yt-paper-button, ytcp-button')]
        .filter(e => re.test((e.innerText || e.getAttribute('aria-label') || '').trim()));
      if (!els.length) return false;
      els[els.length - 1].click();
      return true;
    }""", pattern))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot-only", action="store_true")
    a = ap.parse_args()

    if not AVATAR.exists():
        raise SystemExit(f"no avatar at {AVATAR} (run scripts/brand_pro.py first)")

    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        pg = ctx.new_page()
        pg.set_viewport_size({"width": 1440, "height": 1000})
        pg.goto(IMAGES_URL, wait_until="domcontentloaded", timeout=90000)
        pg.wait_for_timeout(9000)
        print("page:", pg.title(), "|", pg.url[:70])
        print("shot:", _shot(pg, "01-page"))

        if a.shot_only:
            ctx.close()
            return 0

        # The profile-picture control is a hover-revealed edit button. Hover the
        # avatar image, then click whatever camera/pencil control appears.
        hovered = False
        for sel in ('#avatar', 'ytcp-profile-image', '[id*="avatar" i]',
                    'img[src*="ggpht"]'):
            loc = pg.locator(sel).first
            try:
                if loc.count():
                    loc.hover(timeout=8000)
                    hovered = True
                    break
            except Exception:  # noqa: BLE001
                continue
        pg.wait_for_timeout(2500)
        print("hovered:", hovered, "shot:", _shot(pg, "02-hover"))

        fired: dict = {}

        def _on_chooser(fc):
            try:
                fc.set_files(str(AVATAR))
                fired["ok"] = True
            except Exception as exc:  # noqa: BLE001
                print("  set_files:", str(exc)[:120])

        pg.once("filechooser", _on_chooser)

        # Click the edit control (camera / pencil / "เปลี่ยน").
        if not _click_text(pg, "เปลี่ยน|edit|แก้ไข|กล้อง|camera|แทรกรูป"):
            pg.mouse.click(720, 260)  # fall back to the avatar's own hit area
        for _ in range(24):
            if fired.get("ok"):
                break
            pg.wait_for_timeout(500)
        pg.wait_for_timeout(4000)
        print("chooser fired:", fired.get("ok"), "shot:", _shot(pg, "03-upload"))

        if not fired.get("ok"):
            print("RESULT=avatar not uploaded — Studio did not offer a file chooser")
            ctx.close()
            return 2

        # Crop dialog -> Done -> Publish.
        _click_text(pg, "เสร็จสิ้น|done|บันทึก|save|เสร็จ")
        pg.wait_for_timeout(6000)
        _click_text(pg, "เผยแพร่|publish|ยืนยัน|confirm")
        pg.wait_for_timeout(9000)
        print("shot:", _shot(pg, "04-done"))
        print("RESULT=avatar upload attempted")
        ctx.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
