#!/usr/bin/env python3
"""Layer 3 of the AF bench: does the vendor make a CEO decision?

Four questions, twelve points. Layer 1 asks whether the pipe answers and layer 2
whether the arithmetic is right; this layer asks the question the advisor is
actually consulted for — what to do with a limited budget.

  kill       two projects, one is net negative           2 checks
  allocate   10 hours across three EV rates + capacity   4 checks
  sayno      a job that costs more than it pays          3 checks
  price      three price points, revenue not price       3 checks

The scoring is deliberately strict on the one thing that separates a decision
from a survey: a number. "Consider both options" scores zero; "kill A, net -0.3
vs +1.4" scores full.

    python3 tools/af_ceo_bench.py --json out.json
    python3 tools/af_ceo_bench.py --rounds 3 --write     # the measurement to trust
    python3 tools/af_ceo_bench.py --regrade out.json     # re-score saved answers

One round swings about +/-2 points between runs (measured 2026-11-21), so the
default here is three rounds and the table prints the median. A single round is
enough to prove the pipe, not to rank the vendors.

A regrade reads the saved raw answers and writes a new file. It never overwrites
the capture: the answers are the evidence, and the 2026-11-21 regrade lost a
whole round that way.
"""
from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import af_advisor as af  # noqa: E402
import af_bench_kit as kit  # noqa: E402

MAX_POINTS = 12


def _q_kill(data: dict, text: str) -> list[tuple[str, bool]]:
    kill = str(data.get("kill") or "").strip().lower()
    kills_a = kill.startswith("a") or kit.matches(
        text, r"\bkill\b\s*(?:option\s*)?a\b")
    return [
        ("kills A", kills_a and not kill.startswith("b")),
        ("nets -0.3 and +1.4",
         kit.field_or_number(data, "net_a", -0.3, text)
         and kit.field_or_number(data, "net_b", 1.4, text)),
    ]


def _q_allocate(data: dict, text: str) -> list[tuple[str, bool]]:
    return [
        ("hours_x = 6 (fills capacity)", kit.field_or_number(data, "hours_x", 6.0, text)),
        ("hours_y = 4 (the rest)", kit.field_or_number(data, "hours_y", 4.0, text)),
        ("total_ev = 54", kit.field_or_number(data, "total_ev", 54.0, text)),
        ("says why: highest EV per hour first, up to capacity",
         kit.matches(text, r"highest|best ev|capacity|เต็ม|6\s*/\s*h|ก่อน")),
    ]


def _q_sayno(data: dict, text: str) -> list[tuple[str, bool]]:
    call = str(data.get("call") or "").strip().lower()
    declines = (call.startswith("decline") or call.startswith("skip")
                or call.startswith("pass") or call.startswith("no")
                or kit.matches(text, r"\bdecline\b|\bskip\b|\bpass\b|\breject\b|"
                                     r"\bdon'?t take\b|\bdo not take\b"))
    return [
        ("declines the job", declines),
        ("opportunity cost = 4.5/hour", kit.field_or_number(
            data, "opportunity_cost_per_hour", 4.5, text)),
        ("net = -18", kit.field_or_number(data, "net", -18.0, text)),
    ]


def _q_price(data: dict, text: str) -> list[tuple[str, bool]]:
    revenues = all(kit.field_or_number(data, key, value, text)
                   for key, value in (("revenue_025", 0.20),
                                      ("revenue_150", 0.30),
                                      ("revenue_300", 0.60)))
    return [
        ("revenues 0.20 / 0.30 / 0.60", revenues),
        ("picks 3.00", kit.field_or_number(data, "price", 3.0, text)),
        ("reason is revenue, not price or volume",
         kit.matches(text, r"revenue|รายได้")),
    ]


QUESTIONS = [
    {
        "id": "kill",
        "max": 2,
        "prompt": (
            "Two projects, measured per hour. A: 10 users x 0.02 units = 0.2 "
            "revenue/hour, cost 0.5/hour. B: 4 users x 0.5 = 2.0 revenue/hour, cost "
            "0.6/hour. Which do you kill?\n"
            'Reply with JSON only: {"kill": "A" or "B", "net_a": <number>, '
            '"net_b": <number>, "reasoning": "<one line>"}'
        ),
        "checks": _q_kill,
    },
    {
        "id": "allocate",
        "max": 4,
        "prompt": (
            "You have 10 hours. Three tasks, each earns its EV per hour: X 6.0/hour "
            "with capacity 6 hours, Y 4.5/hour with capacity 4 hours, Z 2.0/hour. "
            "Allocate the 10 hours.\n"
            'Reply with JSON only: {"hours_x": <number>, "hours_y": <number>, '
            '"hours_z": <number>, "total_ev": <number>, "reasoning": "<one line>"}'
        ),
        "checks": _q_allocate,
    },
    {
        "id": "sayno",
        "max": 3,
        "prompt": (
            "A client offers 12 units for 4 hours of work. Your best alternative "
            "earns 7.5 units per hour. Take it or decline?\n"
            'Reply with JSON only: {"call": "TAKE" or "DECLINE", '
            '"opportunity_cost_per_hour": <number>, "net": <number>, '
            '"reasoning": "<one line>"}'
        ),
        "checks": _q_sayno,
    },
    {
        "id": "price",
        "max": 3,
        "prompt": (
            "Demand per hour at three price points: 0.25 -> 0.8 units, 1.50 -> 0.2 "
            "units, 3.00 -> 0.2 units. Which price maximizes revenue?\n"
            'Reply with JSON only: {"revenue_025": <number>, "revenue_150": <number>, '
            '"revenue_300": <number>, "price": <number>, "reasoning": "<one line>"}'
        ),
        "checks": _q_price,
    },
]


