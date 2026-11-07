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

AVATAR = ROOT / "channel" / "avatar-pro-800x800.png"
COVER = ROOT / "channel" / "cover-pro-1640x624.png"
TIKTOK_URL = "https://www.tiktok.com/@aeris.music4"
# Each bio carries that surface's own affiliate link (Sub_id = tiktok / facebook)
# plus the disclosure COMPLIANCE.md requires. A Short earns the view; the bio is
# where the view can still turn into a click after the caption has scrolled away,
# and the first affiliate Reels went out with no link in the bio at all.
TIKTOK_BIO = ("🎵 เพลงไทยเพราะๆ ใหม่ทุกวัน\n"
              "🛒 ลิงก์พันธมิตร: https://s.shopee.co.th/60SrsstoP6")
FACEBOOK_ID = "61595890900382"
# The Page's own intro. A four-advisor panel (2026-11-06) said the intro must
# answer "what do I get if I follow?" in the first line, so the benefit leads and
# the follow ask closes it. Same voice as the YouTube description.
FACEBOOK_BIO = ("🎵 เพลงไทยฟังเพลิน ร้องตามได้ 🎶\n"
                "เพลงเศร้า · เพื่อชีวิต · ลูกทุ่ง · คาราโอเกะ เพลงใหม่เรื่อย ๆ\n"
                "กดติดตามไว้ ไม่พลาดเพลงต่อไปครับ ❤️\n"
                "▶️ ฟังเต็มที่ YouTube: @aerismusicth\n"
                "🛒 ของน่าซื้อ (ลิงก์พันธมิตร): https://s.shopee.co.th/2qVq75ACtW")
# The pinned "front door". A stranger who lands on the Page reads this before any
# Reel, so it names the four things the Page posts and asks for the follow. The
# first line is the whole pitch; the rest is scannable on a phone.
WELCOME_POST = ("❤️ ยินดีต้อนรับสู่ AERIS Music\n"
                "เพลงไทยหลากหลายอารมณ์ เพลงใหม่มาลงเรื่อย ๆ\n"
                "🎵 เพลงเศร้า สำหรับวันที่คิดถึงใครบางคน\n"
                "🎸 เพื่อชีวิต สำหรับวันที่ต้องการพลัง\n"
                "🌾 ลูกทุ่ง กลิ่นอายบ้านเรา\n"
                "🎤 คาราโอเกะ สำหรับคนที่อยากร้องตาม\n"
                "กดติดตามเพจไว้ ไม่พลาดเพลงใหม่ครับ ❤️")
# The AERIS Music *Page* (resolves to /people/AERIS-Music/61595890900382/), the
# same Page crosspost.py posts Reels to. Do not point this at 61596276533369 —
# that is K's personal profile ("Aeris-Ak Akath"), which cannot be branded and is
# the wrong surface; branding it is what the Page was created to replace.


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
        if not _open_tiktok_edit(pg):
            _shot(pg, "tiktok-no-edit")
            print("tiktok: edit-profile button not found")
            return 1
        pg.wait_for_timeout(4000)
        _shot(pg, "tiktok-edit")
        # The bio first: uploading the avatar replaces the edit dialog with a crop
        # flow, so the bio field is gone by the time the image is handed over.
        # TikTok's React state ignores the native-setter trick — the field shows
        # the text but the save posts the old value — so type with real key events
        # and click Save with a real mouse press. Verified against the
        # POST /api/update/profile/ response, which carries the new signature.
        landed = _tiktok_set_bio(pg, TIKTOK_BIO)
        print("tiktok: bio field", "set" if landed else "NOT found")
        pg.wait_for_timeout(800)
        if landed:
            _real_click_text(pg, "^save$|^บันทึก$|^confirm$")
            pg.wait_for_timeout(5000)
            _shot(pg, "tiktok-bio-saved")
        # Now the avatar, in a fresh dialog. Reload first: the save above leaves the
        # page on the profile view where the edit entrance is not yet re-mounted.
        try:
            pg.reload(wait_until="domcontentloaded")
            pg.wait_for_timeout(7000)
            _open_tiktok_edit(pg)
            pg.wait_for_timeout(4000)
            pg.locator('[role=dialog] input[type="file"], input[type="file"]').first.set_input_files(str(AVATAR))
            pg.wait_for_timeout(6000)
            print("tiktok: avatar uploaded")
            _shot(pg, "tiktok-avatar")
            _real_click_text(pg, "^save$|^บันทึก$|^confirm$|^apply$|^done$")
            pg.wait_for_timeout(4000)
        except Exception as exc:  # noqa: BLE001
            print(f"tiktok: avatar upload failed: {exc}")
        pg.close()
    return 0


