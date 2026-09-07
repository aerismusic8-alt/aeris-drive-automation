#!/usr/bin/env python3
"""Minimal fail-closed Gemini helper for AX."""
from __future__ import annotations
import json, os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
DEFAULT_MODEL = "gemini-2.5-flash"

class GeminiHelperError(RuntimeError):
    pass

def ask_gemini(prompt: str, *, model: str | None = None, timeout: int = 60) -> str:
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise GeminiHelperError("GEMINI_API_KEY_MISSING")
    if not prompt.strip():
        raise GeminiHelperError("GEMINI_PROMPT_EMPTY")
    selected = model or os.getenv("AX_GEMINI_MODEL") or DEFAULT_MODEL
    url = f"{API_BASE}/{selected}:generateContent?key={key}"
    body = json.dumps({"contents":[{"parts":[{"text":prompt}]}]}).encode()
    req = Request(url, data=body, headers={"Content-Type":"application/json"}, method="POST")
    try:
        with urlopen(req, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        raise GeminiHelperError(f"GEMINI_HTTP_{exc.code}:{detail}") from exc
    except (URLError, OSError) as exc:
        raise GeminiHelperError(f"GEMINI_TRANSPORT_ERROR:{exc}") from exc
    try:
        return payload["candidates"][0]["content"]["parts"][0]["text"].strip()
    except (KeyError, IndexError, TypeError) as exc:
        raise GeminiHelperError("GEMINI_EMPTY_OR_INVALID_RESPONSE") from exc
