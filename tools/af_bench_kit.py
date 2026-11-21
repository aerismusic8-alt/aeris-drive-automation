#!/usr/bin/env python3
"""Shared scoring helpers for the three AF benches.

The benches exist to answer three different questions, and each one has burned a
wrong result before:

  af_vendor_bench.py          is the pipe alive at all? (JSON, known sum)
  af_pick_trading_advisor.py  does it compute money correctly? (4 questions)
  af_ceo_bench.py             does it make a CEO decision? (kill/allocate/sayno/price)

Everything here is a guard against a *scoring* mistake, not a model mistake:

* `parse_json` strips a ``` fence and finds the first balanced object, because a
  model that wraps its JSON in prose is still answering.
* `has_number` matches a number with a relative tolerance, so 0.4 and 0.4000001
  are the same answer and 0.25 is not 0.4.
* `matches` lower-cases before searching. A pattern written as \\bKILL\\b can
  never match lower-cased text — that bug scored a whole round wrong.
* `write_raw` never overwrites. The raw answers are the evidence; a regrade
  writes a new file, and the 2026-11-21 regrade that overwrote a set had to
  re-run the whole bench.
"""
from __future__ import annotations

import json
import re
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import af_advisor as af  # noqa: E402

BENCH_TIMEOUT = 90.0


def ask(vendor: str, prompt: str, timeout: float = BENCH_TIMEOUT):
    """(status, text) with the advisor's retries and error-answer guard."""
    _vendor, status, text = af._ask(vendor, prompt, timeout)
    return status, text


def parse_json(text: str) -> dict:
    body = (text or "").strip()
    if body.startswith("```"):
        body = re.sub(r"^```[a-z]*\s*", "", body)
        body = re.sub(r"\s*```$", "", body)
    try:
        payload = json.loads(body)
        return payload if isinstance(payload, dict) else {}
    except json.JSONDecodeError:
        pass
    start = body.find("{")
    while start != -1:
        depth = 0
        for index in range(start, len(body)):
            char = body[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    try:
                        payload = json.loads(body[start:index + 1])
                        return payload if isinstance(payload, dict) else {}
                    except json.JSONDecodeError:
                        break
        start = body.find("{", start + 1)
    return {}


NUMBER_RE = re.compile(r"-?\d+(?:\.\d+)?")


def numbers(text: str) -> list[float]:
    out = []
    for token in NUMBER_RE.findall((text or "").replace(",", "")):
        try:
            out.append(float(token))
        except ValueError:
            continue
    return out


def close(actual, expected, rel: float = 0.02) -> bool:
    try:
        actual = float(actual)
    except (TypeError, ValueError):
        return False
    if expected == 0:
        return abs(actual) <= rel
    return abs(actual - expected) <= abs(expected) * rel


def has_number(text: str, expected: float, rel: float = 0.02) -> bool:
    return any(close(value, expected, rel) for value in numbers(text))


def field_or_number(data: dict, key: str, expected: float, text: str,
                    rel: float = 0.02) -> bool:
    """Trust an explicit JSON field first; fall back to any number in the prose.

    The field is the precise signal. The fallback exists because a model that
    ignores the JSON instruction still answered correctly, and rejecting it would
    measure format obedience, not arithmetic.
    """
    value = data.get(key)
    if value is not None:
        return close(value, expected, rel)
    return has_number(text, expected, rel)


def norm(text: str) -> str:
    return (text or "").lower()


def matches(text: str, pattern: str) -> bool:
    """Case-insensitive search. Patterns must be written lower-case."""
    return re.search(pattern, norm(text)) is not None


def median(values: list) -> float | None:
    clean = [v for v in values if v is not None]
    return statistics.median(clean) if clean else None


def write_raw(name: str, payload: dict) -> Path:
    return af.write_json(af.OUT_DIR / f"{name}.json", payload)


def load_raw(path: str | Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_roster() -> dict:
    return af.load_roster()


def score_question(data: dict, text: str, checks: list[tuple[str, bool]]) -> dict:
    points = sum(1 for _name, ok in checks if ok)
    return {"points": points, "max": len(checks),
            "checks": {name: bool(ok) for name, ok in checks}}
