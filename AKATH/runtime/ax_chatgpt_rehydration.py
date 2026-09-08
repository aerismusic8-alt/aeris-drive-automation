#!/usr/bin/env python3
"""ChatGPT-facing AX rehydration wrapper; reading never authorizes execution."""
from __future__ import annotations
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
PROFILE = ROOT / "AX_MASTER_BRAIN" / "AX_CHATGPT_REHYDRATION_PROFILE.json"


def fail(reason: str) -> dict[str, Any]:
    return {"rehydration_status":"NOT_VERIFIED","identity":"AX","organization":"AKATH","chat_memory_authority":False,"model_memory_authority":False,"execution_authorized":False,"failure_reasons":[reason]}


def rehydrate() -> dict[str, Any]:
    if not PROFILE.is_file(): return fail("CHATGPT_REHYDRATION_PROFILE_MISSING")
    try: profile=json.loads(PROFILE.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError): return fail("CHATGPT_REHYDRATION_PROFILE_MALFORMED")
    if profile.get("organization") != "AKATH" or profile.get("executive_identity") != "AX": return fail("CHATGPT_PROFILE_IDENTITY_INVALID")
    if profile.get("final_authority") != "K_FINAL_AUTHORITY": return fail("CHATGPT_PROFILE_AUTHORITY_INVALID")
    if profile.get("master_brain", {}).get("role") != "KNOWLEDGE_AND_ACCUMULATED_EXPERIENCE": return fail("CHATGPT_PROFILE_BRAIN_INVALID")
    from ax_rehydration_adapter import rehydrate as ax_rehydrate
    result = ax_rehydrate()
    result["chat_memory_authority"] = False
    result["model_memory_authority"] = False
    result["execution_authorized"] = False
    result["profile_source"] = str(PROFILE)
    return result


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] != "rehydrate":
        print(json.dumps(fail("INVALID_INVOCATION"), ensure_ascii=False)); return 2
    result = rehydrate(); print(json.dumps(result, ensure_ascii=False)); return 0 if result["rehydration_status"] == "VERIFIED" else 1

if __name__ == "__main__": raise SystemExit(main())
