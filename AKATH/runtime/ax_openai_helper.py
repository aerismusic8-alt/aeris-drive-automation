#!/usr/bin/env python3
"""Minimal, fail-closed OpenAI Responses API helper for AX."""
from __future__ import annotations

import json
import os
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

API_URL = "https://api.openai.com/v1/responses"
DEFAULT_MODEL = "gpt-5.6-luna"


class OpenAIHelperError(RuntimeError):
    """Raised for configuration, transport, or response-contract failures."""


def _extract_text(payload: dict[str, Any]) -> str:
    if isinstance(payload.get("output_text"), str) and payload["output_text"].strip():
        return payload["output_text"].strip()

    parts: list[str] = []
    for item in payload.get("output", []):
        if not isinstance(item, dict):
            continue
        for content in item.get("content", []):
            if isinstance(content, dict) and content.get("type") == "output_text":
                text = content.get("text")
                if isinstance(text, str) and text.strip():
                    parts.append(text.strip())
    if parts:
        return "\n".join(parts)
    raise OpenAIHelperError("OPENAI_EMPTY_TEXT_RESPONSE")


def ask_openai(
    prompt: str,
    *,
    system: str | None = None,
    model: str | None = None,
    opener: Callable[..., Any] = urlopen,
    timeout: int = 60,
) -> str:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise OpenAIHelperError("OPENAI_API_KEY_MISSING")
    if not prompt.strip():
        raise OpenAIHelperError("OPENAI_PROMPT_EMPTY")

    selected_model = model or os.getenv("AX_OPENAI_MODEL") or DEFAULT_MODEL
    messages: list[dict[str, str]] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    body = json.dumps({"model": selected_model, "input": messages}).encode("utf-8")
    request = Request(
        API_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with opener(request, timeout=timeout) as response:
            raw = response.read()
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        raise OpenAIHelperError(f"OPENAI_HTTP_{exc.code}:{detail}") from exc
    except URLError as exc:
        raise OpenAIHelperError(f"OPENAI_NETWORK_ERROR:{exc.reason}") from exc
    except OSError as exc:
        raise OpenAIHelperError(f"OPENAI_TRANSPORT_ERROR:{exc}") from exc

    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise OpenAIHelperError("OPENAI_INVALID_JSON_RESPONSE") from exc
    if not isinstance(payload, dict):
        raise OpenAIHelperError("OPENAI_INVALID_RESPONSE_OBJECT")
    return _extract_text(payload)


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Call OpenAI as an AX helper.")
    parser.add_argument("prompt")
    parser.add_argument("--system", default=None)
    parser.add_argument("--model", default=None)
    args = parser.parse_args()

    try:
        print(ask_openai(args.prompt, system=args.system, model=args.model))
        return 0
    except OpenAIHelperError as exc:
        print(f"AX_OPENAI_ERROR={exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
