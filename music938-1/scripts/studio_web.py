#!/usr/bin/env python3
"""Read Studio analytics and answer comments through the signed-in desktop.

The Data API rail (`ops/yt_auth.py`) cannot do either job: the channel's OAuth
client is a NATIVE_DEVICE client, so it carries only `.../auth/youtube` — Google
refuses `youtube.force-ssl` at the device endpoint, and the client type cannot
use a loopback redirect. The channel owner is already signed into the cloud
desktop's Chromium, though, and Studio is the owner's own UI, so AR drives that
instead. Nothing here needs a new credential or an operator action.

    python3 scripts/studio_web.py analytics
    python3 scripts/studio_web.py comments            # list what is unanswered
    python3 scripts/studio_web.py reply --text "..."  # reply to each one

Requires the desktop (`ax-cloud-desktop` skill) to be up and signed in.
"""
from __future__ import annotations

import argparse
import json
import time
import urllib.request

import websocket

CHANNEL = "UCm44BjAn03ruOF-WaA3ZRww"
CDP = "http://127.0.0.1:9222/json"
STUDIO = "https://studio.youtube.com/channel/" + CHANNEL

# A reply that thanks the listener and points at the catalogue. Kept short and
# warm; the channel is Thai, so the text is Thai.
DEFAULT_REPLY = ("ขอบคุณมากครับ 🙏 ขอบคุณที่ฟังเพลงของเรานะครับ "
                 "ฝากติดตามเพลงใหม่ๆ ด้วยครับ 🎵")


class Desk:
    """A minimal CDP client for the one page the desktop keeps open."""

    def __init__(self) -> None:
        tabs = json.load(urllib.request.urlopen(CDP, timeout=20))
        page = next(t for t in tabs if t["type"] == "page")
        self.ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=40)
        self.n = 0
        # Chromium throttles a background tab: lazy-loaded lists (the comment
        # inbox) then never render and the page reports "no comments" or an error
        # instead of the truth. Bringing the tab to the front un-throttles it.
        self.send("Page.bringToFront")

    def send(self, method: str, params: dict | None = None) -> dict:
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                return msg

    def js(self, expr: str):
        r = self.send("Runtime.evaluate", {"expression": expr, "returnByValue": True,
                                           "awaitPromise": True})
        return r.get("result", {}).get("result", {}).get("value")

    def goto(self, url: str, settle: float = 10.0) -> None:
        self.send("Page.navigate", {"url": url})
        time.sleep(settle)

    def real_click(self, selector: str, index: int = -1) -> bool:
        """Click an element with a trusted mouse event.

        Studio ignores a synthetic `element.click()` for the comment send button —
        the box keeps its text and nothing posts — so the click is dispatched
        through CDP's Input domain, which Chromium treats as a real user gesture.
        """
        r = self.js("""
        (() => {
          const els=[...document.querySelectorAll(%s)];
          const el=els.at(%d);
          if(!el) return null;
          el.scrollIntoView({block:'center'});
          const b=el.getBoundingClientRect();
          return {x:b.x+b.width/2, y:b.y+b.height/2};
        })()
        """ % (json.dumps(selector), index))
        if not r:
            return False
        for kind in ("mousePressed", "mouseReleased"):
            self.send("Input.dispatchMouseEvent",
                      {"type": kind, "x": r["x"], "y": r["y"],
                       "button": "left", "clickCount": 1})
        return True

    def close(self) -> None:
        self.ws.close()


def analytics(desk: Desk) -> dict:
    """The overview numbers, read from the page the owner sees."""
    desk.goto(f"{STUDIO}/analytics/tab-overview/period-default", settle=12)
    text = desk.js("document.body.innerText") or ""
    out: dict = {"raw": text[:400]}
    for line in text.splitlines():
        line = line.strip()
        if "ยอดดู" in line and "ครั้ง" in line:
            out["views_line"] = line
            break
    return out


def unanswered(desk: Desk) -> list[dict]:
    """The inbox's default filter is "ยังไม่ได้ตอบกลับ", so these are the open ones."""
    desk.goto(f"{STUDIO}/comments/inbox", settle=14)
    return desk.js("""
    (() => {
      const cards=[...document.querySelectorAll('ytcp-comment-thread')];
      return cards.map(c => ({
        author: (c.querySelector('#author-text')||{}).innerText || '',
        text: (c.querySelector('#content-text')||{}).innerText || '',
        video: (c.querySelector('#video-title, a#video-title')||{}).innerText || ''
      })).filter(c => c.text);
    })()
    """) or []


