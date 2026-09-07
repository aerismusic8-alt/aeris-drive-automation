#!/usr/bin/env python3
"""Contract tests for the AX OpenAI helper using a fake HTTP opener."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "AKATH" / "runtime"))

from ax_openai_helper import OpenAIHelperError, ask_openai  # noqa: E402


class FakeResponse:
    def __init__(self, payload: dict):
        self.payload = payload

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class FakeOpener:
    def __init__(self):
        self.requests = []

    def __call__(self, request, timeout):
        self.requests.append((request, timeout))
        return FakeResponse({
            "output": [{
                "type": "message",
                "content": [{"type": "output_text", "text": "AX helper online"}],
            }]
        })


def main() -> None:
    opener = FakeOpener()
    os.environ["OPENAI_API_KEY"] = "test-key"
    os.environ.pop("AX_OPENAI_MODEL", None)

    result = ask_openai("status check", system="You are an AX helper.", opener=opener)
    assert result == "AX helper online", result
    assert len(opener.requests) == 1

    request, timeout = opener.requests[0]
    assert request.full_url == "https://api.openai.com/v1/responses"
    assert request.get_header("Authorization") == "Bearer test-key"
    assert request.get_header("Content-type") == "application/json"
    body = json.loads(request.data.decode("utf-8"))
    assert body["model"] == "gpt-5.6-luna", body
    assert body["input"] == [
        {"role": "system", "content": "You are an AX helper."},
        {"role": "user", "content": "status check"},
    ], body
    assert timeout == 60

    del os.environ["OPENAI_API_KEY"]
    try:
        ask_openai("must fail", opener=opener)
    except OpenAIHelperError as exc:
        assert str(exc) == "OPENAI_API_KEY_MISSING"
    else:
        raise AssertionError("missing API key must fail closed")

    print("OPENAI_HELPER_TEST_PASS request contract + fail-closed secret handling")


if __name__ == "__main__":
    main()
