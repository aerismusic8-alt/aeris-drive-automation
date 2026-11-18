"""A free, keyless text model, for when the browser advisors are unusable.

The panel's usual channels drive a signed-in web app over CDP. That breaks in
ways the panel cannot retry away: Gemini signed out, ChatGPT free rate-limited,
Duck's tab wedged. Pollinations answers over plain HTTP with no login and no API
key, so it keeps a second *family* in the panel when every browser is down — the
difference between a consultation that passes quorum and one that is skipped.

Same call shape as `duck_ask.ask`, so `ops/consult.py` can treat it as a vendor.
"""
from __future__ import annotations

import json
import time
import urllib.error

import urllib.request

# POST the root with the OpenAI `messages` shape: it answers with bare text and
# has no URL length limit. The GET form is easier but a song prompt is long
# enough to 404, and POST /openai 400s for an anonymous caller. Measured
# 2026-11-07.
ENDPOINT = "https://text.pollinations.ai/"
# One reply per ~45s per IP is the free tier's real limit. Waiting it out is
# cheaper than dropping the song, because the caller has nothing else to do.
FREE_LIMIT_WAIT = 48


def ask(problem: str, timeout: float = 180.0, model: str = "openai",
        max_tokens: int = 8192) -> str:
    # The free models are *reasoning* LLMs (see /models: "GPT-OSS 20B Reasoning
    # LLM"), so `max_tokens` must cover the hidden reasoning tokens *and* the
    # answer. `reasoning_effort: low` keeps that budget small but does not remove
    # it, and a long song brief can still exhaust the ceiling and 400 with
    # `output_token_limit_exceeded` (measured 2026-11-18 at 4096, and once at
    # 8192 under pool load). The retry below doubles the ceiling instead of
    # repeating the same doomed call, so the loop self-heals.
    body_base = {"messages": [{"role": "user", "content": problem}],
                 "reasoning_effort": "low"}
    if model:
        body_base["model"] = model
    for attempt in range(4):
        body = dict(body_base, max_tokens=max_tokens)
        data = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            ENDPOINT, data=data,
            headers={"Content-Type": "application/json",
                     "User-Agent": "aeris-consult/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                answer = r.read().decode("utf-8", "ignore")
            if not answer.strip():
                raise RuntimeError("empty answer from pollinations")
            return answer
        except urllib.error.HTTPError as e:
            # Keep the body: the free tier returns 400 for distinct reasons
            # (token ceiling, model down, load) and a bare "400 Bad Request"
            # cannot tell them apart — that cost a CI run 2026-11-18.
            try:
                detail = e.read().decode("utf-8", "replace")[:200]
            except Exception:  # noqa: BLE001
                detail = ""
            if "output_token_limit_exceeded" in detail and max_tokens < 32768:
                max_tokens *= 2
                continue
            # 400/402/429 also mean "busy, try again": the same body answers
            # seconds later, so a short backoff recovers it.
            if e.code in (400, 402, 429) and attempt < 3:
                time.sleep(FREE_LIMIT_WAIT if e.code in (402, 429) else 8)
                continue
            raise RuntimeError(f"pollinations HTTP {e.code}: {detail}") from e
    raise RuntimeError("pollinations did not answer")


if __name__ == "__main__":
    import sys
    print(ask(" ".join(sys.argv[1:]) or "ตอบสั้น ๆ: 2+2 เท่ากับเท่าไหร่", timeout=60))
