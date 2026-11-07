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
import urllib.request

ENDPOINT = "https://text.pollinations.ai/openai"
# gpt-oss-20b is the model Pollinations serves to anonymous callers; naming a
# bigger one just returns an error rather than a different model.
DEFAULT_MODEL = "openai-fast"


def ask(problem: str, timeout: float = 180.0, model: str = DEFAULT_MODEL) -> str:
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": problem}],
    }).encode("utf-8")
    req = urllib.request.Request(
        ENDPOINT, data=body,
        headers={"Content-Type": "application/json",
                 "User-Agent": "aeris-consult/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode("utf-8", "ignore"))
    answer = (data.get("choices") or [{}])[0].get("message", {}).get("content", "")
    if not answer.strip():
        raise RuntimeError("empty answer from pollinations")
    return answer


if __name__ == "__main__":
    import sys
    print(ask(" ".join(sys.argv[1:]) or "ตอบสั้น ๆ: 2+2 เท่ากับเท่าไหร่", timeout=60))
