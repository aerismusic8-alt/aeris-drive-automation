#!/usr/bin/env python3
"""The AF advisor: free, keyless advice for an agent with no human in the loop.

The standing panel in `ops/consult.py` drives a *signed-in browser* (K's cloud
desktop). That is the right tool for K's own session and the wrong one for an
autonomous rail: on a CI runner the desktop is absent, so a gate built on it can
never go green. This module is the rail-side advisor. Every transport is keyless
and needs no browser:

  pollinations  plain HTTPS, no key, ~1 answer per 45 s per IP
  g4f           community providers behind `g4f`; each vendor is one provider
                class, so the same code reaches Gemini, KiloCode, G4FSpace, ...

The rule the system is built around: ask more vendors than the quorum needs,
keep whoever answers, and **fail closed** when too few do. A missing answer is
never invented, never filled in from another vendor, and never counted as
agreement.

    python3 tools/af_advisor.py "question" --advisor gemini
    python3 tools/af_advisor.py "blocker" --stuck "Traceback ..." --json out.json
    python3 tools/af_advisor.py "question" --vendors Gemini,KiloCode,pollinations --quorum 2
    python3 tools/af_advisor.py --check          # roster + last bench result
    python3 tools/af_advisor.py --selftest       # the guards, no network

Three guards exist because each one was learned from a wrong result:

* `looks_like_error_answer` — g4f sometimes returns an error *page* with HTTP
  200 ("having a hard time fulfilling"). Counting that as an answer is how the
  2026-11-19 bench scored a refusal as a reply.
* `MIN_CHARS` is 20, not 200. "Opportunity cost: 4.5 / DECLINE" is a correct
  answer in 30 characters; a high floor silently deleted the best answers.
* a rate hint waits 50 s instead of 3 s. Pollinations allows one call per 45 s,
  so a short retry just burns an attempt against the same quota.

The roster (`af_advisor_roster.json`) is the registry: which vendors exist, which
are dead and why, which one answers first, and the last measured bench score. A
vendor is never dropped because one call failed — a dead *pipe* and a wrong
*answer* are different faults and are recorded separately.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import importlib
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
ROSTER_PATH = HERE / "af_advisor_roster.json"
# `scripts/bootstrap-pod.sh` installs the shared deps here and links them with a
# `.pth` under $HOME. $HOME is ephemeral, so a recycle drops the link while this
# durable copy survives; check it before spending a pip install.
AX_PYLIBS = Path(os.environ.get("AX_PYLIBS", "/workspace/ax-tools/pylibs"))
OUT_DIR = ROOT / "artifacts" / "vendor_consult"

ATTEMPTS = 3
BACKOFF_SECONDS = 3
RATE_BACKOFF_SECONDS = 50
DEFAULT_TIMEOUT = 180.0

POLLINATIONS_ENDPOINT = "https://text.pollinations.ai/openai"
POLLINATIONS_MODEL = "openai-fast"
# The free models are reasoning models, so `max_tokens` must cover the hidden
# reasoning *and* the answer. 4000 with reasoning_effort=low is the pair that
# survives; without "low" the model spends the whole ceiling thinking and the
# call returns HTTP 400.
POLLINATIONS_MAX_TOKENS = 4000

MIN_CHARS = 20

RATE_HINTS = ("free_limit", "free limit", "quota_exceeded", "quota exceeded",
              "429", "ratelimit", "rate limit", "too many requests")

# Only markers that cannot appear in a real answer. Each one is short enough to
# sit inside a 200 OK error page. The 400-character bound keeps a long answer
# that happens to quote one of them from failing.
ERROR_MARKERS = (
    "i encountered an error",
    "something went wrong",
    "could you try again",
    "please try again later",
    "i cannot assist with that",
    "having a hard time fulfilling",
    "can i help you with something else",
)

# An advert is a different failure from an error page: the provider answers with
# a promo for some other app, usually several hundred characters long, so the
# length bound above cannot catch it. Measured 2026-11-21: G4FSpace returned the
# 584-character "Copilot moved to a new app" card and it counted as an answer.
ADVERT_MARKERS = (
    "copilot moved to a new app",
    "install the new copilot app",
    "unifiedlink.svc.cloud.microsoft",
    "openappstoreonload",
    "appstoreonload",
    "copilot_migration",
)

SYSTEM = (
    "You are the outside advisor for an autonomous agent that has no human in "
    "the loop. Answer as a blunt senior operator: decide, do not survey. Put the "
    "recommendation first, then the numbers behind it, then the one fact that "
    "would change the answer. When the question asks for JSON, reply with JSON "
    "only and no prose around it. Never ask a follow-up question: if a fact is "
    "missing, state the assumption you used and continue."
)


# ---------------------------------------------------------------- the roster

def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_roster() -> dict:
    return json.loads(ROSTER_PATH.read_text(encoding="utf-8"))


def save_roster(roster: dict) -> None:
    """Atomic replace, so a bench cannot truncate the registry mid-write."""
    roster["updated"] = _now()
    tmp = ROSTER_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(roster, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    tmp.replace(ROSTER_PATH)


def resolve_vendor(name: str, roster: dict | None = None) -> str:
    """Map a name to its roster key: exact, then case-insensitive, then provider.

    The roster keys are the g4f provider names ("Gemini") while the mandate and
    the CLI use lower case ("gemini"). Both must reach the same vendor, or
    `--advisor gemini` silently finds no transport.
    """
    roster = roster or load_roster()
    advisors = roster.get("advisors") or {}
    if name in advisors:
        return name
    low = (name or "").lower()
    for key, spec in advisors.items():
        if key.lower() == low or str((spec or {}).get("provider", "")).lower() == low:
            return key
    return name


def vendor_spec(vendor: str, roster: dict | None = None) -> dict:
    roster = roster or load_roster()
    return (roster.get("advisors") or {}).get(resolve_vendor(vendor, roster)) or {}


def default_pool(roster: dict | None = None) -> list[str]:
    roster = roster or load_roster()
    advisors = roster.get("advisors") or {}
    pool = roster.get("default_pool") or list(advisors)
    return [resolve_vendor(v, roster) for v in pool if resolve_vendor(v, roster) in advisors]


def advise_order(roster: dict | None = None) -> list[str]:
    """The default advisor first, then the fallback order, each vendor once."""
    roster = roster or load_roster()
    advisors = roster.get("advisors") or {}
    order: list[str] = []
    for vendor in [roster.get("default_advisor")] + list(roster.get("gemini_order") or []):
        key = resolve_vendor(vendor, roster) if vendor else ""
        if key in advisors and key not in order:
            order.append(key)
    return order


def dead_vendors(roster: dict | None = None) -> dict:
    """Every `dead_*` block, flattened. The reason is kept, not just the name."""
    roster = roster or load_roster()
    out: dict = {}
    for key, block in roster.items():
        if key.startswith("dead_") and isinstance(block, dict):
            for vendor, info in block.items():
                out[vendor] = dict(info, dead_since=key.replace("dead_", ""))
    return out


# ------------------------------------------------------------- the transports

def ensure_g4f():
    """Import g4f, restoring it after a pod recycle.

    Three routes, cheapest first: the import, the durable pylibs directory, then
    a pip install. Measured 2026-11-22: a recycle dropped the `$HOME` `.pth`, so
    every g4f vendor read as dead while `/workspace/ax-tools/pylibs/g4f` was
    intact — the install was never the missing piece.
    """
    def _add_pylibs() -> None:
        if AX_PYLIBS.is_dir() and str(AX_PYLIBS) not in sys.path:
            sys.path.insert(0, str(AX_PYLIBS))
        importlib.invalidate_caches()

    for attempt in range(2):
        try:
            import g4f
            return g4f
        except ImportError:
            if attempt:
                break
            _add_pylibs()

    target = ["--target", str(AX_PYLIBS)] if os.access(AX_PYLIBS, os.W_OK) else ["--user"]
    proc = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-q", *target, "g4f"],
        capture_output=True, text=True, timeout=900)
    _add_pylibs()
    try:
        import g4f
        return g4f
    except ImportError as exc:  # pragma: no cover - depends on the network
        tail = ((proc.stderr or proc.stdout or "").strip().splitlines() or ["no output"])[-1]
        raise RuntimeError(
            f"g4f is not installed and 'pip install g4f' failed "
            f"(rc={proc.returncode}): {exc}; {tail}")


def _with_deadline(fn, timeout: float):
    """Run `fn` in a daemon thread and give up after `timeout`.

    A g4f provider can hang on a socket that never closes; the deadline keeps one
    wedged vendor from holding the whole consultation open.
    """
    box: dict = {}

    def run():
        try:
            box["value"] = fn()
        except BaseException as exc:  # noqa: BLE001
            box["error"] = exc

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    thread.join(timeout)
    if thread.is_alive():
        raise TimeoutError(f"no answer within {timeout:.0f}s")
    if "error" in box:
        raise box["error"]
    return box["value"]


def _text_from_chat_json(raw: str) -> str:
    """Accept an OpenAI chat envelope or bare text; never return the envelope."""
    text = raw.strip()
    if not text:
        raise RuntimeError("pollinations returned an empty body")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return text
    if isinstance(payload, dict):
        choices = payload.get("choices") or []
        if choices:
            content = ((choices[0] or {}).get("message") or {}).get("content")
            if isinstance(content, str):
                return content.strip()
        for key in ("text", "content", "answer"):
            if isinstance(payload.get(key), str):
                return payload[key].strip()
        if payload.get("error"):
            raise RuntimeError(f"pollinations error: {str(payload['error'])[:200]}")
    return text


def ask_pollinations(prompt: str, timeout: float = DEFAULT_TIMEOUT) -> str:
    body = {
        "model": POLLINATIONS_MODEL,
        "max_tokens": POLLINATIONS_MAX_TOKENS,
        "reasoning_effort": "low",
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": prompt},
        ],
    }
    req = urllib.request.Request(
        POLLINATIONS_ENDPOINT,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 "User-Agent": "af-advisor/1.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", "replace")[:200]
        except Exception:  # noqa: BLE001
            pass
        raise RuntimeError(f"pollinations HTTP {exc.code}: {detail or exc.reason}")
    return _text_from_chat_json(raw)


def ask_g4f(provider_name: str, prompt: str, timeout: float = DEFAULT_TIMEOUT) -> str:
    """One g4f provider. The provider *class* is the vendor — never the model name.

    `create(model="o3_mini")` returns the same 584-character Copilot advert for
    every model name; passing `provider=` is the call that reaches the vendor.
    """
    g4f = ensure_g4f()
    provider = getattr(g4f.Provider, provider_name, None)
    if provider is None:
        raise RuntimeError(f"g4f has no provider named {provider_name!r}")

    def call():
        client = g4f.client.Client()
        resp = client.chat.completions.create(
            model="",
            provider=provider,
            messages=[
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": prompt},
            ],
        )
        content = (resp.choices[0].message.content or "").strip()
        if not content:
            raise RuntimeError(f"{provider_name} returned an empty message")
        return content

    return _with_deadline(call, timeout)


def _ask_once(vendor: str, prompt: str, timeout: float = DEFAULT_TIMEOUT) -> str:
    spec = vendor_spec(vendor)
    if (spec or {}).get("transport") == "http":
        return ask_pollinations(prompt, timeout)
    return ask_g4f((spec or {}).get("provider") or vendor, prompt, timeout)


# ------------------------------------------------------------------ the guards

def is_rate_hint(text: str) -> bool:
    low = (text or "").lower()
    return any(hint in low for hint in RATE_HINTS)


def is_advert(text: str) -> bool:
    """A promo for some other product, served instead of an answer.

    Length-independent: the measured advert is 584 characters, which is exactly
    the range where the error-marker test stops looking.
    """
    low = (text or "").lower()
    return any(marker in low for marker in ADVERT_MARKERS)


def looks_like_error_answer(text: str) -> bool:
    """True when `text` is an error page, an advert, a refusal, or too short.

    Deliberately narrow: a short answer is only rejected below MIN_CHARS, and the
    refusal markers only run under 400 characters. Both bounds exist so a correct
    terse answer ("DECLINE", 7 characters) is not thrown away with the errors.
    Adverts are the exception and are rejected at any length.
    """
    body = (text or "").strip()
    if len(body) < MIN_CHARS:
        return True
    if is_advert(body):
        return True
    if len(body) < 400:
        low = body.lower()
        if any(marker in low for marker in ERROR_MARKERS):
            return True
    return False


def _ask(vendor: str, prompt: str, timeout: float = DEFAULT_TIMEOUT):
    """(vendor, "OK"|"FAIL", text). FAIL text is the last real error, not a guess."""
    last = "unknown failure"
    for attempt in range(ATTEMPTS):
        try:
            text = _ask_once(vendor, prompt, timeout)
            if is_advert(text):
                raise RuntimeError(
                    f"advert instead of an answer: {text.strip()[:120]!r}")
            if looks_like_error_answer(text):
                raise RuntimeError(f"error-shaped answer: {text.strip()[:160]!r}")
            return vendor, "OK", text.strip()
        except Exception as exc:  # noqa: BLE001
            last = f"{type(exc).__name__}: {exc}"
            if attempt + 1 < ATTEMPTS:
                wait = (RATE_BACKOFF_SECONDS if is_rate_hint(last)
                        else BACKOFF_SECONDS * (attempt + 1))
                time.sleep(wait)
    return vendor, "FAIL", last


# ----------------------------------------------------------------- the consults

def _timed_ask(vendor: str, prompt: str, timeout: float = DEFAULT_TIMEOUT):
    """`_ask` plus the wall clock, so each row carries its own latency."""
    t0 = time.time()
    vendor, status, text = _ask(vendor, prompt, timeout)
    return vendor, status, text, round(time.time() - t0, 1)


def consult(prompt: str, vendors: list[str] | None = None, quorum: int = 1,
            timeout: float = DEFAULT_TIMEOUT):
    """Ask every vendor in parallel; keep every answer that arrived.

    A vendor that misses `timeout + 60` is recorded as FAIL "timeout" and does not
    discard the answers already collected. `met` is the fail-closed verdict:
    ok_count >= quorum.
    """
    vendors = list(vendors or default_pool())
    results: list[dict] = []
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(vendors)))
    started = {pool.submit(_timed_ask, v, prompt, timeout): v for v in vendors}
    done, pending = concurrent.futures.wait(started, timeout=timeout + 60)
    for future in done:
        try:
            vendor, status, text, seconds = future.result()
        except Exception as exc:  # noqa: BLE001
            vendor, status, text = started[future], "FAIL", f"{type(exc).__name__}: {exc}"
            seconds = None
        row = {"vendor": vendor, "status": status,
               "answer": text if status == "OK" else "",
               "error": "" if status == "OK" else text}
        if seconds is not None:
            row["seconds"] = seconds
        results.append(row)
    for future in pending:
        future.cancel()
        results.append({"vendor": started[future], "status": "FAIL",
                        "answer": "", "error": "timeout"})
    pool.shutdown(wait=False, cancel_futures=True)
    order = {vendor: index for index, vendor in enumerate(vendors)}
    results.sort(key=lambda row: order.get(row["vendor"], len(order)))
    ok = sum(1 for row in results if row["status"] == "OK")
    return results, ok >= quorum


def advise(prompt: str, timeout: float = DEFAULT_TIMEOUT, on_fail=None):
    """The default advisor first, then the fallback order. (result, ok)."""
    last: dict = {"vendor": "", "status": "FAIL", "answer": "",
                  "error": "no vendor in roster"}
    for vendor in advise_order():
        vendor_name, status, text = _ask(vendor, prompt, timeout)
        last = {"vendor": vendor_name, "status": status,
                "answer": text if status == "OK" else "",
                "error": "" if status == "OK" else text}
        if status == "OK":
            return last, True
        if on_fail is not None:
            on_fail(vendor_name, text)
    return last, False


# ------------------------------------------------------------------- reporting

def _consult_digest(prompt: str) -> str:
    norm = " ".join((prompt or "").split()).lower()
    return hashlib.sha256(norm.encode("utf-8")).hexdigest()[:16]


def record_consult(prompt: str, results: list[dict], applied: list[str] | None = None):
    """Append to the standing `ops/consult-log.jsonl`, so the existing gate sees it.

    `ops.consult` is the authority for the row shape, but importing it pulls in
    the browser advisors, which a rail does not have. So: use it when it imports,
    otherwise write the same row here. A consultation the execution gate cannot
    see is a consultation that did not happen.
    """
    answers = {}
    for row in results:
        entry = {"ok": row["status"] == "OK", "answer": row.get("answer", "")}
        if row.get("seconds") is not None:
            entry["seconds"] = row["seconds"]
        if row["status"] != "OK":
            entry["error"] = row.get("error") or row.get("answer") or "failed"
        answers[row["vendor"]] = entry

    try:
        sys.path.insert(0, str(ROOT / "ops"))
        import consult  # noqa: E402
        consult.record(prompt, answers, applied=applied)
        return consult.digest(prompt)
    except Exception:  # noqa: BLE001
        pass

    ok = [vendor for vendor, entry in answers.items() if entry["ok"]]
    families = sorted({"duck" if vendor.startswith("duck") else vendor for vendor in ok})
    row = {
        "at": _now(),
        "digest": _consult_digest(prompt),
        "problem": prompt,
        "answers": answers,
        "families": families,
        "quorum": bool(ok),
        "applied": applied or [],
        "recorded_by": "tools/af_advisor.py",
    }
    log = ROOT / "ops" / "consult-log.jsonl"
    try:
        with log.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    except OSError:
        return None
    return row["digest"]


def write_json(path: Path, payload: dict, force: bool = False) -> Path:
    """Write the result without destroying an earlier raw capture.

    A second run at the same name gets a timestamp instead of overwriting: the
    answers are the evidence, and the 2026-11-21 regrade destroyed a set by
    writing over it.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and not force:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        path = path.with_name(f"{path.stem}-{stamp}{path.suffix}")
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    tmp.replace(path)
    return path


