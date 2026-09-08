"""AI strategy-research interface for XM market context.

The AI proposes and evaluates hypotheses from supplied market/risk context;
it never submits broker orders.
"""
from __future__ import annotations

import json
import os
from typing import Mapping, Any


def build_research_prompt(context: Mapping[str, Any]) -> str:
    payload = json.dumps(dict(context), ensure_ascii=False, sort_keys=True)
    return (
        "Act as the XM strategy research AI. Use only the supplied market and risk context. "
        "Return concise candidate strategy hypotheses, regime assumptions, entry/exit rules, "
        "invalidation conditions, and tests required for out-of-sample validation. "
        "Do not claim guaranteed profit and do not place orders.\n\n"
        f"CONTEXT={payload}"
    )


def propose_strategy(context: Mapping[str, Any]) -> dict[str, Any]:
    prompt = build_research_prompt(context)
    if not os.getenv("OPENAI_API_KEY"):
        return {"status": "UNAVAILABLE", "reason": "OPENAI_API_KEY_MISSING", "prompt": prompt}
    try:
        from ax_openai_helper import ask_openai
        text = ask_openai(prompt)
    except Exception as exc:
        return {"status": "FAILED", "reason": "AI_RESEARCH_FAILED", "detail": str(exc), "prompt": prompt}
    return {"status": "PROPOSED", "result": text, "prompt": prompt}
