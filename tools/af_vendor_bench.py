#!/usr/bin/env python3
"""Layer 1 of the AF bench: does the pipe breathe at all?

This is not a quality test. It asks for one small JSON object with a computed
sum, because that single round trip separates the three faults a vendor can have:

  the pipe is dead      no answer, HTTP 429, a provider traceback
  the pipe is a proxy   an advert or an error page with HTTP 200
  the pipe works        JSON with the right sum

Quality is layer 2 (`af_pick_trading_advisor.py`) and layer 3 (`af_ceo_bench.py`).
Running them before this one wastes minutes on a vendor that answers nothing.

    python3 tools/af_vendor_bench.py                 # one round, all vendors
    python3 tools/af_vendor_bench.py --rounds 3 --write
    python3 tools/af_vendor_bench.py --vendors Gemini,pollinations

`--write` stores the raw answers under artifacts/vendor_consult/ and then the
verdict under `bench.transport` in the roster. A vendor that fails is *reported*,
never removed: one dead call is a retry, not a retirement.
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

PROMPT = ('Reply with JSON only and no prose: {"alive": true, "sum": <17*3>}')
EXPECTED_SUM = 51.0


def probe(vendor: str, timeout: float) -> dict:
    t0 = time.time()
    status, text = kit.ask(vendor, PROMPT, timeout)
    data = kit.parse_json(text) if status == "OK" else {}
    ok = (status == "OK"
          and data.get("alive") is True
          and kit.close(data.get("sum"), EXPECTED_SUM))
    return {
        "vendor": vendor,
        "status": status,
        "ok": bool(ok),
        "chars": len(text or ""),
        "seconds": round(time.time() - t0, 1),
        "answer": text if status == "OK" else "",
        "error": "" if status == "OK" else text,
    }


def summarise(rounds: list[dict]) -> dict:
    total = len(rounds)
    answered = sum(1 for row in rounds if row["status"] == "OK")
    passed = sum(1 for row in rounds if row["ok"])
    return {
        "rounds": total,
        "answered": answered,
        "passed": passed,
        "pipe_dead": total - answered,
        "verdict": "alive" if answered else "dead",
        "answers_wrong": answered - passed,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--vendors", help="comma-separated subset (default: roster pool)")
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=kit.BENCH_TIMEOUT)
    parser.add_argument("--write", action="store_true", help="save raw + roster verdict")
    parser.add_argument("--json", type=Path, help="write the raw result to this path")
    args = parser.parse_args(argv)

    roster = af.load_roster()
    if args.vendors:
        vendors = [af.resolve_vendor(v.strip(), roster)
                   for v in args.vendors.split(",") if v.strip()]
    else:
        vendors = af.default_pool(roster)
    unknown = [v for v in vendors if v not in (roster.get("advisors") or {})]
    if unknown:
        print(f"unknown vendor(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    results: dict[str, list[dict]] = {vendor: [] for vendor in vendors}
    for round_index in range(args.rounds):
        for vendor in vendors:
            row = probe(vendor, args.timeout)
            row["round"] = round_index + 1
            results[vendor].append(row)
            mark = "ok  " if row["ok"] else ("FAIL" if row["status"] == "OK" else "DEAD")
            print(f"[{mark}] {vendor:12s} round {round_index + 1} "
                  f"{row['seconds']:6.1f}s {row['chars']:5d} chars"
                  + ("" if row["ok"] else f"  {row['error'][:120]}"))

    verdicts = {vendor: summarise(rows) for vendor, rows in results.items()}
    print("\nvendor        answered  passed  dead  verdict")
    for vendor, verdict in verdicts.items():
        print(f"{vendor:12s} {verdict['answered']:>6}/{verdict['rounds']:<2} "
              f"{verdict['passed']:>5}  {verdict['pipe_dead']:>4}  {verdict['verdict']}")

    payload = {
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "tool": "af_vendor_bench",
        "prompt": PROMPT,
        "rounds": args.rounds,
        "results": results,
        "verdicts": verdicts,
    }
    if args.write:
        path = kit.write_raw("vendor-bench", payload)
        print(f"\nwrote raw answers: {path}")
        roster = af.load_roster()
        roster.setdefault("bench", {})["transport"] = {
            "measured_at": payload["at"],
            "tool": "tools/af_vendor_bench.py",
            "rounds": args.rounds,
            "results": verdicts,
            "raw": str(path.relative_to(af.ROOT)),
        }
        af.save_roster(roster)
        print(f"updated roster: bench.transport ({af.ROSTER_PATH})")
    if args.json:
        print(f"wrote {af.write_json(args.json, payload)}")
    return 0 if all(v["answered"] for v in verdicts.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
