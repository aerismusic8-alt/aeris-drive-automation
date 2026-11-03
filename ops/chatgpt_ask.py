#!/usr/bin/env python3
"""Ask the signed-in ChatGPT web app a question and return its answer.

Why this exists: K wants ChatGPT used for planning (revenue and follower ideas),
but the ChatGPT API costs money and Rule #1 is free-only. The cloud desktop is
already signed in to `chatgpt.com`, so the free web app is the way to reach it —
the same route the `ax-cloud-desktop` skill uses for Flow Music and Gemini web.

The agent never types a password: the desktop is signed in by the operator once,
and this script only drives the already-open tab over CDP.

    python3 ops/chatgpt_ask.py "prompt text"        # print the answer
    python3 ops/chatgpt_ask.py --file prompt.md     # read the prompt from a file
    python3 ops/chatgpt_ask.py --new "prompt"       # start a fresh chat first

A prompt with newlines is fine. The answer is printed to stdout; diagnostics go
to stderr, so `--json`-free output can be piped into a file.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request

CDP = "http://127.0.0.1:9222/json"
CHATGPT = "chatgpt.com"


class Cdp:
    """A tiny CDP client on the already-open ChatGPT tab."""

    def __init__(self) -> None:
        import websocket  # noqa: PLC0415

        tabs = json.load(urllib.request.urlopen(CDP, timeout=10))
        page = next((t for t in tabs
                     if t.get("type") == "page" and CHATGPT in t.get("url", "")), None)
        if page is None:
            raise RuntimeError(
                "no chatgpt.com tab on the desktop — open one (bootstrap.py, "
                "then navigate to https://chatgpt.com/) and sign in")
        self.ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=60)
        self.n = 0

    def js(self, expr: str, await_: bool = False):
        self.n += 1
        mid = self.n
        self.ws.send(json.dumps({"id": mid, "method": "Runtime.evaluate",
                                 "params": {"expression": expr, "returnByValue": True,
                                            "awaitPromise": await_}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == mid:
                return msg.get("result", {}).get("result", {}).get("value")

    def close(self) -> None:
        self.ws.close()


# The composer is a contenteditable div; `insertText` is what the app listens
# for (setting .innerText leaves React's state empty and Send stays disabled).
# There is also a hidden zero-size contenteditable in the DOM, so pick the one
# that actually has a size.
_COMPOSER = """(() => {
  const all = [...document.querySelectorAll('[contenteditable="true"]')];
  return all.find(e => { const r = e.getBoundingClientRect(); return r.width > 50 && r.height > 0; })
      || all[all.length - 1] || null;
})()"""

_SET_TEXT = """(() => {
  const c = %s;
  if (!c) return 'no-composer';
  c.focus();
  const sel = window.getSelection(); sel.removeAllRanges();
  const r = document.createRange(); r.selectNodeContents(c); sel.addRange(r);
  document.execCommand('delete', false, null);
  document.execCommand('insertText', false, %%s);
  return c.innerText.length;
})()""" % _COMPOSER

_LAST_ANSWER = """(() => {
  const nodes = [...document.querySelectorAll('[class*="MarkdownRoot"], [data-message-author-role="assistant"]')];
  if (!nodes.length) return '';
  return nodes[nodes.length - 1].innerText || '';
})()"""

_BUSY = """(() => !!document.querySelector('button[data-testid="stop-button"], button[aria-label="Stop"]'))()"""

_HAS_COMPOSER = """(() => {
  const all = [...document.querySelectorAll('[contenteditable="true"]')];
  return all.some(e => { const r = e.getBoundingClientRect(); return r.width > 50 && r.height > 0; });
})()"""


def _wait_composer(d, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if d.js(_HAS_COMPOSER):
            return
        time.sleep(0.5)
    raise RuntimeError("ChatGPT composer never appeared")


def ask(prompt: str, *, new_chat: bool = False, timeout: float = 180.0) -> str:
    d = Cdp()
    try:
        if new_chat:
            d.js("""(() => { const b = document.querySelector('a[data-testid="create-new-chat-button"]')
                     || document.querySelector('button[aria-label="New chat"]'); if (b) b.click(); return true; })()""")
            time.sleep(2.0)
        _wait_composer(d)
        before = d.js(_LAST_ANSWER) or ""
        typed = d.js(_SET_TEXT % json.dumps(prompt))
        if typed in ("no-composer", 0, None):
            raise RuntimeError("could not type into the ChatGPT composer")
        time.sleep(0.6)
        clicked = d.js("""(() => { const b = document.querySelector('button[aria-label="Send"]');
                            if (!b) return false; b.click(); return true; })()""")
        if not clicked:
            # Fall back to Enter, which the composer also submits.
            d.js("""(() => { const c = document.querySelector('[contenteditable="true"]');
                     c.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true}));
                     return true; })()""")
        # Wait for the answer to appear and stop streaming.
        deadline = time.time() + timeout
        answer = ""
        while time.time() < deadline:
            time.sleep(2.0)
            cur = d.js(_LAST_ANSWER) or ""
            busy = d.js(_BUSY)
            if cur and cur != before and not busy:
                answer = cur
                break
            if cur and cur != before:
                answer = cur  # keep the latest; loop exits on `not busy`
        if not answer:
            raise RuntimeError("no answer within timeout (rate limit, or not signed in?)")
        return answer
    finally:
        d.close()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("prompt", nargs="?", help="the question to ask")
    ap.add_argument("--file", help="read the prompt from this file instead")
    ap.add_argument("--new", action="store_true", help="start a fresh chat first")
    ap.add_argument("--timeout", type=float, default=180.0)
    args = ap.parse_args()

    prompt = args.prompt
    if args.file:
        prompt = open(args.file, encoding="utf-8").read()
    if not prompt:
        ap.error("give a prompt or --file")

    try:
        print(ask(prompt, new_chat=args.new, timeout=args.timeout))
    except Exception as exc:  # noqa: BLE001
        print(f"chatgpt_ask failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