def _open_tiktok_edit(page) -> bool:
    """Open TikTok's edit-profile dialog. Its test id is a data-e2e attribute, so
    Playwright's get_by_test_id (which looks for data-testid) never matches."""
    sel = '[data-e2e="edit-profile-entrance"]'
    try:
        if page.locator(sel).count():
            page.locator(sel).first.click(timeout=15000)
        elif not _js_click(page, "edit profile|แก้ไขโปรไฟล์"):
            return False
    except Exception:
        return False
    page.wait_for_timeout(4000)
    return bool(page.locator("[role=dialog]").count())


def _tiktok_set_bio(page, text: str) -> bool:
    """Clear and retype the bio inside the open edit dialog, then confirm it took."""
    try:
        ta = page.locator("[role=dialog] textarea").first
        ta.click()
    except Exception:
        return False
    page.wait_for_timeout(400)
    page.keyboard.press("Control+A")
    page.keyboard.press("Delete")
    page.wait_for_timeout(300)
    ta.type(text, delay=25)
    page.wait_for_timeout(1200)
    return ta.input_value() == text


def _real_click_text(page, pattern: str) -> bool:
    """Click a button by its text with a trusted mouse press."""
    box = page.evaluate("""(pat) => {
      const rx = new RegExp(pat, 'i');
      const d = [...document.querySelectorAll('[role=dialog]')].find(x => x.offsetParent !== null);
      if (!d) return null;
      const b = [...d.querySelectorAll('button')].find(x => rx.test((x.innerText||'').trim()));
      if (!b) return null;
      const r = b.getBoundingClientRect();
      return {x: r.x + r.width/2, y: r.y + r.height/2};
    }""", pattern)
    if not box:
        return False
    page.mouse.move(box["x"], box["y"])
    page.wait_for_timeout(250)
    page.mouse.down()
    page.wait_for_timeout(120)
    page.mouse.up()
    return True