def print_results(prompt: str, results: list[dict], met: bool, quorum: int) -> None:
    print(f"PROMPT: {prompt.strip()[:200]}")
    for row in results:
        head = f"\n===== {row['vendor']} [{row['status']}]"
        if row.get("seconds") is not None:
            head += f" {row['seconds']}s"
        print(head + " =====")
        print(row["answer"] if row["status"] == "OK" else f"FAILED: {row.get('error')}")
    ok = sum(1 for row in results if row["status"] == "OK")
    print(f"\nSUMMARY: {ok}/{len(results)} answered, quorum {quorum} -> "
          f"{'PASS' if met else 'FAIL'}")


# ----------------------------------------------------------------------- CLI

def build_prompt(question: str, stuck: str | None) -> str:
    if not stuck:
        return question
    return (f"{question}\n\n---\nSTUCK. The step below failed:\n{stuck}\n\n"
            "Which step is broken, why did it fail, and what exactly should I do "
            "next? Do not change the plan silently; name the failed step.")


def selftest() -> int:
    failures: list[str] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        print(("ok   " if ok else "FAIL ") + name +
              (f"  [{detail}]" if detail and not ok else ""))
        if not ok:
            failures.append(name)

    check("empty is an error", looks_like_error_answer(""))
    check("a refusal is an error",
          looks_like_error_answer("I'm having a hard time fulfilling this request right now."))
    check("a short correct answer is NOT an error",
          not looks_like_error_answer("Opportunity cost: 6.75 / Net loss: 5.25 / DECLINE"))
    check("MIN_CHARS is 20", MIN_CHARS == 20, str(MIN_CHARS))
    advert = ("### Copilot moved to a new app\n\n- Install the new Copilot app "
              "(needs iOS 26 or Android 13)\n" + "filler " * 60 +
              "\n[Install now](https://unifiedlink.svc.cloud.microsoft/app/"
              "copilot/?openAppStoreOnLoad=true)")
    check("a long advert is an error even at 584 characters",
          len(advert) > 400 and looks_like_error_answer(advert))
    check("a real long answer is not an advert",
          not is_advert("The rail shipped: the run history shows the publish "
                        "step at 18:02 and the live place version moved."))
    check("rate hint is recognised", is_rate_hint("HTTP 429 Too Many Requests"))
    check("a normal failure is not a rate hint", not is_rate_hint("connection reset"))
    check("the chat envelope is unwrapped",
          _text_from_chat_json('{"choices":[{"message":{"content":"hello there"}}]}')
          == "hello there")
    roster = load_roster()
    check("roster names a default advisor", bool(roster.get("default_advisor")))
    check("the default advisor resolves to a roster vendor",
          resolve_vendor(roster.get("default_advisor") or "", roster)
          in (roster.get("advisors") or {}))
    check("every fallback vendor exists",
          all(v in (roster.get("advisors") or {}) for v in roster.get("gemini_order") or []))
    check("pollinations is an HTTP vendor",
          vendor_spec("pollinations", roster).get("transport") == "http")
    check("dead vendors carry a reason",
          all(info.get("reason") for info in dead_vendors(roster).values()))
    stuck = build_prompt("the render is stuck", "Traceback: ffmpeg exit 1")
    check("--stuck carries the real error into the question",
          "Traceback: ffmpeg exit 1" in stuck and "which step is broken" in stuck.lower())
    check("a plain question is left alone", build_prompt("q", None) == "q")
    check("ATTEMPTS > 1", ATTEMPTS > 1, str(ATTEMPTS))
    check("rate backoff >= the free-tier window", RATE_BACKOFF_SECONDS >= 45,
          str(RATE_BACKOFF_SECONDS))
    print(f"\nSELFTEST: {'PASS' if not failures else 'FAIL'} "
          f"({len(failures)} failure(s))")
    return 0 if not failures else 1


