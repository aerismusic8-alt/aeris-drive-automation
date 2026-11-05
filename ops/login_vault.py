#!/usr/bin/env python3
"""Persist the cloud-desktop browser session so K signs in once, not every pod.

Why this exists
---------------
The Chrome profile lives on /workspace, which survives a container recycle — but
a *new sandbox* gets a fresh, empty volume, so every sign-in (Google, Facebook,
TikTok) is lost and has to be redone. K has now had to do it more than once, which
is a defect, not a workflow.

What it stores, and what it does not
------------------------------------
Only the browser **session cookies** (the thing that keeps you logged in), read
live over CDP and written to the account-scoped automation KV store that also
backs the knowledge vault. It never touches the account password, so the saved
passwords are deliberately excluded. Cookies are still secrets — treat a snapshot
like a live session, and rotate by signing out.

Why cookies and not the profile directory
-----------------------------------------
Copying the profile's SQLite `Cookies` file is unreliable: Chromium holds it open
and flushes lazily, so a copy can be stale, and the file is encrypted with a key
in `Local State`. Reading the cookies through CDP returns the authoritative set
the browser is actually using, and re-adding them through CDP lets Chromium
re-encrypt them with whatever key the *new* sandbox has. That is why a restore
works on a machine with no keyring at all.

Usage
-----
    python3 ops/login_vault.py save       # after K signs in, capture the session
    python3 ops/login_vault.py restore    # on a fresh sandbox, put it back
    python3 ops/login_vault.py status     # what is stored, and when
"""
from __future__ import annotations

import argparse
import base64
import gzip
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ax_vault  # noqa: E402

CDP = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222")
INDEX_KEY = "axlogin:index"
CHUNK_KEY = "axlogin:d:{i}"
# The bookmark bar lives in the chrome profile on /workspace, so it survives a
# recycle — but a *new* sandbox gets an empty volume and the bar is gone with it.
# K keeps the five work surfaces pinned there, so snapshot it beside the cookies.
BOOKMARKS_KEY = "axlogin:bookmarks"
# localStorage/sessionStorage per origin, stored beside the cookies. Cookies
# alone are not the whole session: Google keeps its device-trust token in
# localStorage, so a cookie-only restore still makes Google ask for the device.
LS_INDEX_KEY = "axlogin:ls:index"
LS_CHUNK_KEY = "axlogin:ls:d:{i}"
# Origins whose storage carries session state worth keeping. Reading a foreign
# origin's storage is impossible from another page, so each is visited in turn.
STORAGE_ORIGINS = ("https://accounts.google.com", "https://myaccount.google.com",
                   "https://gemini.google.com", "https://www.google.com",
                   "https://www.facebook.com", "https://www.tiktok.com",
                   "https://www.flowmusic.app")
PROFILE = Path(os.environ.get(
    "AERIS_CHROME_PROFILE",
    "/workspace/ax-tools/aeris938-state/chrome-profile/Default"))
# Leave room for the JSON envelope under the 65536-byte KV value cap.
CHUNK_CHARS = ax_vault.CHUNK_CHARS
# Surfaces worth reporting on, so `status` says something useful. Flow Music is
# the song engine: if its login is lost, no new song can be generated, so it is
# watched and restored like the rest.
WATCH = (".google.com", "accounts.google.com", ".facebook.com", ".tiktok.com",
         ".flowmusic.app")
# The cookie that actually proves a session on each surface. A restored cookie is
# not a restored session: the site can still reject it, and reporting "ok" on
# mere presence is how a dead session looked healthy for a whole session.
AUTH = {
    ".google.com": "SID",
    ".facebook.com": "c_user",
    ".tiktok.com": "sessionid",
    ".flowmusic.app": "sb-sb-auth-token.0",
}
# Where to look, and what a signed-in page shows instead of a login form. A
# marker prefixed with "!" must be *absent* — Flow Music's landing page keeps a
# "Log in" link, so "signed in" is proved by it being gone, not by a marker
# appearing.
PROBE = {
    ".google.com": ("https://myaccount.google.com/", "บัญชี", "Account"),
    # The signed-in shell renders "ค้นหาเพื่อน" / the owner's name; the
    # logged-out page renders neither. The marker set is deliberately generous
    # because Facebook's first paint varies, and a false "rejected" would send K
    # to re-sign a session that actually works (posting proves it does).
    ".facebook.com": ("https://www.facebook.com/", "ค้นหาเพื่อน", "เพื่อน"),
    ".tiktok.com": ("https://www.tiktok.com/foryou", "ค้นหา", "Search"),
    ".flowmusic.app": ("https://www.flowmusic.app/", "!Log in"),
}


