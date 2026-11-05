#!/usr/bin/env python3
"""Consult the outside advisors before acting, and record what they said.

K's standing rule (2026-11-05):

    "ar พอเจอปัญหาหรือมีโจทย์ ยังไม่ได้ใช้ที่ปรึกษาก่อนตัดสินใจลงมือทำ
     ควรสร้างหลักการนี้ไว้ตลอด"

AR was jumping straight from a problem to an implementation. The rule now is:
for any non-trivial problem or brief, put it to the outside advisors FIRST,
read their answers, and only then decide. This script is that step, so it is one
command instead of a habit that gets skipped under time pressure.

    python3 ops/consult.py "problem statement"
    python3 ops/consult.py --file problem.md
    python3 ops/consult.py --only duck "quick question"
    python3 ops/consult.py --log        # show recent consultations

Every consultation is appended to `ops/consult-log.jsonl` (problem, per-vendor
answer, timestamps) so the reasoning behind a decision is auditable later and the
"which vendor actually helped" question has data behind it.

Vendors, all free (Rule #1), driven over the cloud desktop's CDP:
  - chatgpt  : strongest at separating what is automatable from what is not
  - gemini   : fast, terse, good second opinion
  - duck     : Duck.ai, needs NO login, so it still works when the Google
               session is the thing that is broken
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ask_agents  # noqa: E402
import duck_ask  # noqa: E402

LOG = HERE / "consult-log.jsonl"

# Every vendor the desktop can reach. Ordered so the most reliable-to-drive runs
# first; a failure in one does not stop the rest.
VENDORS = {
    "chatgpt": ask_agents.AGENTS["chatgpt"],
    "gemini": ask_agents.AGENTS["gemini"],
    "duck": duck_ask.ask,
}


def consult(problem: str, which: list[str], timeout: float) -> dict:
    """Ask each vendor, never letting one failure hide another's answer."""
    answers: dict = {}
    for name in which:
        t0 = time.time()
        try:
            answers[name] = {"ok": True,
                             "answer": VENDORS[name](problem, timeout=timeout)}
        except Exception as exc:  # noqa: BLE001
            answers[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
        answers[name]["seconds"] = round(time.time() - t0, 1)
    return answers


def digest(problem: str) -> str:
    """Stable id for a problem, so a gate can prove *this* brief was consulted."""
    norm = " ".join(problem.split()).lower()
    return hashlib.sha256(norm.encode("utf-8")).hexdigest()[:16]


def record(problem: str, answers: dict) -> None:
    row = {"at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "digest": digest(problem), "problem": problem, "answers": answers}
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def consulted(problem: str, max_age_hours: float = 48.0) -> dict | None:
    """Return the consultation for `problem` if it is recent enough, else None.

    This is the execution gate. Writing "consult first" in a document is not
    enough — an agent under time pressure skips a rule it can only remember. So
    the rule is checkable: `require(problem)` raises unless a matching
    consultation is on disk, and the daily rail calls it before it acts. The
    gate cannot be satisfied by intending to ask; only by asking.
    """
    if not LOG.exists():
        return None
    want = digest(problem)
    newest = None
    for line in LOG.read_text(encoding="utf-8").splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("digest") != want:
            continue
        if not any(v.get("ok") for v in row.get("answers", {}).values()):
            continue  # a consultation nobody answered is not a consultation
        newest = row
    if newest is None:
        return None
    age_h = (datetime.now(timezone.utc)
             - datetime.fromisoformat(newest["at"])).total_seconds() / 3600.0
    return newest if age_h <= max_age_hours else None


class NotConsulted(RuntimeError):
    """Raised by require() when a brief has no recent consultation on record."""


def require(problem: str, *, max_age_hours: float = 48.0) -> dict:
    """Assert the brief was consulted, or raise. The gate, in one call.

    Use it at the top of any non-trivial job. On failure the caller must run
    `consult.py` first; the exception message says exactly what to run.
    """
    row = consulted(problem, max_age_hours)
    if row is None:
        raise NotConsulted(
            "this brief has no consultation on record (or it is older than "
            f"{max_age_hours:g}h). Consult first:\n"
            f'  python3 ops/consult.py "{problem.splitlines()[0][:80]}"')
    return row


def show_log(limit: int) -> int:
    if not LOG.exists():
        print("no consultations recorded yet")
        return 0
    rows = LOG.read_text(encoding="utf-8").splitlines()[-limit:]
    for line in rows:
        r = json.loads(line)
        who = ", ".join(f"{k}{'' if v['ok'] else '!'}" for k, v in r["answers"].items())
        print(f"{r['at']}  [{who}]  {r['problem'].splitlines()[0][:80]}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("problem", nargs="?")
    ap.add_argument("--file", help="read the problem from this file")
    ap.add_argument("--only", choices=sorted(VENDORS),
                    help="ask just one vendor")
    ap.add_argument("--timeout", type=float, default=300.0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--log", action="store_true", help="list recent consultations")
    ap.add_argument("--check", metavar="PROBLEM",
                    help="exit 0 if PROBLEM was consulted recently, else 3 "
                         "(the execution gate, for scripts)")
    ap.add_argument("--limit", type=int, default=10)
    a = ap.parse_args()

    if a.log:
        return show_log(a.limit)

    if a.check is not None:
        row = consulted(a.check)
        if row is None:
            print(f"NOT CONSULTED: {a.check.splitlines()[0][:70]}", file=sys.stderr)
            print('run: python3 ops/consult.py "' + a.check.splitlines()[0][:60] + '"',
                  file=sys.stderr)
            return 3
        who = ", ".join(k for k, v in row["answers"].items() if v.get("ok"))
        print(f"consulted {row['at']} by {who}")
        return 0

    problem = a.problem
    if a.file:
        problem = Path(a.file).read_text(encoding="utf-8")
    if not problem:
        ap.error("give a problem or --file (or --log to review past ones)")

    which = [a.only] if a.only else list(VENDORS)
    answers = consult(problem, which, a.timeout)
    record(problem, answers)

    if a.json:
        print(json.dumps({"problem": problem, "answers": answers},
                         ensure_ascii=False, indent=1))
    else:
        for name, r in answers.items():
            print(f"\n{'='*64}\n{name.upper()}  ({r['seconds']}s)\n{'='*64}")
            print(r["answer"] if r["ok"] else f"[unavailable] {r['error']}")
        ok = [k for k, v in answers.items() if v["ok"]]
        print(f"\n[{len(ok)}/{len(answers)} advisors answered: {', '.join(ok) or 'none'}]")
        print(f"[recorded to {LOG.name}]")
    return 0 if any(v["ok"] for v in answers.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