def _fb_switch_to_page(page) -> bool:
    """Become the Page so its admin controls (cover, profile photo) exist.

    A Page opened from the personal profile shows the *visitor* view — no cover
    or photo edit control at all, which is why an aria-label lookup there times
    out. Switching is three clicks: the profile switcher, "สลับ" in its menu,
    then "ใช้เพจ" in the welcome dialog that greets a newly-managed Page. Already
    being the Page is a success, so this is safe to call every time.
    """
    if "แก้ไขรูปภาพหน้าปก" in page.inner_text("body"):
        return True
    page.evaluate("""() => {
      const b = document.querySelector('div[role=button][aria-label="สลับ"]');
      if (b) b.click();
    }""")
    page.wait_for_timeout(3500)
    page.evaluate("""() => {
      for (const m of document.querySelectorAll('div[role=dialog]'))
        for (const el of m.querySelectorAll('div[role=button],a,span'))
          if ((el.innerText || '').trim() === 'สลับ') { el.click(); return; }
    }""")
    page.wait_for_timeout(9000)
    page.evaluate("""() => {
      for (const d of document.querySelectorAll('div[role=dialog]'))
        for (const el of d.querySelectorAll('div[role=button],a,span'))
          if ((el.innerText || '').trim() === 'ใช้เพจ') { el.click(); return; }
    }""")
    page.wait_for_timeout(5000)
    return "แก้ไขรูปภาพหน้าปก" in page.inner_text("body")


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
        pg.set_viewport_size({"width": 1440, "height": 1000})
        pg.goto(f"https://www.facebook.com/profile.php?id={FACEBOOK_ID}",
                wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(6000)
        if B.looks_signed_out(pg.inner_text("body")[:4000]):
            print("facebook: not signed in")
            return 1
        if not _fb_switch_to_page(pg):
            print("facebook: could not switch into the Page")
            _shot(pg, "fb-switch-failed")
            pg.close()
            return 1
        cover = COVER
        # The admin cover control is aria-label "แก้ไขรูปภาพหน้าปก" and its menu
        # item is "อัพโหลดรูปภาพ"; the crop dialog's confirm is
        # "บันทึกการเปลี่ยนแปลง", not the "บันทึก" a bio field uses.
        print("facebook cover:", "set" if _fb_upload(
            pg, "แก้ไขรูปภาพหน้าปก", "อัพโหลดรูปภาพ",
            cover, "บันทึกการเปลี่ยนแปลง") else "NOT set")
        _shot(pg, "fb-cover")
        pg.reload(wait_until="domcontentloaded")
        pg.wait_for_timeout(5000)
        print("facebook photo:", "set" if _fb_upload(
            pg, "การดำเนินการกับรูปโปรไฟล์", "เลือกรูปโปรไฟล์|choose profile picture",
            AVATAR, "บันทึก|^save$", hover=True) else "NOT set")
        _shot(pg, "fb-photo")
        # The intro lives on the About tab, reached by sk=about. Same native
        # setter path as the personal bio, so it is set after the images settle.
        pg.goto(f"https://www.facebook.com/profile.php?id={FACEBOOK_ID}&sk=about",
                wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(6000)
        pg.evaluate("""() => {
          const b=[...document.querySelectorAll('[aria-label],[role=button]')]
            .find(e=>/แก้ไขคำอธิบายตัวเอง|แก้ไขรายละเอียด|edit.*intro|edit details/i
                    .test(e.getAttribute('aria-label')||''));
          if(b) b.click();
        }""")
        pg.wait_for_timeout(3500)
        print("facebook intro:", "set" if _set_bio(pg, FACEBOOK_BIO) else "NOT found")
        pg.wait_for_timeout(800)
        _js_click(pg, "^บันทึก$|^save$")
        pg.wait_for_timeout(4000)
        _shot(pg, "fb-bio")
        pg.close()
    return 0


def bio() -> int:
    """Set only the Page intro — no image upload, so it is safe to re-run.

    The four-advisor panel (2026-11-06) ranked the Page's own copy the #1
    view->follow fix, and `facebook()` re-uploads the cover and avatar every time,
    which is too heavy for a copy change. This drives the About tab alone.
    """
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        pg = ctx.new_page()
        pg.set_viewport_size({"width": 1440, "height": 1000})
        pg.goto(f"https://www.facebook.com/profile.php?id={FACEBOOK_ID}",
                wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(6000)
        if B.looks_signed_out(pg.inner_text("body")[:4000]):
            print("facebook: not signed in")
            pg.close()
            return 1
        if not _fb_switch_to_page(pg):
            print("facebook: could not switch into the Page")
            _shot(pg, "fb-switch-failed")
            pg.close()
            return 1
        pg.goto(f"https://www.facebook.com/profile.php?id={FACEBOOK_ID}&sk=about",
                wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(6000)
        _js_click(pg, "แก้ไขคำอธิบายตัวเอง|แก้ไขรายละเอียด|edit.*intro|edit details")
        pg.wait_for_timeout(3500)
        print("facebook intro:", "set" if _set_bio(pg, FACEBOOK_BIO) else "NOT found")
        pg.wait_for_timeout(800)
        _js_click(pg, "^บันทึก$|^save$")
        pg.wait_for_timeout(4000)
        _shot(pg, "fb-bio")
        pg.close()
    return 0


def welcome() -> int:
    """Post the pinned front door, then pin it. Safe to re-run.

    Three things this encodes, each found the hard way:
      * `document.execCommand('insertText')` does NOT stick on the Page composer
        (only 1 character lands); the CDP `Input.insertText` does.
      * The composer is two steps: caption -> "ถัดไป" -> "โพสต์".
      * A pinned post's action menu offers "เลิกปักหมุดโพสต์" (unpin), so if that
        item is already present the post is pinned and there is nothing to do.
    """
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        pg = ctx.new_page()
        pg.set_viewport_size({"width": 1440, "height": 1100})
        pg.goto(f"https://www.facebook.com/profile.php?id={FACEBOOK_ID}",
                wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(11000)
        if B.looks_signed_out(pg.inner_text("body")[:4000]):
            print("facebook: not signed in")
            pg.close()
            return 1
        if not _fb_switch_to_page(pg):
            print("facebook: could not switch into the Page")
            pg.close()
            return 1

        already = pg.evaluate("""() => {
          const a=[...document.querySelectorAll('[role=article]')]
            .find(x=>/ยินดีต้อนรับสู่ AERIS Music/.test(x.innerText||''));
          return a ? 'found' : 'missing';
        }""")
        if already == "missing":
            pg.evaluate("""() => {const el=[...document.querySelectorAll('[role=button],div[tabindex]')]
              .find(e=>/กำลังคิดอะไรอยู่/i.test(e.innerText||'')); if(el) el.click();}""")
            pg.wait_for_timeout(4500)
            pg.locator('[role=dialog] [contenteditable=true]').first.click()
            pg.wait_for_timeout(800)
            ctx.new_cdp_session(pg).send("Input.insertText", {"text": WELCOME_POST})
            pg.wait_for_timeout(1200)
            pg.evaluate("""() => {const d=document.querySelector('[role=dialog]');
              const b=[...d.querySelectorAll('[role=button]')].find(x=>/^ถัดไป$/.test((x.innerText||'').trim()));
              if(b)b.click();}""")
            pg.wait_for_timeout(5000)
            pg.evaluate("""() => {const d=document.querySelector('[role=dialog]');
              const b=[...d.querySelectorAll('[role=button]')].find(x=>/^โพสต์$/.test((x.innerText||'').trim()));
              if(b)b.click();}""")
            pg.wait_for_timeout(9000)
            print("welcome post: created")

        # Pin it if it is not already pinned. The menu is opened on the post
        # itself; a pinned post's menu carries "เลิกปักหมุดโพสต์".
        state = pg.evaluate("""() => {
          const a=[...document.querySelectorAll('[role=article]')]
            .find(x=>/ยินดีต้อนรับสู่ AERIS Music/.test(x.innerText||''));
          const b=a&&[...a.querySelectorAll('[aria-label]')]
            .find(e=>/การดำเนินการสำหรับโพสต์นี้/.test(e.getAttribute('aria-label')||''));
          if(!b) return 'no-menu';
          b.click(); return 'opened';
        }""")
        pg.wait_for_timeout(3000)
        items = pg.evaluate("""() => [...document.querySelectorAll('[role=menuitem]')].map(m=>(m.innerText||'').trim())""")
        if any(i.startswith("เลิกปักหมุด") for i in items):
            print("welcome pin: already pinned")
        else:
            pg.evaluate("""() => {const it=[...document.querySelectorAll('[role=menuitem]')]
              .find(m=>/^ปักหมุดโพสต์$/.test((m.innerText||'').trim())); if(it)it.click();}""")
            pg.wait_for_timeout(3000)
            print("welcome pin: pinned")
        _shot(pg, "fb-welcome")
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


def youtube() -> int:
    """Set the channel avatar in YouTube Studio. The one YouTube step needing K.

    There is no API for the channel avatar (consult 2026-11-07: "channels.update
    covers metadata/branding, not the profile picture"), so the only route is the
    Studio UI. That makes it the single YouTube action that cannot be automated
    past a sign-in — but once the Google session is restored from the vault it
    re-runs unattended like the other surfaces, so it is "one K action, then
    never again". Studio stages branding edits and requires a final Publish, so
    this clicks that too; without it the avatar upload looks done and never lands.
    """
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        br, ctx = B.connect(p)
        pg = ctx.new_page()
        pg.set_viewport_size({"width": 1440, "height": 1000})
        pg.goto("https://studio.youtube.com/", wait_until="domcontentloaded",
                timeout=60000)
        pg.wait_for_timeout(9000)
        if "accounts.google.com" in pg.url or \
                B.looks_signed_out(pg.inner_text("body")[:4000]):
            print("youtube: not signed in — Google asks the password (the one K step)")
            return 1
        _js_click(pg, "^การปรับแต่ง$|^customi[sz]ation$")
        pg.wait_for_timeout(5000)
        _shot(pg, "yt-customization")
        _js_click(pg, "^การสร้างแบรนด์$|^branding$")
        pg.wait_for_timeout(4000)
        _shot(pg, "yt-branding")
        # The picture's control is a hover button labelled "เปลี่ยนรูปภาพ" /
        # "Change picture"; its accessible name carries "picture".
        opened = bool(pg.evaluate("""() => {
          const re = /เปลี่ยนรูปภาพ|change (profile )?picture|เปลี่ยน|^change$/i;
          const els = [...document.querySelectorAll('button, [role="button"], a')]
            .filter(e => re.test((e.getAttribute('aria-label') || e.innerText || '').trim()));
          if (!els.length) return false;
          els[0].click(); return true;
        }"""))
        print("youtube: picture control", "opened" if opened else "NOT found")
        pg.wait_for_timeout(3000)
        try:
            pg.locator('input[type="file"]').first.set_input_files(str(AVATAR))
            pg.wait_for_timeout(7000)
            _shot(pg, "yt-avatar-upload")
            _real_click_text(pg, "^บันทึก$|^save$|^เสร็จสิ้น$|^done$|^apply$")
            pg.wait_for_timeout(3000)
        except Exception as exc:  # noqa: BLE001
            print(f"youtube: avatar upload failed: {exc}")
        # Studio stages branding edits behind a final Publish; skip it and the
        # avatar silently never goes live.
        _real_click_text(pg, "^เผยแพร่$|^publish$")
        pg.wait_for_timeout(6000)
        _shot(pg, "yt-avatar-published")
        pg.close()
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("target", nargs="?",
                    choices=["tiktok", "facebook", "youtube", "bio", "welcome",
                             "status"], default="status")
    args = ap.parse_args()
    if args.target == "status":
        return status()
    if args.target == "tiktok":
        return tiktok()
    if args.target == "facebook":
        return facebook()
    if args.target == "youtube":
        return youtube()
    if args.target == "bio":
        return bio()
    if args.target == "welcome":
        return welcome()
    print("unknown target", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