def pack(cookies: list[dict], account: str = "") -> tuple[dict, list[str]]:
    """Return (index, chunks) for a cookie set. Pure, so it can be tested."""
    blob = json.dumps({"account": account, "cookies": cookies}).encode()
    b64 = base64.b64encode(gzip.compress(blob)).decode()
    chunks = [b64[i:i + CHUNK_CHARS] for i in range(0, len(b64), CHUNK_CHARS)] or [""]
    domains = sorted({c.get("domain", "") for c in cookies})
    index = {
        "count": len(chunks),
        "n_cookies": len(cookies),
        "domains": domains,
        "account": account,
        "saved_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "surfaces": {d: sum(1 for c in cookies if c.get("domain") == d) for d in WATCH
                     if any(c.get("domain") == d for c in cookies)},
    }
    return index, chunks


def unpack(index: dict, chunks: list[str]) -> list[dict]:
    """Inverse of pack. Pure, so it can be tested."""
    b64 = "".join(chunks)
    return json.loads(gzip.decompress(base64.b64decode(b64)))["cookies"]


def _dump_storage(pg) -> dict:
    """localStorage + sessionStorage of the page currently loaded in `pg`."""
    return pg.evaluate("""() => {
      const out = {local: {}, session: {}};
      try { for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i); out.local[k] = localStorage.getItem(k);
      } } catch (e) {}
      try { for (let i = 0; i < sessionStorage.length; i++) {
        const k = sessionStorage.key(i); out.session[k] = sessionStorage.getItem(k);
      } } catch (e) {}
      return out;
    }""")


def _restore_storage(pg, dump: dict) -> int:
    """Write a dump back into the current origin. Returns the key count."""
    return pg.evaluate("""(dump) => {
      let n = 0;
      try { for (const [k, v] of Object.entries(dump.local || {})) { localStorage.setItem(k, v); n++; } } catch (e) {}
      try { for (const [k, v] of Object.entries(dump.session || {})) { sessionStorage.setItem(k, v); n++; } } catch (e) {}
      return n;
    }""", dump)


