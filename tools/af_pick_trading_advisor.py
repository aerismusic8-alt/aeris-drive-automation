#!/usr/bin/env python3
"""Layer 2 of the AF bench: does the vendor compute money correctly?

Four questions, eleven checks. Each question has one right number, so the score
measures arithmetic and the discipline to show it — not style. A wrong number
with a confident voice scores zero, which is the point: this bench picks the
vendor that answers money questions, and it is allowed to disagree with the
standing advisor.

  expectancy   EV of a 40%/60% bet                      3 checks
  friction     gross -> net after three percentage cuts  3 checks
  growth       compounding over six months               2 checks
  reconcile    two ledgers, one held balance              3 checks

Self-consistency is measured separately: every question is asked twice, in two
independent calls, and the two numbers must agree within 2%. A vendor that
answers 0.4 and then 0.25 is not reliable even when one of the answers is right.

    python3 tools/af_pick_trading_advisor.py --json out.json
    python3 tools/af_pick_trading_advisor.py --write          # updates the roster
    python3 tools/af_pick_trading_advisor.py --regrade out.json

A regrade reads the saved raw answers and writes a **new** file; it never
overwrites the raw capture. The 2026-11-21 regrade destroyed a set that way and
the whole bench had to be re-run.
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

MAX_POINTS = 11


def _shows_multiplication(text: str) -> bool:
    # 0.4 or 0.40, and any spacing or operator between the two factors.
    return (kit.matches(text, r"0\.4\d?[^0-9]{0,14}2\.5")
            or kit.matches(text, r"2\.5[^0-9]{0,14}0\.4"))


def _q_expectancy(data: dict, text: str) -> list[tuple[str, bool]]:
    return [
        ("value = 0.4", kit.field_or_number(data, "value", 0.4, text)),
        ("shows 0.4 x 2.5 (and the losing side)", _shows_multiplication(text)
         and (kit.has_number(text, 1.0) or kit.has_number(text, -1.0))),
        ("call = TAKE", kit.matches(text, r"\btake\b")),
    ]


def _q_friction(data: dict, text: str) -> list[tuple[str, bool]]:
    return [
        ("value = 62", kit.field_or_number(data, "value", 62.0, text)),
        ("shows all three deductions (30, 3, 5)",
         all(kit.has_number(text, n) for n in (30.0, 3.0, 5.0))),
        ("states the 62% margin",
         kit.matches(text, r"62\s*%") or kit.field_or_number(data, "margin", 62.0, text)),
    ]


def _q_growth(data: dict, text: str) -> list[tuple[str, bool]]:
    return [
        ("value = 1771.56", kit.field_or_number(data, "value", 1771.56, text, rel=0.01)),
        ("shows compounding (1.1^6), not 1000+60%",
         kit.matches(text, r"1\.1\d?\s*(\^|\*\*)\s*6|1\.1\s*\*\s*1\.1|compou")),
    ]


def _q_reconcile(data: dict, text: str) -> list[tuple[str, bool]]:
    explicit = data.get("value")
    not_320 = True if explicit is None else not kit.close(explicit, 320.0, rel=0.005)
    return [
        ("value = 350 (net of fees)", kit.field_or_number(data, "value", 350.0, text)),
        ("the 30 is held / receivable, not a cost",
         kit.matches(text, r"receivable|held|pending payout|outstanding|withheld|"
                           r"ค้าง|ยังไม่จ่าย")),
        ("does not book 320 as the net", not_320),
    ]


QUESTIONS = [
    {
        "id": "expectancy",
        "max": 3,
        "prompt": (
            "A paid task succeeds 40% of the time and earns +2.5 units; it fails "
            "60% of the time and loses 1.0 unit. What is the expectancy per attempt?\n"
            'Reply with JSON only: {"value": <number>, "reasoning": "<one line with '
            'the numbers>", "call": "TAKE" or "SKIP"}'
        ),
        "checks": _q_expectancy,
    },
    {
        "id": "friction",
        "max": 3,
        "prompt": (
            "A sale is 100 units gross. The platform keeps 30% of gross, the payment "
            "processor takes 3% of gross, and refunds are 5% of gross. What do you "
            "actually net?\n"
            'Reply with JSON only: {"value": <number>, "reasoning": "<one line>", '
            '"margin": "<percent>"}'
        ),
        "checks": _q_friction,
    },
    {
        "id": "growth",
        "max": 2,
        "prompt": (
            "A channel has 1,000 followers and grows 10% per month, compounded. How "
            "many followers after 6 months?\n"
            'Reply with JSON only: {"value": <number>, "reasoning": "<one line>"}'
        ),
        "checks": _q_growth,
    },
    {
        "id": "reconcile",
        "max": 3,
        "prompt": (
            "Two ledgers for the same month. Ledger A: gross revenue 500, platform "
            "fees 150. Ledger B: cash received 320, plus 30 still held by the "
            "platform. What do you book as revenue net of fees, and what is the 30?\n"
            'Reply with JSON only: {"value": <number>, "reasoning": "<one line>"}'
        ),
        "checks": _q_reconcile,
    },
]

SECOND_OPINION = "\n\nAnswer independently; this is a second opinion on the same question."


def score_answer(question: dict, text: str) -> dict:
    data = kit.parse_json(text)
    checks = question["checks"](data, text)
    return {"points": sum(1 for _name, ok in checks if ok),
            "max": len(checks),
            "checks": {name: bool(ok) for name, ok in checks}}


def score_vendor(rows: list[dict]) -> dict:
    """rows: one per (question, ask). Best ask per question counts; the pair is
    what self-consistency measures."""
    by_question: dict[str, list[dict]] = {}
    for row in rows:
        by_question.setdefault(row["question"], []).append(row)
    points = 0
    consistent = 0
    detail = {}
    for question in QUESTIONS:
        qid = question["id"]
        attempts = by_question.get(qid) or []
        scored = [score_answer(question, row["text"]) for row in attempts
                  if row["status"] == "OK"]
        best = max((s["points"] for s in scored), default=0)
        points += best
        values = [kit.parse_json(row["text"]).get("value") for row in attempts
                  if row["status"] == "OK"]
        if len(values) == 2 and all(isinstance(v, (int, float)) for v in values):
            if kit.close(values[0], float(values[1]), rel=0.02):
                consistent += 1
        detail[qid] = {"points": best, "max": question["max"],
                       "answered": sum(1 for row in attempts if row["status"] == "OK"),
                       "asked": len(attempts)}
    return {"points": points, "max": MAX_POINTS,
            "self_consistency": round(consistent / len(QUESTIONS), 2),
            "detail": detail}


def run(vendors: list[str], rounds: int, timeout: float, consistency: bool) -> dict:
    rows = []
    for round_index in range(1, rounds + 1):
        for vendor in vendors:
            for question in QUESTIONS:
                asks = 2 if consistency else 1
                for ask_index in range(1, asks + 1):
                    prompt = question["prompt"]
                    if ask_index == 2:
                        prompt += SECOND_OPINION
                    t0 = time.time()
                    status, text = kit.ask(vendor, prompt, timeout)
                    row = {"round": round_index, "vendor": vendor,
                           "question": question["id"], "ask": ask_index,
                           "status": status,
                           "seconds": round(time.time() - t0, 1),
                           "text": text if status == "OK" else "",
                           "error": "" if status == "OK" else text}
                    rows.append(row)
                    scored = (score_answer(question, text)["points"]
                              if status == "OK" else None)
                    print(f"[{round_index}/{rounds}] {vendor:12s} {question['id']:11s} "
                          f"ask{ask_index} {status:4s} "
                          f"{'--' if scored is None else f'{scored}/{question['max']}'} "
                          f"{row['seconds']:6.1f}s"
                          + ("" if status == "OK" else f"  {row['error'][:100]}"))
    return {"at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "tool": "af_pick_trading_advisor", "rounds": rounds,
            "consistency": consistency, "rows": rows}


def summarise(payload: dict, vendors: list[str]) -> dict:
    rows = payload.get("rows") or []
    out = {}
    for vendor in vendors:
        rounds = sorted({row["round"] for row in rows if row["vendor"] == vendor})
        per_round = [score_vendor([row for row in rows
                                   if row["vendor"] == vendor and row["round"] == r])
                     for r in rounds]
        if not per_round:
            out[vendor] = {"points": None, "median": None, "self_consistency": None,
                           "rounds": 0}
            continue
        out[vendor] = {
            "rounds": len(per_round),
            "points": max(p["points"] for p in per_round),
            "median": kit.median([p["points"] for p in per_round]),
            "self_consistency": kit.median([p["self_consistency"] for p in per_round]),
            "detail": per_round[-1]["detail"],
        }
    return out


def pick(scores: dict, standing: str | None = None) -> str | None:
    """Highest median; ties to self-consistency, then the best round, then the
    standing advisor. A tie is not evidence that the default is wrong."""
    candidates = [(name, row) for name, row in scores.items()
                  if row.get("median") is not None]
    if not candidates:
        return None
    candidates.sort(key=lambda item: (-item[1]["median"],
                                      -(item[1]["self_consistency"] or 0),
                                      -item[1]["points"],
                                      0 if item[0] == standing else 1))
    return candidates[0][0]


def print_table(scores: dict, chosen: str | None) -> None:
    print(f"\nvendor        median  best  consistent")
    for vendor, row in scores.items():
        median = "-" if row.get("median") is None else f"{row['median']:g}/{MAX_POINTS}"
        best = "-" if row.get("points") is None else f"{row['points']}/{MAX_POINTS}"
        consistency = "-" if row.get("self_consistency") is None else f"{row['self_consistency']:.2f}"
        mark = "  <- trading advisor" if vendor == chosen else ""
        print(f"{vendor:12s} {median:>7} {best:>5} {consistency:>11}{mark}")


def write_roster(scores: dict, chosen: str | None, payload: dict) -> None:
    roster = af.load_roster()
    roster.setdefault("bench", {})["trading"] = {
        "measured_at": payload["at"],
        "tool": "tools/af_pick_trading_advisor.py",
        "rounds": payload["rounds"],
        "max_points": MAX_POINTS,
        "results": {name: {k: v for k, v in row.items() if k != "detail"}
                    for name, row in scores.items()},
    }
    if chosen:
        row = scores[chosen]
        roster["trading_advisor"] = {
            "vendor": chosen,
            "score": f"{row['median']:g}/{MAX_POINTS}",
            "self_consistency": row["self_consistency"],
            "measured_at": payload["at"],
            "note": "Written by af_pick_trading_advisor.py --write: highest median "
                    "points; ties go to self-consistency, then to the standing "
                    "advisor.",
        }
    af.save_roster(roster)
    print(f"updated roster: bench.trading"
          + (f" + trading_advisor={chosen}" if chosen else ""))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--vendors", help="comma-separated subset (default: roster pool)")
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=kit.BENCH_TIMEOUT)
    parser.add_argument("--no-consistency", action="store_true",
                        help="ask each question once (halves the run)")
    parser.add_argument("--write", action="store_true", help="save raw + roster verdict")
    parser.add_argument("--json", type=Path, help="write the raw result to this path")
    parser.add_argument("--regrade", type=Path,
                        help="re-score a saved raw file into a NEW file")
    args = parser.parse_args(argv)

    if args.regrade:
        payload = kit.load_raw(args.regrade)
        vendors = sorted({row["vendor"] for row in payload.get("rows") or []})
        scores = summarise(payload, vendors)
        chosen = pick(scores, af.resolve_vendor(
            af.load_roster().get("default_advisor") or ""))
        print_table(scores, chosen)
        out = dict(payload, regraded_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                   scores=scores, chosen=chosen,
                   source=str(args.regrade))
        print(f"wrote {af.write_json(args.regrade.with_name(args.regrade.stem + '-regrade.json'), out)}")
        if args.write:
            write_roster(scores, chosen, payload)
        return 0

    roster = af.load_roster()
    vendors = ([af.resolve_vendor(v.strip(), roster) for v in args.vendors.split(",")
                if v.strip()] if args.vendors else af.default_pool(roster))
    unknown = [v for v in vendors if v not in (roster.get("advisors") or {})]
    if unknown:
        print(f"unknown vendor(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    payload = run(vendors, args.rounds, args.timeout, not args.no_consistency)
    scores = summarise(payload, vendors)
    chosen = pick(scores, af.resolve_vendor(roster.get("default_advisor") or "", roster))
    payload["scores"] = scores
    payload["chosen"] = chosen
    print_table(scores, chosen)
    if args.write:
        path = kit.write_raw("trading-bench", payload)
        print(f"\nwrote raw answers: {path}")
        write_roster(scores, chosen, payload)
    if args.json:
        print(f"wrote {af.write_json(args.json, payload)}")
    return 0 if chosen else 1


if __name__ == "__main__":
    sys.exit(main())
