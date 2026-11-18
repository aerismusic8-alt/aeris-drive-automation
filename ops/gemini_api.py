#!/usr/bin/env python3
"""Draft text with the Gemini API free tier — plain HTTP, so it runs in CI.

K's rule (Rule #1): free only. Gemini's free tier needs no card, and its content
filter is looser than the keyless channels', so it is the drafter of record for
the lyric rail. That is Gemini's own advice (2026-11-18), taken after the keyless
drafters started refusing the Thai rap prompt with "I can't produce that
content": a browser tab cannot exist on a GitHub Actions runner, and the keyless
HTTP channel refuses, so the rail produced nothing.

    python3 ops/gemini_api.py "prompt text"
    python3 ops/gemini_api.py --file prompt.md
    GEMINI_MODEL=gemini-3.5-flash-lite python3 ops/gemini_api.py "..."

Key: env `GEMINI_API_KEY` (or `GOOGLE_API_KEY`). In CI it is a repository secret;
on a pod it is recovered from the vault (`axsecrets:gemini-api-key`). With no key
the call raises `GeminiUnavailable`, so a caller falls through to another drafter
rather than failing the whole run.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

# The free tier's standard Flash model (checked against the model list 2026-11-18).
# Override with GEMINI_MODEL when the free lineup moves; the caller's lint still
# decides whether the answer is usable.
DEFAULT_MODEL = "gemini-3.8-flash"
API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"


class GeminiUnavailable(RuntimeError):
    """No key, or the API refused. Callers treat it like any other dead drafter."""


def api_key() -> str:
    return (os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
            or "").strip()


def ask(problem: str, timeout: float = 120.0, model: str | None = None) -> str:
    """Return the model's text answer for `problem`.

    Raises `GeminiUnavailable` when there is no key (a normal, non-fatal state on
    a fresh pod) and `RuntimeError` when the API itself errors, with the response
    body attached — a bare "400" hid the real reason once already.
    """
    key = api_key()
    if not key:
        raise GeminiUnavailable("GEMINI_API_KEY is not set")
    model = model or os.environ.get("GEMINI_MODEL") or DEFAULT_MODEL
    url = f"{API_BASE}/{model}:generateContent"
    body = json.dumps({
        "contents": [{"parts": [{"text": problem}]}],
        # The draft is Thai lyrics; a little heat helps variety across the ~60
        # themes, and the caller lints shape and language regardless.
        "generationConfig": {"temperature": 1.0, "maxOutputTokens": 2048},
    }).encode("utf-8")
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"gemini api HTTP {exc.code}: {detail}") from exc
    return _extract_text(payload)


def _extract_text(payload: dict) -> str:
    """Join the text parts of the first candidate.

    A blocked prompt comes back with no `parts` and a `finishReason` of SAFETY,
    so that case is reported as an explicit error rather than an empty draft.
    """
    cands = payload.get("candidates") or []
    if not cands:
        reason = (payload.get("promptFeedback") or {}).get("blockReason")
        raise RuntimeError(f"gemini api returned no candidate (blocked: {reason})")
    parts = (cands[0].get("content") or {}).get("parts") or []
    text = "".join(p.get("text", "") for p in parts).strip()
    if not text:
        raise RuntimeError(
            f"gemini api returned no text (finishReason="
            f"{cands[0].get('finishReason')})")
    return text


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("problem", nargs="?", help="the prompt")
    ap.add_argument("--file", help="read the prompt from a file")
    ap.add_argument("--model", help=f"override the model (default {DEFAULT_MODEL})")
    a = ap.parse_args(argv)
    prompt = a.file and open(a.file, encoding="utf-8").read() or a.problem
    if not prompt:
        ap.error("give a prompt or --file")
    try:
        print(ask(prompt, model=a.model))
    except GeminiUnavailable as exc:
        print(f"gemini_api unavailable: {exc}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