def save_storage() -> int:
    """Capture localStorage/sessionStorage for each watched origin.

    A cookie-only snapshot is not a full session — Google stores its device-trust
    token in localStorage, so restoring cookies alone still triggers a device
    check. This walks each origin in the open browser and stores its storage.
    """
    pw, br, ctx = _context()
    collected: dict = {}
    try:
        pg = ctx.new_page()
        try:
            for origin in STORAGE_ORIGINS:
                try:
                    pg.goto(origin, wait_until="domcontentloaded", timeout=45000)
                    pg.wait_for_timeout(2500)
                    dump = _dump_storage(pg)
                    if dump["local"] or dump["session"]:
                        collected[origin] = dump
                except Exception as exc:  # noqa: BLE001
                    print(f"  {origin}: skipped ({str(exc)[:50]})")
        finally:
            pg.close()
    finally:
        pw.stop()
    blob = json.dumps(collected).encode()
    b64 = base64.b64encode(gzip.compress(blob)).decode()
    chunks = [b64[i:i + CHUNK_CHARS] for i in range(0, len(b64), CHUNK_CHARS)] or [""]
    aid = ax_vault.ensure_anchor()
    for i, c in enumerate(chunks):
        ax_vault.kv_put(aid, LS_CHUNK_KEY.format(i=i), c)
    ax_vault.kv_put(aid, LS_INDEX_KEY, {
        "count": len(chunks),
        "origins": {o: len(v["local"]) + len(v["session"]) for o, v in collected.items()},
        "saved_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    })
    n = sum(len(v["local"]) + len(v["session"]) for v in collected.values())
    print(f"saved {n} storage key(s) across {len(collected)} origin(s)")
    for o, c in sorted(collected.items()):
        print(f"  {o}: {len(c['local'])} local, {len(c['session'])} session")
    return 0


def restore_storage() -> int:
    """Put the saved storage back into each origin, before the pages are used."""
    aid = ax_vault.ensure_anchor()
    index = ax_vault.kv_get(aid, LS_INDEX_KEY)
    if not index:
        print("no saved storage (login_vault.py save has never run)")
        return 0
    chunks = [ax_vault.kv_get(aid, LS_CHUNK_KEY.format(i=i)) or ""
              for i in range(index["count"])]
    collected = json.loads(gzip.decompress(
        base64.b64decode("".join(chunks))).decode())
    pw, br, ctx = _context()
    total = 0
    try:
        pg = ctx.new_page()
        try:
            for origin, dump in collected.items():
                try:
                    pg.goto(origin, wait_until="domcontentloaded", timeout=45000)
                    pg.wait_for_timeout(1500)
                    total += _restore_storage(pg, dump)
                except Exception as exc:  # noqa: BLE001
                    print(f"  {origin}: skipped ({str(exc)[:50]})")
        finally:
            pg.close()
    finally:
        pw.stop()
    print(f"restored {total} storage key(s) (saved {index['saved_at']})")
    return 0


def read_bookmarks() -> list[dict]:
    """The bookmark-bar url entries, flattened. [] when the profile has no file."""
    path = PROFILE / "Bookmarks"
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    out: list[dict] = []

    def walk(node: dict) -> None:
        for child in node.get("children", []):
            if child.get("type") == "folder":
                walk(child)
            elif child.get("type") == "url" and child.get("url"):
                out.append({"name": child.get("name", ""), "url": child["url"]})

    walk(data.get("roots", {}).get("bookmark_bar", {}))
    return out


def write_bookmarks(entries: list[dict]) -> int:
    """Put the entries on the bookmark bar by editing `Bookmarks` on disk.

    This is only the *fallback*; prefer `restore_bookmarks_via_cdp`, which lets
    Chrome own the write. A hand-written file is unreliable: Chrome verifies the
    `checksum` field and silently discards a file whose checksum it cannot
    reproduce (a 9-entry file written here was dropped on the next start, losing
    K's whole bar). Must run while Chromium is down anyway — Chrome reads
    `Bookmarks` at profile load and rewrites it on exit.
    """
    if not entries:
        return 0
    path = PROFILE / "Bookmarks"
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
    else:
        data = {"roots": {
            "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "children": []},
            "other": {"type": "folder", "name": "Other bookmarks", "children": []},
            "synced": {"type": "folder", "name": "Mobile bookmarks", "children": []},
        }}
    bar = data["roots"].setdefault(
        "bookmark_bar", {"type": "folder", "name": "Bookmarks bar", "children": []})
    bar.setdefault("children", [])
    have = {c.get("url") for c in bar["children"] if c.get("type") == "url"}
    added = 0
    for e in entries:
        if e["url"] in have:
            continue
        bar["children"].append({"type": "url", "name": e.get("name", ""), "url": e["url"]})
        have.add(e["url"])
        added += 1
    if added:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, ensure_ascii=False, indent=3), encoding="utf-8")
    return added


# Chrome's bookmark bar folder id is "1" in every profile.
_ADD_SCRIPT = """(entries) => new Promise((resolve) => {
    chrome.bookmarks.getChildren('1', (kids) => {
        const have = new Set(kids.map(k => k.url).filter(Boolean));
        const todo = entries.filter(e => !have.has(e.url));
        if (todo.length === 0) return resolve({added: 0, total: kids.length});
        let done = 0;
        todo.forEach((e) => chrome.bookmarks.create(
            {parentId: '1', title: e.name, url: e.url}, () => {
                done++;
                if (done === todo.length) resolve({added: done, total: kids.length + done});
            }));
    });
})"""


