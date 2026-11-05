#!/usr/bin/env python3
"""Ask Duck.ai (DuckDuckGo's AI chat) a question and return its answer.

Why this exists: `ops/chatgpt_ask.py` and `ops/gemini_ask.py` both depend on a
signed-in Google/ChatGPT session on the cloud desktop, and that login is the
recurring thing K has to redo after every pod recycle. Duck.ai needs **no
login at all** — it is free, anonymous, and reachable over the same CDP
connection — so it keeps working when the other two are signed out.

    python3 ops/duck_ask.py "prompt text"
    python3 ops/duck_ask.py --file prompt.md

The agent never types a password; there is nothing to sign in to.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request

CDP = "http://127.0.0.1:9222/json"
HOST = "duck.ai"


class Cdp:
    """A tiny CDP client on the open Duck.ai tab."""

    def __init__(self) -> None:
        import websocket  # noqa: PLC0415

        tabs = json.load(urllib.request.urlopen(CDP, timeout=10))
        page = next((t for t in tabs
                     if t.get("type") == "page" and HOST in t.get("url", "")), None)
        if page is None:
            raise RuntimeError(
                "no duck.ai tab on the desktop — open one with "
                "curl -X PUT 'http://127.0.0.1:9222/json/new?https://duck.ai/'")
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


# The composer is a <textarea>. The native value setter is used, then an `input`
# event, because Duck.ai (React) ignores a plain `.value =` assignment and the
# Ask button stays disabled.
_SET_TEXT = """(() => {
  const t = [...document.querySelectorAll('textarea')]
    .find(e => { const r = e.getBoundingClientRect(); return r.width > 80 && r.height > 0; });
  if (!t) return 'no-composer';
  t.focus();
  const s = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
  s.call(t, %s);
  t.dispatchEvent(new Event('input', { bubbles: true }));
  return t.value.length;
})()"""

_HAS_COMPOSER = """(() => [...document.querySelectorAll('textarea')]
  .some(e => { const r = e.getBoundingClientRect(); return r.width > 80 && r.height > 0; }))()"""

# Duck.ai renders each turn as "You said / <prompt> / Duck.ai said / <model> /
# <answer>", and the conversation column ends with a block of chrome
# ("Jump to latest response", "All chats are private", ...). So the answer is
# what sits after the last "Duck.ai said", minus the model line and that tail.
_ANSWER = """(() => (document.querySelector('main') || document.body).innerText || '')()"""

_BUSY = """(() => !!document.querySelector('button[aria-label*="Stop"], button[aria-label*="Cancel"]'))()"""

# How many answers the column already holds. Counting turns is more robust than
# diffing the text: asking the same prompt twice appends a second identical
# answer, which a text diff would miss.
_COUNT = """(() => ((document.querySelector('main')||document.body).innerText
  .match(/Duck\\.ai said/g) || []).length)()"""

# The chrome that follows the last answer in the conversation column.
_TAIL_MARKERS = ("Jump to latest response", "All chats are private",
                 "Duck.ai, by DuckDuckGo")


def _extract_answer(column: str) -> str:
    """Pull the assistant's reply out of the Duck.ai conversation column."""
    for marker in _TAIL_MARKERS:
        column = column.split(marker)[0]
    if "Duck.ai said" not in column:
        return ""
    body = column.rsplit("Duck.ai said", 1)[-1]
    lines = [ln for ln in body.splitlines()]
    while lines and not lines[0].strip():
        lines.pop(0)
    # The first non-empty line is the model name (e.g. "GPT-6 Luna"); it is not
    # part of the answer.
    if lines and len(lines[0].strip()) <= 30:
        lines.pop(0)
    return "\n".join(lines).strip()


def _wait_composer(d: Cdp, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if d.js(_HAS_COMPOSER):
            return
        time.sleep(0.5)
    raise RuntimeError("Duck.ai composer never appeared")


def ask(prompt: str, *, timeout: float = 180.0) -> str:
    d = Cdp()
    try:
        _wait_composer(d)
        before_count = d.js(_COUNT) or 0
        typed = d.js(_SET_TEXT % json.dumps(prompt))
        if typed in ("no-composer", 0, None):
            raise RuntimeError("could not type into the Duck.ai composer")
        time.sleep(0.6)
        # The send control is the button labelled "Ask" (or a submit button).
        clicked = d.js("""(() => {
          const b = [...document.querySelectorAll('button')]
            .find(e => /^(Ask|Send)$/i.test((e.getAttribute('aria-label')||e.innerText||'').trim()));
          if (!b) return false; b.click(); return true;
        })()""")
        if not clicked:
            d.js("""(() => { const t = document.querySelector('textarea');
                     t.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true}));
                     return true; })()""")
        # Wait for a NEW answer to appear (the count grows), then for streaming
        # to stop. A long answer streams for a while, so `busy` is what decides
        # when it is safe to read.
        deadline = time.time() + timeout
        answer = ""
        while time.time() < deadline:
            time.sleep(2.0)
            count = d.js(_COUNT) or 0
            if count <= before_count:
                continue
            answer = _extract_answer(d.js(_ANSWER) or "")
            if answer and not d.js(_BUSY):
                break
        if not answer:
            raise RuntimeError("no answer within timeout (rate limit, or the page changed)")
        return answer
    finally:
        d.close()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("prompt", nargs="?", help="the question (or use --file)")
    ap.add_argument("--file", help="read the prompt from a file")
    ap.add_argument("--timeout", type=float, default=180.0)
    args = ap.parse_args()
    prompt = (open(args.file, encoding="utf-8").read() if args.file
              else (args.prompt or "").strip())
    if not prompt:
        ap.error("give a prompt or --file")
    try:
        print(ask(prompt, timeout=args.timeout))
    except Exception as e:  # noqa: BLE001 - a clear message beats a traceback
        print(f"duck_ask: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
