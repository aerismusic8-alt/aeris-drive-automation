#!/usr/bin/env python3
"""Ask ChatGPT and Gemini the same question and compare their answers.

K wants more than one planner agent. Both the ChatGPT and Gemini APIs are paid
(Rule #1 is free-only), but the cloud desktop is signed in to both web apps, so
`ops/chatgpt_ask.py` and `ops/gemini_ask.py` drive them over CDP. This wrapper
runs both and prints them side by side, which is more useful than either alone:
one model's blind spot is often the other's strength.

    python3 ops/ask_agents.py "prompt text"
    python3 ops/ask_agents.py --file prompt.md
    python3 ops/ask_agents.py --only gemini "prompt"
    python3 ops/ask_agents.py --json "prompt" > answers.json

A model that fails (rate limit, not signed in, slow) is reported as an error in
its own section; the other still returns. Exit code is 0 if at least one answered.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import chatgpt_ask  # noqa: E402
import gemini_ask  # noqa: E402

AGENTS = {
    "chatgpt": chatgpt_ask.ask,
    "gemini": gemini_ask.ask,
}


def run(which: list[str], prompt: str, *, new: bool, timeout: float) -> dict:
    out: dict = {}
    for name in which:
        t0 = time.time()
        try:
            out[name] = {"ok": True, "answer": AGENTS[name](prompt, new_chat=new,
                                                           timeout=timeout)}
        except Exception as exc:  # noqa: BLE001
            out[name] = {"ok": False, "error": str(exc)}
        out[name]["seconds"] = round(time.time() - t0, 1)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("prompt", nargs="?")
    ap.add_argument("--file", help="read the prompt from this file")
    ap.add_argument("--only", choices=sorted(AGENTS), help="ask just one agent")
    ap.add_argument("--new", action="store_true", help="fresh chat in each app")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("--timeout", type=float, default=420.0)
    args = ap.parse_args()

    prompt = args.prompt
    if args.file:
        prompt = open(args.file, encoding="utf-8").read()
    if not prompt:
        ap.error("give a prompt or --file")

    which = [args.only] if args.only else ["chatgpt", "gemini"]
    results = run(which, prompt, new=args.new, timeout=args.timeout)

    if args.json:
        print(json.dumps({"prompt": prompt, "answers": results},
                         ensure_ascii=False, indent=1))
    else:
        for name, r in results.items():
            print(f"\n{'='*60}\n{name.upper()}  ({r['seconds']}s)\n{'='*60}")
            print(r["answer"] if r["ok"] else f"[error] {r['error']}")
    return 0 if any(r["ok"] for r in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
