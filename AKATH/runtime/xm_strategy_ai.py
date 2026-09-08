"""AI strategy-research interface for XM market context.

This module prepares bounded research prompts and optionally delegates to the
existing AX OpenAI helper. It does not submit broker orders.
"""
from __future__ import annotations

import json
import os
from typing import Mapping, Any


def build_research_prompt(context: Mapping[str, Any]) -> str:
    payload = json.dumps(dict(context), ensure_ascii=False, sort_keys=True)
    return (
        "Act as XM strategy research AI. Analyze only the supplied market and risk context. "
        "Return candidate strategy hypotheses, assumptions, invalidation conditions, risk limits, "
        "and tests needed for out-of-sample validation. Never claim guaranteed profit and never place orders.\n\n"
        f"CONTEXT={payload}"
    )


def propose_strategy(context: Mapping[str, Any]) -> dict[str, Any]:
    prompt = build_research_prompt(context)
    try:
        from ax_openai_helper import ask_openai
    except Exception as exc:
        return {"status": "UNAVAILABLE", "reason": "OPENAI_HELPER_IMPORT_FAILED", "detail": str(exc), "prompt": prompt}

    if not os.getenv("OPENAI_API_KEY"):
        return {"status": "UNAVAILABLE", "reason": "OPENAI_API_KEY_MISSING", "prompt": prompt}

    try:
        result = ask_openai(prompt)
        return {"status": "PROPOSED", "result": result, "prompt": prompt}
    except Exception as exc:
        return {"status": "FAILED", "reason": "AI_RESEARCH_FAILED", "detail": str(exc), "prompt": prompt}
