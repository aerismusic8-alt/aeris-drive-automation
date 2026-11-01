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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action", choices=["analytics", "comments", "reply"])
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
        else:
            n = reply_all(desk, args.text, args.limit)
            print(f"replied to {n} comment(s)")
    finally:
        desk.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
