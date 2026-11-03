#!/usr/bin/env python3
"""Ask the signed-in Gemini web app a question and return its answer.

Companion to `ops/chatgpt_ask.py`: K wants more than one planner agent, and the
Gemini API is paid (Rule #1 is free-only), but the cloud desktop is already
signed in to `gemini.google.com`. So this drives that tab over CDP — no API key,
no cost.

    python3 ops/gemini_ask.py "prompt text"
    python3 ops/gemini_ask.py --file prompt.md
    python3 ops/gemini_ask.py --new "prompt"     # start a fresh chat first

Prefer `ops/ask_agents.py` when you want ChatGPT and Gemini compared side by side.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request

CDP = "http://127.0.0.1:9222/json"
HOST = "gemini.google.com"

# Gemini's composer is a Quill editor; `insertText` is what it listens for.
# Clear it first: Quill appends otherwise, so a second call would concatenate.
_SET_TEXT = """(() => {
  const c = document.querySelector('.ql-editor');
  if (!c) return 'no-composer';
  c.focus();
  const sel = window.getSelection(); sel.removeAllRanges();
  const r = document.createRange(); r.selectNodeContents(c); sel.addRange(r);
  document.execCommand('delete', false, null);
  document.execCommand('insertText', false, %s);
  return c.innerText.length;
})()"""


def _flatten(prompt: str) -> str:
    """Collapse a multi-line prompt into one line.

    Gemini's composer is Quill, and `execCommand('insertText')` inserts only the
    first line of a multi-line string — the rest is silently dropped, so a
    structured prompt arrived as a single line and Gemini answered a greeting
    instead of the question. Every newline becomes a space; the meaning survives
    because the prompt's own separators (numbers, dashes) do the structuring.
    """
    return re.sub(r"\s*\n\s*", " ", prompt).strip()


_CLEAR = """(() => {
  const c = document.querySelector('.ql-editor');
  if (!c) return false;
  c.focus();
  const sel = window.getSelection(); sel.removeAllRanges();
  const r = document.createRange(); r.selectNodeContents(c); sel.addRange(r);
  document.execCommand('delete', false, null);
  return c.innerText.trim().length === 0;
})()"""

# The answer lives in the last `.response-container`. `innerText` returns only
# the "Gemini บอกว่า" label there (the text node is in a collapsed node), so use
# `textContent` and strip the label.
_LAST_ANSWER = """(() => {
  const nodes = [...document.querySelectorAll('.response-container')];
  if (!nodes.length) return '';
  let t = nodes[nodes.length - 1].textContent || '';
  return t.replace(/^\\s*Gemini\\s*บอกว่า\\s*/, '').trim();
})()"""

_HAS_COMPOSER = """(() => !!document.querySelector('.ql-editor'))()"""

_SEND = """(() => {
  const b = document.querySelector('button[aria-label="ส่งข้อความ"]')
         || document.querySelector('button[aria-label="Send message"]');
  if (!b) return false; b.click(); return true;
})()"""


class Cdp:
    def __init__(self) -> None:
        import websocket  # noqa: PLC0415

        tabs = json.load(urllib.request.urlopen(CDP, timeout=10))
        page = next((t for t in tabs
                     if t.get("type") == "page" and HOST in t.get("url", "")), None)
        if page is None:
            raise RuntimeError(
                "no gemini.google.com tab on the desktop — open one and sign in")
        self.ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=60)
        self.n = 0

    def js(self, expr: str):
        self.n += 1
        mid = self.n
        self.ws.send(json.dumps({"id": mid, "method": "Runtime.evaluate",
                                 "params": {"expression": expr, "returnByValue": True}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == mid:
                return msg.get("result", {}).get("result", {}).get("value")

    def close(self) -> None:
        self.ws.close()


def _wait_composer(d, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if d.js(_HAS_COMPOSER):
            return
        time.sleep(0.5)
    raise RuntimeError("Gemini composer never appeared")


def ask(prompt: str, *, new_chat: bool = False, timeout: float = 420.0) -> str:
    d = Cdp()
    try:
        if new_chat:
            d.js("""(() => { const a = document.querySelector('a[href="/app"]')
                     || document.querySelector('button[aria-label*="แชทใหม่"]');
                     if (a) a.click(); return true; })()""")
            time.sleep(2.5)
        _wait_composer(d)
        before = d.js(_LAST_ANSWER) or ""
        flat = _flatten(prompt)
        typed = d.js(_SET_TEXT % json.dumps(flat))
        if typed in ("no-composer", 0, None):
            raise RuntimeError("could not type into the Gemini composer")
        # `insertText` can still land short (Quill re-renders mid-insert). Verify
        # the composer holds the prompt and retry once before sending, or Gemini
        # answers a truncated question.
        time.sleep(1.2)
        got = d.js("document.querySelector('.ql-editor')?.innerText||''") or ""
        if len(got) < len(flat) * 0.9:
            d.js(_CLEAR)
            time.sleep(0.6)
            typed = d.js(_SET_TEXT % json.dumps(flat))
            time.sleep(1.2)
            got = d.js("document.querySelector('.ql-editor')?.innerText||''") or ""
            if len(got) < len(flat) * 0.9:
                raise RuntimeError(
                    f"composer holds {len(got)} of {len(flat)} chars after retry")
        time.sleep(0.8)
        if not d.js(_SEND):
            raise RuntimeError("could not find Gemini's send button")
        # Consider it done when the answer text is non-empty and stops changing.
        deadline = time.time() + timeout
        answer = ""
        stable = 0
        while time.time() < deadline:
            time.sleep(3.0)
            cur = d.js(_LAST_ANSWER) or ""
            if cur and cur != before:
                if cur == answer:
                    stable += 1
                    if stable >= 2:
                        break
                else:
                    answer, stable = cur, 0
        if not answer:
            raise RuntimeError("no answer within timeout (rate limit, or not signed in?)")
        return answer
    finally:
        d.close()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("prompt", nargs="?")
    ap.add_argument("--file", help="read the prompt from this file instead")
    ap.add_argument("--new", action="store_true", help="start a fresh chat first")
    ap.add_argument("--timeout", type=float, default=420.0)
    args = ap.parse_args()

    prompt = args.prompt
    if args.file:
        prompt = open(args.file, encoding="utf-8").read()
    if not prompt:
        ap.error("give a prompt or --file")

    try:
        print(ask(prompt, new_chat=args.new, timeout=args.timeout))
    except Exception as exc:  # noqa: BLE001
        print(f"gemini_ask failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
