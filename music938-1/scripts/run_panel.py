#!/usr/bin/env python3
"""Run an advisor panel and save each answer as it arrives.

`ops/consult10.py` writes its `--out` file only after every advisor has
answered, so one advisor that hangs or crashes loses the whole consultation
(this happened: nine answers were produced and none were saved). This driver
saves after each answer, so a crash costs at most the advisor in flight.

    python3 scripts/run_panel.py --brief work/brief.md --out work/answers.json \
        --only chatgpt --only duck-luna --only duck-mistral --only duck-oss
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "ops"))

import consult10  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--brief", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--timeout", type=float, default=300.0)
    ap.add_argument("--only", action="append")
    args = ap.parse_args()

    problem = Path(args.brief).read_text(encoding="utf-8")
    out = Path(args.out)
    answers: dict = {}
    for name, fn in consult10.panel():
        if args.only and name not in args.only:
            continue
        t0 = time.time()
        try:
            answers[name] = {"ok": True, "answer": fn(problem, timeout=args.timeout)}
        except Exception as exc:  # noqa: BLE001
            answers[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
        answers[name]["seconds"] = round(time.time() - t0, 1)
        out.write_text(json.dumps(answers, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"[{name}] {'ok' if answers[name]['ok'] else 'FAIL'} "
              f"({answers[name]['seconds']}s) saved", flush=True)

    ok = sum(1 for a in answers.values() if a.get("ok"))
    print(f"\n{ok}/{len(answers)} advisors answered -> {out}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