def restore_bookmarks_via_cdp(entries: list[dict]) -> int:
    """Add the entries through Chrome's own bookmark API.

    Chrome verifies a `checksum` in `Bookmarks` and drops a file whose checksum
    it cannot reproduce, so writing the file is not enough on its own. Going
    through `chrome.bookmarks.create` makes Chrome own the write and the bar
    survives the next start. The browser must already be running.
    """
    pw, br, ctx = _context()
    pg = ctx.new_page()
    try:
        pg.goto("chrome://bookmarks/", wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(2000)
        res = pg.evaluate(_ADD_SCRIPT, entries)
        return int(res.get("added", 0))
    finally:
        pg.close()
        pw.stop()


def save_bookmarks() -> int:
    entries = read_bookmarks()
    ax_vault.kv_put(ax_vault.ensure_anchor(), BOOKMARKS_KEY,
                    {"saved_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                     "entries": entries})
    print(f"saved {len(entries)} bookmark(s)")
    for e in entries:
        print(f"  - {e['name']} -> {e['url']}")
    return 0


def restore_bookmarks() -> int:
    blob = ax_vault.kv_get(ax_vault.ensure_anchor(), BOOKMARKS_KEY)
    if not blob:
        print("no saved bookmarks (login_vault.py save has never run)")
        return 0
    entries = blob.get("entries", [])
    # Prefer Chrome's own API when the browser is up: a hand-written file is
    # dropped because Chrome cannot reproduce the checksum (that is what lost the
    # bar). Fall back to the file only when there is no browser to talk to.
    try:
        added = restore_bookmarks_via_cdp(entries)
        how = "via CDP"
    except Exception as exc:  # noqa: BLE001
        print(f"[=] CDP bookmark restore unavailable ({exc}); writing the file")
        added = write_bookmarks(entries)
        how = "to file (unverified)"
    print(f"restored {added} bookmark(s) {how} (saved {blob.get('saved_at')})")
    return 0


def _context():
    """Attach to the running cloud-desktop browser, or explain how to start it."""
    from playwright.sync_api import sync_playwright
    pw = sync_playwright().start()
    try:
        br = pw.chromium.connect_over_cdp(CDP)
    except Exception as exc:  # noqa: BLE001
        pw.stop()
        raise SystemExit(
            f"no cloud desktop on {CDP} ({exc}).\n"
            "  start it first: python3 .agents/skills/ax-cloud-desktop/scripts/bootstrap.py")
    return pw, br, (br.contexts[0] if br.contexts else br.new_context())


def save() -> int:
    pw, br, ctx = _context()
    try:
        cookies = ctx.cookies()
        account = ""
        try:
            pg = ctx.pages[0] if ctx.pages else ctx.new_page()
            account = pg.evaluate(
                "() => { const m = document.body.innerText.match(/[\\w.+-]+@[\\w-]+\\.[\\w.]+/);"
                " return m ? m[0] : ''; }")
        except Exception:  # noqa: BLE001
            pass
    finally:
        pw.stop()
    if not cookies:
        raise SystemExit("the browser has no cookies to save")
    index, chunks = pack(cookies, account)
    aid = ax_vault.ensure_anchor()
    for i, c in enumerate(chunks):
        ax_vault.kv_put(aid, CHUNK_KEY.format(i=i), c)
    ax_vault.kv_put(aid, INDEX_KEY, index)
    print(f"saved {index['n_cookies']} cookies across {len(chunks)} chunk(s)")
    print(f"  account : {account or '(unknown)'}")
    print(f"  surfaces: {index['surfaces']}")
    print(f"  at      : {index['saved_at']}")
    save_bookmarks()
    save_storage()
    return 0


def _signed_in(ctx, domain: str) -> bool:
    """True only if the surface actually answers as a signed-in user.

    Presence of the auth cookie is necessary but not sufficient — Facebook kept
    `c_user`/`xs` while serving the logged-out page. So this loads the surface
    and looks for content that only appears when signed in.
    """
    probe = PROBE.get(domain)
    if not probe:
        return False
    url, *markers = probe
    pg = ctx.new_page()
    try:
        pg.goto(url, wait_until="domcontentloaded", timeout=60000)
        pg.wait_for_timeout(9000)
        body = pg.inner_text("body")
        if "เข้าสู่ระบบ" in body[:200] and "รหัสผ่าน" in body:
            return False
        # "!marker" means the page is signed in only when the marker is gone
        # (Flow Music keeps a "Log in" link on its landing page).
        want = [m for m in markers if not m.startswith("!")]
        gone = [m[1:] for m in markers if m.startswith("!")]
        if any(m in body for m in gone):
            return False
        return any(m in body for m in want)
    except Exception:  # noqa: BLE001
        return False
    finally:
        pg.close()


def restore(verify: bool = True) -> int:
    index = ax_vault.kv_get(ax_vault.ensure_anchor(), INDEX_KEY)
    if not index:
        raise SystemExit("no saved session; run `login_vault.py save` after signing in")
    aid = ax_vault.ensure_anchor()
    chunks = [ax_vault.kv_get(aid, CHUNK_KEY.format(i=i)) or "" for i in range(index["count"])]
    cookies = unpack(index, chunks)
    pw, br, ctx = _context()
    try:
        ctx.add_cookies(cookies)
        present = {c["domain"] for c in ctx.cookies()}
        auth = {
            d: any(c["domain"] == d and c["name"] == AUTH[d] for c in ctx.cookies())
            for d in WATCH if d in AUTH
        }
        live = {d: _signed_in(ctx, d) for d in WATCH if d in PROBE} if verify else {}
    finally:
        pw.stop()
    print(f"restored {len(cookies)} cookies (saved {index['saved_at']})")
    for d in sorted(set(index.get("surfaces", {})) | set(WATCH)):
        if d not in present:
            print(f"  {d}: MISSING (cookie not accepted)")
            continue
        bits = ["cookie ok" if auth.get(d) else "auth cookie absent"]
        if d in live:
            bits.append("SIGNED IN" if live[d] else "**SESSION REJECTED — sign in again**")
        print(f"  {d}: {', '.join(bits)}")
    if live and not any(live.values()):
        print("\n[!] cookies restored but no surface accepted them; the saved session is dead.")
    # Storage is restored after the cookies so the device-trust token is in place
    # before any surface is loaded for real.
    restore_storage()
    return 0


def heartbeat() -> int:
    """Load each surface in the open browser so its session stays warm.

    Server-side inactivity timeouts are a cause of re-authentication that a
    cookie snapshot cannot fix (all three advisors said this). A low-frequency
    authenticated page load resets that timer. Kept to the surfaces that have a
    PROBE and a minimum gap between runs, so it does not look like scraping.
    """
    pw, br, ctx = _context()
    try:
        for d in WATCH:
            if d not in PROBE:
                continue
            ok = _signed_in(ctx, d)
            print(f"  {d}: {'alive' if ok else 'EXPIRED'}")
    finally:
        pw.stop()
    return 0


def status() -> int:
    index = ax_vault.kv_get(ax_vault.ensure_anchor(), INDEX_KEY)
    if not index:
        print("no saved session (login_vault.py save has never run)")
    else:
        print(f"saved {index['n_cookies']} cookies at {index['saved_at']}")
        print(f"  account : {index.get('account') or '(unknown)'}")
        print(f"  surfaces: {index.get('surfaces')}")
    blob = ax_vault.kv_get(ax_vault.ensure_anchor(), BOOKMARKS_KEY)
    if blob:
        print(f"saved {len(blob.get('entries', []))} bookmark(s) at {blob.get('saved_at')}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["save", "restore", "status", "heartbeat",
                                        "save-bookmarks", "restore-bookmarks"])
    a = ap.parse_args()
    return {"save": save, "restore": restore, "status": status,
            "heartbeat": heartbeat,
            "save-bookmarks": save_bookmarks,
            "restore-bookmarks": restore_bookmarks}[a.command]()


if __name__ == "__main__":
    sys.exit(main())
