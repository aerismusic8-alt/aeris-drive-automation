#!/usr/bin/env python3
"""Mint a Shopee affiliate Custom Link for a target page, tagged by surface.

Why this exists. The per-surface links in `channel/monetization.json` pointed at
Shopee's homepage, and a viewer who taps a link from a music video lands on a
generic storefront with nothing to buy — the reported clicks were 0. Shopee's own
Custom Link tool can point at any page it converts on (product, search, campaign,
category), which is what actually makes a click possible.

This drives the signed-in affiliate dashboard on the cloud desktop (the same
login the read path uses) to mint one link per surface. It is free and needs no
API key.

    python3 ops/shopee_mint.py --target "https://shopee.co.th/search?keyword=หูฟัง"
    python3 ops/shopee_mint.py --target <url> --surfaces youtube tiktok facebook

The minted links are printed; pass `--write` to update `channel/monetization.json`
under `shopee_links`. A target must be a shopee.co.th page (the tool rejects
anything else).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request

CDP = "http://127.0.0.1:9222"
AFF = "affiliate.shopee.co.th"
CUSTOM_LINK = "https://affiliate.shopee.co.th/offer/custom_link"


class Tab:
    def __init__(self) -> None:
        import websocket  # noqa: PLC0415

        ver = json.load(urllib.request.urlopen(f"{CDP}/json/version", timeout=10))
        self.ws = websocket.create_connection(ver["webSocketDebuggerUrl"], timeout=60)
        tabs = json.load(urllib.request.urlopen(f"{CDP}/json", timeout=10))
        page = next((t for t in tabs
                     if t.get("type") == "page" and AFF in t.get("url", "")), None)
        if page is None:
            raise RuntimeError("no affiliate.shopee.co.th tab — open the dashboard first")
        self.n = 0
        self.sess = self._cmd("Target.attachToTarget",
                              {"targetId": page["id"], "flatten": True})["sessionId"]

    def _cmd(self, method: str, params: dict) -> dict:
        self.n += 1
        mid = self.n
        msg: dict = {"id": mid, "method": method, "params": params}
        if getattr(self, "sess", None):
            msg["sessionId"] = self.sess
        self.ws.send(json.dumps(msg))
        while True:
            reply = json.loads(self.ws.recv())
            if reply.get("id") == mid:
                return reply.get("result", {})

    def js(self, expr: str):
        r = self._cmd("Runtime.evaluate",
                      {"expression": expr, "returnByValue": True})
        return r.get("result", {}).get("value")

    def close(self) -> None:
        self.ws.close()


_SET_FIELD = """(() => {
  const el = document.querySelector(%s);
  if (!el) return false;
  const proto = el.tagName === 'TEXTAREA'
      ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, %s);
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.dispatchEvent(new Event('change', {bubbles: true}));
  return true;
})()"""


def mint(target: str, sub_id: str, *, tab: Tab) -> str:
    tab.js(f"location.href={json.dumps(CUSTOM_LINK)}")
    time.sleep(9)
    if not tab.js(_SET_FIELD % (json.dumps("textarea"), json.dumps(target))):
        raise RuntimeError("custom-link textarea not found")
    tab.js(_SET_FIELD % (json.dumps("#customLink_sub_id1"), json.dumps(sub_id)))
    time.sleep(0.6)
    if not tab.js("""(() => { const b = [...document.querySelectorAll('button')]
                       .find(x => /Get Link/i.test(x.innerText || ''));
                       if (!b) return false; b.click(); return true; })()"""):
        raise RuntimeError("Get Link button not found")
    time.sleep(6)
    link = tab.js("""(() => { const d = document.querySelector('[role=dialog],.modal,[class*=dialog]');
                        if (!d) return ''; const ta = d.querySelector('textarea');
                        return ta ? ta.value.trim() : ''; })()""")
    if not link or not link.startswith("http"):
        raise RuntimeError(f"no link in the dialog (got {link!r})")
    return link


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", required=True, help="the shopee.co.th page to link to")
    ap.add_argument("--surfaces", nargs="+", default=["youtube", "tiktok", "facebook"])
    ap.add_argument("--write", action="store_true",
                    help="update channel/monetization.json under shopee_links")
    ap.add_argument("--config", default="music938-1/channel/monetization.json")
    args = ap.parse_args()

    if "shopee.co.th" not in args.target:
        ap.error("--target must be a shopee.co.th page")

    tab = Tab()
    links: dict[str, str] = {}
    try:
        for s in args.surfaces:
            links[s] = mint(args.target, s, tab=tab)
            print(f"{s}: {links[s]}")
    finally:
        tab.close()

    if args.write:
        cfg = json.loads(open(args.config, encoding="utf-8").read())
        cfg.setdefault("shopee_links", {}).update(links)
        cfg["_shopee_links_target"] = args.target
        open(args.config, "w", encoding="utf-8").write(
            json.dumps(cfg, ensure_ascii=False, indent=2) + "\n")
        print(f"wrote {args.config}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