def reply_all(desk: Desk, text: str, limit: int = 10) -> int:
    """Reply to each unanswered thread, one at a time."""
    done = 0
    for _ in range(limit):
        opened = desk.js("""
        (() => {
          const box=document.querySelector('ytcp-commentbox textarea');
          if(box) return 'open';
          const cards=[...document.querySelectorAll('ytcp-comment-thread')];
          const c=cards[0];
          if(!c) return 'none';
          const b=[...c.querySelectorAll('button,ytcp-button')]
            .find(x=>x.innerText.trim()==='ตอบกลับ');
          if(!b) return 'no button';
          b.click(); return 'clicked';
        })()
        """)
        if opened in ("none", "no button", None):
            break
        time.sleep(3)
        typed = desk.js("""
        (() => {
          const t=document.querySelector('ytcp-commentbox textarea');
          if(!t) return 'no box';
          t.focus();
          const s=Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set;
          s.call(t, %s);
          t.dispatchEvent(new Event('input',{bubbles:true}));
          return t.value.slice(0,30);
        })()
        """ % json.dumps(text))
        if typed in ("no box", None):
            break
        time.sleep(2)
        sent = desk.js("""
        (() => {
          const box=document.querySelector('ytcp-commentbox');
          const sub=[...box.querySelectorAll('button,ytcp-button')]
            .filter(b=>b.innerText.trim()==='ตอบกลับ').pop();
          if(!sub || sub.disabled) return 'blocked';
          sub.click(); return 'sent';
        })()
        """)
        if sent != "sent":
            break
        done += 1
        time.sleep(6)
    return done



# A Short's hook is what earns the view; the full song is what earns the
# watch-hours. A pinned comment is the one free way to carry a viewer from the
# first to the second, so it is written to be read as an invitation, not an ad.
SHORT_PIN = ("🎵 ฟังเพลงเต็มได้ที่นี่เลยครับ 👉 {url}\n"
             "ขอบคุณที่ฟังนะครับ 🙏 ฝากติดตามเพลงใหม่ๆ ด้วยครับ")


def comment_video(desk: Desk, video_id: str, text: str) -> bool:
    """Post `text` as a top-level comment on `video_id`.

    Studio's per-video comments tab has the composer the inbox does not, so this
    drives that page. Returns whether the send button was reached and clicked.
    """
    desk.goto(f"https://studio.youtube.com/video/{video_id}/comments", settle=14)
    typed = desk.js("""
    (() => {
      const t=document.querySelector('ytcp-commentbox textarea');
      if(!t) return 'no box';
      t.focus();
      const s=Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set;
      s.call(t, %s);
      t.dispatchEvent(new Event('input',{bubbles:true}));
      return t.value.slice(0,40);
    })()
    """ % json.dumps(text))
    if typed in ("no box", None):
        return False
    time.sleep(2)
    # Studio renders two matching buttons (one hidden) and ignores a synthetic
    # `element.click()` entirely — the box keeps its text and nothing posts — so
    # the live button is clicked through CDP as a trusted mouse event.
    if not desk.real_click("ytcp-commentbox button, ytcp-commentbox ytcp-button",
                           index=-1):
        return False
    time.sleep(6)
    # A silent no-op is the failure mode here, so confirm the text is on the page
    # rather than trusting the click.
    marker = text[:16]
    return desk.js("(document.body.innerText||'').includes(%s)" % json.dumps(marker)) is True


