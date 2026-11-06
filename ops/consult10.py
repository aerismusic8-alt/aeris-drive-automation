#!/usr/bin/env python3
"""Ask a panel of TEN AI advisors the same brief and record every answer.

K asked (2026-11-06) for a ten-agent panel on a hard problem, one platform at a
time. `ops/consult.py` runs the standing five (ChatGPT web, Gemini web, and three
Duck.ai models) and is the gate the daily rails call. This script widens the
panel to ten *distinct* models:

  chatgpt                     ChatGPT web app   (cloud desktop)
  gemini                      Gemini web app    (cloud desktop)
  duck-*                      eight Duck.ai models, driven one at a time

Duck.ai is used sequentially because it is a single page whose model is switched
before each question; asking two models at once would race the switch.

    python3 ops/consult10.py --file brief.md --out /tmp/consult10.json
    python3 ops/consult10.py --list

Answers are also appended to `ops/consult-log.jsonl` so the execution gate in
`consult.py` sees this consultation and the reasoning stays auditable.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ask_agents  # noqa: E402
import duck_ask  # noqa: E402
from consult import record  # noqa: E402

# Eight Duck.ai models, each a separate opinion. The default model carries tools;
# "Fast" is the same base without them; the rest are the other vendors Duck
# routes to. Names must match the Duck.ai model menu.
DUCK_MODELS = [
    ("duck-luna", "6 Luna"),
    ("duck-luna-fast", "Fast 6 Luna"),
    ("duck-mistral", "Mistral Small 4"),
    ("duck-oss", "gpt-oss 120B"),
    ("duck-gpt-terra", "GPT-5.6 Terra PLUS"),
    ("duck-claude-sonnet", "Claude Sonnet 5.5 PLUS"),
    ("duck-gpt-sol", "GPT-5.6 Sol PRO"),
    ("duck-claude-opus", "Claude Opus 5.5 PRO"),
]

WEB_APPS = [
    ("chatgpt", ask_agents.AGENTS["chatgpt"]),
    ("gemini", ask_agents.AGENTS["gemini"]),
]


def panel() -> list[tuple[str, callable]]:
    out: list[tuple[str, callable]] = list(WEB_APPS)
    for name, model in DUCK_MODELS:
        out.append((name, _duck(model)))
    return out


def _duck(model: str):
    def run(prompt: str, timeout: float = 300.0) -> str:
        return duck_ask.ask(prompt, timeout=timeout, model=model)
    return run


def consult(problem: str, timeout: float, only: list[str] | None) -> dict:
    answers: dict = {}
    for name, fn in panel():
        if only and name not in only:
            continue
        t0 = time.time()
        try:
            answers[name] = {"ok": True, "answer": fn(problem, timeout=timeout)}
        except Exception as exc:  # noqa: BLE001
            answers[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
        answers[name]["seconds"] = round(time.time() - t0, 1)
        print(f"[{name}] {'ok' if answers[name]['ok'] else 'FAIL'} "
              f"({answers[name]['seconds']}s)", flush=True)
    return answers


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("problem", nargs="?")
    ap.add_argument("--file")
    ap.add_argument("--out")
    ap.add_argument("--timeout", type=float, default=300.0)
    ap.add_argument("--only", action="append")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(argv)

    if args.list:
        for name, _ in panel():
            print(name)
        return 0

    problem = args.problem
    if args.file:
        problem = Path(args.file).read_text(encoding="utf-8")
    if not problem:
        ap.error("give a problem string or --file")

    answers = consult(problem, args.timeout, args.only)
    ok = sum(1 for a in answers.values() if a.get("ok"))
    print(f"\n{ok}/{len(answers)} advisors answered")
    record(problem, answers)  # satisfies the consult.py gate + audit trail
    if args.out:
        Path(args.out).write_text(json.dumps(answers, ensure_ascii=False, indent=1),
                                  encoding="utf-8")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
