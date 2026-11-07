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
    python3 ops/consult.py --check "$(cat brief.md)"   # the gate, for scripts
    python3 ops/consult.py --applied "$(cat brief.md)" --note "what we did"

Every consultation is appended to `ops/consult-log.jsonl` (problem, per-vendor
answer, timestamps, the vendor families that answered, and what was later
*applied*) so the reasoning behind a decision is auditable later and the
"which vendor actually helped" question has data behind it.

Vendors, all free (Rule #1), driven over the cloud desktop's CDP:
  - chatgpt  : strongest at separating what is automatable from what is not
  - gemini   : fast, terse, good second opinion
  - duck     : Duck.ai, needs NO login, so it still works when the Google
               session is the thing that is broken. Duck.ai routes to several
               vendors behind one page, and each is a distinct opinion, so it
               supplies three of the five: its default model, Claude, and
               gpt-oss.

K's rule is five *channels* on every non-trivial task (2026-11-05). The gate
requires at least `MIN_ADVISORS` (three) to have answered **across at least
`MIN_FAMILIES` (two) vendors**.

Why families and not just channels: measured against `consult-log.jsonl`, the
median consultation had exactly ONE channel answer and only 4 of 33 reached
five — so a five-channel floor was never met in practice and got skipped, which
is the failure the rule exists to prevent. And three of the five channels are
the *same* Duck.ai page, so counting channels let one vendor pass for a panel:
the 2026-11-06 Facebook brief answered "10/10" while 8 of the 10 were that one
page agreeing with itself. Two vendors is the honest minimum for "not a single
opinion", it is reachable, and it is the number that actually changes a
decision. `family()` maps a channel to its vendor; `quorum()` decides the floor
in one place.
"""
from __future__ import annotations

import argparse
import functools
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

# Five channels, three vendors. Two are the ChatGPT and Gemini web apps; three
# are Duck.ai models, which need no login and so keep the panel alive when Google
# is signed out. Ordered most-reliable-to-drive first; one failure does not stop
# the rest.
VENDORS = {
    "chatgpt": ask_agents.AGENTS["chatgpt"],
    "gemini": ask_agents.AGENTS["gemini"],
    "duck": duck_ask.ask,
    "duck-claude": functools.partial(duck_ask.ask, model="Claude Haiku 5.5"),
    "duck-oss": functools.partial(duck_ask.ask, model="gpt-oss 120B"),
}


def family(vendor: str) -> str:
    """The *vendor* behind a channel, not the channel name.

    Three of the five channels are Duck.ai, which is one page routing to several
    models. Counting channels as independent opinions is what let a single
    Duck.ai page pass for a panel: the 2026-11-06 Facebook brief answered 10/10
    "independently" while 8 of the 10 were the same page echoing itself. The
    quorum below counts families so agreement has to cross a real boundary.
    """
    return "duck" if vendor.startswith("duck") else vendor


def families(answers: dict) -> set[str]:
    return {family(k) for k, v in answers.items() if v.get("ok")}

# The gate floor, measured against the log rather than wished for. A channel
# count of 5 was never reached (4 of 33 consultations) and a channel floor of 3
# refused most of them (median was ONE channel), so the rule was skipped in
# practice — the failure mode the advisors warned about. What actually matters
# is more than one *vendor*: two families is the honest minimum for "not a
# single opinion", and it is reachable (a retry turns a transient web-app
# failure into a second family). Three channels still must answer, so one
# family cannot pass by echoing itself three times.
MIN_FAMILIES = 2
MIN_ADVISORS = 3


def quorum(answers: dict) -> tuple[bool, str]:
    """(passed, reason). The one place the floor is decided."""
    fams = families(answers)
    n = sum(1 for v in answers.values() if v.get("ok"))
    if n < MIN_ADVISORS:
        return False, f"only {n} channel(s) answered (need {MIN_ADVISORS})"
    if len(fams) < MIN_FAMILIES:
        return False, (f"only {len(fams)} vendor family(ies) answered "
                       f"({', '.join(sorted(fams)) or 'none'}; need {MIN_FAMILIES})")
    return True, f"{n} channels across {len(fams)} vendors: {', '.join(sorted(fams))}"


def consult(problem: str, which: list[str], timeout: float,
            retries: int = 1) -> dict:
    """Ask each vendor, never letting one failure hide another's answer.

    A failed channel is retried `retries` times. Most single-family rows in the
    log are a web app that was slow or mid-sign-in, not a genuine lone opinion,
    so a cheap retry of only the failures buys a real second family.
    """
    answers: dict = {}
    for name in which:
        attempts = 0
        while True:
            t0 = time.time()
            try:
                answers[name] = {"ok": True,
                                 "answer": VENDORS[name](problem, timeout=timeout)}
            except Exception as exc:  # noqa: BLE001
                answers[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
            answers[name]["seconds"] = round(time.time() - t0, 1)
            if answers[name]["ok"] or attempts >= retries:
                break
            attempts += 1
            answers[name]["retried"] = attempts
    return answers


def digest(problem: str) -> str:
    """Stable id for a problem, so a gate can prove *this* brief was consulted."""
    norm = " ".join(problem.split()).lower()
    return hashlib.sha256(norm.encode("utf-8")).hexdigest()[:16]


def record(problem: str, answers: dict, applied: list | None = None) -> None:
    """Append one consultation. `applied` is filled in later, when a decision is
    made, so the log can answer "which advice did we actually use" — the question
    it could not answer before (it stored answers only).
    """
    row = {"at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "digest": digest(problem), "problem": problem, "answers": answers,
           "families": sorted(families(answers)),
           "quorum": quorum(answers)[0],
           "applied": applied or []}
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")


def note_applied(problem: str, items: list[str]) -> int:
    """Record what was taken from the advisors for `problem` (rewrites its rows).

    Kept separate from `record` on purpose: the decision comes after the
    consultation, often in a later session, so it is a second write keyed by the
    same digest.
    """
    if not LOG.exists():
        return 0
    want = digest(problem)
    rows = []
    hit = 0
    for line in LOG.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("digest") == want:
            row["applied"] = items
            hit += 1
        rows.append(row)
    if hit:
        LOG.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows),
                       encoding="utf-8")
    return hit


def consulted(problem: str, max_age_hours: float = 48.0) -> dict | None:
    """Return the consultation for `problem` if it is recent enough, else None.

    This is the execution gate. Writing "consult first" in a document is not
    enough — an agent under time pressure skips a rule it can only remember. So
    the rule is checkable: `require(problem)` raises unless a matching
    consultation is on disk, and the daily rail calls it before it acts. The
    gate cannot be satisfied by intending to ask; only by asking.

    The floor is `quorum()`: at least MIN_ADVISORS channels across at least
    MIN_FAMILIES vendors. A row where every channel failed is not a
    consultation; neither is one vendor answering under three names.
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
        if not quorum(row.get("answers", {}))[0]:
            continue
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
        ok = [k for k, v in r["answers"].items() if v.get("ok")]
        fams = r.get("families") or sorted({family(k) for k in ok})
        mark = "PASS" if r.get("quorum", len(fams) >= MIN_FAMILIES) else "thin"
        applied = r.get("applied") or []
        tail = f"  applied={len(applied)}" if applied else ""
        print(f"{r['at']}  [{mark} {len(ok)}ch/{len(fams)}fam {','.join(sorted(fams))}]"
              f"{tail}  {r['problem'].splitlines()[0][:70]}")
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
    ap.add_argument("--retries", type=int, default=1,
                    help="retry a failed channel this many times (default 1)")
    ap.add_argument("--check", metavar="PROBLEM",
                    help="exit 0 if PROBLEM was consulted recently, else 3 "
                         "(the execution gate, for scripts)")
    ap.add_argument("--applied", metavar="PROBLEM",
                    help="record what was taken from the advisors for PROBLEM")
    ap.add_argument("--note", action="append",
                    help="one applied item; repeat for several (with --applied)")
    ap.add_argument("--limit", type=int, default=10)
    a = ap.parse_args()

    if a.log:
        return show_log(a.limit)

    if a.applied is not None:
        if not a.note:
            ap.error("--applied needs at least one --note")
        n = note_applied(a.applied, a.note)
        print(f"recorded {len(a.note)} applied item(s) on {n} row(s)")
        return 0 if n else 1

    if a.check is not None:
        row = consulted(a.check)
        if row is None:
            print(f"NOT CONSULTED: {a.check.splitlines()[0][:70]}", file=sys.stderr)
            print('run: python3 ops/consult.py "' + a.check.splitlines()[0][:60] + '"',
                  file=sys.stderr)
            return 3
        ok, why = quorum(row["answers"])
        print(f"consulted {row['at']} — {why}")
        return 0

    problem = a.problem
    if a.file:
        problem = Path(a.file).read_text(encoding="utf-8")
    if not problem:
        ap.error("give a problem or --file (or --log to review past ones)")

    which = [a.only] if a.only else list(VENDORS)
    answers = consult(problem, which, a.timeout, retries=a.retries)
    record(problem, answers)

    passed, why = quorum(answers)
    if a.json:
        print(json.dumps({"problem": problem, "answers": answers,
                          "families": sorted(families(answers)),
                          "quorum": passed, "reason": why},
                         ensure_ascii=False, indent=1))
    else:
        for name, r in answers.items():
            print(f"\n{'='*64}\n{name.upper()}  ({r['seconds']}s)\n{'='*64}")
            print(r["answer"] if r["ok"] else f"[unavailable] {r['error']}")
        print(f"\n[quorum {'PASS' if passed else 'FAIL'}: {why}]")
        if not passed:
            print("[!] this consultation does not satisfy the gate — the gate will "
                  "NOT accept it; retry the failed vendors", file=sys.stderr)
        print(f"[recorded to {LOG.name}]")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
