#!/usr/bin/env python3
"""Live view and control of the cloud desktop browser over CDP.

Why this exists next to noVNC. noVNC ships the whole 1600x900 X screen, so on a
phone the address bar is a few pixels tall and the desktop is letterboxed. This
module instead talks to the browser the agent already drives, and does two
things noVNC cannot:

  * `Page.startScreencast` pushes a frame only when the page repaints, so an idle
    tab costs nothing and an active one streams without a per-frame round trip.
    That is the difference between a live view and a screenshot poller.
  * Input goes straight in as `Input.dispatch*` CDP events, addressed to the
    page, so a tap lands on a DOM element the same way Playwright's would.

It is the free option (Rule #1): the browser is already running, and the only
dependencies are `websocket-client` and the stdlib.

    python3 ops/live_view.py --probe            # is a frame coming?
    python3 ops/live_view.py --click 800 400    # tap the watched page
"""
from __future__ import annotations

import base64
import json
import threading
import time
import urllib.request

import websocket

CDP = "http://127.0.0.1:9222"


class LiveView:
    """One CDP connection to one page target.

    The transport is synchronous request/response under a single lock. A
    background reader thread was tried first and removed: two threads calling
    `recv()` on one websocket (the reader plus a request waiter) corrupted the
    stream, and the screencast push it existed for does not work on this
    Chromium build anyway (see `watch`). Every call here sends one message and
    reads until its own id comes back, acknowledging any screencast frames it
    passes on the way.
    """

    def __init__(self, cdp: str = CDP):
        self.cdp = cdp.rstrip("/")
        self._ws = None
        self._lock = threading.RLock()
        self._frame = b""
        self._frame_ts = 0.0
        self._frames = 0
        self._id = 0
        self._target = None
        self._metrics = {"w": 0, "h": 0}
        self._err = ""

    # --- CDP plumbing ------------------------------------------------------

    def _http(self, path: str):
        return json.load(urllib.request.urlopen(self.cdp + path, timeout=5))

    def pages(self) -> list:
        try:
            return [t for t in self._http("/json/list") if t.get("type") == "page"]
        except Exception:
            return []

    def _on_event(self, msg: dict) -> None:
        if msg.get("method") == "Page.screencastFrame":
            p = msg.get("params", {})
            try:
                self._frame = base64.b64decode(p.get("data", ""))
                self._frame_ts = time.time()
                self._frames += 1
            except Exception:
                pass
            self._send_nowait("Page.screencastFrameAck",
                              {"sessionId": p.get("sessionId")})

    def _call(self, method: str, params: dict | None = None, timeout: float = 8.0):
        """Send one CDP command and return its result message."""
        with self._lock:
            if not self._ws:
                return None
            self._id += 1
            mid = self._id
            try:
                self._ws.send(json.dumps({"id": mid, "method": method,
                                          "params": params or {}}))
            except Exception as e:
                self._err = f"send: {type(e).__name__}: {e}"
                return None
            deadline = time.time() + timeout
            while time.time() < deadline:
                try:
                    msg = json.loads(self._ws.recv())
                except websocket.WebSocketTimeoutException:
                    break
                except Exception as e:
                    self._err = f"recv: {type(e).__name__}: {e}"
                    break
                if msg.get("id") == mid:
                    return msg
                self._on_event(msg)
            return None

    def _send_nowait(self, method: str, params: dict | None = None) -> None:
        with self._lock:
            if not self._ws:
                return
            self._id += 1
            try:
                self._ws.send(json.dumps({"id": self._id, "method": method,
                                          "params": params or {}}))
            except Exception as e:
                self._err = f"send: {type(e).__name__}: {e}"

    # --- lifecycle ---------------------------------------------------------

    def stop(self) -> None:
        with self._lock:
            ws, self._ws = self._ws, None
        try:
            if ws:
                ws.close()
        except Exception:
            pass

    def watch(self, target_id: str | None = None, screencast: bool = False) -> bool:
        """Attach to a page target. Idempotent.

        `Page.startScreencast` is not used by default: on this sandbox's
        Chromium build the compositor never pushes frames, so it yields one
        frame and stalls. `capture()` takes a fresh `Page.captureScreenshot`
        instead, measured at ~85 ms / ~12 fps against the live Facebook page.
        """
        self.stop()
        pages = self.pages()
        if not pages:
            self._err = "no page targets"
            return False
        if target_id:
            t = next((p for p in pages if p.get("id") == target_id), None)
            if t is None:
                self._err = "target not found"
                return False
        else:
            # Prefer the last tab the agent opened, which is usually the work.
            t = pages[-1]
        self._target = t
        self._err = ""
        try:
            self._ws = websocket.create_connection(
                t["webSocketDebuggerUrl"], timeout=8, suppress_origin=True)
        except Exception as e:
            self._err = f"connect: {type(e).__name__}: {e}"
            return False
        self._call("Page.enable")
        if screencast:
            self._call("Page.startScreencast",
                       {"format": "jpeg", "quality": 55, "maxWidth": 720,
                        "maxHeight": 1280, "everyNthFrame": 1})
        self._refresh_metrics()
        return True

    def _refresh_metrics(self) -> None:
        r = self._call("Page.getLayoutMetrics")
        try:
            vv = (r or {}).get("result", {}).get("cssVisualViewport", {})
            self._metrics["w"] = int(vv.get("clientWidth") or 0)
            self._metrics["h"] = int(vv.get("clientHeight") or 0)
        except Exception:
            pass

    # --- read side ---------------------------------------------------------

    def capture(self, quality: int = 60) -> bytes:
        """A fresh JPEG of the watched page: what the operator should see now.

        This is the path that actually works here; it was measured at ~85 ms and
        ~12 fps against the live Facebook page.
        """
        r = self._call("Page.captureScreenshot",
                       {"format": "jpeg", "quality": quality}, timeout=8)
        try:
            return base64.b64decode(r["result"]["data"])
        except Exception:
            return b""

    def frame(self) -> bytes:
        """The last screencast frame if one was pushed, else a fresh capture."""
        return self._frame or self.capture()

    def status(self) -> dict:
        return {"target": (self._target or {}).get("url", ""),
                "frames": self._frames, "age": round(time.time() - self._frame_ts, 1)
                if self._frame_ts else None, "err": self._err,
                "metrics": self._metrics}

    # --- write side --------------------------------------------------------

    def _scale(self, x: float, y: float):
        """Map a tap in the streamed frame back to page CSS pixels."""
        fw, fh = self._frame_size()
        w = self._metrics["w"] or fw
        h = self._metrics["h"] or fh
        if not fw or not fh:
            return x, y
        return x * w / fw, y * h / fh

    def _frame_size(self):
        import io
        if not self._frame:
            return 0, 0
        try:
            from PIL import Image
            with Image.open(io.BytesIO(self._frame)) as im:
                return im.size
        except Exception:
            return 0, 0

    def click(self, x: float, y: float, button: str = "left") -> None:
        px, py = self._scale(x, y)
        for typ in ("mousePressed", "mouseReleased"):
            self._send_nowait("Input.dispatchMouseEvent",
                              {"type": typ, "x": px, "y": py, "button": button,
                               "clickCount": 1})

    # --- normalized input (0..1 of the visible page), for the web view ------

    def _page_size(self):
        return self._metrics["w"] or 1477, self._metrics["h"] or 679

    def click_norm(self, u: float, v: float, button: str = "left") -> None:
        w, h = self._page_size()
        self.click(u * w, v * h, button)

    def move_norm(self, u: float, v: float) -> None:
        w, h = self._page_size()
        self.move(u * w, v * h)

    def scroll_norm(self, u: float, v: float, dy: float) -> None:
        w, h = self._page_size()
        self.scroll(u * w, v * h, dy)

    def bring_to_front(self) -> None:
        self._call("Page.bringToFront")

    def open_url(self, url: str) -> str | None:
        """Focus the tab already showing `url`, else open a new one; return its id.

        Reusing the tab is what keeps a signed-in surface signed in: a new tab
        reloads the page, an activate does not. The match is by host, because a
        surface that has bounced through a login redirect (studio.youtube.com ->
        accounts.google.com) no longer has the surface's own URL — matching the
        full URL there opened a second tab on every tap.
        """
        host = urllib.parse.urlsplit(url).netloc
        for p in self.pages():
            pu = p.get("url", "")
            if pu.split("?")[0].rstrip("/") == url.split("?")[0].rstrip("/"):
                return self._activate(p["id"])
            if host and (urllib.parse.urlsplit(pu).netloc == host
                         or host in urllib.parse.unquote(pu)):
                return self._activate(p["id"])
        try:
            req = urllib.request.Request(
                f"{self.cdp}/json/new?{urllib.parse.quote(url, safe='')}", method="PUT")
            t = json.load(urllib.request.urlopen(req, timeout=8))
            return t.get("id")
        except Exception as e:
            self._err = f"open: {type(e).__name__}: {e}"
            return None

    def _activate(self, tid: str) -> str | None:
        try:
            urllib.request.urlopen(f"{self.cdp}/json/activate/{tid}", timeout=6).read()
            return tid
        except Exception as e:
            self._err = f"activate: {type(e).__name__}: {e}"
            return None

    def close(self, tid: str) -> bool:
        try:
            urllib.request.urlopen(f"{self.cdp}/json/close/{tid}", timeout=6).read()
            return True
        except Exception as e:
            self._err = f"close: {type(e).__name__}: {e}"
            return False

    def move(self, x: float, y: float) -> None:
        px, py = self._scale(x, y)
        self._send_nowait("Input.dispatchMouseEvent",
                          {"type": "mouseMoved", "x": px, "y": py})

    def scroll(self, x: float, y: float, dy: float) -> None:
        px, py = self._scale(x, y)
        self._send_nowait("Input.dispatchMouseEvent",
                          {"type": "mouseWheel", "x": px, "y": py,
                           "deltaX": 0, "deltaY": dy})

    def text(self, s: str) -> None:
        self._send_nowait("Input.insertText", {"text": s})

    def key(self, name: str) -> None:
        self._send_nowait("Input.dispatchKeyEvent",
                          {"type": "keyDown", "key": name,
                           "windowsVirtualKeyCode": _VK.get(name, 0)})
        self._send_nowait("Input.dispatchKeyEvent",
                          {"type": "keyUp", "key": name,
                           "windowsVirtualKeyCode": _VK.get(name, 0)})

    def goto(self, url: str) -> None:
        self._call("Page.navigate", {"url": url})

    def reload(self) -> None:
        self._call("Page.reload")


_VK = {"Enter": 13, "Backspace": 8, "Tab": 9, "Escape": 27, "ArrowDown": 40,
       "ArrowUp": 38, "ArrowLeft": 37, "ArrowRight": 39, " ": 32}


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--click", nargs=2, type=float)
    ap.add_argument("--url")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    lv = LiveView()
    if a.list:
        for p in lv.pages():
            print(p.get("id"), "|", p.get("title", "")[:40], "|", p.get("url", "")[:70])
        return 0
    if not lv.watch():
        print("watch failed:", lv._err)
        return 1
    if a.url:
        lv.goto(a.url)
        time.sleep(3)
    if a.click:
        lv.click(*a.click)
        time.sleep(2)
    deadline = time.time() + 12
    while time.time() < deadline and not lv.frame():
        time.sleep(0.5)
    f = lv.frame()
    print("status:", json.dumps(lv.status(), ensure_ascii=False))
    print("frame bytes:", len(f))
    if a.probe and not f:
        return 1
    lv.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
