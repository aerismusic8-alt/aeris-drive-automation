#!/usr/bin/env python3
"""Fill in the AERIS Music profiles on the social surfaces.

K, 2026-11-01: "Fb tk shoppee ต้องอัพเดทโปรไฟล์ หาผู้ติดตามด้วยใช่ไหม kเห็นโล่งๆ".
Right — a profile with no avatar and no bio reads as abandoned, so a viewer who
lands there from a Short does not follow. There is no free API for any of this,
so AR drives the signed-in cloud desktop.

    python3 scripts/profile_setup.py tiktok        # bio + avatar
    python3 scripts/profile_setup.py facebook       # page photo + intro
    python3 scripts/profile_setup.py --status       # read what is there now
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))

import browser as B  # noqa: E402

AVATAR = ROOT / "channel" / "avatar-800x800.png"
TIKTOK_URL = "https://www.tiktok.com/@aeris.music4"
TIKTOK_BIO = ("🎵 เพลงไทยเพราะๆ ใหม่ทุกวัน · ฟังเต็มที่ YouTube\n"
              "AERIS Music 🎧 เพลงใหม่ทุกวัน")
FACEBOOK_ID = "61596276533369"


def _shot(page, name: str) -> None:
    d = ROOT / "work"
    d.mkdir(exist_ok=True)
    page.screenshot(path=str(d / f"profile-{name}.png"))


def _js_click(page, pattern: str) -> bool:
    return bool(page.evaluate("""(pat) => {
      const re = new RegExp(pat, 'i');
      const els = [...document.querySelectorAll('button, a, [role="button"], [role="menuitem"]')]
        .filter(e => re.test((e.innerText || e.getAttribute('aria-label') || '').trim()));
      if (!els.length) return false;
      els[els.length - 1].click();
      return true;
    }""", pattern))


def _set_bio(page, text: str) -> bool:
    """Focus the bio field and set it with the native setter, then Save."""
    ok = page.evaluate("""(txt) => {
      const cands = [...document.querySelectorAll('textarea, [contenteditable="true"], input')]
        .filter(e => {
          const hint = (e.placeholder || e.getAttribute('aria-label') ||
                        e.getAttribute('data-e2e') || '').toLowerCase();
          return e.tagName === 'TEXTAREA' || /bio|signature|简介|약력/.test(hint);
        });
      const el = cands[0];
      if (!el) return 'no-field';
      el.focus();
      if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
        const proto = el.tagName === 'TEXTAREA'
          ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
        setter.call(el, txt);
        el.dispatchEvent(new Event('input', {bubbles: true}));
        el.dispatchEvent(new Event('change', {bubbles: true}));
      } else {
        el.innerText = txt;
        el.dispatchEvent(new InputEvent('input', {bubbles: true}));
      }
      return 'ok';
    }""", text)
    return ok == "ok"


def tiktok() -> int:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        pg = ctx.new_page()
        pg.goto(TIKTOK_URL, wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(5000)
        if B.looks_signed_out(pg.inner_text("body")[:4000]):
            print("tiktok: not signed in")
            return 1
        # open the edit-profile dialog
        try:
            pg.get_by_test_id("edit-profile-entrance").click(timeout=15000)
        except Exception:
            if not _js_click(pg, "edit profile|แก้ไขโปรไฟล์"):
                _shot(pg, "tiktok-no-edit")
                print("tiktok: edit-profile button not found")
                return 1
        pg.wait_for_timeout(4000)
        _shot(pg, "tiktok-edit")
        # The dialog's single image input is the avatar.
        try:
            pg.locator('input[type="file"]').first.set_input_files(str(AVATAR))
            pg.wait_for_timeout(6000)
            print("tiktok: avatar uploaded")
            _shot(pg, "tiktok-avatar")
        except Exception as exc:  # noqa: BLE001
            print(f"tiktok: avatar upload failed: {exc}")
        landed = _set_bio(pg, TIKTOK_BIO)
        print("tiktok: bio field", "set" if landed else "NOT found")
        pg.wait_for_timeout(1000)
        if landed:
            _js_click(pg, "^save$|^บันทึก$|^confirm$")
            pg.wait_for_timeout(4000)
            _shot(pg, "tiktok-after-save")
        pg.close()
    return 0


def _fb_upload(page, opener: str, item: str, image: Path, done: str,
               hover: bool = False) -> bool:
    """Open an FB photo menu, choose its upload item, hand the file to the chooser.

    The cover control reacts to a plain click, but the profile-picture control
    only opens its menu on hover, so `hover` selects that path. Both menus then
    raise a native file chooser bound to a hidden input, so the file is handed to
    the chooser itself — a plain `input.set_input_files` can bind to the
    composer's input and silently do nothing.
    """
    try:
        if hover:
            ctrl = page.locator(f'[aria-label*="{opener}"]').last
            ctrl.hover()
            page.wait_for_timeout(1200)
            ctrl.click(force=True)
        else:
            if not _js_click(page, opener):
                return False
    except Exception as exc:  # noqa: BLE001
        print(f"  fb opener: {str(exc)[:100]}")
        return False
    page.wait_for_timeout(2500)
    fired: dict = {}

    def _on_chooser(fc):
        try:
            fc.set_files(str(image))
            fired["ok"] = True
        except Exception as exc:  # noqa: BLE001
            print(f"  fb set_files: {str(exc)[:100]}")

    page.once("filechooser", _on_chooser)

    def _wait(seconds: int) -> bool:
        for _ in range(seconds * 2):
            if fired.get("ok"):
                return True
            page.wait_for_timeout(500)
        return bool(fired.get("ok"))

    # The cover menu item raises the chooser directly; the profile-photo item
    # opens a dialog whose own "อัพโหลดรูปภาพ" raises it. Try the item, then the
    # dialog button, and let whichever exists win.
    if item:
        _js_click(page, item)
        _wait(6)
    if not fired.get("ok"):
        _js_click(page, "อัพโหลดรูปภาพ|อัปโหลดรูปภาพ|upload photo|upload")
        _wait(10)
    if not fired.get("ok"):
        print("  fb file chooser: never fired")
        return False
    page.wait_for_timeout(9000)
    _js_click(page, done)
    page.wait_for_timeout(8000)
    return True


def facebook() -> int:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        pg = ctx.new_page()
        pg.goto(f"https://www.facebook.com/profile.php?id={FACEBOOK_ID}",
                wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(6000)
        if B.looks_signed_out(pg.inner_text("body")[:4000]):
            print("facebook: not signed in")
            return 1
        cover = ROOT / "channel" / "cover-facebook-1640x624.png"
        print("facebook cover:", "set" if _fb_upload(
            pg, "หน้าปก|cover photo", "อัพโหลดรูปภาพ|อัปโหลดรูปภาพ|upload photo",
            cover, "บันทึก|^save$") else "NOT set")
        _shot(pg, "fb-cover")
        pg.reload(wait_until="domcontentloaded")
        pg.wait_for_timeout(5000)
        print("facebook photo:", "set" if _fb_upload(
            pg, "การดำเนินการกับรูปโปรไฟล์", "เลือกรูปโปรไฟล์|choose profile picture",
            AVATAR, "บันทึก|^save$", hover=True) else "NOT set")
        _shot(pg, "fb-photo")
        pg.close()
    return 0


def status() -> int:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        for name, url in (("tiktok", TIKTOK_URL),
                          ("facebook", f"https://www.facebook.com/profile.php?id={FACEBOOK_ID}")):
            pg = ctx.new_page()
            pg.goto(url, wait_until="domcontentloaded", timeout=60000)
            pg.wait_for_timeout(5000)
            body = pg.inner_text("body")[:600].replace("\n", " | ")
            print(f"{name}: {body[:400]}")
            pg.close()
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("target", nargs="?", choices=["tiktok", "facebook", "status"], default="status")
    args = ap.parse_args()
    if args.target == "status":
        return status()
    if args.target == "tiktok":
        return tiktok()
    if args.target == "facebook":
        return facebook()
    print("unknown target", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
