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


def ask(problem: str, timeout: float = 180.0, model: str = "openai") -> str:
    # `reasoning_effort: low` is not cosmetic: the default reasoning budget is
    # spent before the model emits an answer, and a song prompt is long enough to
    # trigger `output_token_limit_exceeded` (HTTP 400). Measured 2026-11-07.
    body = {"messages": [{"role": "user", "content": problem}],
            "reasoning_effort": "low"}
    if model:
        body["model"] = model
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        ENDPOINT, data=data,
        headers={"Content-Type": "application/json",
                 "User-Agent": "aeris-consult/1.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                answer = r.read().decode("utf-8", "ignore")
            if not answer.strip():
                raise RuntimeError("empty answer from pollinations")
            return answer
        except urllib.error.HTTPError as e:
            if e.code not in (402, 429) or attempt == 2:
                raise
            time.sleep(FREE_LIMIT_WAIT)
    raise RuntimeError("pollinations did not answer")


if __name__ == "__main__":
    import sys
    print(ask(" ".join(sys.argv[1:]) or "ตอบสั้น ๆ: 2+2 เท่ากับเท่าไหร่", timeout=60))