def _age_hours(stamp: str) -> float:
    then = datetime.fromisoformat(stamp)
    return (datetime.now(timezone.utc) - then).total_seconds() / 3600.0


def show_check() -> int:
    roster = load_roster()
    print(f"roster: {ROSTER_PATH}  (updated {roster.get('updated')})")
    mandate = (roster.get("mandate") or {}).get("current") or {}
    if mandate:
        print(f"mandate: {mandate.get('text')} ({mandate.get('date')})")
    print(f"default advisor: {roster.get('default_advisor')}")
    print(f"fallback order: {' -> '.join(roster.get('gemini_order') or [])}")
    bench = roster.get("bench") or {}
    scores = (bench.get("ceo") or {}).get("scores") or {}
    ages = [f"{layer} {_age_hours(row['measured_at']):.1f}h"
            for layer, row in bench.items() if row.get("measured_at")]
    if ages:
        print("bench age: " + ", ".join(ages) + "   (re-run past 24h)")
    print("\nadvisors:")
    for name, spec in (roster.get("advisors") or {}).items():
        score = f"  ceo={scores[name]}" if name in scores else ""
        print(f"  {name:12s} {str(spec.get('transport')):5s} "
              f"{str(spec.get('status')):10s}{score}")
    dead = dead_vendors(roster)
    if dead:
        print("\ndead:")
        for name, info in dead.items():
            print(f"  {name}: {info.get('reason')} (since {info.get('dead_since')})")
    trading = roster.get("trading_advisor") or {}
    if trading:
        print(f"\ntrading advisor: {trading.get('vendor')} ({trading.get('score')}, "
              f"self-consistent {trading.get('self_consistency')})")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("question", nargs="?", help="the question or problem")
    parser.add_argument("--file", type=Path, help="read the question from a file")
    parser.add_argument("--advisor", help="one advisor, with fallback (default from roster)")
    parser.add_argument("--vendors", help="comma-separated pool, asked in parallel")
    parser.add_argument("--quorum", type=int, default=1,
                        help="how many vendors must answer (default 1)")
    parser.add_argument("--stuck", help="the real error that blocked the step")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    parser.add_argument("--json", type=Path, help="write the answers to this file")
    parser.add_argument("--force", action="store_true", help="allow overwriting --json")
    parser.add_argument("--no-record", action="store_true",
                        help="do not append to ops/consult-log.jsonl")
    parser.add_argument("--check", action="store_true", help="print the roster health")
    parser.add_argument("--selftest", action="store_true", help="exercise the guards offline")
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()
    if args.check:
        return show_check()

    question = args.file.read_text(encoding="utf-8") if args.file else args.question
    if not question:
        parser.error("a question is required (or --file, --check, --selftest)")
    prompt = build_prompt(question, args.stuck)

    if args.vendors:
        roster = load_roster()
        vendors = [resolve_vendor(v.strip(), roster)
                   for v in args.vendors.split(",") if v.strip()]
        unknown = [v for v in vendors if v not in (roster.get("advisors") or {})]
        if unknown:
            print(f"unknown vendor(s): {', '.join(unknown)}", file=sys.stderr)
            return 2
        results, met = consult(prompt, vendors=vendors, quorum=args.quorum,
                               timeout=args.timeout)
        print_results(prompt, results, met, args.quorum)
        payload = {"at": _now(), "mode": "consult", "prompt": prompt,
                   "stuck": args.stuck, "quorum": args.quorum,
                   "met": met, "results": results}
        ok = met
    else:
        def on_fail(vendor: str, error: str) -> None:
            print(f"[af_advisor] {vendor} failed: {error[:200]}", file=sys.stderr)

        t0 = time.time()
        result, ok = advise(prompt, timeout=args.timeout, on_fail=on_fail)
        result["seconds"] = round(time.time() - t0, 1)
        results = [result]
        print_results(prompt, results, ok, 1)
        payload = {"at": _now(), "mode": "advise", "prompt": prompt,
                   "stuck": args.stuck, "advisor": args.advisor or "roster default",
                   "met": ok, "results": results}
    if not args.no_record:
        digest = record_consult(prompt, results)
        if digest:
            payload["consult_digest"] = digest
    if args.json:
        written = write_json(args.json, payload, force=args.force)
        print(f"wrote {written}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