def score_answer(question: dict, text: str) -> dict:
    data = kit.parse_json(text)
    checks = question["checks"](data, text)
    return {"points": sum(1 for _name, ok in checks if ok),
            "max": len(checks),
            "checks": {name: bool(ok) for name, ok in checks}}


def score_round(rows: list[dict]) -> dict:
    per_question = {}
    for question in QUESTIONS:
        row = next((r for r in rows if r["question"] == question["id"]), None)
        if row is None or row["status"] != "OK":
            per_question[question["id"]] = {"points": 0, "max": question["max"],
                                            "answered": False}
            continue
        scored = score_answer(question, row["text"])
        per_question[question["id"]] = dict(scored, answered=True)
    return {"points": sum(v["points"] for v in per_question.values()),
            "max": MAX_POINTS, "per_question": per_question}


def run(vendors: list[str], rounds: int, timeout: float) -> dict:
    rows = []
    for round_index in range(1, rounds + 1):
        for vendor in vendors:
            for question in QUESTIONS:
                t0 = time.time()
                status, text = kit.ask(vendor, question["prompt"], timeout)
                row = {"round": round_index, "vendor": vendor,
                       "question": question["id"], "status": status,
                       "seconds": round(time.time() - t0, 1),
                       "text": text if status == "OK" else "",
                       "error": "" if status == "OK" else text}
                rows.append(row)
                scored = (score_answer(question, text)["points"]
                          if status == "OK" else None)
                print(f"[{round_index}/{rounds}] {vendor:12s} {question['id']:9s} "
                      f"{status:4s} "
                      f"{'--' if scored is None else f'{scored}/{question['max']}'} "
                      f"{row['seconds']:6.1f}s"
                      + ("" if status == "OK" else f"  {row['error'][:100]}"))
    return {"at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "tool": "af_ceo_bench", "rounds": rounds, "rows": rows}


def summarise(payload: dict, vendors: list[str]) -> dict:
    rows = payload.get("rows") or []
    out = {}
    for vendor in vendors:
        rounds = sorted({row["round"] for row in rows if row["vendor"] == vendor})
        scored = [score_round([row for row in rows
                               if row["vendor"] == vendor and row["round"] == r])
                  for r in rounds]
        if not scored:
            out[vendor] = {"median": None, "rounds": 0, "per_question": {}}
            continue
        per_question = {}
        for question in QUESTIONS:
            qid = question["id"]
            per_question[qid] = kit.median([s["per_question"][qid]["points"]
                                            for s in scored])
        out[vendor] = {
            "rounds": len(scored),
            "median": kit.median([s["points"] for s in scored]),
            "scores": [s["points"] for s in scored],
            "per_question": per_question,
            "answered": sum(1 for row in rows if row["vendor"] == vendor
                            and row["status"] == "OK"),
            "asked": sum(1 for row in rows if row["vendor"] == vendor),
        }
    return out


def print_table(scores: dict) -> None:
    ids = [q["id"] for q in QUESTIONS]
    print("\nvendor        median  " + "  ".join(f"{qid:>8s}" for qid in ids)
          + "  answered")
    for vendor, row in scores.items():
        median = "-" if row.get("median") is None else f"{row['median']:g}/{MAX_POINTS}"
        cells = []
        for qid in ids:
            value = row["per_question"].get(qid)
            cells.append(f"{'-' if value is None else f'{value:g}':>8s}")
        print(f"{vendor:12s} {median:>7}  " + "  ".join(cells)
              + f"  {row['answered']}/{row['asked']}")


def write_roster(scores: dict, payload: dict) -> None:
    roster = af.load_roster()
    roster.setdefault("bench", {})["ceo"] = {
        "measured_at": payload["at"],
        "tool": "tools/af_ceo_bench.py",
        "rounds": payload["rounds"],
        "max_points": MAX_POINTS,
        "scores": {name: row["median"] for name, row in scores.items()},
        "per_question": {name: row["per_question"] for name, row in scores.items()},
        "note": "Median of the rounds, not a single run: one round swings +/-2.",
    }
    af.save_roster(roster)
    print(f"updated roster: bench.ceo ({af.ROSTER_PATH})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--vendors", help="comma-separated subset (default: roster pool)")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=kit.BENCH_TIMEOUT)
    parser.add_argument("--write", action="store_true", help="save raw + roster verdict")
    parser.add_argument("--json", type=Path, help="write the raw result to this path")
    parser.add_argument("--regrade", type=Path,
                        help="re-score a saved raw file into a NEW file")
    args = parser.parse_args(argv)

    if args.regrade:
        payload = kit.load_raw(args.regrade)
        vendors = sorted({row["vendor"] for row in payload.get("rows") or []})
        scores = summarise(payload, vendors)
        print_table(scores)
        out = dict(payload,
                   regraded_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                   scores=scores, source=str(args.regrade))
        print(f"wrote {af.write_json(args.regrade.with_name(args.regrade.stem + '-regrade.json'), out)}")
        if args.write:
            write_roster(scores, payload)
        return 0

    roster = af.load_roster()
    vendors = ([af.resolve_vendor(v.strip(), roster) for v in args.vendors.split(",")
                if v.strip()] if args.vendors else af.default_pool(roster))
    unknown = [v for v in vendors if v not in (roster.get("advisors") or {})]
    if unknown:
        print(f"unknown vendor(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    payload = run(vendors, args.rounds, args.timeout)
    scores = summarise(payload, vendors)
    payload["scores"] = scores
    print_table(scores)
    if args.write:
        path = kit.write_raw("ceo-bench", payload)
        print(f"\nwrote raw answers: {path}")
        write_roster(scores, payload)
    if args.json:
        print(f"wrote {af.write_json(args.json, payload)}")
    return 0 if all(row.get("median") is not None for row in scores.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