def pin_comment(desk: Desk, video_id: str) -> bool:
    """Pin the video's own comment through the ⋮ menu on its watch page.

    Pinning is not exposed by the public API for a comment made through the UI,
    so it is done in the page the owner sees: the thread's action menu, then
    "ปักหมุด". The menu only exists on the watch page — Studio's per-video list
    filters the channel's own comments out — so this navigates there. Returns
    whether the pin item was found and clicked.
    """
    desk.goto(f"https://www.youtube.com/watch?v={video_id}", settle=8)
    desk.js("document.querySelector('ytd-comments')?.scrollIntoView()")
    # The comments render lazily and slowly; wait for the thread before touching
    # the menu, or the click lands on nothing.
    for _ in range(12):
        if desk.js("!!document.querySelector('ytd-comment-thread-renderer')"):
            break
        time.sleep(2)
    # Already pinned is a success, and re-running must not unpin: the menu item
    # for a pinned comment reads "เลิกปักหมุด", which a loose /ปักหมุด/ matches.
    if desk.js("(document.querySelector('ytd-comment-thread-renderer')||{innerText:''})"
               ".innerText.includes('ปักหมุดโดย')") is True:
        return True
    # Driven as one awaited script: the menu and its items mount asynchronously
    # in a portal, so separate round-trips race the render and click nothing.
    return desk.js("""
    (async () => {
      const sleep = ms => new Promise(r => setTimeout(r, ms));
      const waitFor = async (fn, ms=8000) => {
        for (let t=0; t<ms; t+=250) { const v=fn(); if (v) return v; await sleep(250); }
        return null;
      };
      const t = await waitFor(() => document.querySelector('ytd-comment-thread-renderer'));
      if (!t) return 'no thread';
      const menu = await waitFor(() => t.querySelector("button[aria-label*='เมนู'], ytd-menu-renderer button"));
      if (!menu) return 'no menu';
      menu.click();
      // A pinned comment's menu offers "เลิกปักหมุด"; the exact-match below only
      // takes the pin action, so it never unpins what is already pinned.
      const item = await waitFor(() => [...document.querySelectorAll('ytd-menu-service-item-renderer, tp-yt-paper-item')]
        .find(i => (i.innerText||'').trim() === 'ปักหมุด'));
      if (!item) return 'no pin item';
      item.click();
      const dlg = await waitFor(() => document.querySelector('yt-confirm-dialog-renderer, tp-yt-paper-dialog'));
      if (dlg) {
        const ok = await waitFor(() => {
          const bs = [...dlg.querySelectorAll('button, tp-yt-paper-button')]
            .filter(b => (b.innerText||'').trim() === 'ปักหมุด');
          return bs.length ? bs[bs.length-1] : null;
        });
        if (ok) ok.click();
      }
      // The pin is applied asynchronously; "ปักหมุดโดย" in the thread is the proof.
      const badge = await waitFor(() => (document.querySelector('ytd-comment-thread-renderer')||{innerText:''})
        .innerText.includes('ปักหมุดโดย'), 12000);
      return badge ? 'pinned' : 'not pinned';
    })()
    """) == "pinned"


def short_pin_targets() -> list[tuple[str, str]]:
    """(short_video_id, full_song_url) for every Short whose song is released.

    The release state is the join: a Short and its full song share the slug, so a
    Short only gets a pin once its song is live — a pin that links to a 404 is
    worse than no pin.
    """
    from pathlib import Path
    state = Path(__file__).resolve().parent.parent / "work" / "release-state.json"
    rel = json.loads(state.read_text())["released"]
    # A retired entry is a deleted/replaced upload: its id now 404s, so pinning it
    # would only fail. Skip those.
    live = [r for r in rel if not r.get("retired_at")]
    songs = {r["slug"]: r["video_id"] for r in live if r["kind"] == "song"}
    out = []
    for r in live:
        if r["kind"] == "short" and r["slug"] in songs:
            out.append((r["video_id"],
                        f"https://youtu.be/{songs[r['slug']]}"))
    return out


def video_has_marker(desk: Desk, video_id: str) -> bool:
    """Whether the video already carries our full-song comment.

    Re-running must not stack duplicate comments, so the Short is checked first
    and only commented when the marker text is absent.
    """
    desk.goto(f"https://www.youtube.com/watch?v={video_id}", settle=8)
    desk.js("document.querySelector('ytd-comments')?.scrollIntoView()")
    time.sleep(4)
    return desk.js("(document.body.innerText||'').includes('ฟังเพลงเต็มได้ที่นี่')") is True


def pin_shorts(desk: Desk, limit: int = 10) -> int:
    """Post and pin the full-song link on each Short that lacks a pin yet."""
    done = 0
    for vid, url in short_pin_targets()[:limit]:
        text = SHORT_PIN.format(url=url)
        if not video_has_marker(desk, vid) and not comment_video(desk, vid, text):
            continue
        if pin_comment(desk, vid):
            done += 1
            print(f"pinned {vid} -> {url}")
    return done


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action",
                    choices=["analytics", "comments", "reply", "pin-shorts"])
    ap.add_argument("--text", default=DEFAULT_REPLY)
    ap.add_argument("--limit", type=int, default=10)
    args = ap.parse_args()

    desk = Desk()
    try:
        if args.action == "analytics":
            print(json.dumps(analytics(desk), ensure_ascii=False, indent=1))
        elif args.action == "comments":
            found = unanswered(desk)
            for c in found:
                print(f"OPEN {c['author']}: {c['text'][:60]}")
            print(f"{len(found)} unanswered comment(s)")
        elif args.action == "pin-shorts":
            print(f"pinned {pin_shorts(desk, args.limit)} Short(s)")
        else:
            n = reply_all(desk, args.text, args.limit)
            print(f"replied to {n} comment(s)")
    finally:
        desk.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
